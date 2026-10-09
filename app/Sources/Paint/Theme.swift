import AppKit

/// The app's colour palette, with a light and a dark variant for each colour.
enum Theme {
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    static let chromeBackground = dynamic(light: NSColor(hex: "#EEF1F6"), dark: NSColor(hex: "#1C2130"))
    static let ribbonBackground = dynamic(light: NSColor(hex: "#F3F5F9"), dark: NSColor(hex: "#232838"))
    static let canvasAreaBackground = dynamic(light: NSColor(hex: "#EEF1F6"), dark: NSColor(hex: "#1C2130"))
    static let panelBackground = dynamic(light: NSColor(hex: "#F7F8FB"), dark: NSColor(hex: "#262B3B"))
    static let divider = dynamic(light: NSColor(white: 0, alpha: 0.08), dark: NSColor(white: 1, alpha: 0.08))
    static let strongDivider = dynamic(light: NSColor(white: 0, alpha: 0.16), dark: NSColor(white: 1, alpha: 0.16))
    static let text = dynamic(light: NSColor(hex: "#1B1B1B"), dark: NSColor(hex: "#FFFFFF"))
    static let secondaryText = dynamic(light: NSColor(hex: "#5D5D5D"), dark: NSColor(hex: "#C5C5C5"))
    static let hover = dynamic(light: NSColor(white: 0, alpha: 0.05), dark: NSColor(white: 1, alpha: 0.06))
    static let pressed = dynamic(light: NSColor(white: 0, alpha: 0.09), dark: NSColor(white: 1, alpha: 0.03))
    static let accent = dynamic(light: NSColor(hex: "#0067C0"), dark: NSColor(hex: "#4CC2FF"))
    static let accentSelection = dynamic(light: NSColor(hex: "#0067C0").withAlphaComponent(0.12), dark: NSColor(hex: "#4CC2FF").withAlphaComponent(0.18))
    static let selectedRow = dynamic(light: NSColor(white: 0, alpha: 0.06), dark: NSColor(white: 1, alpha: 0.08))
    static let controlBorder = dynamic(light: NSColor(white: 0, alpha: 0.12), dark: NSColor(white: 1, alpha: 0.12))
    static let controlBackground = dynamic(light: NSColor(hex: "#FFFFFF"), dark: NSColor(hex: "#3A3A3A"))

    /// Translucent tint laid over the window's blurred backdrop for the ribbon and status bar bands.
    static let glassBand = dynamic(light: NSColor(white: 1, alpha: 0.28), dark: NSColor(white: 1, alpha: 0.05))
    /// Neutral (not blue-tinted) solid fill for flat cards such as the Size / Opacity sliders.
    static let flatCard = dynamic(light: NSColor(hex: "#ECECEE"), dark: NSColor(hex: "#303032"))
    /// Translucent veil laid inside floating glass cards so they stay visible over a pure white or black
    /// canvas regardless of the glass material's own light / dark adaptation.
    static let cardVeil = dynamic(light: NSColor(hex: "#EFEFF1").withAlphaComponent(0.42), dark: NSColor(hex: "#2C2C2E").withAlphaComponent(0.42))
    /// Material for floating cards (Layers, Size / Opacity) that blur the canvas beneath them.
    static let cardMaterial: NSVisualEffectView.Material = .popover
    /// Material for the window backdrop (desktop shows through, like Finder's sidebar).
    static let windowMaterial: NSVisualEffectView.Material = .underWindowBackground

    /// Tooltip text with its keyboard shortcut appended, e.g. "Pencil (N)" or "Undo (⌘Z)".
    static func tip(_ title: String, _ shortcut: String) -> String { "\(title) (\(shortcut))" }

    static let cornerRadius: CGFloat = 4
    static let buttonSize: CGFloat = 36
    static let ribbonHeight: CGFloat = 96
    static let menuStripHeight: CGFloat = 38
    static let statusBarHeight: CGFloat = 30
    static let layersPanelWidth: CGFloat = 120

    static func symbol(_ name: String, size: CGFloat = 18, weight: NSFont.Weight = .regular) -> NSImage? {
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        return img.withSymbolConfiguration(config)
    }

    static var zoomLevels: [CGFloat] { [0.125, 0.25, 0.5, 1, 2, 3, 4, 5, 6, 7, 8] }

    private static var cursorCache: [String: NSCursor] = [:]

