import AppKit

/// Contextual toolbar shown while the Text tool is active: font, size, style and background.
final class TextOptionsBar: NSView {
    let state: ToolState
    private let fontPopup = NSPopUpButton()
    private let sizeCombo = NSComboBox()
    private var styleButtons: [RibbonButton] = []
    private var opaqueButton: RibbonButton!
    private var transparentButton: RibbonButton!
    private var observer: Any?
    private var glassObserver: Any?

    init(state: ToolState) {
        self.state = state
        super.init(frame: .zero)
        build()
        observer = NotificationCenter.default.addObserver(forName: .toolStateChanged, object: state, queue: .main) { [weak self] _ in self?.refresh() }
        glassObserver = NotificationCenter.default.addObserver(forName: .liquidGlassSettingChanged, object: nil, queue: .main) { [weak self] _ in self?.needsDisplay = true }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }
    deinit {
        if let o = observer { NotificationCenter.default.removeObserver(o) }
        if let o = glassObserver { NotificationCenter.default.removeObserver(o) }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.divider.setFill()
        CGRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill(using: .sourceOver)
    }

    private func build() {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let fontLabel = NSTextField(labelWithString: L("Font"))
        fontLabel.font = NSFont.systemFont(ofSize: 12)
        fontLabel.textColor = Theme.secondaryText
        stack.addArrangedSubview(fontLabel)
        fontPopup.addItems(withTitles: NSFontManager.shared.availableFontFamilies.sorted())
        fontPopup.target = self
        fontPopup.action = #selector(fontChanged)
        fontPopup.widthAnchor.constraint(equalToConstant: 180).isActive = true
        stack.addArrangedSubview(fontPopup)

        sizeCombo.addItems(withObjectValues: [8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 72])
        sizeCombo.target = self
        sizeCombo.action = #selector(sizeChanged)
        sizeCombo.widthAnchor.constraint(equalToConstant: 64).isActive = true
        sizeCombo.delegate = self
        stack.addArrangedSubview(sizeCombo)

        stack.addArrangedSubview(RibbonSeparator())
        let defs: [(String, String, (ToolState) -> Bool, (ToolState) -> Void)] = [
            ("bold", L("Bold"), { $0.bold }, { $0.bold.toggle() }),
            ("italic", L("Italic"), { $0.italic }, { $0.italic.toggle() }),
            ("underline", L("Underline"), { $0.underline }, { $0.underline.toggle() }),
            ("strikethrough", L("Strikethrough"), { $0.strikethrough }, { $0.strikethrough.toggle() }),
        ]
        for (symbol, title, _, toggle) in defs {
            let b = RibbonButton(symbol: symbol, tooltip: title) { [weak self] in
                guard let self else { return }
                toggle(self.state)
            }
            styleButtons.append(b)
            stack.addArrangedSubview(b)
        }
        stack.addArrangedSubview(RibbonSeparator())
        let bgLabel = NSTextField(labelWithString: L("Background"))
        bgLabel.font = NSFont.systemFont(ofSize: 12)
        bgLabel.textColor = Theme.secondaryText
        stack.addArrangedSubview(bgLabel)
        opaqueButton = RibbonButton(symbol: "square.fill", title: L("Opaque"), style: .wide, tooltip: L("Opaque")) { [weak self] in self?.state.textOpaqueBackground = true }
        transparentButton = RibbonButton(symbol: "square.dashed", title: L("Transparent"), style: .wide, tooltip: L("Transparent")) { [weak self] in self?.state.textOpaqueBackground = false }
        stack.addArrangedSubview(opaqueButton)
        stack.addArrangedSubview(transparentButton)
    }

    private func refresh() {
        fontPopup.selectItem(withTitle: state.fontName)
        if fontPopup.indexOfSelectedItem < 0, let family = NSFont(name: state.fontName, size: 12)?.familyName {
            fontPopup.selectItem(withTitle: family)
        }
        sizeCombo.stringValue = "\(Int(state.fontSize))"
        let flags = [state.bold, state.italic, state.underline, state.strikethrough]
        for (b, on) in zip(styleButtons, flags) { b.isSelected = on }
        opaqueButton.isSelected = state.textOpaqueBackground
        transparentButton.isSelected = !state.textOpaqueBackground
    }

    @objc private func fontChanged() {
        guard let family = fontPopup.titleOfSelectedItem else { return }
        if let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 12) {
            state.fontName = font.fontName
        } else {
            state.fontName = family
        }
    }

    @objc private func sizeChanged() {
        let v = CGFloat(sizeCombo.doubleValue)
        if v >= 1 && v <= 500 { state.fontSize = v }
    }
}

extension TextOptionsBar: NSComboBoxDelegate {
    func comboBoxSelectionDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.sizeChanged() }
    }
}
