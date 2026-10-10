import AppKit

/// How the colour spectrum maps its two axes.
enum SpectrumMode: Int {
    /// Hue across, saturation down, drawn at full brightness; value lives on a slider.
    case hueSaturation = 0
    /// Saturation across, value down, for the current hue; hue lives on a slider.
    case saturationValue = 1

    static let all: [SpectrumMode] = [.hueSaturation, .saturationValue]

    var title: String { self == .hueSaturation ? L("Spectrum") : L("Shades") }

    var detail: String {
        self == .hueSaturation ? L("Hue × saturation spectrum, value on a slider") : L("Saturation × value square, hue on a slider")
    }

    /// A small picture of the spectrum for menus and switches (red as the square's hue).
    var thumbnail: NSImage {
        let mode = self
        return NSImage(size: NSSize(width: 16, height: 16), flipped: true) { r in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let box = r.insetBy(dx: 0.5, dy: 0.5)
            ctx.addPath(CGPath(roundedRect: box, cornerWidth: 3, cornerHeight: 3, transform: nil))
            ctx.clip()
            func gradient(_ colors: [NSColor], from a: CGPoint, to b: CGPoint) {
                if let g = CGGradient(colorsSpace: Bitmap.colorSpace, colors: colors.map(\.cgColor) as CFArray, locations: nil) {
                    ctx.drawLinearGradient(g, start: a, end: b, options: [])
                }
            }
            switch mode {
            case .hueSaturation:
                gradient(stride(from: 0, through: 6, by: 1).map { NSColor(colorSpace: .sRGB, hue: CGFloat($0) / 6, saturation: 1, brightness: 1, alpha: 1) },
                         from: CGPoint(x: box.minX, y: 0), to: CGPoint(x: box.maxX, y: 0))
                gradient([NSColor.white.withAlphaComponent(0), .white], from: CGPoint(x: 0, y: box.minY), to: CGPoint(x: 0, y: box.maxY))
            case .saturationValue:
                ctx.setFillColor(NSColor(colorSpace: .sRGB, hue: 0, saturation: 1, brightness: 1, alpha: 1).cgColor)
                ctx.fill(box)
                gradient([.white, NSColor.white.withAlphaComponent(0)], from: CGPoint(x: box.minX, y: 0), to: CGPoint(x: box.maxX, y: 0))
                gradient([NSColor.black.withAlphaComponent(0), .black], from: CGPoint(x: 0, y: box.minY), to: CGPoint(x: 0, y: box.maxY))
            }
            ctx.resetClip()
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.25).cgColor)
            ctx.setLineWidth(1)
            ctx.addPath(CGPath(roundedRect: box, cornerWidth: 3, cornerHeight: 3, transform: nil))
            ctx.strokePath()
            return true
        }
    }
}

