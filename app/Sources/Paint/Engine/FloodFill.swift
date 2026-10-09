import Foundation

enum FloodFill {
    /// Scanline flood fill replacing the contiguous colour at (x, y) with `fill`.
    static func fill(_ bmp: Bitmap, x: Int, y: Int, fill: Bitmap.Pixel) {
        guard bmp.contains(x: x, y: y) else { return }
        let w = bmp.width, h = bmp.height, bpr = bmp.bytesPerRow
        let data = bmp.data
        let target = bmp.pixel(x: x, y: y)
        if target == fill { return }
        @inline(__always) func matches(_ px: Int, _ py: Int) -> Bool {
            let p = data + py * bpr + px * 4
            return p[0] == target.r && p[1] == target.g && p[2] == target.b && p[3] == target.a
        }
        @inline(__always) func set(_ px: Int, _ py: Int) {
            let p = data + py * bpr + px * 4
            p[0] = fill.r; p[1] = fill.g; p[2] = fill.b; p[3] = fill.a
        }
        var stack: [(Int, Int)] = [(x, y)]
        stack.reserveCapacity(1024)
        while let (sx, sy) = stack.popLast() {
            guard matches(sx, sy) else { continue }
            var left = sx
            while left > 0 && matches(left - 1, sy) { left -= 1 }
            var right = sx
            while right < w - 1 && matches(right + 1, sy) { right += 1 }
            for px in left...right { set(px, sy) }
            for ny in [sy - 1, sy + 1] where ny >= 0 && ny < h {
                var px = left
                while px <= right {
                    if matches(px, ny) {
                        stack.append((px, ny))
                        while px <= right && matches(px, ny) { px += 1 }
                    } else {
                        px += 1
                    }
                }
            }
        }
    }
}
