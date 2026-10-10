import AppKit

struct Selection {
    var path: CGPath
    var evenOdd: Bool = false
    var rect: CGRect { path.boundingBoxOfPath }
    var isRectangular: Bool

    static func rectangle(_ r: CGRect) -> Selection {
        Selection(path: CGPath(rect: r.integral, transform: nil), isRectangular: true)
    }

    func contains(_ p: CGPoint) -> Bool { path.contains(p, using: evenOdd ? .evenOdd : .winding) }

    func inverted(in canvas: CGRect) -> Selection {
        let m = CGMutablePath()
        m.addRect(canvas)
        m.addPath(path)
        return Selection(path: m, evenOdd: !evenOdd, isRectangular: false)
    }
}

struct FloatingSelection {
    var image: CGImage
    var rect: CGRect
}

enum Handle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    func point(in r: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: r.minX, y: r.minY)
        case .top: return CGPoint(x: r.midX, y: r.minY)
        case .topRight: return CGPoint(x: r.maxX, y: r.minY)
        case .right: return CGPoint(x: r.maxX, y: r.midY)
        case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
        case .bottom: return CGPoint(x: r.midX, y: r.maxY)
        case .bottomLeft: return CGPoint(x: r.minX, y: r.maxY)
        case .left: return CGPoint(x: r.minX, y: r.midY)
        }
    }

    /// Resizes `r` so the handle moves to `p`, keeping the opposite side fixed.
    func resize(_ r: CGRect, to p: CGPoint) -> CGRect {
        var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
        switch self {
        case .topLeft: minX = p.x; minY = p.y
        case .top: minY = p.y
        case .topRight: maxX = p.x; minY = p.y
        case .right: maxX = p.x
        case .bottomRight: maxX = p.x; maxY = p.y
        case .bottom: maxY = p.y
        case .bottomLeft: minX = p.x; maxY = p.y
        case .left: minX = p.x
        }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY), width: max(1, abs(maxX - minX)), height: max(1, abs(maxY - minY)))
    }

    /// Like `resize`, but keeps `r`'s aspect ratio: a corner scales from the opposite corner, an edge scales
    /// the other dimension around its centre.
    func resizeKeepingAspect(_ r: CGRect, to p: CGPoint) -> CGRect {
        let free = resize(r, to: p)
        let aspect = r.width / max(1, r.height)
        var w: CGFloat, h: CGFloat
        switch self {
        case .left, .right: w = free.width; h = w / aspect
        case .top, .bottom: h = free.height; w = h * aspect
        default:
            let s = max(free.width / max(1, r.width), free.height / max(1, r.height))
            w = r.width * s; h = r.height * s
        }
        w = max(1, w.rounded()); h = max(1, h.rounded())
        let x: CGFloat, y: CGFloat
        switch self {
        case .left, .topLeft, .bottomLeft: x = r.maxX - w
        case .right, .topRight, .bottomRight: x = r.minX
        case .top, .bottom: x = (r.midX - w / 2).rounded()
        }
        switch self {
        case .top, .topLeft, .topRight: y = r.maxY - h
        case .bottom, .bottomLeft, .bottomRight: y = r.minY
        case .left, .right: y = (r.midY - h / 2).rounded()
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// The system frame-resize cursor for this handle; macOS 14 has no diagonal one, so corners use a
    /// double-arrow symbol there.
    var cursor: NSCursor {
        if #available(macOS 15, *) {
            let position: NSCursor.FrameResizePosition
            switch self {
            case .topLeft: position = .topLeft
            case .top: position = .top
            case .topRight: position = .topRight
            case .right: position = .right
            case .bottomRight: position = .bottomRight
            case .bottom: position = .bottom
            case .bottomLeft: position = .bottomLeft
            case .left: position = .left
            }
            return .frameResize(position: position, directions: .all)
        }
        switch self {
        case .top, .bottom: return .resizeUpDown
        case .left, .right: return .resizeLeftRight
        case .topLeft, .bottomRight: return Theme.cursor(symbol: "arrow.up.left.and.arrow.down.right", anchor: .center)
        case .topRight, .bottomLeft: return Theme.cursor(symbol: "arrow.up.right.and.arrow.down.left", anchor: .center)
        }
    }
}

enum FootprintShape {
    case circle, square
    /// Calligraphy nib: a thin line rotated by `angle` radians.
    case nib(CGFloat)
}

enum OverlayDrawing {
    /// Draws the outline of the area a tool would paint at `center` (view coordinates), white-on-black so it
    /// reads on any colour. Footprints smaller than a few pixels are shown as a small crosshair instead.
    static func drawFootprint(_ shape: FootprintShape, size: CGFloat, at center: CGPoint, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setLineWidth(1)
        if size < 6 {
            for (color, lw) in [(NSColor.white, 3.0), (NSColor.black, 1.0)] as [(NSColor, CGFloat)] {
                ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(lw)
                ctx.move(to: CGPoint(x: center.x - 6, y: center.y)); ctx.addLine(to: CGPoint(x: center.x - 2, y: center.y))
                ctx.move(to: CGPoint(x: center.x + 2, y: center.y)); ctx.addLine(to: CGPoint(x: center.x + 6, y: center.y))
                ctx.move(to: CGPoint(x: center.x, y: center.y - 6)); ctx.addLine(to: CGPoint(x: center.x, y: center.y - 2))
                ctx.move(to: CGPoint(x: center.x, y: center.y + 2)); ctx.addLine(to: CGPoint(x: center.x, y: center.y + 6))
                ctx.strokePath()
            }
            ctx.restoreGState()
            return
        }
        let r = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        switch shape {
        case .circle:
            ctx.setStrokeColor(NSColor.white.cgColor); ctx.strokeEllipse(in: r.insetBy(dx: -0.5, dy: -0.5))
            ctx.setStrokeColor(NSColor.black.cgColor); ctx.strokeEllipse(in: r.insetBy(dx: 0.5, dy: 0.5))
        case .square:
            ctx.setStrokeColor(NSColor.white.cgColor); ctx.stroke(r.insetBy(dx: -0.5, dy: -0.5))
            ctx.setStrokeColor(NSColor.black.cgColor); ctx.stroke(r.insetBy(dx: 0.5, dy: 0.5))
        case .nib(let angle):
            let n = CGPoint(x: cos(angle), y: sin(angle)) * (size / 2)
            for (color, lw) in [(NSColor.white, 3.0), (NSColor.black, 1.0)] as [(NSColor, CGFloat)] {
                ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(lw)
                ctx.move(to: center - n); ctx.addLine(to: center + n); ctx.strokePath()
            }
        }
        ctx.restoreGState()
    }

    static func drawHandles(for rect: CGRect, in ctx: CGContext, handles: [Handle] = Handle.allCases) {
        for h in handles {
            let c = h.point(in: rect)
            let r = CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(r)
            ctx.setStrokeColor(NSColor(hex: "#0067C0").cgColor)
            ctx.setLineWidth(1.5)
            ctx.stroke(r)
        }
    }

    static func drawMarchingAnts(_ path: CGPath, in ctx: CGContext) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setLineWidth(1)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.strokePath()
        ctx.addPath(path)
        ctx.setStrokeColor(NSColor(hex: "#0067C0").cgColor)
        ctx.setLineDash(phase: 0, lengths: [4, 4])
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func handle(at viewPoint: CGPoint, for rect: CGRect, handles: [Handle] = Handle.allCases) -> Handle? {
        for h in handles where h.point(in: rect).distance(to: viewPoint) <= 7 { return h }
        return nil
    }
}
