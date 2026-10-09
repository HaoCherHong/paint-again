import AppKit

// Draws a plain gradient squircle tile, stacks one or more transparent glyph layers on it (same framing,
// scaled to ~70 % of the tile) and writes a 1024 px PNG — the classic (pre-Liquid-Glass) icon for macOS 14 / 15.
// Usage: compose-legacy-icon <out.png> <layer.png> [more layers…]   (env ICON_TOP / ICON_BOTTOM = hex colours)
let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: compose-legacy-icon <out.png> <layer.png> [more layers…]\n".data(using: .utf8)!)
    exit(1)
}
func color(_ hex: String) -> NSColor {
    var s = hex; if s.hasPrefix("#") { s.removeFirst() }
    let v = UInt32(s, radix: 16) ?? 0
    return NSColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}
let env = ProcessInfo.processInfo.environment
let top = color(env["ICON_TOP"] ?? "#3A3D45"), bottom = color(env["ICON_BOTTOM"] ?? "#17191E")
// A layer argument may carry an offset in source pixels and a shadow flag: "path.png@dx,dy[,shadow]"
// (positive dy moves it down). ICON_GLYPH_SCALE (default 0.7) sets how much of the tile the layers span.
struct Layer { let image: NSImage; let offset: CGPoint; let shadow: Bool }
let layers: [Layer] = args.dropFirst(2).compactMap { arg in
    let parts = arg.split(separator: "@", maxSplits: 1).map(String.init)
    guard let img = NSImage(contentsOfFile: parts[0]) else { return nil }
    var offset = CGPoint.zero, shadow = false
    if parts.count == 2 {
        let fields = parts[1].split(separator: ",").map(String.init)
        let xy = fields.compactMap { Double($0) }
        if xy.count >= 2 { offset = CGPoint(x: xy[0], y: xy[1]) }
        shadow = fields.contains("shadow")
    }
    return Layer(image: img, offset: offset, shadow: shadow)
}
let glyphScale = CGFloat(Double(env["ICON_GLYPH_SCALE"] ?? "") ?? 0.62)
/// Fraction of the tile the group's actual (alpha) bounding box may span; the group is then centred.
let groupFit = CGFloat(Double(env["ICON_GROUP_FIT"] ?? "") ?? 0.66)
/// Optical adjustments as fractions of the tile: positive lift moves the group up, positive shift moves it right.
let opticalLift = CGFloat(Double(env["ICON_OPTICAL_LIFT"] ?? "") ?? -0.01)
let opticalShift = CGFloat(Double(env["ICON_OPTICAL_SHIFT"] ?? "") ?? 0.0)

/// Bounding box (top-left origin, source pixels) of pixels with alpha > 10 %.
func alphaBounds(_ img: NSImage) -> CGRect {
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return CGRect(origin: .zero, size: img.size) }
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    guard maxX >= 0 else { return CGRect(origin: .zero, size: img.size) }
    let sx = img.size.width / CGFloat(rep.pixelsWide), sy = img.size.height / CGFloat(rep.pixelsHigh)
    return CGRect(x: CGFloat(minX) * sx, y: CGFloat(minY) * sy, width: CGFloat(maxX - minX + 1) * sx, height: CGFloat(maxY - minY + 1) * sy)
}
// Union of all layers' content (with offsets) in source space, top-left origin.
let groupBounds: CGRect = layers.map { alphaBounds($0.image).offsetBy(dx: $0.offset.x, dy: $0.offset.y) }.reduce(CGRect.null) { $0.union($1) }
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    // Apple's icon grid: the tile fills ~82 % of the canvas.
    let tile = rect.insetBy(dx: size * 0.09, dy: size * 0.09)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(colors: [top, bottom])!.draw(in: path, angle: -90)
    // Scale so the group's real bounding box spans `groupFit` of the tile, then centre that box.
    let scale = min(tile.width * groupFit / groupBounds.width, tile.height * groupFit / groupBounds.height)
    let groupCenterSrc = CGPoint(x: groupBounds.midX, y: groupBounds.midY)
    let target = CGPoint(x: tile.midX + tile.width * opticalShift, y: tile.midY + tile.height * opticalLift)
    for layer in layers {
        let img = layer.image
        // Where this layer's (0,0) source corner lands, given that the group centre maps to `target`.
        let originX = target.x + (layer.offset.x - groupCenterSrc.x) * scale
        let originYTop = target.y - (layer.offset.y - groupCenterSrc.y) * scale   // y-up: source top edge
        let r = NSRect(x: originX, y: originYTop - img.size.height * scale, width: img.size.width * scale, height: img.size.height * scale)
        NSGraphicsContext.current?.saveGraphicsState()
        if layer.shadow {
            let sh = NSShadow()
            sh.shadowColor = NSColor(white: 0, alpha: 0.38)
            sh.shadowBlurRadius = size * 0.022
            sh.shadowOffset = NSSize(width: 0, height: -size * 0.012)
            sh.set()
        }
        img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.current?.restoreGraphicsState()
    }
    return true
}
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
