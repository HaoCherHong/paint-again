import AppKit

/// Places an editable text box on the canvas; the text is rasterised into the active layer on commit.
final class TextTool: Tool, NSTextViewDelegate {
    private var textView: NSTextView?
    private var rect: CGRect = .zero
    private var creating = false
    private var moving: CGPoint?
    private var start: CGPoint = .zero

    override var hasPendingObject: Bool { textView != nil }

    override func mouseDown(at p: CGPoint, button: MouseButton, event: NSEvent) {
        if textView != nil {
            let border = rect.insetBy(dx: -8 / canvas.zoom, dy: -8 / canvas.zoom)
            if border.contains(p) && !rect.contains(p) {
                moving = p
                return
            }
            commit()
        }
        start = p.rounded
        rect = CGRect(origin: start, size: .zero)
        creating = true
        canvas.needsDisplay = true
    }

    override func mouseDragged(to p: CGPoint, button: MouseButton, event: NSEvent) {
        if let last = moving {
            let d = p.rounded - last
            rect = rect.offsetBy(dx: d.x, dy: d.y)
            moving = p.rounded
            layoutTextView()
            return
        }
        guard creating else { return }
        rect = CGRect(p1: start, p2: p.rounded)
        canvas.needsDisplay = true
    }

    override func mouseUp(at p: CGPoint, button: MouseButton, event: NSEvent) {
        if moving != nil { moving = nil; return }
        guard creating else { return }
        creating = false
        if rect.width < 10 || rect.height < 10 {
            rect = CGRect(x: start.x, y: start.y, width: max(160, state.fontSize * 8), height: state.fontSize * 1.6 + 8)
        }
        createTextView()
    }

    private func createTextView() {
        let tv = NSTextView(frame: canvas.viewRect(fromImage: rect))
        tv.delegate = self
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainerInset = NSSize(width: 2, height: 2)
        tv.textContainer?.widthTracksTextView = true
        tv.minSize = NSSize(width: 10, height: 10)
        tv.maxSize = NSSize(width: 100000, height: 100000)
        canvas.addSubview(tv)
        textView = tv
        applyStyle()
        canvas.window?.makeFirstResponder(tv)
        canvas.needsDisplay = true
    }

    private func applyStyle() {
        guard let tv = textView else { return }
        let z = canvas.zoom
        var font = state.font()
        font = NSFont(descriptor: font.fontDescriptor, size: state.fontSize * z) ?? font
        tv.font = font
        tv.textColor = state.color1
        tv.insertionPointColor = state.color1
        tv.drawsBackground = state.textOpaqueBackground
        tv.backgroundColor = state.textOpaqueBackground ? state.color2 : .clear
        var attrs = state.textAttributes(color: state.color1)
        attrs[.font] = font
        tv.typingAttributes = attrs
        if let storage = tv.textStorage, storage.length > 0 {
            storage.setAttributes(attrs, range: NSRange(location: 0, length: storage.length))
        }
        layoutTextView()
    }

    private func layoutTextView() {
        guard let tv = textView else { return }
        tv.frame = canvas.viewRect(fromImage: rect)
        canvas.needsDisplay = true
    }

    override func settingsChanged() { applyStyle() }

    func textDidChange(_ notification: Notification) {
        guard let tv = textView else { return }
        tv.sizeToFit()
        let vr = tv.frame
        var r = canvas.imageRect(fromView: vr)
        r.size.width = rect.width
        r.origin = rect.origin
        rect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(rect.height, r.height.rounded()))
        tv.frame = canvas.viewRect(fromImage: rect)
        canvas.needsDisplay = true
    }

    override func commit() {
        guard let tv = textView else { return }
        let text = tv.string
        textView = nil
        tv.removeFromSuperview()
        canvas.window?.makeFirstResponder(canvas)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            canvas.needsDisplay = true
            return
        }
        let attrs = state.textAttributes(color: state.color1)
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let target = rect
        let opaque = state.textOpaqueBackground
        let bg = state.color2
        let opacity = state.opacity
        document.performLayerChange(L("Text")) { layer in
            let ctx = layer.bitmap.context
            ctx.saveGState()
            ctx.setAlpha(opacity)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            if opaque {
                ctx.setFillColor(bg.cgColor)
                ctx.fill(target)
            }
            let gc = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = gc
            attributed.draw(with: target.insetBy(dx: 2, dy: 2), options: [.usesLineFragmentOrigin, .usesFontLeading])
            NSGraphicsContext.restoreGraphicsState()
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
        canvas.needsDisplay = true
    }

    override func cancel() {
        textView?.removeFromSuperview()
        textView = nil
        canvas.window?.makeFirstResponder(canvas)
        canvas.needsDisplay = true
    }

    override func drawOverlay(in ctx: CGContext) {
        guard textView != nil || creating else { return }
        let vr = canvas.viewRect(fromImage: rect)
        ctx.saveGState()
        ctx.setStrokeColor(NSColor(hex: "#0067C0").cgColor)
        ctx.setLineDash(phase: 0, lengths: [4, 3])
        ctx.setLineWidth(1)
        ctx.stroke(vr.insetBy(dx: -1, dy: -1))
        ctx.restoreGState()
    }

    override var cursor: NSCursor { .iBeam }

    override func cursor(at p: CGPoint) -> NSCursor {
        guard textView != nil else { return .iBeam }
        let border = rect.insetBy(dx: -8 / canvas.zoom, dy: -8 / canvas.zoom)
        return border.contains(p) && !rect.contains(p) ? .openHand : .iBeam
    }
}
