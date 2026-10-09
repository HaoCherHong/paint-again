import AppKit

/// Draws gallery shapes. A drawn shape stays editable (move / resize / bend) until it is committed.
final class ShapeTool: Tool {
    let shape: ShapeKind

    private struct Pending {
        var rect: CGRect
        var points: [CGPoint]      // line / curve endpoints, polygon vertices
        var controls: [CGPoint]    // curve control points
        var swapped: Bool          // drawn with the secondary button: colours swapped
    }

    private enum Mode {
        case idle, creating, moving(CGPoint), resizing(Handle, CGRect), draggingPoint(Int), draggingControl(Int), polygonAdding
    }

    private var pending: Pending?
    private var mode: Mode = .idle
    private var start: CGPoint = .zero

    init(shape: ShapeKind, canvas: CanvasView) {
        self.shape = shape
        super.init(kind: .shape(shape), canvas: canvas)
    }

    override var hasPendingObject: Bool { pending != nil }
    private var usesPoints: Bool { shape == .line || shape == .curve || shape == .polygon }

    override func mouseDown(at p: CGPoint, button: MouseButton, event: NSEvent) {
        let vp = canvas.viewPoint(fromImage: p)
        if var pend = pending {
            if case .polygonAdding = mode {
                if event.clickCount >= 2 {
                    commit()
                } else {
                    pend.points.append(p.rounded)
                    pend.rect = boundingRect(pend)
                    pending = pend
                    canvas.needsDisplay = true
                }
                return
            }
            if usesPoints {
                if let i = pend.points.firstIndex(where: { canvas.viewPoint(fromImage: $0).distance(to: vp) <= 7 }) {
                    mode = .draggingPoint(i)
                    return
                }
                if shape == .curve {
                    if let i = pend.controls.firstIndex(where: { canvas.viewPoint(fromImage: $0).distance(to: vp) <= 7 }) {
                        mode = .draggingControl(i)
                        return
                    }
                    if pend.controls.count < 2 {
                        pend.controls.append(p)
                        pending = pend
                        mode = .draggingControl(pend.controls.count - 1)
                        canvas.needsDisplay = true
                        return
                    }
                }
                if pend.rect.insetBy(dx: -6 / canvas.zoom, dy: -6 / canvas.zoom).contains(p) {
                    mode = .moving(p)
                    return
                }
            } else {
                if let h = OverlayDrawing.handle(at: vp, for: canvas.viewRect(fromImage: pend.rect)) {
                    mode = .resizing(h, pend.rect)
                    return
                }
                if pend.rect.contains(p) {
                    mode = .moving(p)
                    return
                }
            }
            commit()
        }
        start = p.rounded
        pending = Pending(rect: CGRect(origin: start, size: .zero), points: [start, start], controls: [], swapped: button == .secondary)
        mode = .creating
    }

    override func mouseDragged(to p: CGPoint, button: MouseButton, event: NSEvent) {
        guard var pend = pending else { return }
        var q = p.rounded
        switch mode {
        case .creating:
            if event.modifierFlags.contains(.shift) {
                let d = max(abs(q.x - start.x), abs(q.y - start.y))
                q = CGPoint(x: start.x + (q.x >= start.x ? d : -d), y: start.y + (q.y >= start.y ? d : -d))
            }
            if usesPoints {
                pend.points = [start, q]
                pend.rect = boundingRect(pend)
            } else {
                pend.rect = CGRect(p1: start, p2: q)
            }
        case .moving(let last):
            let d = q - last
            pend.rect = pend.rect.offsetBy(dx: d.x, dy: d.y)
            pend.points = pend.points.map { $0 + d }
            pend.controls = pend.controls.map { $0 + d }
            mode = .moving(q)
        case .resizing(let h, let startRect):
            pend.rect = h.resize(startRect, to: q)
        case .draggingPoint(let i):
            pend.points[i] = q
            pend.rect = boundingRect(pend)
        case .draggingControl(let i):
            pend.controls[i] = p
            pend.rect = boundingRect(pend)
        case .idle, .polygonAdding:
            break
        }
        pending = pend
        canvas.needsDisplay = true
    }

