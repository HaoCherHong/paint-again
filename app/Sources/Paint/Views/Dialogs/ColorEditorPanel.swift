import AppKit

/// "Edit colors" sheet: hue × saturation spectrum, a vertical preview bar,
/// a vertical value slider, hex / RGB / HSV fields, a Basic colors grid and user-managed Custom colors.
final class ColorEditorPanel: NSObject {
    private let window: NSWindow
    private let state: ToolState
    private let spectrum = SpectrumView()
    private let valueSlider = ValueSliderView()
    private let preview = NSView()
    private let hexField = NSTextField(string: "")
    private let modelPopup = NSPopUpButton()
    private let fields = [NSTextField(string: ""), NSTextField(string: ""), NSTextField(string: "")]
    private let fieldLabels = [NSTextField(labelWithString: ""), NSTextField(labelWithString: ""), NSTextField(labelWithString: "")]
    private var basicGrid: SwatchGridView!
    private var customGrid: SwatchGridView!
    private var hue: CGFloat = 0, saturation: CGFloat = 1, value: CGFloat = 1
    /// Custom slot that "+" writes into; selecting a slot also applies its colour.
    private var selectedSlot: Int?
    private var updatingFields = false
    private let completion: (NSColor?) -> Void

    private var isHSV: Bool { modelPopup.indexOfSelectedItem == 1 }
    var color: NSColor { NSColor(colorSpace: .sRGB, hue: hue, saturation: saturation, brightness: value, alpha: 1) }

    static let basicColors: [NSColor] = [
        "#E8837A", "#F03A2E", "#B85C57", "#B36A5E", "#7A1C1C", "#6CF3E8", "#3EE0D5", "#3B8BEA", "#2456F5", "#1A2ECC", "#2F8FE0", "#1D3FA8",
        "#F9E86F", "#F4E020", "#F0A040", "#EE6C2C", "#8B5A1A", "#A9A03A", "#9A7BEA", "#6A2FD0", "#4A7CC9", "#0A1650", "#7A2CB8", "#56147A",
        "#8CF08A", "#4EE054", "#48C548", "#2BD85A", "#23C453", "#8A9A3A", "#F58AC0", "#F0A6E0", "#F04CF0", "#E03A8A", "#8C8CF0", "#B02A6A",
        "#3BA02E", "#1F8F5A", "#1C9C8C", "#1F8F70", "#1F7A2C", "#245F5A", "#7B1FA2", "#5A1FA8", "#000000", "#7A7A7A", "#C8C8C8", "#FFFFFF",
    ].map { NSColor(hex: $0) }

    static func present(on parent: NSWindow, initial: NSColor, state: ToolState, completion: @escaping (NSColor?) -> Void) {
        let panel = ColorEditorPanel(initial: initial, state: state, completion: completion)
        parent.beginSheet(panel.window) { _ in }
        activePanels.append(panel)
    }

    private static var activePanels: [ColorEditorPanel] = []

