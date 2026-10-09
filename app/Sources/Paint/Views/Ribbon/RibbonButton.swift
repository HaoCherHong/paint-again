import AppKit

/// Icon button used throughout the ribbon, panels and popovers.
final class RibbonButton: NSView {
    enum Style { case small, large, wide }

    var image: NSImage? { didSet { needsDisplay = true } }
    var title: String? { didSet { needsDisplay = true; invalidateIntrinsicContentSize() } }
    var style: Style { didSet { invalidateIntrinsicContentSize() } }
    var showsChevron = false { didSet { needsDisplay = true } }
    var isSelected = false { didSet { needsDisplay = true } }
    var isEnabled = true { didSet { needsDisplay = true } }
    var tintsWhenSelected = true
    /// Draw hover / pressed backgrounds as a circle (used for round buttons such as the Layers "+").
    var isCircular = false
    /// Large buttons show selection as an accent outline; small ones as a tinted fill.
    var selectedAsOutline: Bool { style == .large }
    var onClick: (() -> Void)?
    var onChevron: (() -> Void)?
    /// Custom drawing for the icon area (used for colour swatches and shape previews).
    var customIcon: ((CGContext, CGRect) -> Void)?
    var preferredSize: CGSize?

    private var hovered = false { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    init(symbol: String? = nil, title: String? = nil, style: Style = .small, tooltip: String? = nil, onClick: (() -> Void)? = nil) {
        self.style = style
        self.title = title
        super.init(frame: .zero)
        if let s = symbol { image = Theme.symbol(s, size: style == .small ? 16 : 22) }
        self.onClick = onClick
        self.toolTip = tooltip ?? title
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        if let s = preferredSize { return s }
        switch style {
        case .small: return NSSize(width: 30, height: 28)
        case .large: return NSSize(width: 50, height: 60)
        case .wide:
            let text = title.map { ($0 as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width } ?? 0
            let w = text + (image == nil && customIcon == nil ? 16 : 34)
            return NSSize(width: max(40, w), height: 28)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false; pressed = false }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, pressed else { pressed = false; return }
        pressed = false
        let p = convert(event.locationInWindow, from: nil)
        guard bounds.contains(p) else { return }
        if showsChevron, let chevron = onChevron, isInChevronZone(p) {
            chevron()
        } else if let click = onClick {
            click()
        } else if let chevron = onChevron {
            chevron()
        }
    }

    private func isInChevronZone(_ p: CGPoint) -> Bool {
        switch style {
        case .large: return p.y > bounds.height - 16
        default: return p.x > bounds.width - 16
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = bounds
        let bg: NSColor? = !isEnabled ? nil : pressed ? Theme.pressed : (isSelected && !selectedAsOutline) ? Theme.accentSelection : hovered ? Theme.hover : nil
        if let bg {
            ctx.setFillColor(bg.cgColor)
            if isCircular {
                let d = min(r.width, r.height)
                ctx.fillEllipse(in: CGRect(x: r.midX - d / 2, y: r.midY - d / 2, width: d, height: d))
            } else {
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: Theme.cornerRadius, cornerHeight: Theme.cornerRadius, transform: nil))
                ctx.fillPath()
            }
        }
        if isSelected && tintsWhenSelected && selectedAsOutline {
            ctx.setStrokeColor(Theme.accent.cgColor)
            ctx.setLineWidth(1.5)
            ctx.addPath(CGPath(roundedRect: r.insetBy(dx: 0.75, dy: 0.75), cornerWidth: Theme.cornerRadius + 1, cornerHeight: Theme.cornerRadius + 1, transform: nil))
            ctx.strokePath()
        }

        let tint = isEnabled ? (isSelected && tintsWhenSelected && !selectedAsOutline ? Theme.accent : Theme.text) : Theme.secondaryText.withAlphaComponent(0.5)
        let iconSize: CGFloat = style == .small ? 16 : 24
        var iconRect: CGRect
        let chevronSpace: CGFloat = showsChevron ? 12 : 0
        let titleHeight: CGFloat = (title != nil && style != .wide) ? 14 : 0
        switch style {
        case .small:
            iconRect = CGRect(x: r.minX + (r.width - chevronSpace - iconSize) / 2, y: r.minY + (r.height - iconSize) / 2, width: iconSize, height: iconSize)
        case .large:
            let contentH = iconSize + titleHeight + chevronSpace
            iconRect = CGRect(x: r.midX - iconSize / 2, y: r.minY + (r.height - contentH) / 2, width: iconSize, height: iconSize)
        case .wide:
            iconRect = image == nil && customIcon == nil
                ? CGRect(x: r.minX + 2, y: r.midY - 8, width: 0, height: 16)
                : CGRect(x: r.minX + 8, y: r.midY - 8, width: 16, height: 16)
        }
        if let custom = customIcon {
            custom(ctx, iconRect)
        } else if let img = image {
            let tinted = img.tinted(tint)
            tinted.draw(in: iconRect.insetBy(dx: (iconRect.width - img.size.width * iconSize / max(img.size.width, img.size.height)) / 2,
                                             dy: (iconRect.height - img.size.height * iconSize / max(img.size.width, img.size.height)) / 2),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        if let t = title {
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: style == .wide ? 12 : 10), .foregroundColor: tint]
            let size = (t as NSString).size(withAttributes: attrs)
            let textRect: CGRect
            if style == .wide {
                textRect = CGRect(x: iconRect.maxX + 6, y: r.midY - size.height / 2, width: r.width - iconRect.maxX - 8, height: size.height)
            } else {
                textRect = CGRect(x: r.minX, y: iconRect.maxY + 1, width: r.width, height: size.height)
            }
            let ps = NSMutableParagraphStyle()
            ps.alignment = style == .wide ? .left : .center
            ps.lineBreakMode = .byTruncatingTail
            var a = attrs
            a[.paragraphStyle] = ps
            (t as NSString).draw(in: textRect, withAttributes: a)
        }
        if showsChevron {
            let chevron = Theme.symbol("chevron.down", size: 8, weight: .semibold)?.tinted(Theme.secondaryText)
            let cr: CGRect = style == .large
                ? CGRect(x: r.midX - 5, y: r.maxY - 14, width: 10, height: 8)
                : CGRect(x: r.maxX - 14, y: r.midY - 4, width: 10, height: 8)
            chevron?.draw(in: cr, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    override var isFlipped: Bool { true }
}

extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let img = NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        img.isTemplate = false
        return img
    }
}

/// A vertical ribbon group: content on top, caption below.
final class RibbonGroup: NSView {
    let content = NSStackView()
    private let label = NSTextField(labelWithString: "")

    init(title: String, spacing: CGFloat = 2) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .horizontal
        content.spacing = spacing
        content.alignment = .centerY
        content.translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = title
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = Theme.secondaryText
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        addSubview(label)
        // Content occupies a fixed 60 pt band and the caption sits at a fixed offset below it, so every
        // group's caption lines up regardless of how tall its content actually is.
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 6),
            content.heightAnchor.constraint(equalToConstant: 60),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 70),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Arranges buttons in a grid with `rows` rows, filling column by column.
    func addGrid(_ buttons: [RibbonButton], rows: Int, spacing: CGFloat = 2) {
        var columns: [[RibbonButton]] = []
        for (i, b) in buttons.enumerated() {
            if i % rows == 0 { columns.append([]) }
            columns[columns.count - 1].append(b)
        }
        for col in columns {
            let v = NSStackView(views: col)
            v.orientation = .vertical
            v.spacing = spacing
            v.alignment = .centerX
            content.addArrangedSubview(v)
        }
    }
}

final class RibbonSeparator: NSView {
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 1).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        Theme.strongDivider.setFill()
        bounds.insetBy(dx: 0, dy: 12).fill()
    }
}
