import AppKit

final class ColorPickerTool: Tool {
    override func mouseDown(at p: CGPoint, button: MouseButton, event: NSEvent) {
        guard document.canvasRect.contains(p) else { return }
        canvas.sampleColor(at: p, button: button)
        let back = canvas.previousToolKind
        DispatchQueue.main.async { [canvas] in canvas.selectTool(back) }
    }

    override var cursor: NSCursor { Theme.cursor(symbol: "eyedropper", anchor: .bottomLeft) }
}
