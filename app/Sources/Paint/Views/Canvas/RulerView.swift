import AppKit

/// Pixel ruler drawn along the top or left edge of the canvas scroll view.
final class RulerView: NSView {
    let horizontal: Bool
    var zoom: CGFloat = 1 { didSet { needsDisplay = true } }
    /// Position (in this view's coordinates) where image coordinate 0 lies.
    var origin: CGFloat = 0 { didSet { needsDisplay = true } }
    var cursor: CGFloat? { didSet { needsDisplay = true } }
    /// Canvas that receives guides dragged out of this ruler.
    weak var canvas: CanvasView?
    private var dragging = false

    init(horizontal: Bool) {
        self.horizontal = horizontal
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        Theme.glassBand.setFill()
        bounds.fill(using: .sourceOver)
        Theme.divider.setFill()
        if horizontal {
            CGRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
        } else {
            CGRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
        }
        let steps: [CGFloat] = [1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 5000]
        let major = steps.first(where: { $0 * zoom >= 60 }) ?? 5000
        let minor = major / 5
        let length = horizontal ? bounds.width : bounds.height
        let thickness = horizontal ? bounds.height : bounds.width
        let startValue = floor((0 - origin) / zoom / minor) * minor
        let endValue = (length - origin) / zoom
        ctx.setStrokeColor(Theme.secondaryText.cgColor)
        ctx.setLineWidth(1)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: Theme.secondaryText]
        var v = startValue
        while v <= endValue {
            let pos = (origin + v * zoom).rounded() + 0.5
            let isMajor = abs(v.truncatingRemainder(dividingBy: major)) < 0.001
            let tick: CGFloat = isMajor ? thickness * 0.55 : thickness * 0.25
            if horizontal {
                ctx.move(to: CGPoint(x: pos, y: thickness)); ctx.addLine(to: CGPoint(x: pos, y: thickness - tick))
            } else {
                ctx.move(to: CGPoint(x: thickness, y: pos)); ctx.addLine(to: CGPoint(x: thickness - tick, y: pos))
            }
            ctx.strokePath()
            if isMajor {
                let s = "\(Int(v))" as NSString
                if horizontal {
                    s.draw(at: CGPoint(x: pos + 2, y: 1), withAttributes: attrs)
                } else {
                    ctx.saveGState()
                    ctx.translateBy(x: 1, y: pos - 2)
                    ctx.rotate(by: -.pi / 2)
                    s.draw(at: .zero, withAttributes: attrs)
                    ctx.restoreGState()
                }
            }
            v += minor
        }
        if let c = cursor {
            ctx.setStrokeColor(Theme.accent.cgColor)
            let pos = (origin + c * zoom).rounded() + 0.5
            if horizontal {
                ctx.move(to: CGPoint(x: pos, y: 0)); ctx.addLine(to: CGPoint(x: pos, y: thickness))
            } else {
                ctx.move(to: CGPoint(x: 0, y: pos)); ctx.addLine(to: CGPoint(x: thickness, y: pos))
            }
            ctx.strokePath()
        }
    }
}

extension RulerView {
    private var guideAxis: CanvasView.GuideAxis { horizontal ? .horizontal : .vertical }

    override func mouseDown(with event: NSEvent) {
        dragging = true
        canvas?.updateGuideDrag(axis: guideAxis, windowPoint: event.locationInWindow)
        (horizontal ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        canvas?.updateGuideDrag(axis: guideAxis, windowPoint: event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        canvas?.finishGuideDrag(windowPoint: event.locationInWindow)
        NSCursor.arrow.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: horizontal ? .resizeUpDown : .resizeLeftRight)
    }
}

final class RulerCornerView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Theme.glassBand.setFill()
        bounds.fill(using: .sourceOver)
    }
}

/// Keeps a document view centered when it is smaller than the clip view.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return r }
        if doc.frame.width < r.width { r.origin.x = (doc.frame.width - r.width) / 2 }
        if doc.frame.height < r.height { r.origin.y = (doc.frame.height - r.height) / 2 }
        return r
    }
}
