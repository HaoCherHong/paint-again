import AppKit
import UniformTypeIdentifiers

extension Notification.Name {
    /// Pixel content or structure of the document changed; observers should redraw.
    static let documentDidChange = Notification.Name("PaintDocumentDidChange")
    /// Layer list (order, count, visibility, active) changed.
    static let layersDidChange = Notification.Name("PaintLayersDidChange")
}

final class PaintDocument: NSDocument {
    static let defaultSize = CGSize(width: 1152, height: 648)

    private(set) var canvasSize: CGSize = PaintDocument.defaultSize
    private(set) var layers: [Layer] = []
    /// Solid colour shown beneath all layers (the fixed "Background" entry of the Layers panel).
    private(set) var backgroundColor: NSColor = .white
    private(set) var backgroundVisible = true
    var activeLayerIndex: Int = 0 {
        didSet {
            activeLayerIndex = max(0, min(layers.count - 1, activeLayerIndex))
            if oldValue != activeLayerIndex { NotificationCenter.default.post(name: .layersDidChange, object: self) }
        }
    }
    let toolState = ToolState()

    var activeLayer: Layer { layers[activeLayerIndex] }
    var canvasRect: CGRect { CGRect(origin: .zero, size: canvasSize) }
    var isBottomLayer: Bool { activeLayerIndex == 0 }

    override init() {
        super.init()
        let bmp = Bitmap(width: Int(Self.defaultSize.width), height: Int(Self.defaultSize.height))
        layers = [Layer(name: String(format: L("Layer %d"), 1), bitmap: bmp)]
        undoManager?.levelsOfUndo = 50
        hasUndoManager = true
    }

