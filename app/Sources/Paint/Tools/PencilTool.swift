import AppKit

/// Aliased freehand line. The whole stroke is re-rendered into the stroke buffer so opacity applies evenly.
final class PencilTool: Tool {
    private var points: [CGPoint] = []
    private var color: NSColor = .black
    private var hoverPoint: CGPoint?
    /// End of the previous stroke; Shift-click draws a straight segment from here.
    private var lastStrokeEnd: CGPoint?

    private var width: CGFloat { max(1, state.lineWidth) }

    override func mouseDown(at p: CGPoint, button: MouseButton, event: NSEvent) {
        color = state.color(for: button)
        points = (event.modifierFlags.contains(.shift) ? lastStrokeEnd.map { [$0] } : nil) ?? []
        points.append(p)
        canvas.strokeBuffer = Bitmap(width: Int(document.canvasSize.width), height: Int(document.canvasSize.height))
        canvas.strokeBlend = .normal
        canvas.strokeAlpha = state.opacity
        hoverPoint = p
        render()
    }

    override func mouseDragged(to p: CGPoint, button: MouseButton, event: NSEvent) {
        hoverPoint = p
        guard canvas.strokeBuffer != nil else { return }
        points.append(p)
        render()
    }

    override func mouseUp(at p: CGPoint, button: MouseButton, event: NSEvent) {
        guard let buf = canvas.strokeBuffer else { return }
        points.append(p)
        render()
        if let img = buf.makeImage() {
            let alpha = canvas.strokeAlpha
            document.performLayerChange(L("Pencil")) { layer in
                layer.bitmap.draw(img, in: layer.bitmap.bounds, alpha: alpha, interpolate: false)
            }
        }
        canvas.strokeBuffer = nil
        points = []
        lastStrokeEnd = p
    }

    override func mouseMoved(to p: CGPoint) {
        hoverPoint = p
        canvas.needsDisplay = true
    }

    override func settingsChanged() { canvas.needsDisplay = true }

    private func render() {
        guard let buf = canvas.strokeBuffer else { return }
        buf.clear()
        let ctx = buf.context
        let w = width
        ctx.saveGState()
        ctx.setShouldAntialias(false)
        ctx.setFillColor(color.cgColor)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(w)
        ctx.setLineCap(w <= 1 ? .square : .round)
        ctx.setLineJoin(.round)
        let o: CGFloat = w <= 1 ? 0.5 : 0
        let pts = points.map { CGPoint(x: floor($0.x) + o, y: floor($0.y) + o) }
        if pts.count < 2 || pts.allSatisfy({ $0 == pts[0] }) {
            let p = pts[0]
            if w <= 1 {
                ctx.fill(CGRect(x: floor(p.x), y: floor(p.y), width: 1, height: 1))
            } else {
                ctx.fillEllipse(in: CGRect(x: p.x - w / 2, y: p.y - w / 2, width: w, height: w))
            }
        } else {
            ctx.addLines(between: pts)
            ctx.strokePath()
        }
        ctx.restoreGState()
        canvas.needsDisplay = true
    }

    override func mouseExited() {
        hoverPoint = nil
        canvas.needsDisplay = true
    }

    /// Shows the exact footprint a click would paint: one pixel, or a circle of the current width.
    override func drawOverlay(in ctx: CGContext) {
        guard let p = hoverPoint else { return }
        let z = canvas.zoom
        if width <= 1 {
            let r = canvas.viewRect(fromImage: CGRect(x: floor(p.x), y: floor(p.y), width: 1, height: 1))
            OverlayDrawing.drawFootprint(.square, size: r.width, at: r.center, in: ctx)
        } else {
            let vp = canvas.viewPoint(fromImage: CGPoint(x: floor(p.x), y: floor(p.y)))
            OverlayDrawing.drawFootprint(.circle, size: width * z, at: vp, in: ctx)
        }
    }

    override var cursor: NSCursor { Theme.invisibleCursor }
}
