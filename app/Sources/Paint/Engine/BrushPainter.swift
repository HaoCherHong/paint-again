import AppKit

/// Renders one stroke of a gallery brush into a bitmap. Used by the Brush tool while painting and by the
/// brush gallery to draw stroke previews with the real algorithms.
final class BrushPainter {
    let brush: BrushKind
    let width: CGFloat
    let color: NSColor
    let buffer: Bitmap
    private(set) var points: [CGPoint] = []
    private var rng: SeededRandom
    private var bristles: [(offset: CGFloat, width: CGFloat, alpha: CGFloat)] = []

    /// Alpha to use when compositing `buffer` onto the layer (before the user's opacity setting).
    var compositeAlpha: CGFloat { brush == .marker ? 0.5 : 1 }

    /// Diameter of the footprint painted around the pointer, in image pixels.
    static func footprint(for brush: BrushKind, width: CGFloat) -> CGFloat {
        switch brush {
        case .watercolor: return width * 1.5
        default: return width
        }
    }

    init(brush: BrushKind, width: CGFloat, color: NSColor, size: CGSize, seed: UInt64) {
        self.brush = brush
        self.width = max(1, width)
        self.color = color
        self.buffer = Bitmap(width: Int(size.width), height: Int(size.height))
        self.rng = SeededRandom(seed: seed)
        if brush == .oil {
            let n = 7
            bristles = (0..<n).map { i in
                let t = (CGFloat(i) + 0.5) / CGFloat(n) - 0.5
                return (offset: t * self.width, width: self.width / CGFloat(n) * 1.6, alpha: 0.55 + rng.nextCGFloat() * 0.45)
            }
        }
    }

    private var rendersWholeStroke: Bool {
        switch brush {
        case .brush, .marker, .watercolor, .naturalPencil: return true
        default: return false
        }
    }

    func begin(at p: CGPoint) {
        points = [p]
        render(segmentFrom: p, to: p)
    }

    func extend(to p: CGPoint) {
        guard let last = points.last else { begin(at: p); return }
        if last == p { return }
        points.append(p)
        render(segmentFrom: last, to: p)
    }

    private func render(segmentFrom a: CGPoint, to b: CGPoint) {
        if rendersWholeStroke { renderWhole() } else { renderSegment(from: a, to: b) }
    }

    private func renderWhole() {
        buffer.clear()
        let ctx = buffer.context
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let path = CGMutablePath()
        if points.count == 1 {
            path.move(to: points[0]); path.addLine(to: points[0])
        } else {
            path.addLines(between: points)
        }
        switch brush {
        case .brush:
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(width)
            ctx.addPath(path); ctx.strokePath()
        case .marker:
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineCap(.square)
            ctx.setLineJoin(.bevel)
            ctx.setLineWidth(width)
            ctx.addPath(path); ctx.strokePath()
        case .watercolor:
            for (scale, alpha) in [(1.5, 0.12), (1.15, 0.18), (0.8, 0.28), (0.45, 0.35)] as [(CGFloat, CGFloat)] {
                ctx.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
                ctx.setLineWidth(width * scale)
                ctx.addPath(path); ctx.strokePath()
            }
        case .naturalPencil:
            ctx.setLineWidth(max(1, width / 3))
            for pass in 0..<3 {
                let jittered = CGMutablePath()
                var seeded = SeededRandom(seed: UInt64(pass * 7919 + 13))
                let amp = width * 0.35
                let pts = points.map { CGPoint(x: $0.x + (seeded.nextCGFloat() - 0.5) * amp, y: $0.y + (seeded.nextCGFloat() - 0.5) * amp) }
                if pts.count == 1 { jittered.move(to: pts[0]); jittered.addLine(to: pts[0]) } else { jittered.addLines(between: pts) }
                ctx.setStrokeColor(color.withAlphaComponent(0.4).cgColor)
                ctx.addPath(jittered); ctx.strokePath()
            }
        default:
            break
        }
        ctx.restoreGState()
    }

