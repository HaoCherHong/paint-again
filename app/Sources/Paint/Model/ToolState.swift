import AppKit

extension Notification.Name {
    static let toolStateChanged = Notification.Name("PaintToolStateChanged")
}

/// User-facing tool settings shared across the ribbon and the canvas of one document window.
final class ToolState {
    var tool: ToolKind = .pencil { didSet { changed() } }
    var lastBrush: BrushKind = .brush
    var lastShape: ShapeKind = .rectangle
    var color1: NSColor = .black { didSet { changed() } }
    var color2: NSColor = .white { didSet { changed() } }
    var lineWidth: CGFloat = 3 { didSet { lineWidth = max(1, min(100, lineWidth.rounded())); changed() } }
    /// Paint opacity 0…1 applied to pencil, brushes, shapes, text, fill and eraser.
    var opacity: CGFloat = 1 { didSet { opacity = max(0, min(1, opacity)); changed() } }
    var shapeStroke: ShapeStrokeStyle = .solid { didSet { changed() } }
    var shapeFill: ShapeFillStyle = .none { didSet { changed() } }
    var transparentSelection = false { didSet { changed() } }
    var fontName: String = "Helvetica" { didSet { changed() } }
    var fontSize: CGFloat = 24 { didSet { changed() } }
    var bold = false { didSet { changed() } }
    var italic = false { didSet { changed() } }
    var underline = false { didSet { changed() } }
    var strikethrough = false { didSet { changed() } }
    var textOpaqueBackground = false { didSet { changed() } }
    /// 24 user-defined colour slots filled from the Edit colors dialog (persisted; nil = empty slot).
    var customColors: [NSColor?] = ToolState.loadCustomColors() {
        didSet {
            UserDefaults.standard.set(customColors.map { $0?.hexString ?? "" }, forKey: ToolState.customColorsKey)
            changed()
        }
    }
    static let customColorsKey = "CustomColors"
    static let maxCustomColors = 24

    private static func loadCustomColors() -> [NSColor?] {
        var slots: [NSColor?] = (UserDefaults.standard.stringArray(forKey: customColorsKey) ?? []).map { $0.isEmpty ? nil : NSColor(hex: $0) }
        if slots.count > maxCustomColors { slots = Array(slots.prefix(maxCustomColors)) }
        while slots.count < maxCustomColors { slots.append(nil) }
        return slots
    }

    static let paletteColors: [NSColor] = [
        "#000000", "#7F7F7F", "#880015", "#ED1C24", "#FF7F27", "#FFF200", "#22B14C", "#00A2E8", "#3F48CC", "#A349A4",
        "#FFFFFF", "#C3C3C3", "#B97A57", "#FFAEC9", "#FFC90E", "#EFE4B0", "#B5E61D", "#99D9EA", "#7092BE", "#C8BFE7",
    ].map { NSColor(hex: $0) }

    func color(for button: MouseButton) -> NSColor { button == .primary ? color1 : color2 }

    func setCustomColor(_ c: NSColor, at index: Int) {
        guard customColors.indices.contains(index) else { return }
        customColors[index] = c
    }

    /// Index of the first empty custom slot, if any.
    var firstEmptyCustomSlot: Int? { customColors.firstIndex { $0 == nil } }

    func font() -> NSFont {
        var font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let fm = NSFontManager.shared
        if bold { font = fm.convert(font, toHaveTrait: .boldFontMask) }
        if italic { font = fm.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }

    func textAttributes(color: NSColor) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [.font: font(), .foregroundColor: color]
        if underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if strikethrough { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return attrs
    }

    private func changed() {
        NotificationCenter.default.post(name: .toolStateChanged, object: self)
    }
}

extension NSColor {
    convenience init(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16) ?? 0
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    func isSameColor(as other: NSColor) -> Bool {
        let a = Bitmap.premultiplied(self), b = Bitmap.premultiplied(other)
        return a == b
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}