    /// Minimal precision cursor (a small dot) used with tools that draw their own size outline.
    static let dotCursor: NSCursor = {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            let c = rect.insetBy(dx: 3, dy: 3)
            NSColor.white.setFill(); NSBezierPath(ovalIn: c.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSColor.black.setFill(); NSBezierPath(ovalIn: c).fill()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 6, y: 6))
    }()

    /// Fully transparent cursor for tools that draw their own footprint outline (Photoshop-style brush cursor).
    static let invisibleCursor: NSCursor = {
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { _ in true }
        return NSCursor(image: image, hotSpot: NSPoint(x: 4, y: 4))
    }()

    enum CursorAnchor {
        case center
        /// The glyph's bottom-left corner (pencil tip, eyedropper tip).
        case bottomLeft
        /// Unit coordinates (0…1, origin top-left) inside the glyph's bounding box.
        case inGlyph(CGFloat, CGFloat)
    }

    /// A cursor built from an SF Symbol: black glyph with a white outline. The hot spot is computed from the
    /// glyph's actual opaque bounds so the anchor lands exactly on the pixel that gets painted.
    static func cursor(symbol: String, anchor: CursorAnchor) -> NSCursor {
        let key = "\(symbol)-\(anchor)"
        if let c = cursorCache[key] { return c }
        let size = NSSize(width: 26, height: 26)
        guard let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)) else {
            return dotCursor
        }
        let inner = NSRect(x: 3, y: 3, width: 20, height: 20)
        let glyphOnly = NSImage(size: size, flipped: false) { _ in
            glyph.tinted(.black).draw(in: inner)
            return true
        }
        let bbox = opaqueBounds(of: glyphOnly) ?? CGRect(x: 3, y: 3, width: 20, height: 20)
        let hot: CGPoint
        switch anchor {
        case .center: hot = CGPoint(x: bbox.midX, y: bbox.midY)
        case .bottomLeft: hot = CGPoint(x: bbox.minX, y: bbox.maxY)
        case .inGlyph(let fx, let fy): hot = CGPoint(x: bbox.minX + bbox.width * fx, y: bbox.minY + bbox.height * fy)
        }
        let image = NSImage(size: size, flipped: false) { _ in
            let white = glyph.tinted(.white)
            for dx in [-1.2, 0, 1.2] as [CGFloat] {
                for dy in [-1.2, 0, 1.2] as [CGFloat] where dx != 0 || dy != 0 {
                    white.draw(in: inner.offsetBy(dx: dx, dy: dy))
                }
            }
            glyph.tinted(.black).draw(in: inner)
            return true
        }
        let cursor = NSCursor(image: image, hotSpot: NSPoint(x: hot.x, y: hot.y))
        cursorCache[key] = cursor
        return cursor
    }

    /// Bounding box (top-left origin, in points) of pixels with alpha > 50 %.
    private static func opaqueBounds(of image: NSImage) -> CGRect? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let sx = CGFloat(rep.pixelsWide) / image.size.width, sy = CGFloat(rep.pixelsHigh) / image.size.height
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: CGFloat(minX) / sx, y: CGFloat(minY) / sy, width: CGFloat(maxX - minX + 1) / sx, height: CGFloat(maxY - minY + 1) / sy)
    }

    /// Draws the paint-bucket glyph used by the Fill tool (icon and cursor). `rect` is in a flipped context.
    static func drawBucket(in rect: CGRect, _ ctx: CGContext, color: NSColor, outline: NSColor? = nil) {
        let w = rect.width, h = rect.height
        func pt(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { CGPoint(x: rect.minX + fx * w, y: rect.minY + fy * h) }
        // Tilted bucket body
        let body = CGMutablePath()
        body.move(to: pt(0.08, 0.42))
        body.addLine(to: pt(0.52, 0.06))
        body.addLine(to: pt(0.86, 0.42))
        body.addLine(to: pt(0.46, 0.80))
        body.closeSubpath()
        // Paint pouring out to the bottom-right
        let pour = CGMutablePath()
        pour.move(to: pt(0.80, 0.50))
        pour.addQuadCurve(to: pt(0.96, 0.78), control: pt(0.98, 0.52))
        pour.addQuadCurve(to: pt(0.86, 0.96), control: pt(0.98, 0.96))
        pour.addQuadCurve(to: pt(0.72, 0.62), control: pt(0.70, 0.90))
        pour.closeSubpath()
        // Handle
        let handle = CGMutablePath()
        handle.move(to: pt(0.20, 0.32))
        handle.addQuadCurve(to: pt(0.60, 0.16), control: pt(0.28, 0.02))
        ctx.saveGState()
        if let o = outline {
            ctx.setStrokeColor(o.cgColor); ctx.setLineWidth(3); ctx.setLineJoin(.round)
            ctx.addPath(body); ctx.strokePath()
            ctx.addPath(pour); ctx.strokePath()
            ctx.setLineCap(.round); ctx.addPath(handle); ctx.strokePath()
        }
        ctx.setFillColor(color.cgColor)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1.4)
        ctx.setLineJoin(.round)
        ctx.addPath(body); ctx.strokePath()
        ctx.addPath(pour); ctx.fillPath()
        ctx.setLineCap(.round)
        ctx.addPath(handle); ctx.strokePath()
        // Rim highlight line inside the body
        ctx.setLineWidth(1)
        ctx.move(to: pt(0.30, 0.30)); ctx.addLine(to: pt(0.64, 0.30)); ctx.strokePath()
        ctx.restoreGState()
    }

    /// Fill tool cursor: bucket with the hot spot at the tip of the pouring paint.
    static let bucketCursor: NSCursor = {
        let size = NSSize(width: 26, height: 26)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawBucket(in: rect.insetBy(dx: 2, dy: 2), ctx, color: .black, outline: .white)
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 2 + 0.86 * 22, y: 2 + 0.96 * 22))
    }()
}