    private func renderSegment(from a: CGPoint, to b: CGPoint) {
        let ctx = buffer.context
        ctx.saveGState()
        switch brush {
        case .calligraphy1, .calligraphy2:
            let angle: CGFloat = brush == .calligraphy1 ? -.pi / 4 : .pi / 4
            let n = CGPoint(x: cos(angle), y: sin(angle)) * (width / 2)
            ctx.setFillColor(color.cgColor)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(1)
            let quad = CGMutablePath()
            quad.addLines(between: [a - n, a + n, b + n, b - n])
            quad.closeSubpath()
            ctx.addPath(quad); ctx.drawPath(using: .fillStroke)
        case .airbrush:
            spray(at: b)
            let d = a.distance(to: b)
            if d > 2 {
                let steps = Int(d / 2)
                for i in 1..<max(2, steps) {
                    let t = CGFloat(i) / CGFloat(steps)
                    spray(at: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), density: 0.3)
                }
            }
        case .oil:
            let d = b - a
            let len = max(0.001, d.length)
            let perp = CGPoint(x: -d.y / len, y: d.x / len)
            ctx.setLineCap(.round)
            for br in bristles {
                let off = perp * br.offset
                ctx.setStrokeColor(color.withAlphaComponent(br.alpha).cgColor)
                ctx.setLineWidth(br.width)
                ctx.move(to: a + off); ctx.addLine(to: b + off)
                ctx.strokePath()
            }
        case .crayon:
            let len = a.distance(to: b)
            let count = min(600, max(6, Int(len * width * 0.5)))
            for _ in 0..<count {
                let t = rng.nextCGFloat()
                let center = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                let spread = (rng.nextCGFloat() + rng.nextCGFloat() - 1) * width / 2
                let ang = rng.nextCGFloat() * 2 * .pi
                let p = CGPoint(x: center.x + cos(ang) * spread, y: center.y + sin(ang) * spread)
                let size = 0.8 + rng.nextCGFloat() * 1.4
                ctx.setFillColor(color.withAlphaComponent(0.25 + rng.nextCGFloat() * 0.45).cgColor)
                ctx.fillEllipse(in: CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size))
            }
        default:
            break
        }
        ctx.restoreGState()
    }

    /// Sprays airbrush dots inside the brush footprint centred on `p`.
    func spray(at p: CGPoint, density: CGFloat = 1) {
        let ctx = buffer.context
        let radius = max(1, width / 2)
        let count = max(1, Int(radius * 2.4 * density))
        ctx.setFillColor(color.cgColor)
        for _ in 0..<count {
            let r = sqrt(rng.nextCGFloat()) * radius
            let ang = rng.nextCGFloat() * 2 * .pi
            let q = CGPoint(x: p.x + cos(ang) * r, y: p.y + sin(ang) * r)
            ctx.fill(CGRect(x: floor(q.x), y: floor(q.y), width: 1, height: 1))
        }
    }

    // MARK: - Gallery previews

    private static var previewCache: [String: NSImage] = [:]

    /// A sample stroke drawn with the brush, for the gallery and the ribbon button.
    static func preview(for brush: BrushKind, size: CGSize = CGSize(width: 72, height: 30), color: NSColor) -> NSImage {
        let key = "\(brush.rawValue)-\(Int(size.width))x\(Int(size.height))-\(color.hexString)"
        if let img = previewCache[key] { return img }
        let painter = BrushPainter(brush: brush, width: 9, color: color, size: size, seed: 42)
        let pts = stride(from: 8, through: size.width - 8, by: 3).map { x -> CGPoint in
            let t = (x - 8) / (size.width - 16)
            return CGPoint(x: x, y: size.height / 2 + sin(t * .pi * 2) * size.height * 0.22)
        }
        painter.begin(at: pts[0])
        for p in pts.dropFirst() { painter.extend(to: p) }
        if brush == .airbrush { for p in pts { painter.spray(at: p, density: 1.5) } }
        let out = Bitmap(width: Int(size.width), height: Int(size.height))
        if let img = painter.buffer.makeImage() { out.draw(img, in: out.bounds, alpha: painter.compositeAlpha) }
        let image = out.makeImage().map { NSImage(cgImage: $0, size: size) } ?? NSImage(size: size)
        previewCache[key] = image
        return image
    }
}

/// Deterministic xorshift generator so textured brushes stay stable across redraws.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
    mutating func nextCGFloat() -> CGFloat { CGFloat(next() % 1_000_000) / 1_000_000 }
}
