import AppKit

/// An RGBA8 (premultiplied, R-G-B-A byte order, sRGB) raster whose drawing coordinates
/// have their origin at the top-left corner, matching image pixel coordinates.
/// The context is tagged sRGB so on-screen rendering and colour comparisons match the
/// sRGB colours used by the tools; a DeviceRGB tag would display raw values unmanaged.
final class Bitmap {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let context: CGContext
    let data: UnsafeMutablePointer<UInt8>

    var size: CGSize { CGSize(width: width, height: height) }
    var bounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }

    init(width: Int, height: Int) {
        let w = max(1, width), h = max(1, height)
        self.width = w
        self.height = h
        self.bytesPerRow = w * 4
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: Bitmap.colorSpace,
                                  bitmapInfo: info) else {
            fatalError("Could not create bitmap context \(w)x\(h)")
        }
        self.context = ctx
        self.data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        // Flip so that y grows downward.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
    }

    convenience init(copying other: Bitmap) {
        self.init(width: other.width, height: other.height)
        memcpy(data, other.data, bytesPerRow * height)
    }

    convenience init(image: CGImage) {
        self.init(width: image.width, height: image.height)
        draw(image, in: bounds)
    }

    var byteCount: Int { bytesPerRow * height }

    func makeImage() -> CGImage? { context.makeImage() }

    func clear() { memset(data, 0, byteCount) }

    func fill(_ color: NSColor) {
        context.saveGState()
        context.setBlendMode(.copy)
        context.setFillColor(color.cgColor)
        context.fill(bounds)
        context.restoreGState()
    }

    /// Draws an image using top-left based coordinates.
    func draw(_ image: CGImage, in rect: CGRect, blend: CGBlendMode = .normal, alpha: CGFloat = 1, interpolate: Bool = true) {
        context.saveGState()
        context.setBlendMode(blend)
        context.setAlpha(alpha)
        context.interpolationQuality = interpolate ? .high : .none
        // Compensate for the flip so images are not drawn upside down.
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    func snapshot() -> Data { Data(bytes: data, count: byteCount) }

    func restore(_ snapshot: Data) {
        guard snapshot.count == byteCount else { return }
        _ = snapshot.withUnsafeBytes { buf in
            memcpy(data, buf.baseAddress!, byteCount)
        }
    }

    struct Pixel: Equatable {
        var r: UInt8, g: UInt8, b: UInt8, a: UInt8
    }

    @inline(__always) func pixel(x: Int, y: Int) -> Pixel {
        let p = data + y * bytesPerRow + x * 4
        return Pixel(r: p[0], g: p[1], b: p[2], a: p[3])
    }

    @inline(__always) func setPixel(_ px: Pixel, x: Int, y: Int) {
        let p = data + y * bytesPerRow + x * 4
        p[0] = px.r; p[1] = px.g; p[2] = px.b; p[3] = px.a
    }

    func contains(x: Int, y: Int) -> Bool { x >= 0 && y >= 0 && x < width && y < height }

    /// Unpremultiplied color at a point, or nil when outside.
    func color(at point: CGPoint) -> NSColor? {
        let x = Int(floor(point.x)), y = Int(floor(point.y))
        guard contains(x: x, y: y) else { return nil }
        let p = pixel(x: x, y: y)
        if p.a == 0 { return NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0) }
        let a = CGFloat(p.a) / 255
        return NSColor(srgbRed: CGFloat(p.r) / 255 / a, green: CGFloat(p.g) / 255 / a, blue: CGFloat(p.b) / 255 / a, alpha: a)
    }

    static func premultiplied(_ color: NSColor) -> Pixel {
        let c = color.usingColorSpace(.sRGB) ?? color
        let a = c.alphaComponent
        return Pixel(r: UInt8(clamping: Int((c.redComponent * a * 255).rounded())),
                     g: UInt8(clamping: Int((c.greenComponent * a * 255).rounded())),
                     b: UInt8(clamping: Int((c.blueComponent * a * 255).rounded())),
                     a: UInt8(clamping: Int((a * 255).rounded())))
    }

    /// Returns a copy of `rect` (clipped to bounds) as a standalone image.
    func cropped(to rect: CGRect) -> CGImage? {
        let r = rect.integral.intersection(bounds)
        guard !r.isEmpty, let img = makeImage() else { return nil }
        return img.cropping(to: r)
    }

    /// Returns a new bitmap scaled to the given size.
    func resized(to size: CGSize, interpolate: Bool = true) -> Bitmap {
        let out = Bitmap(width: Int(size.width.rounded()), height: Int(size.height.rounded()))
        if let img = makeImage() { out.draw(img, in: out.bounds, interpolate: interpolate) }
        return out
    }

    /// Returns a new bitmap containing this bitmap transformed by `transform`, sized `newSize`.
    func transformed(size newSize: CGSize, _ transform: CGAffineTransform) -> Bitmap {
        let out = Bitmap(width: Int(newSize.width.rounded()), height: Int(newSize.height.rounded()))
        guard let img = makeImage() else { return out }
        let ctx = out.context
        ctx.saveGState()
        ctx.concatenate(transform)
        // draw image un-flipped inside the (already flipped) context
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: width, height: height))
        ctx.restoreGState()
        return out
    }

    /// Makes every pixel that matches `color` (ignoring alpha, exact RGB) fully transparent.
    func makeTransparent(matching color: NSColor) {
        let target = Bitmap.premultiplied(color.withAlphaComponent(1))
        for y in 0..<height {
            let row = data + y * bytesPerRow
            for x in 0..<width {
                let p = row + x * 4
                if p[3] == 255 && p[0] == target.r && p[1] == target.g && p[2] == target.b {
                    p[0] = 0; p[1] = 0; p[2] = 0; p[3] = 0
                }
            }
        }
    }

    /// Multiplies alpha by `mask` (a grayscale image scaled to this bitmap's size).
    func applyAlphaMask(_ mask: CGImage) {
        let maskBitmap = Bitmap(width: width, height: height)
        maskBitmap.draw(mask, in: maskBitmap.bounds)
        for y in 0..<height {
            let row = data + y * bytesPerRow
            let mrow = maskBitmap.data + y * maskBitmap.bytesPerRow
            for x in 0..<width {
                let p = row + x * 4
                let m = Int(mrow[x * 4])  // red channel of gray mask
                if m == 255 { continue }
                p[0] = UInt8(Int(p[0]) * m / 255)
                p[1] = UInt8(Int(p[1]) * m / 255)
                p[2] = UInt8(Int(p[2]) * m / 255)
                p[3] = UInt8(Int(p[3]) * m / 255)
            }
        }
    }
}