/// Colour spectrum in either `SpectrumMode`. Reports the full HSV colour after a click or drag.
final class SpectrumView: NSView {
    var mode: SpectrumMode = .hueSaturation { didSet { needsDisplay = true } }
    var hue: CGFloat = 0 { didSet { needsDisplay = true } }
    var saturation: CGFloat = 1 { didSet { needsDisplay = true } }
    var value: CGFloat = 1 { didSet { needsDisplay = true } }
    var onChange: ((_ hue: CGFloat, _ saturation: CGFloat, _ value: CGFloat) -> Void)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = bounds
        let path = CGPath(roundedRect: r, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        let marker: CGPoint
        switch mode {
        case .hueSaturation:
            let hues = stride(from: 0, through: 6, by: 1).map { NSColor(colorSpace: .sRGB, hue: CGFloat($0) / 6, saturation: 1, brightness: 1, alpha: 1).cgColor }
            if let rainbow = CGGradient(colorsSpace: Bitmap.colorSpace, colors: hues as CFArray, locations: nil) {
                ctx.drawLinearGradient(rainbow, start: CGPoint(x: r.minX, y: 0), end: CGPoint(x: r.maxX, y: 0), options: [])
            }
            if let fade = CGGradient(colorsSpace: Bitmap.colorSpace,
                                     colors: [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.cgColor] as CFArray, locations: [0, 1]) {
                ctx.drawLinearGradient(fade, start: CGPoint(x: 0, y: r.minY), end: CGPoint(x: 0, y: r.maxY), options: [])
            }
            marker = CGPoint(x: r.minX + hue * r.width, y: r.minY + (1 - saturation) * r.height)
        case .saturationValue:
            ctx.setFillColor(NSColor(colorSpace: .sRGB, hue: hue, saturation: 1, brightness: 1, alpha: 1).cgColor)
            ctx.fill(r)
            if let white = CGGradient(colorsSpace: Bitmap.colorSpace,
                                      colors: [NSColor.white.cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1]) {
                ctx.drawLinearGradient(white, start: CGPoint(x: r.minX, y: 0), end: CGPoint(x: r.maxX, y: 0), options: [])
            }
            if let black = CGGradient(colorsSpace: Bitmap.colorSpace,
                                      colors: [NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.cgColor] as CFArray, locations: [0, 1]) {
                ctx.drawLinearGradient(black, start: CGPoint(x: 0, y: r.minY), end: CGPoint(x: 0, y: r.maxY), options: [])
            }
            marker = CGPoint(x: r.minX + saturation * r.width, y: r.minY + (1 - value) * r.height)
        }
        ctx.restoreGState()
        let ring = CGRect(x: marker.x - 7, y: marker.y - 7, width: 14, height: 14)
        ctx.setLineWidth(2.5)
        ctx.setStrokeColor(NSColor.white.cgColor); ctx.strokeEllipse(in: ring)
        ctx.setLineWidth(1)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.5).cgColor); ctx.strokeEllipse(in: ring.insetBy(dx: -1.5, dy: -1.5))
    }

    private func update(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let fx = max(0, min(1, p.x / bounds.width)), fy = max(0, min(1, 1 - p.y / bounds.height))
        switch mode {
        case .hueSaturation: onChange?(fx, fy, value)
        case .saturationValue: onChange?(hue, fx, fy)
        }
    }

    override func mouseDown(with event: NSEvent) { update(with: event) }
    override func mouseDragged(with event: NSEvent) { update(with: event) }
}

/// HSV sliders next to a spectrum: saturation and value, plus hue first when the spectrum is a
/// saturation × value square. Horizontal sliders stack in rows, vertical ones stand in columns. Each track
/// shows the colours that position would produce.
final class HSVSlidersView: NSView {
    static let rowHeight: CGFloat = 20, rowGap: CGFloat = 6
    static let columnWidth: CGFloat = 24, columnGap: CGFloat = 8

    static func sliderCount(for mode: SpectrumMode) -> CGFloat { mode == .saturationValue ? 3 : 2 }

    /// Height of the horizontal layout.
    static func height(for mode: SpectrumMode) -> CGFloat {
        sliderCount(for: mode) * rowHeight + (sliderCount(for: mode) - 1) * rowGap
    }

    /// Width of the vertical layout.
    static func width(for mode: SpectrumMode) -> CGFloat {
        sliderCount(for: mode) * columnWidth + (sliderCount(for: mode) - 1) * columnGap
    }

    let vertical: Bool

    var mode: SpectrumMode = .hueSaturation {
        didSet { hueSlider.isHidden = mode == .hueSaturation; needsLayout = true }
    }
    var onChange: ((_ hue: CGFloat, _ saturation: CGFloat, _ value: CGFloat) -> Void)?

    private var hue: CGFloat = 0, saturation: CGFloat = 0, value: CGFloat = 0
    private let hueSlider = GradientSliderView()
    private let saturationSlider = GradientSliderView()
    private let valueSlider = GradientSliderView()

    init(vertical: Bool = false) {
        self.vertical = vertical
        super.init(frame: .zero)
        [hueSlider, saturationSlider, valueSlider].forEach { $0.vertical = vertical }
        hueSlider.toolTip = L("Hue")
        saturationSlider.toolTip = L("Saturation")
        valueSlider.toolTip = L("Value")
        hueSlider.isHidden = true
        hueSlider.onChange = { [weak self] h in guard let self else { return }; self.onChange?(h, self.saturation, self.value) }
        saturationSlider.onChange = { [weak self] s in guard let self else { return }; self.onChange?(self.hue, s, self.value) }
        valueSlider.onChange = { [weak self] v in guard let self else { return }; self.onChange?(self.hue, self.saturation, v) }
        [hueSlider, saturationSlider, valueSlider].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        var offset: CGFloat = 0
        for slider in [hueSlider, saturationSlider, valueSlider] where !slider.isHidden {
            if vertical {
                slider.frame = CGRect(x: offset, y: 0, width: Self.columnWidth, height: bounds.height)
                offset += Self.columnWidth + Self.columnGap
            } else {
                slider.frame = CGRect(x: 0, y: offset, width: bounds.width, height: Self.rowHeight)
                offset += Self.rowHeight + Self.rowGap
            }
        }
    }

