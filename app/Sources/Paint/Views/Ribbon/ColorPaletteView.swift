import AppKit

/// The Colors group: Color 1 / Color 2 wells, the fixed palette, custom colors and the Edit colors wheel.
final class ColorPaletteView: NSView {
    let state: ToolState
    /// Which well receives palette clicks.
    var target: MouseButton {
        get { state.colorTarget }
        set { state.colorTarget = newValue }
    }
    var onEditColors: (() -> Void)?

    private let swatch: CGFloat = 16
    private let gap: CGFloat = 4
    private var hovered: Int?
    private var trackingArea: NSTrackingArea?
    private var observer: Any?

    init(state: ToolState) {
        self.state = state
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        observer = NotificationCenter.default.addObserver(forName: .toolStateChanged, object: state, queue: .main) { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) { fatalError() }
    deinit { if let o = observer { NotificationCenter.default.removeObserver(o) } }

    override var isFlipped: Bool { true }

    private var paletteOrigin: CGPoint { CGPoint(x: 50, y: 2) }
    private var paletteWidth: CGFloat { 10 * swatch + 9 * gap }
    private var editRect: CGRect { CGRect(x: paletteOrigin.x + paletteWidth + 12, y: 4, width: 24, height: 24) }

    override var intrinsicContentSize: NSSize { NSSize(width: editRect.maxX + 4, height: 60) }

    private func wellRect(_ b: MouseButton) -> CGRect {
        b == .primary ? CGRect(x: 4, y: 2, width: 28, height: 28) : CGRect(x: 7, y: 36, width: 22, height: 22)
    }

    private func swatchRect(_ index: Int) -> CGRect {
        let col = index % 10, row = index / 10
        return CGRect(x: paletteOrigin.x + CGFloat(col) * (swatch + gap), y: paletteOrigin.y + CGFloat(row) * (swatch + gap), width: swatch, height: swatch)
    }

    private func swatchColor(_ index: Int) -> NSColor? {
        if index < 20 { return ToolState.paletteColors[index] }
        let i = index - 20
        return i < state.customColors.count ? state.customColors[i] : nil   // first 10 of the 24 custom slots
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        for b in [MouseButton.primary, .secondary] {
            let r = wellRect(b)
            drawCircle(state.color(for: b), in: r, ctx)
            if target == b {
                ctx.setStrokeColor(Theme.accent.cgColor)
                ctx.setLineWidth(2)
                ctx.strokeEllipse(in: r.insetBy(dx: -3.5, dy: -3.5))
            }
        }
        for i in 0..<30 {
            let r = swatchRect(i)
            if let c = swatchColor(i) {
                drawCircle(c, in: r, ctx)
                if hovered == i {
                    ctx.setStrokeColor(Theme.accent.cgColor)
                    ctx.setLineWidth(1.5)
                    ctx.strokeEllipse(in: r.insetBy(dx: -2, dy: -2))
                }
            } else {
                ctx.setStrokeColor(Theme.strongDivider.cgColor)
                ctx.setLineWidth(1)
                ctx.strokeEllipse(in: r.insetBy(dx: 0.5, dy: 0.5))
            }
        }
        drawWheel(in: editRect, ctx)
        if hovered == -1 {
            ctx.setStrokeColor(Theme.accent.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: editRect.insetBy(dx: -2.5, dy: -2.5))
        }
    }

    private func drawCircle(_ color: NSColor, in r: CGRect, _ ctx: CGContext) {
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: r)
        ctx.setStrokeColor(Theme.controlBorder.cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: r.insetBy(dx: 0.5, dy: 0.5))
    }

    private func drawWheel(in r: CGRect, _ ctx: CGContext) {
        let c = CGPoint(x: r.midX, y: r.midY), rad = r.width / 2
        let n = 24
        for i in 0..<n {
            let a0 = CGFloat(i) / CGFloat(n) * 2 * .pi, a1 = CGFloat(i + 1) / CGFloat(n) * 2 * .pi + 0.02
            ctx.setFillColor(NSColor(colorSpace: .sRGB, hue: CGFloat(i) / CGFloat(n), saturation: 0.9, brightness: 1, alpha: 1).cgColor)
            ctx.move(to: c)
            ctx.addArc(center: c, radius: rad, startAngle: a0, endAngle: a1, clockwise: false)
            ctx.closePath()
            ctx.fillPath()
        }
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x - rad * 0.32, y: c.y - rad * 0.32, width: rad * 0.64, height: rad * 0.64))
    }

    private func hitIndex(_ p: CGPoint) -> Int? {
        for i in 0..<30 where swatchRect(i).insetBy(dx: -2, dy: -2).contains(p) { return i }
        if editRect.insetBy(dx: -3, dy: -3).contains(p) { return -1 }
        return nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseMoved(with event: NSEvent) {
        hovered = hitIndex(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) { hovered = nil; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { handleClick(event, button: .primary) }
    override func rightMouseDown(with event: NSEvent) { handleClick(event, button: .secondary) }

    /// A click picks a well or a colour; a left double-click on a well or a filled swatch then opens Edit colors
    /// on the target well (the first click has already applied the swatch).
    private func handleClick(_ event: NSEvent, button: MouseButton) {
        let p = convert(event.locationInWindow, from: nil)
        let opensEditor = button == .primary && event.clickCount == 2
        if wellRect(.primary).insetBy(dx: -4, dy: -4).contains(p) {
            target = .primary
            if opensEditor { onEditColors?() }
            return
        }
        if wellRect(.secondary).insetBy(dx: -4, dy: -4).contains(p) {
            target = .secondary
            if opensEditor { onEditColors?() }
            return
        }
        guard let i = hitIndex(p) else { return }
        if i == -1 { onEditColors?(); return }
        guard let c = swatchColor(i) else { return }
        let dest = button == .secondary ? MouseButton.secondary : target
        if dest == .primary { state.color1 = c } else { state.color2 = c }
        if opensEditor { onEditColors?() }
    }
}