    override func mouseUp(at p: CGPoint, button: MouseButton, event: NSEvent) {
        guard let pend = pending else { return }
        if case .creating = mode {
            if shape == .polygon {
                mode = .polygonAdding
                return
            }
            let tooSmall = usesPoints ? pend.points[0].distance(to: pend.points[1]) < 1 : (pend.rect.width < 1 || pend.rect.height < 1)
            if tooSmall { pending = nil }
        }
        if case .polygonAdding = mode { return }
        mode = .idle
        canvas.needsDisplay = true
    }

    override func keyDown(_ event: NSEvent) -> Bool {
        if event.keyCode == 36 || event.keyCode == 76, pending != nil { commit(); return true }
        if event.keyCode == 53, pending != nil { cancel(); return true }
        return false
    }

    override func commit() {
        guard let pend = pending else { return }
        pending = nil
        mode = .idle
        document.performLayerChange(shape.title) { layer in
            render(pend, in: layer.bitmap.context, scale: 1)
        }
        canvas.needsDisplay = true
    }

    override func cancel() {
        pending = nil
        mode = .idle
        canvas.needsDisplay = true
    }

    override func settingsChanged() { canvas.needsDisplay = true }

    override func drawOverlay(in ctx: CGContext) {
        guard let pend = pending else { return }
        ctx.saveGState()
        ctx.concatenate(canvas.viewTransform)
        render(pend, in: ctx, scale: 1)
        ctx.restoreGState()
        if usesPoints {
            var pts = pend.points
            if shape == .curve { pts += pend.controls }
            for p in pts {
                let vp = canvas.viewPoint(fromImage: p)
                let r = CGRect(x: vp.x - 4, y: vp.y - 4, width: 8, height: 8)
                ctx.setFillColor(NSColor.white.cgColor); ctx.fill(r)
                ctx.setStrokeColor(NSColor(hex: "#0067C0").cgColor); ctx.setLineWidth(1.5); ctx.stroke(r)
            }
        } else {
            let vr = canvas.viewRect(fromImage: pend.rect)
            ctx.saveGState()
            ctx.setStrokeColor(NSColor(hex: "#0067C0").withAlphaComponent(0.7).cgColor)
            ctx.setLineDash(phase: 0, lengths: [4, 3]); ctx.setLineWidth(1)
            ctx.stroke(vr)
            ctx.restoreGState()
            OverlayDrawing.drawHandles(for: vr, in: ctx)
        }
    }

    private func boundingRect(_ pend: Pending) -> CGRect {
        var r = CGRect(p1: pend.points[0], p2: pend.points[0])
        for p in pend.points.dropFirst() + pend.controls { r = r.union(CGRect(origin: p, size: .zero)) }
        return r
    }

    private func render(_ pend: Pending, in ctx: CGContext, scale: CGFloat) {
        let strokeColor = pend.swapped ? state.color2 : state.color1
        let fillColor = pend.swapped ? state.color1 : state.color2
        let path: CGPath = usesPoints
            ? ShapePaths.path(points: pend.points, controls: pend.controls, kind: shape)
            : ShapePaths.path(for: shape, in: pend.rect)
        ctx.saveGState()
        ctx.setAlpha(state.opacity)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setLineWidth(max(1, state.lineWidth))
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        if state.shapeFill == .solid && !shape.isOpenPath {
            ctx.setFillColor(fillColor.cgColor)
            ctx.addPath(path)
            ctx.fillPath(using: .winding)
        }
        if state.shapeStroke == .solid || shape.isOpenPath || state.shapeFill == .none {
            ctx.setStrokeColor(strokeColor.cgColor)
            ctx.addPath(path)
            ctx.strokePath()
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    override var cursor: NSCursor { .crosshair }

    override func cursor(at p: CGPoint) -> NSCursor {
        guard let pend = pending else { return .crosshair }
        let vp = canvas.viewPoint(fromImage: p)
        if usesPoints {
            let pts = pend.points + (shape == .curve ? pend.controls : [])
            if pts.contains(where: { canvas.viewPoint(fromImage: $0).distance(to: vp) <= 7 }) { return .pointingHand }
            if pend.rect.insetBy(dx: -6 / canvas.zoom, dy: -6 / canvas.zoom).contains(p) { return .openHand }
            return .crosshair
        }
        if let h = OverlayDrawing.handle(at: vp, for: canvas.viewRect(fromImage: pend.rect)) { return h.cursor }
        if pend.rect.contains(p) { return .openHand }
        return .crosshair
    }
}
