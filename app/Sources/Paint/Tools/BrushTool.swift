import AppKit

/// Paints with the selected gallery brush into the canvas stroke buffer; the stroke is composited onto the
/// active layer with the current opacity when the mouse is released.
final class BrushTool: Tool {
    let brush: BrushKind
    private var painter: BrushPainter?
    private var timer: Timer?
    private var hoverPoint: CGPoint?
    /// End of the previous stroke; Shift-click paints a straight segment from here.
    private var lastStrokeEnd: CGPoint?

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
        if event.modifierFlags.contains(.shift), let from = lastStrokeEnd {
            painter.begin(at: from)
            painter.extend(to: p)
        } else {
            painter.begin(at: p)
        }
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
        hoverPoint = p
        guard let painter else { return }
        painter.extend(to: p)
        canvas.needsDisplay = true
    }

    override func mouseUp(at p: CGPoint, button: MouseButton, event: NSEvent) {
        guard let painter else { return }
        timer?.invalidate(); timer = nil
        painter.extend(to: p)
        if let img = painter.buffer.makeImage() {
            let alpha = canvas.strokeAlpha
            document.performLayerChange(brush.title) { layer in
                layer.bitmap.draw(img, in: layer.bitmap.bounds, alpha: alpha, interpolate: false)
            }
        }
        canvas.strokeBuffer = nil
        self.painter = nil
        lastStrokeEnd = p
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
