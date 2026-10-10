import AppKit

/// Floating colour card pinned above the Layers card: Color 1 / Color 2 wells, a hex field, a gear menu for the
/// spectrum mode, the spectrum and HSV sliders under it. Every change applies to the target well immediately.
final class ColorPanelView: NSView {
    /// The card floats over the canvas, whose tracking area would otherwise keep its (invisible) brush cursor here.
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

    /// Height of the panel including the gap above the card (the Layers card below brings its own gap); a hue
    /// slider joins the others in the saturation × value mode.
    static var height: CGFloat { 8 + 10 + ColorWellsView.size.height + 10 + spectrumHeight + 10 + HSVSlidersView.height(for: AppSettings.spectrumMode) + 10 }
    private static let spectrumHeight: CGFloat = 120

    let state: ToolState
    private let card = GlassHost(cornerRadius: 10, material: .blur, shadow: true, veil: Theme.cardVeil)
    private let wells: ColorWellsView
    private let spectrum = SpectrumView()
    private let sliders = HSVSlidersView()
    private var gearButton: RibbonButton!
    private let hexField = NSTextField(string: "")
    private var hue: CGFloat = 0, saturation: CGFloat = 0, value: CGFloat = 0
    /// Set while this panel writes to `state`, so the change notification does not reset the HSV values.
    private var applying = false
    private var observers: [Any] = []

    private var color: NSColor { NSColor(colorSpace: .sRGB, hue: hue, saturation: saturation, brightness: value, alpha: 1) }

    init(state: ToolState) {
        self.state = state
        wells = ColorWellsView(state: state)
        super.init(frame: .zero)
        build()
        loadFromState()
        observers.append(NotificationCenter.default.addObserver(forName: .toolStateChanged, object: state, queue: .main) { [weak self] _ in
            self?.stateChanged()
        })
        observers.append(NotificationCenter.default.addObserver(forName: .settingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.applyMode()
        })
        applyMode()
    }

    required init?(coder: NSCoder) { fatalError() }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    override var isFlipped: Bool { true }

