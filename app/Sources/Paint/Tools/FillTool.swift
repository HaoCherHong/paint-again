import AppKit

final class FillTool: Tool {
    override func mouseDown(at p: CGPoint, button: MouseButton, event: NSEvent) {
        let x = Int(floor(p.x)), y = Int(floor(p.y))
        guard document.activeLayer.bitmap.contains(x: x, y: y) else { return }
        if let sel = canvas.selection, !sel.contains(p) { return }
        let color = Bitmap.premultiplied(state.color(for: button))
        let opacity = state.opacity
        let selection = canvas.selection
        document.performLayerChange(L("Fill")) { layer in
            // Fill a copy, then blend it back so opacity and the selection clip apply.
            let copy = Bitmap(copying: layer.bitmap)
            FloodFill.fill(copy, x: x, y: y, fill: color)
            let ctx = layer.bitmap.context
            ctx.saveGState()
            if let sel = selection {
                ctx.addPath(sel.path)
                if sel.evenOdd { ctx.clip(using: .evenOdd) } else { ctx.clip() }
            }
            if let img = copy.makeImage() {
                layer.bitmap.draw(img, in: layer.bitmap.bounds, blend: opacity >= 1 ? .copy : .normal, alpha: opacity, interpolate: false)
            }
            ctx.restoreGState()
        }
    }

    override var cursor: NSCursor { Theme.bucketCursor }
}
