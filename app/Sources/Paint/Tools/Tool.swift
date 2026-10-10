import AppKit

/// Base class for interactive canvas tools. Points are in image pixel coordinates.
class Tool: NSObject {
    unowned let canvas: CanvasView
    let kind: ToolKind

    var document: PaintDocument { canvas.document }
    var state: ToolState { canvas.state }

    init(kind: ToolKind, canvas: CanvasView) {
        self.kind = kind
        self.canvas = canvas
        super.init()
    }

    func mouseDown(at p: CGPoint, button: MouseButton, event: NSEvent) {}
    func mouseDragged(to p: CGPoint, button: MouseButton, event: NSEvent) {}
    func mouseUp(at p: CGPoint, button: MouseButton, event: NSEvent) {}
    func mouseMoved(to p: CGPoint) {}
    /// The pointer left the canvas; tools drop any hover preview.
    func mouseExited() {}
    /// Draws in view coordinates on top of the canvas.
    func drawOverlay(in ctx: CGContext) {}
    /// Returns true when the key was consumed.
    func keyDown(_ event: NSEvent) -> Bool { false }
    /// Commits any pending floating object (shape, text).
    func commit() {}
    /// Discards any pending floating object.
    func cancel() {}
    func deactivate() { commit() }
    /// Called when tool settings (colour, width, font…) change while the tool is active.
    func settingsChanged() {}
    var cursor: NSCursor { .crosshair }
    /// Cursor to show while hovering `p` (image coordinates); defaults to `cursor`.
    func cursor(at p: CGPoint) -> NSCursor { cursor }
    /// Whether the tool currently owns a floating object that a click elsewhere would commit.
    var hasPendingObject: Bool { false }

    /// `p` moved onto the nearest of 16 directions (22.5° steps) from `anchor`, keeping its distance.
    static func snapped16(_ p: CGPoint, from anchor: CGPoint) -> CGPoint {
        let step = CGFloat.pi / 8
        let angle = (atan2(p.y - anchor.y, p.x - anchor.x) / step).rounded() * step
        let length = anchor.distance(to: p)
        return CGPoint(x: anchor.x + cos(angle) * length, y: anchor.y + sin(angle) * length)
    }

    static func make(_ kind: ToolKind, canvas: CanvasView) -> Tool {
        switch kind {
        case .selectRectangle, .selectFreeform: return SelectionTool(kind: kind, canvas: canvas)
        case .pencil: return PencilTool(kind: kind, canvas: canvas)
        case .fill: return FillTool(kind: kind, canvas: canvas)
        case .text: return TextTool(kind: kind, canvas: canvas)
        case .eraser: return EraserTool(kind: kind, canvas: canvas)
        case .colorPicker: return ColorPickerTool(kind: kind, canvas: canvas)
        case .magnifier: return MagnifierTool(kind: kind, canvas: canvas)
        case .brush(let b): return BrushTool(brush: b, canvas: canvas)
        case .shape(let s): return ShapeTool(shape: s, canvas: canvas)
        }
    }
}

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
    static func / (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x / s, y: a.y / s) }
    func distance(to b: CGPoint) -> CGFloat { hypot(x - b.x, y - b.y) }
    var length: CGFloat { hypot(x, y) }
    var rounded: CGPoint { CGPoint(x: x.rounded(), y: y.rounded()) }
    var floored: CGPoint { CGPoint(x: floor(x), y: floor(y)) }
}

extension CGRect {
    init(p1: CGPoint, p2: CGPoint) {
        self.init(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
    }
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

/// Shift-drag constraint for freehand tools: once the pointer has moved a few pixels from the anchor, the
/// direction snaps to the nearest of 16 (22.5° steps) and every later point is projected onto that line,
/// so painting continues along it in either direction.
struct StrokeLineLock {
    let anchor: CGPoint
    private var direction: CGPoint?

    init(anchor: CGPoint) { self.anchor = anchor }

    /// Where to paint for pointer `p`, or nil while the direction is still undecided.
    mutating func constrain(_ p: CGPoint) -> CGPoint? {
        if direction == nil {
            guard anchor.distance(to: p) >= 3 else { return nil }
            let s = Tool.snapped16(p, from: anchor) - anchor
            direction = s / s.length
        }
        guard let d = direction else { return nil }
        let t = (p.x - anchor.x) * d.x + (p.y - anchor.y) * d.y
        return anchor + d * t
    }
}