    private init(initial: NSColor, state: ToolState, completion: @escaping (NSColor?) -> Void) {
        self.completion = completion
        self.state = state
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 620), styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        setColor(initial)
        build()
        syncFromHSV()
    }

    // MARK: - Layout (window coordinates, y up)

    private func build() {
        let root = NSView(frame: window.contentView!.bounds)
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.chromeBackground.cgColor
        window.contentView = root

        let title = NSTextField(labelWithString: L("Edit colors"))
        title.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        title.textColor = Theme.text
        title.frame = NSRect(x: 24, y: 576, width: 300, height: 26)
        root.addSubview(title)

        spectrum.frame = NSRect(x: 24, y: 300, width: 256, height: 256)
        spectrum.onChange = { [weak self] h, s in
            guard let self else { return }
            self.hue = h; self.saturation = s
            self.syncFromHSV()
        }
        root.addSubview(spectrum)

        preview.wantsLayer = true
        preview.layer?.cornerRadius = 6
        preview.frame = NSRect(x: 296, y: 300, width: 40, height: 256)
        root.addSubview(preview)

        valueSlider.frame = NSRect(x: 348, y: 300, width: 24, height: 256)
        valueSlider.onChange = { [weak self] v in
            guard let self else { return }
            self.value = v
            self.syncFromHSV()
        }
        root.addSubview(valueSlider)

        hexField.frame = NSRect(x: 396, y: 526, width: 130, height: 26)
        hexField.delegate = self
        hexField.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        root.addSubview(hexField)

        modelPopup.addItems(withTitles: ["RGB", "HSV"])
        modelPopup.frame = NSRect(x: 396, y: 484, width: 130, height: 26)
        modelPopup.target = self
        modelPopup.action = #selector(modelChanged)
        root.addSubview(modelPopup)

        for i in 0..<3 {
            let y = 438 - CGFloat(i) * 44
            fields[i].frame = NSRect(x: 396, y: y, width: 130, height: 26)
            fields[i].alignment = .left
            fields[i].delegate = self
            fields[i].font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            root.addSubview(fields[i])
            fieldLabels[i].frame = NSRect(x: 536, y: y + 3, width: 90, height: 20)
            fieldLabels[i].textColor = Theme.text
            root.addSubview(fieldLabels[i])
        }

        let basicTitle = NSTextField(labelWithString: L("Basic colors"))
        basicTitle.textColor = Theme.text
        basicTitle.frame = NSRect(x: 24, y: 258, width: 200, height: 20)
        root.addSubview(basicTitle)
        basicGrid = SwatchGridView(columns: 12, rows: 4) { [weak self] _, color in
            if let color { self?.pick(color) }
        }
        basicGrid.colors = Self.basicColors
        basicGrid.highlightsMatchingColor = true
        basicGrid.frame = NSRect(x: 24, y: 130, width: 12 * 30, height: 4 * 30)
        root.addSubview(basicGrid)

        let customTitle = NSTextField(labelWithString: L("Custom colors"))
        customTitle.textColor = Theme.text
        customTitle.frame = NSRect(x: 410, y: 258, width: 160, height: 20)
        root.addSubview(customTitle)
        let add = NSButton(image: Theme.symbol("plus", size: 12)?.tinted(Theme.text) ?? NSImage(), target: self, action: #selector(addCustom))
        add.bezelStyle = .smallSquare
        add.isBordered = true
        add.toolTip = L("Add current color to custom colors")
        add.frame = NSRect(x: 596, y: 254, width: 26, height: 26)
        root.addSubview(add)
        customGrid = SwatchGridView(columns: 6, rows: 4) { [weak self] index, color in
            guard let self else { return }
            self.selectedSlot = index
            self.customGrid.selectedIndex = index
            if let color { self.pick(color) }
        }
        customGrid.colors = state.customColors
        selectedSlot = state.firstEmptyCustomSlot
        customGrid.selectedIndex = selectedSlot
        customGrid.frame = NSRect(x: 410, y: 130, width: 6 * 30, height: 4 * 30)
        root.addSubview(customGrid)

        let ok = NSButton(title: L("OK"), target: self, action: #selector(okPressed))
        ok.keyEquivalent = "\r"
        ok.bezelStyle = .rounded
        ok.controlSize = .large
        ok.bezelColor = Theme.accent
        ok.frame = NSRect(x: 24, y: 28, width: 300, height: 34)
        root.addSubview(ok)
        let cancel = NSButton(title: L("Cancel"), target: self, action: #selector(cancelPressed))
        cancel.keyEquivalent = "\u{1b}"
        cancel.bezelStyle = .rounded
        cancel.controlSize = .large
        cancel.frame = NSRect(x: 336, y: 28, width: 300, height: 34)
        root.addSubview(cancel)
    }

    // MARK: - State

    private func setColor(_ c: NSColor) {
        let d = c.usingColorSpace(.sRGB) ?? c
        hue = d.hueComponent; saturation = d.saturationComponent; value = d.brightnessComponent
    }

    private func pick(_ c: NSColor) {
        setColor(c)
        syncFromHSV()
    }

    private func syncFromHSV() {
        spectrum.hue = hue; spectrum.saturation = saturation
        valueSlider.hue = hue; valueSlider.saturation = saturation; valueSlider.value = value
        preview.layer?.backgroundColor = color.cgColor
        basicGrid?.selected = color
        updateFields()
    }

    private func updateFields() {
        updatingFields = true
        defer { updatingFields = false }
        let c = color
        if isHSV {
            fieldLabels[0].stringValue = L("Hue"); fieldLabels[1].stringValue = L("Saturation"); fieldLabels[2].stringValue = L("Value")
            fields[0].stringValue = "\(Int((hue * 360).rounded()) % 360)"
            fields[1].stringValue = "\(Int((saturation * 100).rounded()))"
            fields[2].stringValue = "\(Int((value * 100).rounded()))"
        } else {
            fieldLabels[0].stringValue = L("Red"); fieldLabels[1].stringValue = L("Green"); fieldLabels[2].stringValue = L("Blue")
            fields[0].stringValue = "\(Int((c.redComponent * 255).rounded()))"
            fields[1].stringValue = "\(Int((c.greenComponent * 255).rounded()))"
            fields[2].stringValue = "\(Int((c.blueComponent * 255).rounded()))"
        }
        hexField.stringValue = c.hexString
    }

    @objc private func modelChanged() { updateFields() }

    /// Writes the current colour into the selected slot (or the first empty one) and moves the selection on.
    @objc private func addCustom() {
        let index = selectedSlot ?? state.firstEmptyCustomSlot ?? (ToolState.maxCustomColors - 1)
        state.setCustomColor(color, at: index)
        customGrid.colors = state.customColors
        selectedSlot = min(index + 1, ToolState.maxCustomColors - 1)
        customGrid.selectedIndex = selectedSlot
    }

    @objc private func okPressed() {
        window.sheetParent?.endSheet(window)
        completion(color)
        Self.activePanels.removeAll { $0 === self }
    }

    @objc private func cancelPressed() {
        window.sheetParent?.endSheet(window)
        completion(nil)
        Self.activePanels.removeAll { $0 === self }
    }
}

extension ColorEditorPanel: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard !updatingFields, let field = obj.object as? NSTextField else { return }
        if field === hexField {
            var s = hexField.stringValue.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("#") { s.removeFirst() }
            guard s.count == 6, UInt32(s, radix: 16) != nil else { return }
            setColor(NSColor(hex: s))
            updatingFields = true
            spectrum.hue = hue; spectrum.saturation = saturation
            valueSlider.hue = hue; valueSlider.saturation = saturation; valueSlider.value = value
            preview.layer?.backgroundColor = color.cgColor
            let c = color
            if isHSV {
                fields[0].stringValue = "\(Int((hue * 360).rounded()) % 360)"; fields[1].stringValue = "\(Int((saturation * 100).rounded()))"; fields[2].stringValue = "\(Int((value * 100).rounded()))"
            } else {
                fields[0].stringValue = "\(Int((c.redComponent * 255).rounded()))"; fields[1].stringValue = "\(Int((c.greenComponent * 255).rounded()))"; fields[2].stringValue = "\(Int((c.blueComponent * 255).rounded()))"
            }
            updatingFields = false
            return
        }
        let values = fields.map { Double($0.stringValue) ?? 0 }
        if isHSV {
            hue = CGFloat(max(0, min(360, values[0]))) / 360
            saturation = CGFloat(max(0, min(100, values[1]))) / 100
            value = CGFloat(max(0, min(100, values[2]))) / 100
        } else {
            setColor(NSColor(srgbRed: CGFloat(max(0, min(255, values[0]))) / 255, green: CGFloat(max(0, min(255, values[1]))) / 255,
                             blue: CGFloat(max(0, min(255, values[2]))) / 255, alpha: 1))
        }
        spectrum.hue = hue; spectrum.saturation = saturation
        valueSlider.hue = hue; valueSlider.saturation = saturation; valueSlider.value = value
        preview.layer?.backgroundColor = color.cgColor
        updatingFields = true
        hexField.stringValue = color.hexString
        updatingFields = false
    }
}

