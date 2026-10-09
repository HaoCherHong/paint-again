import AppKit

extension Notification.Name {
    /// Posted when the user toggles View → Appearance → Liquid Glass.
    static let liquidGlassSettingChanged = Notification.Name("PaintLiquidGlassSettingChanged")
}

/// A card whose material is Liquid Glass (`NSGlassEffectView`) on macOS 26 and a vibrancy blur before that.
/// Put subviews into `content`, never into the host itself.
final class GlassHost: NSView {
    enum Fallback { case blur, none }
    /// `.glass` uses Liquid Glass (falls back to blur); `.blur` is always a within-window backdrop blur plus the
    /// veil colour, independent of the Liquid Glass setting; `.flat` is a plain rounded card with a solid fill.
    enum Material { case glass, blur, flat }

    static let liquidGlassDefaultsKey = "LiquidGlassEnabled"

    /// Whether the OS offers Liquid Glass at all.
    static var supportsLiquidGlass: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// User preference (View → Appearance → Liquid Glass), on by default.
    static var liquidGlassEnabled: Bool {
        get { UserDefaults.standard.object(forKey: liquidGlassDefaultsKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: liquidGlassDefaultsKey)
            NotificationCenter.default.post(name: .liquidGlassSettingChanged, object: nil)
        }
    }

    /// Development aid: render every host with the fallback material regardless of the user setting
    /// (offscreen snapshots cannot capture NSGlassEffectView content).
    static var forceFallback = false

    /// True when hosts are currently rendering with Liquid Glass.
    static var hasLiquidGlass: Bool { supportsLiquidGlass && liquidGlassEnabled && !forceFallback }

    /// Flipped like the rest of the chrome so manual layout inside a card uses top-left coordinates.
    let content: NSView = FlippedContainerView()
    private var backing = NSView()
    private var usesGlass = false
    private var isFlat = false
    private let cornerRadius: CGFloat
    private let tint: NSColor?
    private let fallback: Fallback
    private let material: Material
    private let dropsShadow: Bool
    private let veil: NSView?
    private let veilColor: NSColor?
    private var observer: Any?

    init(cornerRadius: CGFloat, tint: NSColor? = nil, fallback: Fallback = .blur, material: Material = .glass, shadow: Bool = false, veil veilColor: NSColor? = nil) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.fallback = fallback
        self.material = material
        self.dropsShadow = shadow
        self.veilColor = veilColor
        content.autoresizingMask = [.width, .height]
        if let veilColor {
            let v = NSView()
            v.wantsLayer = true
            v.layer?.backgroundColor = veilColor.cgColor
            v.layer?.cornerRadius = cornerRadius
            v.autoresizingMask = [.width, .height]
            content.addSubview(v)
            veil = v
        } else {
            veil = nil
        }
        super.init(frame: .zero)
        if shadow {
            wantsLayer = true
            layer?.masksToBounds = false
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = 0.22
            layer?.shadowRadius = 10
            layer?.shadowOffset = CGSize(width: 0, height: -3)
        }
        rebuildBacking()
        observer = NotificationCenter.default.addObserver(forName: .liquidGlassSettingChanged, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildBacking()
        }
    }

    required init?(coder: NSCoder) { fatalError() }
    deinit { if let o = observer { NotificationCenter.default.removeObserver(o) } }

    /// (Re)creates the material view behind `content` according to the current setting.
    private func rebuildBacking() {
        // Detach the content cleanly: NSGlassEffectView installs constraints on its contentView and turns
        // off autoresizing translation, which must be undone before a plain container can size it.
        if #available(macOS 26.0, *), let glass = backing as? NSGlassEffectView { glass.contentView = nil }
        content.removeFromSuperview()
        content.removeConstraints(content.constraints.filter { $0.firstItem === content && $0.secondItem == nil })
        content.translatesAutoresizingMaskIntoConstraints = true
        content.autoresizingMask = [.width, .height]
        backing.removeFromSuperview()
        isFlat = false
        usesGlass = false
        if material == .flat {
            let plain = NSView()
            plain.wantsLayer = true
            plain.layer?.cornerRadius = cornerRadius
            plain.layer?.masksToBounds = true
            plain.layer?.borderWidth = 1
            plain.addSubview(content)
            backing = plain
            isFlat = true
        } else if #available(macOS 26.0, *), Self.liquidGlassEnabled, !Self.forceFallback, material == .glass {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.tintColor = tint
            glass.contentView = content
            backing = glass
            usesGlass = true
        } else {
            switch fallback {
            case .blur:
                let effect = NSVisualEffectView()
                effect.material = Theme.cardMaterial
                effect.blendingMode = .withinWindow
                effect.state = .active
                effect.wantsLayer = true
                effect.layer?.cornerRadius = cornerRadius
                effect.layer?.masksToBounds = true
                effect.layer?.borderWidth = cornerRadius > 0 ? 1 : 0
                effect.addSubview(content)
                backing = effect
            case .none:
                let plain = NSView()
                plain.addSubview(content)
                backing = plain
            }
        }
        backing.autoresizingMask = [.width, .height]
        backing.frame = bounds
        addSubview(backing)
        content.frame = backing.bounds
        pinContentAppearance()
        needsLayout = true
    }

    override var isFlipped: Bool { true }

    /// Development aid: one line per host describing the material actually in use.
    static func debugReport(in root: NSView) -> String {
        var lines: [String] = []
        func walk(_ v: NSView, _ path: String) {
            if let h = v as? GlassHost {
                lines.append("\(path): backing=\(type(of: h.backing)) usesGlass=\(h.usesGlass) flat=\(h.isFlat) subviews=\(h.content.subviews.count) host=\(Int(h.frame.width))x\(Int(h.frame.height)) content=\(Int(h.content.frame.minX)),\(Int(h.content.frame.minY)) \(Int(h.content.frame.width))x\(Int(h.content.frame.height)) tamic=\(h.content.translatesAutoresizingMaskIntoConstraints)")
            }
            for s in v.subviews { walk(s, path + "/" + String(describing: type(of: s))) }
        }
        walk(root, "")
        return lines.joined(separator: "\n")
    }

    override func layout() {
        super.layout()
        backing.frame = bounds
        if dropsShadow {
            layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        }
        veil?.frame = content.bounds
        if !usesGlass {
            content.frame = backing.bounds
            applyColors()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        pinContentAppearance()
        if !usesGlass { applyColors() }
        if let veil, let veilColor { veil.layer?.backgroundColor = veilColor.cgColor }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        pinContentAppearance()
    }

    /// Liquid Glass flips its content to light or dark to match what is behind it; controls inside the
    /// card should instead follow the app's appearance so text, icons and sliders keep their contrast.
    private func pinContentAppearance() {
        content.appearance = NSAppearance(named: effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .darkAqua : .aqua)
    }

    private func applyColors() {
        backing.layer?.borderColor = Theme.divider.cgColor
        if isFlat { backing.layer?.backgroundColor = Theme.flatCard.cgColor }
    }
}

/// Availability-safe probe for `NSGlassEffectView.contentView`.
protocol NSGlassEffectViewBox { func holds(_ v: NSView) -> Bool }
@available(macOS 26.0, *)
extension NSGlassEffectView: NSGlassEffectViewBox {
    func holds(_ v: NSView) -> Bool { contentView === v }
}