    override class var autosavesInPlace: Bool { false }
    override class var readableTypes: [String] {
        ["public.png", "public.jpeg", "com.microsoft.bmp", "com.compuserve.gif", "public.tiff", "public.heic", "public.image"]
    }
    override class var writableTypes: [String] {
        ["public.png", "public.jpeg", "com.microsoft.bmp", "com.compuserve.gif", "public.tiff"]
    }
    override class func isNativeType(_ type: String) -> Bool { true }

    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] { Self.writableTypes }

    override func makeWindowControllers() {
        addWindowController(MainWindowController(document: self))
    }

    // MARK: - Reading / writing

    override func read(from data: Data, ofType typeName: String) throws {
        guard let rep = NSBitmapImageRep(data: data) ?? (NSImage(data: data)?.representations.first as? NSBitmapImageRep),
              let cg = rep.cgImage else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError,
                          userInfo: [NSLocalizedDescriptionKey: L("The file could not be read as an image.")])
        }
        let bmp = Bitmap(image: cg)
        canvasSize = bmp.size
        layers = [Layer(name: String(format: L("Layer %d"), 1), bitmap: bmp)]
        backgroundColor = .white
        backgroundVisible = true
        activeLayerIndex = 0
        undoManager?.removeAllActions()
        NotificationCenter.default.post(name: .layersDidChange, object: self)
        NotificationCenter.default.post(name: .documentDidChange, object: self)
    }

    override func data(ofType typeName: String) throws -> Data {
        let supportsAlpha = typeName == "public.png" || typeName == "public.tiff" || typeName == "com.compuserve.gif"
        guard let cg = flattenedImage(background: supportsAlpha ? nil : (backgroundVisible ? backgroundColor : .white)) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError)
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        let fileType: NSBitmapImageRep.FileType
        var props: [NSBitmapImageRep.PropertyKey: Any] = [:]
        switch typeName {
        case "public.jpeg": fileType = .jpeg; props[.compressionFactor] = 0.92
        case "com.microsoft.bmp": fileType = .bmp
        case "com.compuserve.gif": fileType = .gif
        case "public.tiff": fileType = .tiff
        default: fileType = .png
        }
        guard let out = rep.representation(using: fileType, properties: props) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError)
        }
        return out
    }

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let info = NSPrintInfo(dictionary: printSettings)
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        let view = NSImageView(frame: canvasRect)
        if let cg = flattenedImage(background: .white) {
            view.image = NSImage(cgImage: cg, size: canvasSize)
        }
        return NSPrintOperation(view: view, printInfo: info)
    }

    /// Composites the background colour (when visible) and all visible layers.
    /// `background` forces an opaque backdrop for formats without alpha.
    func flattenedImage(background: NSColor? = nil, onlyVisible: Bool = true) -> CGImage? {
        let out = Bitmap(width: Int(canvasSize.width), height: Int(canvasSize.height))
        if let bg = background { out.fill(bg) }
        if backgroundVisible { out.fill(backgroundColor) }
        for layer in layers where (layer.isVisible || !onlyVisible) {
            if let img = layer.bitmap.makeImage() {
                out.draw(img, in: out.bounds, alpha: layer.opacity)
            }
        }
        return out.makeImage()
    }

    // MARK: - Undo support

    struct Snapshot {
        let canvasSize: CGSize
        let layers: [Layer.Snapshot]
        let activeIndex: Int
        let backgroundColor: NSColor
        let backgroundVisible: Bool
    }

    func captureAll() -> Snapshot {
        Snapshot(canvasSize: canvasSize, layers: layers.map { $0.snapshot() }, activeIndex: activeLayerIndex,
                 backgroundColor: backgroundColor, backgroundVisible: backgroundVisible)
    }

    @objc private func restoreAll(_ box: SnapshotBox) {
        let redo = captureAll()
        undoManager?.registerUndo(withTarget: self, selector: #selector(restoreAll(_:)), object: SnapshotBox(redo))
        let s = box.snapshot
        canvasSize = s.canvasSize
        layers = s.layers.map { Layer.restore($0) }
        activeLayerIndex = s.activeIndex
        backgroundColor = s.backgroundColor
        backgroundVisible = s.backgroundVisible
        notifyLayersChanged()
        notifyChanged()
    }

    @objc private func restoreLayer(_ box: LayerSnapshotBox) {
        let s = box.snapshot
        guard let layer = layers.first(where: { $0.id == s.id }) else { return }
        undoManager?.registerUndo(withTarget: self, selector: #selector(restoreLayer(_:)), object: LayerSnapshotBox(layer.snapshot()))
        if layer.bitmap.width == s.width && layer.bitmap.height == s.height {
            layer.bitmap.restore(s.pixels)
        } else {
            let bmp = Bitmap(width: s.width, height: s.height)
            bmp.restore(s.pixels)
            layer.bitmap = bmp
        }
        layer.name = s.name
        layer.isVisible = s.isVisible
        layer.opacity = s.opacity
        notifyChanged()
    }

    /// Runs a change that may alter canvas size or the layer list, recording a full undo snapshot.
    func performStructuralChange(_ name: String, _ body: () -> Void) {
        let before = captureAll()
        body()
        undoManager?.registerUndo(withTarget: self, selector: #selector(restoreAll(_:)), object: SnapshotBox(before))
        undoManager?.setActionName(name)
        notifyLayersChanged()
        notifyChanged()
    }

    /// Runs a change to a single layer's pixels or metadata, recording only that layer.
    func performLayerChange(_ name: String, layer: Layer? = nil, _ body: (Layer) -> Void) {
        let target = layer ?? activeLayer
        let before = target.snapshot()
        body(target)
        commitLayerEdit(before, name: name)
    }

    /// Begins an interactive edit of a layer; pair with `commitLayerEdit`.
    func beginLayerEdit(_ layer: Layer? = nil) -> Layer.Snapshot {
        (layer ?? activeLayer).snapshot()
    }

    func commitLayerEdit(_ before: Layer.Snapshot, name: String) {
        undoManager?.registerUndo(withTarget: self, selector: #selector(restoreLayer(_:)), object: LayerSnapshotBox(before))
        undoManager?.setActionName(name)
        notifyChanged()
    }

    func notifyChanged() {
        NotificationCenter.default.post(name: .documentDidChange, object: self)
    }

    func notifyLayersChanged() {
        NotificationCenter.default.post(name: .layersDidChange, object: self)
    }

    // MARK: - Layer operations

    func addLayer() {
        performStructuralChange(L("Add layer")) {
            let bmp = Bitmap(width: Int(canvasSize.width), height: Int(canvasSize.height))
            let layer = Layer(name: String(format: L("Layer %d"), layers.count + 1), bitmap: bmp)
            layers.insert(layer, at: activeLayerIndex + 1)
            activeLayerIndex += 1
        }
    }

    func duplicateLayer() {
        performStructuralChange(L("Duplicate layer")) {
            let copy = activeLayer.copy(name: activeLayer.name + " " + L("copy"))
            layers.insert(copy, at: activeLayerIndex + 1)
            activeLayerIndex += 1
        }
    }

    func deleteLayer() {
        guard layers.count > 1 else { return }
        performStructuralChange(L("Delete layer")) {
            layers.remove(at: activeLayerIndex)
            activeLayerIndex = min(activeLayerIndex, layers.count - 1)
        }
    }

    func mergeLayerDown() {
        guard activeLayerIndex > 0 else { return }
        performStructuralChange(L("Merge down")) {
            let top = layers[activeLayerIndex]
            let below = layers[activeLayerIndex - 1]
            if top.isVisible, let img = top.bitmap.makeImage() {
                below.bitmap.draw(img, in: below.bitmap.bounds, alpha: top.opacity)
            }
            layers.remove(at: activeLayerIndex)
            activeLayerIndex -= 1
        }
    }

    func moveLayer(up: Bool) {
        let target = activeLayerIndex + (up ? 1 : -1)
        guard target >= 0 && target < layers.count else { return }
        performStructuralChange(up ? L("Move layer up") : L("Move layer down")) {
            layers.swapAt(activeLayerIndex, target)
            activeLayerIndex = target
        }
    }

    /// Moves the layer at `from` so that it ends up at array index `to` (0 = bottom).
    func moveLayer(from: Int, to: Int) {
        guard from != to, layers.indices.contains(from), (0..<layers.count).contains(to) else { return }
        performStructuralChange(L("Reorder layers")) {
            let layer = layers.remove(at: from)
            layers.insert(layer, at: to)
            activeLayerIndex = to
        }
    }

    func toggleLayerVisibility(_ layer: Layer) {
        performLayerChange(layer.isVisible ? L("Hide layer") : L("Show layer"), layer: layer) { l in
            l.isVisible.toggle()
        }
        notifyLayersChanged()
    }

    func setLayerOpacity(_ layer: Layer, _ opacity: CGFloat) {
        performLayerChange(L("Layer opacity"), layer: layer) { $0.opacity = opacity }
        notifyLayersChanged()
    }

    func renameLayer(_ layer: Layer, to name: String) {
        performLayerChange(L("Rename layer"), layer: layer) { $0.name = name }
        notifyLayersChanged()
    }

    func setBackgroundColor(_ color: NSColor) {
        performStructuralChange(L("Background color")) { backgroundColor = color }
    }

    func toggleBackgroundVisible() {
        performStructuralChange(backgroundVisible ? L("Hide background") : L("Show background")) { backgroundVisible.toggle() }
    }

    // MARK: - Canvas / image operations

    /// Changes the canvas size. Existing pixels are shifted by `offset` (top-left anchored when zero);
    /// new area is transparent.
    func resizeCanvas(to newSize: CGSize, offset: CGPoint = .zero) {
        let size = CGSize(width: max(1, newSize.width.rounded()), height: max(1, newSize.height.rounded()))
        guard size != canvasSize || offset != .zero else { return }
        performStructuralChange(L("Resize canvas")) {
            for layer in layers {
                let bmp = Bitmap(width: Int(size.width), height: Int(size.height))
                if let img = layer.bitmap.makeImage() {
                    bmp.draw(img, in: layer.bitmap.bounds.offsetBy(dx: offset.x, dy: offset.y), interpolate: false)
                }
                layer.bitmap = bmp
            }
            canvasSize = size
        }
    }

    /// Scales every layer to the new size, with optional horizontal / vertical skew in degrees.
    func resizeImage(to newSize: CGSize, skewX: CGFloat = 0, skewY: CGFloat = 0) {
        let size = CGSize(width: max(1, newSize.width.rounded()), height: max(1, newSize.height.rounded()))
        performStructuralChange(L("Resize")) {
            let sx = size.width / canvasSize.width, sy = size.height / canvasSize.height
            let tx = tan(skewX * .pi / 180), ty = tan(skewY * .pi / 180)
            // Expand the canvas to contain the skewed parallelogram.
            let extraW = abs(tx) * size.height, extraH = abs(ty) * size.width
            let outSize = CGSize(width: size.width + extraW, height: size.height + extraH)
            let scale = CGAffineTransform(scaleX: sx, y: sy)
            let skew = CGAffineTransform(a: 1, b: ty, c: tx, d: 1,
                                         tx: tx < 0 ? extraW : 0, ty: ty < 0 ? extraH : 0)
            let t = scale.concatenating(skew)
            for layer in layers {
                layer.bitmap = layer.bitmap.transformed(size: outSize, t)
            }
            canvasSize = CGSize(width: outSize.width.rounded(), height: outSize.height.rounded())
        }
    }

    enum Rotation { case right90, left90, half }

    func rotate(_ rotation: Rotation) {
        performStructuralChange(L("Rotate")) {
            let w = canvasSize.width, h = canvasSize.height
            let newSize: CGSize
            let t: CGAffineTransform
            switch rotation {
            case .right90:
                newSize = CGSize(width: h, height: w)
                t = CGAffineTransform(translationX: h, y: 0).rotated(by: .pi / 2)
            case .left90:
                newSize = CGSize(width: h, height: w)
                t = CGAffineTransform(translationX: 0, y: w).rotated(by: -.pi / 2)
            case .half:
                newSize = canvasSize
                t = CGAffineTransform(translationX: w, y: h).rotated(by: .pi)
            }
            for layer in layers { layer.bitmap = layer.bitmap.transformed(size: newSize, t) }
            canvasSize = newSize
        }
    }

    func flip(horizontal: Bool) {
        performStructuralChange(horizontal ? L("Flip horizontal") : L("Flip vertical")) {
            let t = horizontal
                ? CGAffineTransform(translationX: canvasSize.width, y: 0).scaledBy(x: -1, y: 1)
                : CGAffineTransform(translationX: 0, y: canvasSize.height).scaledBy(x: 1, y: -1)
            for layer in layers { layer.bitmap = layer.bitmap.transformed(size: canvasSize, t) }
        }
    }

    func crop(to rect: CGRect) {
        let r = rect.integral.intersection(canvasRect)
        guard !r.isEmpty else { return }
        performStructuralChange(L("Crop")) {
            let t = CGAffineTransform(translationX: -r.minX, y: -r.minY)
            for layer in layers { layer.bitmap = layer.bitmap.transformed(size: r.size, t) }
            canvasSize = r.size
        }
    }

    /// Replaces the whole document contents with a single image (used for New / paste-as-new).
    func replaceContents(with image: CGImage) {
        performStructuralChange(L("Replace image")) {
            let bmp = Bitmap(image: image)
            canvasSize = bmp.size
            layers = [Layer(name: String(format: L("Layer %d"), 1), bitmap: bmp)]
            activeLayerIndex = 0
        }
    }
}

final class SnapshotBox: NSObject {
    let snapshot: PaintDocument.Snapshot
    init(_ s: PaintDocument.Snapshot) { snapshot = s }
}

final class LayerSnapshotBox: NSObject {
    let snapshot: Layer.Snapshot
    init(_ s: Layer.Snapshot) { snapshot = s }
}