/// Hue (horizontal) × saturation (vertical) spectrum rendered at full brightness.
final class SpectrumView: NSView {
    var hue: CGFloat = 0 { didSet { needsDisplay = true } }
    var saturation: CGFloat = 1 { didSet { needsDisplay = true } }
    var onChange: ((CGFloat, CGFloat) -> Void)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = bounds
        let path = CGPath(roundedRect: r, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        let hues = stride(from: 0, through: 6, by: 1).map { NSColor(colorSpace: .sRGB, hue: CGFloat($0) / 6, saturation: 1, brightness: 1, alpha: 1).cgColor }
        if let rainbow = CGGradient(colorsSpace: Bitmap.colorSpace, colors: hues as CFArray, locations: nil) {
            ctx.drawLinearGradient(rainbow, start: CGPoint(x: r.minX, y: 0), end: CGPoint(x: r.maxX, y: 0), options: [])
        }
        if let fade = CGGradient(colorsSpace: Bitmap.colorSpace,
                                 colors: [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.cgColor] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(fade, start: CGPoint(x: 0, y: r.minY), end: CGPoint(x: 0, y: r.maxY), options: [])
        }
        ctx.restoreGState()
        let p = CGPoint(x: r.minX + hue * r.width, y: r.minY + (1 - saturation) * r.height)
        let ring = CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)
        ctx.setLineWidth(2.5)
        ctx.setStrokeColor(NSColor.white.cgColor); ctx.strokeEllipse(in: ring)
        ctx.setLineWidth(1)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.5).cgColor); ctx.strokeEllipse(in: ring.insetBy(dx: -1.5, dy: -1.5))
    }

    private func update(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        onChange?(max(0, min(1, p.x / bounds.width)), max(0, min(1, 1 - p.y / bounds.height)))
    }

    override func mouseDown(with event: NSEvent) { update(with: event) }
    override func mouseDragged(with event: NSEvent) { update(with: event) }
}

