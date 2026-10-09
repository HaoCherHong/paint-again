import AppKit

enum ShapePaths {
    static func path(for kind: ShapeKind, in r: CGRect) -> CGPath {
        let w = r.width, h = r.height, x = r.minX, y = r.minY
        func pt(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { CGPoint(x: x + fx * w, y: y + fy * h) }
        func polygon(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
            let p = CGMutablePath()
            p.addLines(between: pts.map { pt($0.0, $0.1) })
            p.closeSubpath()
            return p
        }
        func star(points n: Int, inner: CGFloat) -> CGPath {
            var pts: [CGPoint] = []
            for i in 0..<(n * 2) {
                let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / CGFloat(n)
                let rad: CGFloat = i % 2 == 0 ? 1 : inner
                pts.append(CGPoint(x: r.midX + cos(a) * w / 2 * rad, y: r.midY + sin(a) * h / 2 * rad))
            }
            let p = CGMutablePath()
            p.addLines(between: pts)
            p.closeSubpath()
            return p
        }
        func regular(_ n: Int) -> CGPath {
            var pts: [CGPoint] = []
            for i in 0..<n {
                let a = -CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / CGFloat(n)
                pts.append(CGPoint(x: r.midX + cos(a) * w / 2, y: r.midY + sin(a) * h / 2))
            }
            let p = CGMutablePath()
            p.addLines(between: pts)
            p.closeSubpath()
            return p
        }
        func ellipsePoints(center: CGPoint, rx: CGFloat, ry: CGFloat, from a0: CGFloat, to a1: CGFloat, steps: Int = 64) -> [CGPoint] {
            (0...steps).map { i in
                let a = a0 + (a1 - a0) * CGFloat(i) / CGFloat(steps)
                return CGPoint(x: center.x + cos(a) * rx, y: center.y + sin(a) * ry)
            }
        }

        switch kind {
        case .line, .curve, .polygon:
            return CGPath(rect: r, transform: nil)
        case .oval:
            return CGPath(ellipseIn: r, transform: nil)
        case .rectangle:
            return CGPath(rect: r, transform: nil)
        case .roundedRectangle:
            let rad = min(w, h) * 0.2
            return CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
        case .triangle:
            return polygon([(0.5, 0), (1, 1), (0, 1)])
        case .rightTriangle:
            return polygon([(0, 0), (0, 1), (1, 1)])
        case .diamond:
            return polygon([(0.5, 0), (1, 0.5), (0.5, 1), (0, 0.5)])
        case .pentagon:
            return regular(5)
        case .hexagon:
            return polygon([(0.25, 0), (0.75, 0), (1, 0.5), (0.75, 1), (0.25, 1), (0, 0.5)])
        case .rightArrow:
            return polygon([(0, 0.25), (0.6, 0.25), (0.6, 0), (1, 0.5), (0.6, 1), (0.6, 0.75), (0, 0.75)])
        case .leftArrow:
            return polygon([(1, 0.25), (0.4, 0.25), (0.4, 0), (0, 0.5), (0.4, 1), (0.4, 0.75), (1, 0.75)])
        case .upArrow:
            return polygon([(0.25, 1), (0.25, 0.4), (0, 0.4), (0.5, 0), (1, 0.4), (0.75, 0.4), (0.75, 1)])
        case .downArrow:
            return polygon([(0.25, 0), (0.25, 0.6), (0, 0.6), (0.5, 1), (1, 0.6), (0.75, 0.6), (0.75, 0)])
        case .fourPointStar:
            return star(points: 4, inner: 0.38)
        case .fivePointStar:
            return star(points: 5, inner: 0.382)
        case .sixPointStar:
            return star(points: 6, inner: 0.577)
        case .roundedCallout:
            let body = CGRect(x: x, y: y, width: w, height: h * 0.75)
            let rad = min(body.width, body.height) * 0.2
            let p = CGMutablePath()
            p.move(to: CGPoint(x: body.minX + rad, y: body.minY))
            p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.maxY), radius: rad)
            p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.maxY), radius: rad)
            p.addLine(to: pt(0.4, 0.75))
            p.addLine(to: pt(0.15, 1))
            p.addLine(to: pt(0.25, 0.75))
            p.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.minY), radius: rad)
            p.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.minY), radius: rad)
            p.closeSubpath()
            return p
        case .ovalCallout:
            let c = CGPoint(x: r.midX, y: y + h * 0.375)
            let deg = CGFloat.pi / 180
            var pts = ellipsePoints(center: c, rx: w / 2, ry: h * 0.375, from: 130 * deg, to: 465 * deg)
            pts.append(pt(0.15, 1))
            let p = CGMutablePath()
            p.addLines(between: pts)
            p.closeSubpath()
            return p
        case .cloudCallout:
            let c = CGPoint(x: r.midX, y: y + h * 0.36)
            let rx = w * 0.46, ry = h * 0.33
            var pts: [CGPoint] = []
            let steps = 180
            for i in 0..<steps {
                let a = CGFloat(i) / CGFloat(steps) * 2 * .pi
                let bump = 0.86 + 0.14 * abs(sin(a * 4.5))
                pts.append(CGPoint(x: c.x + cos(a) * rx * bump, y: c.y + sin(a) * ry * bump))
            }
            let p = CGMutablePath()
            p.addLines(between: pts)
            p.closeSubpath()
            p.addEllipse(in: CGRect(x: x + w * 0.22, y: y + h * 0.72, width: w * 0.12, height: h * 0.1))
            p.addEllipse(in: CGRect(x: x + w * 0.12, y: y + h * 0.86, width: w * 0.08, height: h * 0.07))
            return p
        case .lightning:
            return polygon([(0.35, 0), (0.7, 0), (0.55, 0.38), (0.8, 0.38), (0.3, 1), (0.42, 0.58), (0.18, 0.58)])
        }
    }

    /// Path for line / curve / polygon shapes defined by explicit points.
    static func path(points: [CGPoint], controls: [CGPoint], kind: ShapeKind) -> CGPath {
        let p = CGMutablePath()
        guard let first = points.first else { return p }
        p.move(to: first)
        switch kind {
        case .curve where points.count >= 2:
            let end = points[1]
            if controls.count >= 2 {
                p.addCurve(to: end, control1: controls[0], control2: controls[1])
            } else if controls.count == 1 {
                p.addQuadCurve(to: end, control: controls[0])
            } else {
                p.addLine(to: end)
            }
        case .polygon:
            for q in points.dropFirst() { p.addLine(to: q) }
            if points.count > 2 { p.closeSubpath() }
        default:
            for q in points.dropFirst() { p.addLine(to: q) }
        }
        return p
    }
}
