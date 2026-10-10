import AppKit

final class EraserTool: Tool {
    private var last: CGPoint = .zero
    private var active = false
    /// Set while Shift is held during a drag: new points are projected onto a 16-direction line and the pointer
    /// is held on it, so releasing Shift continues freehand from where the stroke is.
    private var lineLock: StrokeLineLock?

    override func mouseDown(at p: CGPoint, button: MouseButton, event: NSEvent) {
        let bmp = Bitmap(width: Int(document.canvasSize.width), height: Int(document.canvasSize.height))
        canvas.strokeBuffer = bmp
        canvas.strokeAlpha = state.opacity
        canvas.strokeBlend = .destinationOut
        active = true
        lineLock = nil
        last = p
        drawSegment(from: p, to: p)
    }

    override func mouseDragged(to p: CGPoint, button: MouseButton, event: NSEvent) {
        guard active else { hoverPoint = p; return }
        hoverPoint = addPoint(p, shift: event.modifierFlags.contains(.shift)) ?? last
    }

    /// Erases freehand to `p`, or with Shift to its projection onto the locked line; returns the point reached.
    @discardableResult
    private func addPoint(_ p: CGPoint, shift: Bool) -> CGPoint? {
        var q = p
        if !shift { lineLock = nil }
        if shift {
            if lineLock == nil { lineLock = StrokeLineLock(anchor: last) }
            guard let c = lineLock?.constrain(p) else { return nil }
            if c.distance(to: p) > 0.01 { canvas.warpPointer(toImage: c) }
            q = c
        }
        drawSegment(from: last, to: q)
        last = q
        return q
    }

    override func mouseUp(at p: CGPoint, button: MouseButton, event: NSEvent) {
        guard active, let buf = canvas.strokeBuffer else { return }
        addPoint(p, shift: event.modifierFlags.contains(.shift))
        let alpha = canvas.strokeAlpha
        if let img = buf.makeImage() {
            document.performLayerChange(L("Eraser")) { layer in
                layer.bitmap.draw(img, in: layer.bitmap.bounds, blend: .destinationOut, alpha: alpha, interpolate: false)
            }
        }
        canvas.strokeBuffer = nil
        active = false
        lineLock = nil
    }

    private func drawSegment(from a: CGPoint, to b: CGPoint) {
        guard let buf = canvas.strokeBuffer else { return }
        let ctx = buf.context
        let w = max(1, state.lineWidth)
        let color = NSColor.black
        ctx.saveGState()
        ctx.setShouldAntialias(false)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(w)
        ctx.setLineCap(.square)
        ctx.setLineJoin(.miter)
        if a == b {
            ctx.setFillColor(color.cgColor)
            ctx.fill(CGRect(x: a.x - w / 2, y: a.y - w / 2, width: w, height: w))
        } else {
            ctx.move(to: a)
            ctx.addLine(to: b)
            ctx.strokePath()
        }
        ctx.restoreGState()
        canvas.needsDisplay = true
    }

    override func drawOverlay(in ctx: CGContext) {
        guard let p = hoverPoint else { return }
        let w = max(1, state.lineWidth) * canvas.zoom
        OverlayDrawing.drawFootprint(.square, size: w, at: canvas.viewPoint(fromImage: p), in: ctx)
    }

    private var hoverPoint: CGPoint?
    override func mouseMoved(to p: CGPoint) {
        hoverPoint = p
        canvas.needsDisplay = true
    }

    override func mouseExited() {
        hoverPoint = nil
        canvas.needsDisplay = true
    }

    override var cursor: NSCursor { Theme.invisibleCursor }
}
