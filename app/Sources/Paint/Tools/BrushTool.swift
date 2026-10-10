import AppKit

/// Paints with the selected gallery brush into the canvas stroke buffer; the stroke is composited onto the
/// active layer with the current opacity when the mouse is released.
final class BrushTool: Tool {
    let brush: BrushKind
    private var painter: BrushPainter?
    private var timer: Timer?
    private var hoverPoint: CGPoint?
    /// Set while Shift is held during a drag: new points are projected onto a 16-direction line and the pointer
    /// is held on it, so releasing Shift continues freehand from where the stroke is.
    private var lineLock: StrokeLineLock?

    init(brush: BrushKind, canvas: CanvasView) {
        self.brush = brush
        super.init(kind: .brush(brush), canvas: canvas)
    }

    override func mouseDown(at p: CGPoint, button: MouseButton, event: NSEvent) {
        let painter = BrushPainter(brush: brush, width: state.lineWidth, color: state.color(for: button),
                                   size: document.canvasSize, seed: UInt64(Date().timeIntervalSince1970 * 1000))
        self.painter = painter
        canvas.strokeBuffer = painter.buffer
        canvas.strokeBlend = .normal
        canvas.strokeAlpha = painter.compositeAlpha * state.opacity
        painter.begin(at: p)
        lineLock = nil
        hoverPoint = p
        canvas.needsDisplay = true
        if brush == .airbrush {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 40.0, repeats: true) { [weak self] _ in
                guard let self, let painter = self.painter, let last = painter.points.last else { return }
                painter.spray(at: last)
                self.canvas.needsDisplay = true
            }
        }
    }

    override func mouseDragged(to p: CGPoint, button: MouseButton, event: NSEvent) {
        guard painter != nil else { hoverPoint = p; return }
        hoverPoint = addPoint(p, shift: event.modifierFlags.contains(.shift)) ?? p
        canvas.needsDisplay = true
    }

    /// Extends the stroke freehand, or with Shift to its projection onto the locked line; returns the
    /// point painted.
    @discardableResult
    private func addPoint(_ p: CGPoint, shift: Bool) -> CGPoint? {
        guard let painter else { return nil }
        guard shift, let last = painter.points.last else {
            lineLock = nil
            painter.extend(to: p)
            return p
        }
        if lineLock == nil { lineLock = StrokeLineLock(anchor: last) }
        guard let q = lineLock?.constrain(p) else { return nil }
        if q.distance(to: p) > 0.01 { canvas.warpPointer(toImage: q) }
        painter.extend(to: q)
        return q
    }

    override func mouseUp(at p: CGPoint, button: MouseButton, event: NSEvent) {
        guard let painter else { return }
        timer?.invalidate(); timer = nil
        addPoint(p, shift: event.modifierFlags.contains(.shift))
        if let img = painter.buffer.makeImage() {
            let alpha = canvas.strokeAlpha
            document.performLayerChange(brush.title) { layer in
                layer.bitmap.draw(img, in: layer.bitmap.bounds, alpha: alpha, interpolate: false)
            }
        }
        canvas.strokeBuffer = nil
        self.painter = nil
        lineLock = nil
    }

    override func mouseMoved(to p: CGPoint) {
        hoverPoint = p
        canvas.needsDisplay = true
    }

    override func settingsChanged() { canvas.needsDisplay = true }

    override func mouseExited() {
        hoverPoint = nil
        canvas.needsDisplay = true
    }

    /// Outline of the brush footprint at the pointer, matching what a click would paint.
    override func drawOverlay(in ctx: CGContext) {
        guard let p = hoverPoint else { return }
        let vp = canvas.viewPoint(fromImage: p)
        let w = BrushPainter.footprint(for: brush, width: max(1, state.lineWidth)) * canvas.zoom
        let shape: FootprintShape
        switch brush {
        case .calligraphy1: shape = .nib(-.pi / 4)
        case .calligraphy2: shape = .nib(.pi / 4)
        case .marker: shape = .square
        default: shape = .circle
        }
        OverlayDrawing.drawFootprint(shape, size: w, at: vp, in: ctx)
    }

    override var cursor: NSCursor { Theme.invisibleCursor }
}