    private func build() {
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        let inner = card.content

        wells.translatesAutoresizingMaskIntoConstraints = false
        inner.addSubview(wells)

        hexField.translatesAutoresizingMaskIntoConstraints = false
        hexField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        hexField.alignment = .center
        hexField.controlSize = .small
        hexField.delegate = self
        hexField.toolTip = L("Hex")
        inner.addSubview(hexField)

        gearButton = RibbonButton(symbol: "gearshape", tooltip: L("Color picker style")) { [weak self] in self?.showModeMenu() }
        gearButton.preferredSize = NSSize(width: 24, height: 24)
        inner.addSubview(gearButton)

        spectrum.translatesAutoresizingMaskIntoConstraints = false
        spectrum.onChange = { [weak self] h, s, v in self?.edit(h, s, v) }
        inner.addSubview(spectrum)

        sliders.translatesAutoresizingMaskIntoConstraints = false
        sliders.onChange = { [weak self] h, s, v in self?.edit(h, s, v) }
        inner.addSubview(sliders)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            wells.topAnchor.constraint(equalTo: inner.topAnchor, constant: 10),
            wells.leadingAnchor.constraint(equalTo: inner.leadingAnchor, constant: 10),
            wells.widthAnchor.constraint(equalToConstant: ColorWellsView.size.width),
            wells.heightAnchor.constraint(equalToConstant: ColorWellsView.size.height),
            hexField.centerYAnchor.constraint(equalTo: wells.centerYAnchor),
            hexField.trailingAnchor.constraint(equalTo: gearButton.leadingAnchor, constant: -6),
            gearButton.centerYAnchor.constraint(equalTo: wells.centerYAnchor),
            gearButton.trailingAnchor.constraint(equalTo: inner.trailingAnchor, constant: -8),
            hexField.widthAnchor.constraint(equalToConstant: 64),
            spectrum.topAnchor.constraint(equalTo: wells.bottomAnchor, constant: 10),
            spectrum.leadingAnchor.constraint(equalTo: inner.leadingAnchor, constant: 10),
            spectrum.trailingAnchor.constraint(equalTo: inner.trailingAnchor, constant: -10),
            spectrum.heightAnchor.constraint(equalToConstant: Self.spectrumHeight),
            sliders.topAnchor.constraint(equalTo: spectrum.bottomAnchor, constant: 10),
            sliders.leadingAnchor.constraint(equalTo: spectrum.leadingAnchor),
            sliders.trailingAnchor.constraint(equalTo: spectrum.trailingAnchor),
            sliders.bottomAnchor.constraint(equalTo: inner.bottomAnchor, constant: -10),
        ])
    }

    // MARK: - State

    /// The gear's menu: the two spectrum modes, the current one checked.
    private func showModeMenu() {
        let menu = NSMenu()
        for mode in SpectrumMode.all {
            let item = NSMenuItem(title: mode.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.image = mode.thumbnail
            item.toolTip = mode.detail
            item.tag = mode.rawValue
            item.state = AppSettings.spectrumMode == mode ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: gearButton.bounds.maxY + 4), in: gearButton)
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        AppSettings.spectrumMode = SpectrumMode(rawValue: sender.tag) ?? .hueSaturation
    }

    private func applyMode() {
        spectrum.mode = AppSettings.spectrumMode
        sliders.mode = AppSettings.spectrumMode
    }

    private func edit(_ h: CGFloat, _ s: CGFloat, _ v: CGFloat) {
        hue = h; saturation = s; value = v
        apply()
    }

    private func setHSV(from c: NSColor) {
        let d = c.usingColorSpace(.sRGB) ?? c
        // Black and greys carry no hue / saturation; keep the current ones so the spectrum marker stays put.
        if d.brightnessComponent > 0 { saturation = d.saturationComponent }
        if d.brightnessComponent > 0, d.saturationComponent > 0 { hue = d.hueComponent }
        value = d.brightnessComponent
    }

    private func loadFromState() {
        setHSV(from: state.color(for: state.colorTarget))
        refreshViews()
    }

    private func stateChanged() {
        wells.needsDisplay = true
        guard !applying, state.color(for: state.colorTarget).hexString != color.hexString else { return }
        loadFromState()
    }

    /// Writes the edited colour into the target well.
    private func apply(updateHex: Bool = true) {
        applying = true
        if state.colorTarget == .primary { state.color1 = color } else { state.color2 = color }
        applying = false
        refreshViews(updateHex: updateHex)
    }

    private func refreshViews(updateHex: Bool = true) {
        spectrum.hue = hue; spectrum.saturation = saturation; spectrum.value = value
        sliders.set(hue: hue, saturation: saturation, value: value)
        if updateHex { hexField.stringValue = color.hexString }
        wells.needsDisplay = true
    }
}

extension ColorPanelView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        var s = hexField.stringValue.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, UInt32(s, radix: 16) != nil else { return }
        setHSV(from: NSColor(hex: s))
        apply(updateHex: false)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        hexField.stringValue = color.hexString
        window?.makeFirstResponder(nil)
    }
}

/// Color 1 and Color 2 side by side; clicking one makes it the well the editors change.
final class ColorWellsView: NSView {
    static let size = CGSize(width: 64, height: 30)
    let state: ToolState

    init(state: ToolState) {
        self.state = state
        super.init(frame: .zero)
        toolTip = L("Color 1") + " / " + L("Color 2")
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    private func wellRect(_ b: MouseButton) -> CGRect {
        CGRect(x: b == .primary ? 3 : 37, y: 3, width: 24, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        for b in [MouseButton.primary, .secondary] {
            let r = wellRect(b)
            ctx.setFillColor(state.color(for: b).cgColor)
            ctx.fillEllipse(in: r)
            ctx.setStrokeColor(Theme.controlBorder.cgColor)
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: r.insetBy(dx: 0.5, dy: 0.5))
            if state.colorTarget == b {
                ctx.setStrokeColor(Theme.accent.cgColor)
                ctx.setLineWidth(2)
                ctx.strokeEllipse(in: r.insetBy(dx: -2.5, dy: -2.5))
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for b in [MouseButton.primary, .secondary] where wellRect(b).insetBy(dx: -3, dy: -3).contains(p) {
            state.colorTarget = b
            return
        }
    }
}
