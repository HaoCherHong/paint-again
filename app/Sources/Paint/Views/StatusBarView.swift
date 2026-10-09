import AppKit

/// Bottom status bar: cursor position, selection size, image size, zoom controls.
final class StatusBarView: NSView {
    private let cursorLabel = NSTextField(labelWithString: "")
    private let selectionLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let zoomPopup = NSPopUpButton()
    private let slider = NSSlider()
    private var updating = false
    var onZoomChanged: ((CGFloat) -> Void)?
    var onZoomIn: (() -> Void)?
    var onZoomOut: (() -> Void)?

    init() {
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.glassBand.setFill()
        bounds.fill(using: .sourceOver)
        Theme.divider.setFill()
        CGRect(x: 0, y: 0, width: bounds.width, height: 1).fill(using: .sourceOver)
    }

    private func item(_ symbol: String, _ label: NSTextField, minWidth: CGFloat) -> NSView {
        let h = NSStackView()
        h.orientation = .horizontal
        h.spacing = 6
        let icon = NSImageView(image: Theme.symbol(symbol, size: 13)?.tinted(Theme.secondaryText) ?? NSImage())
        h.addArrangedSubview(icon)
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = Theme.text
        h.addArrangedSubview(label)
        h.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth).isActive = true
        return h
    }

    private func build() {
        let left = NSStackView()
        left.orientation = .horizontal
        left.spacing = 18
        left.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 0)
        left.translatesAutoresizingMaskIntoConstraints = false
        left.addArrangedSubview(item("cursorarrow", cursorLabel, minWidth: 120))
        left.addArrangedSubview(item("rectangle.dashed", selectionLabel, minWidth: 120))
        left.addArrangedSubview(item("square.dashed", sizeLabel, minWidth: 120))
        addSubview(left)

        let right = NSStackView()
        right.orientation = .horizontal
        right.spacing = 6
        right.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 12)
        right.translatesAutoresizingMaskIntoConstraints = false
        zoomPopup.controlSize = .small
        zoomPopup.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        for z in Theme.zoomLevels { zoomPopup.addItem(withTitle: Self.format(z)) }
        zoomPopup.target = self
        zoomPopup.action = #selector(popupChanged)
        zoomPopup.widthAnchor.constraint(equalToConstant: 76).isActive = true
        let minus = RibbonButton(symbol: "minus.magnifyingglass", tooltip: Theme.tip(L("Zoom out"), "⌘−")) { [weak self] in self?.onZoomOut?() }
        minus.preferredSize = NSSize(width: 24, height: 22)
        let plus = RibbonButton(symbol: "plus.magnifyingglass", tooltip: Theme.tip(L("Zoom in"), "⌘+")) { [weak self] in self?.onZoomIn?() }
        plus.preferredSize = NSSize(width: 24, height: 22)
        slider.minValue = -3
        slider.maxValue = 3
        slider.doubleValue = 0
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.widthAnchor.constraint(equalToConstant: 120).isActive = true
        right.addArrangedSubview(zoomPopup)
        right.addArrangedSubview(minus)
        right.addArrangedSubview(slider)
        right.addArrangedSubview(plus)
        addSubview(right)

        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: leadingAnchor),
            left.centerYAnchor.constraint(equalTo: centerYAnchor),
            right.trailingAnchor.constraint(equalTo: trailingAnchor),
            right.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private static func format(_ z: CGFloat) -> String {
        let pct = z * 100
        return pct == pct.rounded() ? "\(Int(pct))%" : String(format: "%.1f%%", pct)
    }

    @objc private func sliderChanged() {
        guard !updating else { return }
        onZoomChanged?(pow(2, CGFloat(slider.doubleValue)))
    }

    @objc private func popupChanged() {
        guard !updating, zoomPopup.indexOfSelectedItem >= 0, zoomPopup.indexOfSelectedItem < Theme.zoomLevels.count else { return }
        onZoomChanged?(Theme.zoomLevels[zoomPopup.indexOfSelectedItem])
    }

    func setCursor(_ p: CGPoint?) {
        cursorLabel.stringValue = p.map { "\(Int($0.x)), \(Int($0.y)) px" } ?? ""
    }

    func setSelection(_ s: CGSize?) {
        selectionLabel.stringValue = s.map { "\(Int($0.width)) × \(Int($0.height)) px" } ?? ""
    }

    func setImageSize(_ s: CGSize) {
        sizeLabel.stringValue = "\(Int(s.width)) × \(Int(s.height)) px"
    }

    func setZoom(_ z: CGFloat) {
        updating = true
        slider.doubleValue = Double(log2(z))
        if let i = Theme.zoomLevels.firstIndex(where: { abs($0 - z) < 0.001 }) {
            if zoomPopup.numberOfItems > Theme.zoomLevels.count { zoomPopup.removeItem(at: zoomPopup.numberOfItems - 1) }
            zoomPopup.selectItem(at: i)
        } else {
            if zoomPopup.numberOfItems > Theme.zoomLevels.count { zoomPopup.removeItem(at: zoomPopup.numberOfItems - 1) }
            zoomPopup.addItem(withTitle: "\(Int((z * 100).rounded()))%")
            zoomPopup.selectItem(at: zoomPopup.numberOfItems - 1)
        }
        updating = false
    }
}