/// Vertical brightness slider: the current hue / saturation at full brightness on top, black at the bottom.
final class ValueSliderView: NSView {
    var hue: CGFloat = 0 { didSet { needsDisplay = true } }
    var saturation: CGFloat = 1 { didSet { needsDisplay = true } }
    var value: CGFloat = 1 { didSet { needsDisplay = true } }
    var onChange: ((CGFloat) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let track = CGRect(x: bounds.midX - 5, y: bounds.minY + 8, width: 10, height: bounds.height - 16)
        let path = CGPath(roundedRect: track, cornerWidth: 5, cornerHeight: 5, transform: nil)
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        let bright = NSColor(colorSpace: .sRGB, hue: hue, saturation: saturation, brightness: 1, alpha: 1).cgColor
        if let g = CGGradient(colorsSpace: Bitmap.colorSpace, colors: [NSColor.black.cgColor, bright] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: track.minY), end: CGPoint(x: 0, y: track.maxY), options: [])
        }
        ctx.restoreGState()
        let y = track.minY + value * track.height
        let knob = CGRect(x: bounds.midX - 8, y: y - 8, width: 16, height: 16)
        ctx.setFillColor(NSColor(colorSpace: .sRGB, hue: hue, saturation: saturation, brightness: value, alpha: 1).cgColor)
        ctx.fillEllipse(in: knob)
        ctx.setLineWidth(2.5)
        ctx.setStrokeColor(NSColor.white.cgColor); ctx.strokeEllipse(in: knob)
        ctx.setLineWidth(1)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.4).cgColor); ctx.strokeEllipse(in: knob.insetBy(dx: -1.5, dy: -1.5))
    }

    private func update(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let track = CGRect(x: 0, y: bounds.minY + 8, width: bounds.width, height: bounds.height - 16)
        onChange?(max(0, min(1, (p.y - track.minY) / track.height)))
    }

    override func mouseDown(with event: NSEvent) { update(with: event) }
    override func mouseDragged(with event: NSEvent) { update(with: event) }
}

/// Grid of round swatches; empty slots are drawn as dashed circles. Reports the tapped slot and its colour.
final class SwatchGridView: NSView {
    let columns: Int, rows: Int
    var colors: [NSColor?] = [] { didSet { needsDisplay = true } }
    /// Colour to ring when `highlightsMatchingColor` is on (Basic colors).
    var selected: NSColor? { didSet { needsDisplay = true } }
    var highlightsMatchingColor = false
    /// Slot to ring regardless of colour (Custom colors).
    var selectedIndex: Int? { didSet { needsDisplay = true } }
    private let onSelect: (Int, NSColor?) -> Void
    private let cell: CGFloat = 30, diameter: CGFloat = 20

    init(columns: Int, rows: Int, onSelect: @escaping (Int, NSColor?) -> Void) {
        self.columns = columns; self.rows = rows; self.onSelect = onSelect
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    private func rect(_ index: Int) -> CGRect {
        let c = index % columns, r = index / columns
        return CGRect(x: CGFloat(c) * cell + (cell - diameter) / 2, y: CGFloat(r) * cell + (cell - diameter) / 2, width: diameter, height: diameter)
    }

    private func color(at index: Int) -> NSColor? { index < colors.count ? colors[index] : nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        for i in 0..<(columns * rows) {
            let r = rect(i)
            if let c = color(at: i) {
                ctx.setFillColor(c.cgColor)
                ctx.fillEllipse(in: r)
                ctx.setStrokeColor(Theme.controlBorder.cgColor)
                ctx.setLineWidth(1)
                ctx.strokeEllipse(in: r.insetBy(dx: 0.5, dy: 0.5))
            } else {
                ctx.saveGState()
                ctx.setStrokeColor(Theme.strongDivider.cgColor)
                ctx.setLineWidth(1)
                ctx.setLineDash(phase: 0, lengths: [2.5, 2.5])
                ctx.strokeEllipse(in: r.insetBy(dx: 0.5, dy: 0.5))
                ctx.restoreGState()
            }
            let ringed = (selectedIndex == i) || (highlightsMatchingColor && selected != nil && color(at: i).map { $0.isSameColor(as: selected!) } == true)
            if ringed {
                ctx.setStrokeColor(Theme.text.cgColor)
                ctx.setLineWidth(1.5)
                ctx.strokeEllipse(in: r.insetBy(dx: -3, dy: -3))
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for i in 0..<(columns * rows) where rect(i).insetBy(dx: -4, dy: -4).contains(p) {
            onSelect(i, color(at: i))
            return
        }
    }
}
