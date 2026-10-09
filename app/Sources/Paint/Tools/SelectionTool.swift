import AppKit

final class SelectionTool: Tool {
    private enum Mode { case idle, selecting, moving(CGPoint), resizing(Handle, CGRect) }
    private var mode: Mode = .idle
    private var start: CGPoint = .zero
    private var freeformPoints: [CGPoint] = []

    override var cursor: NSCursor { .crosshair }

    override func cursor(at p: CGPoint) -> NSCursor {
        let vp = canvas.viewPoint(fromImage: p)
        if let f = canvas.floating {
            if let h = OverlayDrawing.handle(at: vp, for: canvas.viewRect(fromImage: f.rect)) { return h.cursor }
            if f.rect.contains(p) { return .openHand }
        } else if let sel = canvas.selection {
            if let h = OverlayDrawing.handle(at: vp, for: canvas.viewRect(fromImage: sel.rect)) { return h.cursor }
            if sel.contains(p) { return .openHand }
        }
        return .crosshair
    }

    override func mouseDown(at p: CGPoint, button: MouseButton, event: NSEvent) {
        let vp = canvas.viewPoint(fromImage: p)
        if let f = canvas.floating {
            if let h = OverlayDrawing.handle(at: vp, for: canvas.viewRect(fromImage: f.rect)) {
                mode = .resizing(h, f.rect)
                return
            }
            if f.rect.contains(p) {
                mode = .moving(p - f.rect.origin)
                return
            }
            canvas.commitFloating()
        } else if let sel = canvas.selection {
            if let h = OverlayDrawing.handle(at: vp, for: canvas.viewRect(fromImage: sel.rect)) {
                canvas.liftSelection()
                if let f = canvas.floating { mode = .resizing(h, f.rect) }
                return
            }
            if sel.contains(p) {
                canvas.liftSelection()
                if let f = canvas.floating { mode = .moving(p - f.rect.origin) }
                return
            }
        }
        start = p.rounded
        freeformPoints = [start]
        canvas.selection = nil
        mode = .selecting
    }

    override func mouseDragged(to p: CGPoint, button: MouseButton, event: NSEvent) {
        switch mode {
        case .selecting:
            if kind == .selectRectangle {
                var end = p.rounded
                if event.modifierFlags.contains(.shift) {
                    let d = max(abs(end.x - start.x), abs(end.y - start.y))
                    end = CGPoint(x: start.x + (end.x >= start.x ? d : -d), y: start.y + (end.y >= start.y ? d : -d))
                }
                let r = CGRect(p1: start, p2: end).intersection(document.canvasRect)
                canvas.selection = r.isEmpty ? nil : Selection.rectangle(r)
            } else {
                freeformPoints.append(p)
                let path = CGMutablePath()
                path.addLines(between: freeformPoints)
                path.closeSubpath()
                canvas.selection = Selection(path: path, isRectangular: false)
            }
        case .moving(let offset):
            guard var f = canvas.floating else { return }
            f.rect.origin = (p - offset).rounded
            canvas.floating = f
            canvas.selection = Selection.rectangle(f.rect)
        case .resizing(let h, let startRect):
            guard var f = canvas.floating else { return }
            var r = h.resize(startRect, to: p.rounded)
            if event.modifierFlags.contains(.shift) {
                let aspect = startRect.width / max(1, startRect.height)
                r.size.height = max(1, (r.width / aspect).rounded())
            }
            f.rect = r
            canvas.floating = f
            canvas.selection = Selection.rectangle(r)
        case .idle:
            break
        }
    }

    override func mouseUp(at p: CGPoint, button: MouseButton, event: NSEvent) {
        if case .selecting = mode, let sel = canvas.selection {
            if sel.rect.width < 1 || sel.rect.height < 1 {
                canvas.selection = nil
            } else if kind == .selectFreeform {
                // Clip the free-form path to the canvas so it never extends outside the image.
                let clipped = CGMutablePath()
                clipped.addPath(sel.path)
                canvas.selection = Selection(path: clipped, isRectangular: false)
            }
        }
        mode = .idle
    }

    override func drawOverlay(in ctx: CGContext) {
        if canvas.floating == nil, let sel = canvas.selection, case .idle = mode {
            OverlayDrawing.drawHandles(for: canvas.viewRect(fromImage: sel.rect), in: ctx)
        }
    }
}
