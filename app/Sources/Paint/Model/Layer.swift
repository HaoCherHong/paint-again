import AppKit

final class Layer {
    let id: UUID
    var name: String
    var isVisible: Bool
    var opacity: CGFloat
    var bitmap: Bitmap

    init(name: String, bitmap: Bitmap, isVisible: Bool = true, opacity: CGFloat = 1, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.bitmap = bitmap
        self.isVisible = isVisible
        self.opacity = opacity
    }

    func copy(name: String? = nil) -> Layer {
        Layer(name: name ?? self.name, bitmap: Bitmap(copying: bitmap), isVisible: isVisible, opacity: opacity)
    }

    struct Snapshot {
        let id: UUID
        let name: String
        let isVisible: Bool
        let opacity: CGFloat
        let width: Int
        let height: Int
        let pixels: Data
    }

    func snapshot() -> Snapshot {
        Snapshot(id: id, name: name, isVisible: isVisible, opacity: opacity,
                 width: bitmap.width, height: bitmap.height, pixels: bitmap.snapshot())
    }

    static func restore(_ s: Snapshot) -> Layer {
        let bmp = Bitmap(width: s.width, height: s.height)
        bmp.restore(s.pixels)
        return Layer(name: s.name, bitmap: bmp, isVisible: s.isVisible, opacity: s.opacity, id: s.id)
    }
}