    func set(hue: CGFloat, saturation: CGFloat, value: CGFloat) {
        self.hue = hue; self.saturation = saturation; self.value = value
        func hsv(_ h: CGFloat, _ s: CGFloat, _ v: CGFloat) -> NSColor { NSColor(colorSpace: .sRGB, hue: h, saturation: s, brightness: v, alpha: 1) }
        let current = hsv(hue, saturation, value)
        hueSlider.set(position: hue, colors: stride(from: 0, through: 6, by: 1).map { hsv(CGFloat($0) / 6, 1, 1) }, knob: hsv(hue, 1, 1))
        saturationSlider.set(position: saturation, colors: [hsv(hue, 0, value), hsv(hue, 1, value)], knob: current)
        valueSlider.set(position: value, colors: [.black, hsv(hue, saturation, 1)], knob: current)
    }
}

/// Slider over a gradient track; reports a position from 0 (left / bottom) to 1 (right / top).
final class GradientSliderView: NSView {
    var onChange: ((CGFloat) -> Void)?
    var vertical = false { didSet { needsDisplay = true } }
    private var position: CGFloat = 0
    private var colors: [NSColor] = [.black, .white]
    private var knobColor: NSColor = .black

    func set(position: CGFloat, colors: [NSColor], knob: NSColor) {
        self.position = position; self.colors = colors; knobColor = knob
        needsDisplay = true
    }

    override var isFlipped: Bool { true }

    private var track: CGRect {
        vertical ? CGRect(x: bounds.midX - 5, y: bounds.minY + 8, width: 10, height: bounds.height - 16)
                 : CGRect(x: bounds.minX + 8, y: bounds.midY - 5, width: bounds.width - 16, height: 10)
    }

    /// Knob centre for `position` along the track.
    private func knobCenter(_ t: CGRect) -> CGPoint {
        vertical ? CGPoint(x: t.midX, y: t.maxY - position * t.height) : CGPoint(x: t.minX + position * t.width, y: t.midY)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let t = track
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: t, cornerWidth: 5, cornerHeight: 5, transform: nil)); ctx.clip()
        if let g = CGGradient(colorsSpace: Bitmap.colorSpace, colors: colors.map(\.cgColor) as CFArray, locations: nil) {
            let (start, end) = vertical ? (CGPoint(x: 0, y: t.maxY), CGPoint(x: 0, y: t.minY))
                                        : (CGPoint(x: t.minX, y: 0), CGPoint(x: t.maxX, y: 0))
            ctx.drawLinearGradient(g, start: start, end: end, options: [])
        }
        ctx.restoreGState()
        let c = knobCenter(t)
        let knob = CGRect(x: c.x - 8, y: c.y - 8, width: 16, height: 16)
        ctx.setFillColor(knobColor.cgColor)
        ctx.fillEllipse(in: knob)
        ctx.setLineWidth(2.5)
        ctx.setStrokeColor(NSColor.white.cgColor); ctx.strokeEllipse(in: knob)
        ctx.setLineWidth(1)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.4).cgColor); ctx.strokeEllipse(in: knob.insetBy(dx: -1.5, dy: -1.5))
    }

    private func update(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let t = track
        let f = vertical ? (t.maxY - p.y) / t.height : (p.x - t.minX) / t.width
        onChange?(max(0, min(1, f)))
    }

    override func mouseDown(with event: NSEvent) { update(with: event) }
    override func mouseDragged(with event: NSEvent) { update(with: event) }
}

/// Two-segment switch for `AppSettings.spectrumMode`; every instance follows the shared setting.
final class SpectrumModeControl: NSSegmentedControl {
    private var observer: Any?

    convenience init() {
        self.init(labels: SpectrumMode.all.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
        target = self
        action = #selector(changed)
        for mode in SpectrumMode.all {
            setImage(mode.thumbnail, forSegment: mode.rawValue)
            setImageScaling(.scaleNone, forSegment: mode.rawValue)
            setToolTip(mode.detail, forSegment: mode.rawValue)
        }
        selectedSegment = AppSettings.spectrumMode.rawValue
        observer = NotificationCenter.default.addObserver(forName: .settingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.selectedSegment = AppSettings.spectrumMode.rawValue
        }
    }

    deinit { if let o = observer { NotificationCenter.default.removeObserver(o) } }

    @objc private func changed() {
        AppSettings.spectrumMode = SpectrumMode(rawValue: selectedSegment) ?? .hueSaturation
    }
}
