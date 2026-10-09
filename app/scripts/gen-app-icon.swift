import AppKit
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let inset = rect.insetBy(dx: size * 0.1, dy: size * 0.1)
    let path = NSBezierPath(roundedRect: inset, xRadius: size * 0.2, yRadius: size * 0.2)
    let gradient = NSGradient(colors: [NSColor(red: 0.16, green: 0.53, blue: 0.9, alpha: 1), NSColor(red: 0.0, green: 0.36, blue: 0.75, alpha: 1)])!
    gradient.draw(in: path, angle: -90)
    // Paper
    let paper = NSBezierPath(roundedRect: NSRect(x: size * 0.24, y: size * 0.26, width: size * 0.52, height: size * 0.48), xRadius: 24, yRadius: 24)
    NSColor.white.setFill(); paper.fill()
    // Brush strokes
    let colors: [NSColor] = [NSColor(red: 0.93, green: 0.11, blue: 0.14, alpha: 1), NSColor(red: 1, green: 0.79, blue: 0.05, alpha: 1), NSColor(red: 0.13, green: 0.69, blue: 0.3, alpha: 1)]
    for (i, c) in colors.enumerated() {
        let stroke = NSBezierPath()
        let y = size * (0.62 - CGFloat(i) * 0.12)
        stroke.move(to: NSPoint(x: size * 0.3, y: y))
        stroke.curve(to: NSPoint(x: size * 0.7, y: y), controlPoint1: NSPoint(x: size * 0.42, y: y + size * 0.06), controlPoint2: NSPoint(x: size * 0.58, y: y - size * 0.06))
        stroke.lineWidth = size * 0.045
        stroke.lineCapStyle = .round
        c.setStroke(); stroke.stroke()
    }
    return true
}
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
