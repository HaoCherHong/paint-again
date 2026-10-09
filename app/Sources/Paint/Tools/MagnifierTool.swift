import AppKit

final class MagnifierTool: Tool {
    override func mouseDown(at p: CGPoint, button: MouseButton, event: NSEvent) {
        let levels = Theme.zoomLevels
        let z = canvas.zoom
        let target: CGFloat
        if button == .primary {
            target = levels.first(where: { $0 > z + 0.001 }) ?? levels.last!
        } else {
            target = levels.last(where: { $0 < z - 0.001 }) ?? levels.first!
        }
        canvas.setZoom(target, anchor: p)
    }

    override var cursor: NSCursor { Theme.cursor(symbol: "magnifyingglass", anchor: .inGlyph(0.42, 0.42)) }
}
