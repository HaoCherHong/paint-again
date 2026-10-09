import AppKit

/// Floating Layers card: "+" on top, layer thumbnails (top layer first) and the fixed Background entry at the bottom.
final class LayersPanelView: NSView {
    let document: PaintDocument
    private let card = GlassHost(cornerRadius: 10, material: .blur, shadow: true, veil: Theme.cardVeil)
    private let scroll = NSScrollView()
    private let listContainer = FlippedContainerView()
    private let list = NSStackView()
    private let insertionLine = NSView()
    private var drag: (fromIndex: Int, slot: Int)?
    private let backgroundThumb: LayerThumbView
    private var observers: [Any] = []
    private var rows: [LayerThumbView] = []

    init(document: PaintDocument) {
        self.document = document
        backgroundThumb = LayerThumbView(document: document, layerIndex: nil)
        super.init(frame: .zero)
        build()
        observers.append(NotificationCenter.default.addObserver(forName: .layersDidChange, object: document, queue: .main) { [weak self] _ in self?.reload() })
        observers.append(NotificationCenter.default.addObserver(forName: .documentDidChange, object: document, queue: .main) { [weak self] _ in self?.refreshThumbnails() })
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    override var isFlipped: Bool { true }

    private func build() {
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        let inner = card.content

        let add = RibbonButton(tooltip: Theme.tip(L("Add layer"), "⇧⌘N")) { NSApp.sendAction(#selector(MainWindowController.addLayer(_:)), to: nil, from: nil) }
        add.preferredSize = NSSize(width: 28, height: 28)
        add.isCircular = true
        add.customIcon = { ctx, rect in
            let d: CGFloat = 20
            let c = CGRect(x: rect.midX - d / 2, y: rect.midY - d / 2, width: d, height: d)
            ctx.setStrokeColor(Theme.text.cgColor)
            ctx.setLineWidth(1.2)
            ctx.strokeEllipse(in: c)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: c.midX - 5, y: c.midY)); ctx.addLine(to: CGPoint(x: c.midX + 5, y: c.midY))
            ctx.move(to: CGPoint(x: c.midX, y: c.midY - 5)); ctx.addLine(to: CGPoint(x: c.midX, y: c.midY + 5))
            ctx.strokePath()
        }
        inner.addSubview(add)

        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        listContainer.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = listContainer
        list.orientation = .vertical
        list.spacing = 8
        list.alignment = .centerX
        list.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        list.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(list)
        insertionLine.wantsLayer = true
        insertionLine.layer?.backgroundColor = Theme.accent.cgColor
        insertionLine.layer?.cornerRadius = 1
        insertionLine.isHidden = true
        listContainer.addSubview(insertionLine)
        inner.addSubview(scroll)

        backgroundThumb.translatesAutoresizingMaskIntoConstraints = false
        inner.addSubview(backgroundThumb)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            add.topAnchor.constraint(equalTo: inner.topAnchor, constant: 6),
            add.centerXAnchor.constraint(equalTo: inner.centerXAnchor),
            scroll.topAnchor.constraint(equalTo: add.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: inner.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: inner.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: backgroundThumb.topAnchor, constant: -10),
            listContainer.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            listContainer.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
            list.topAnchor.constraint(equalTo: listContainer.topAnchor),
            list.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            list.bottomAnchor.constraint(lessThanOrEqualTo: listContainer.bottomAnchor),
            backgroundThumb.bottomAnchor.constraint(equalTo: inner.bottomAnchor, constant: -10),
            backgroundThumb.centerXAnchor.constraint(equalTo: inner.centerXAnchor),
            backgroundThumb.widthAnchor.constraint(equalToConstant: LayerThumbView.size.width),
            backgroundThumb.heightAnchor.constraint(equalToConstant: LayerThumbView.size.height),
        ])
    }

    func reload() {
        rows.forEach { $0.removeFromSuperview() }
        rows = []
        for i in document.layers.indices.reversed() {
            let row = LayerThumbView(document: document, layerIndex: i)
            row.widthAnchor.constraint(equalToConstant: LayerThumbView.size.width).isActive = true
            row.heightAnchor.constraint(equalToConstant: LayerThumbView.size.height).isActive = true
            row.onDrag = { [weak self] thumb, phase, windowPoint in self?.handleDrag(thumb, phase: phase, windowPoint: windowPoint) }
            list.addArrangedSubview(row)
            rows.append(row)
        }
        refreshThumbnails()
    }

    // MARK: - Drag to reorder

    /// Display slot (0 = above the top row) nearest to a point in list-container coordinates.
    private func slot(forY y: CGFloat) -> Int {
        for (i, row) in rows.enumerated() where y < row.frame.midY { return i }
        return rows.count
    }

    private func handleDrag(_ thumb: LayerThumbView, phase: LayerThumbView.DragPhase, windowPoint: CGPoint) {
        guard let from = thumb.layerIndex else { return }
        let p = listContainer.convert(windowPoint, from: nil)
        switch phase {
        case .began:
            drag = (from, slot(forY: p.y))
            thumb.alphaValue = 0.5
            insertionLine.isHidden = false
            updateInsertionLine()
        case .moved:
            guard drag != nil else { return }
            drag?.slot = slot(forY: p.y)
            updateInsertionLine()
            listContainer.autoscroll(with: NSApp.currentEvent ?? NSEvent())
        case .ended:
            guard let d = drag else { return }
            drag = nil
            thumb.alphaValue = 1
            insertionLine.isHidden = true
            let n = document.layers.count
            let fromDisplay = n - 1 - d.fromIndex
            var s = d.slot
            if s > fromDisplay { s -= 1 }
            let to = (n - 1) - s
            document.moveLayer(from: d.fromIndex, to: to)
        }
    }

    private func updateInsertionLine() {
        guard let d = drag else { return }
        let y: CGFloat
        if rows.isEmpty { y = 4 }
        else if d.slot >= rows.count { y = rows[rows.count - 1].frame.maxY + 3 }
        else { y = rows[d.slot].frame.minY - 5 }
        let w = LayerThumbView.size.width
        insertionLine.frame = CGRect(x: (listContainer.bounds.width - w) / 2, y: y, width: w, height: 2)
    }

    private func refreshThumbnails() {
        for row in rows { row.needsDisplay = true }
        backgroundThumb.needsDisplay = true
    }
}

/// One thumbnail in the Layers card. `layerIndex == nil` represents the solid Background.
final class LayerThumbView: NSView {
    static let size = CGSize(width: 88, height: 52)
    unowned let document: PaintDocument
    let layerIndex: Int?
    private var hovered = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    enum DragPhase { case began, moved, ended }
    /// Reports a press-and-drag on a layer thumbnail (window coordinates) so the panel can reorder layers.
    var onDrag: ((LayerThumbView, DragPhase, CGPoint) -> Void)?
    private var pressLocation: CGPoint?
    private var dragging = false

    init(document: PaintDocument, layerIndex: Int?) {
        self.document = document
        self.layerIndex = layerIndex
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    private var layer_: Layer? { layerIndex.map { document.layers[$0] } }
    private var isSelected: Bool { layerIndex != nil && layerIndex == document.activeLayerIndex }
    private var isVisible: Bool { layerIndex == nil ? document.backgroundVisible : (layer_?.isVisible ?? true) }
    private var eyeRect: CGRect { CGRect(x: bounds.maxX - 22, y: 3, width: 19, height: 19) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = bounds
        let inner = r.insetBy(dx: 2, dy: 2)
        let path = CGPath(roundedRect: inner, cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        // Checkerboard
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(inner)
        ctx.setFillColor(NSColor(white: 0.82, alpha: 1).cgColor)
        var y = inner.minY, rowIdx = 0
        while y < inner.maxY {
            var x = inner.minX + (rowIdx % 2 == 0 ? 0 : 5)
            while x < inner.maxX { ctx.fill(CGRect(x: x, y: y, width: 5, height: 5)); x += 10 }
            y += 5; rowIdx += 1
        }
        if let layer = layer_ {
            // Fit the canvas aspect inside the thumbnail.
            let aspect = document.canvasSize.width / max(1, document.canvasSize.height)
            var tr = inner
            if aspect > inner.width / inner.height {
                tr.size.height = inner.width / aspect; tr.origin.y = inner.midY - tr.height / 2
            } else {
                tr.size.width = inner.height * aspect; tr.origin.x = inner.midX - tr.width / 2
            }
            if let img = layer.bitmap.makeImage() {
                ctx.saveGState()
                ctx.translateBy(x: tr.minX, y: tr.maxY)
                ctx.scaleBy(x: 1, y: -1)
                ctx.setAlpha(layer.opacity)
                ctx.interpolationQuality = .medium
                ctx.draw(img, in: CGRect(origin: .zero, size: tr.size))
                ctx.restoreGState()
            }
        } else if document.backgroundVisible {
            ctx.setFillColor(document.backgroundColor.cgColor)
            ctx.fill(inner)
        }
        if !isVisible {
            ctx.setFillColor(NSColor(white: 0.5, alpha: 0.35).cgColor)
            ctx.fill(inner)
        }
        ctx.restoreGState()

        ctx.setLineWidth(isSelected ? 2 : 1)
        ctx.setStrokeColor(isSelected ? Theme.accent.cgColor : (hovered ? Theme.strongDivider.cgColor : Theme.controlBorder.cgColor))
        ctx.addPath(CGPath(roundedRect: inner.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 4, cornerHeight: 4, transform: nil))
        ctx.strokePath()

        if hovered || !isVisible {
            let er = eyeRect
            ctx.setFillColor(NSColor(white: 1, alpha: 0.9).cgColor)
            ctx.fillEllipse(in: er)
            ctx.setStrokeColor(NSColor(white: 0, alpha: 0.15).cgColor)
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: er.insetBy(dx: 0.5, dy: 0.5))
            if let eye = Theme.symbol(isVisible ? "eye" : "eye.slash", size: 10)?.tinted(.black) {
                eye.draw(in: er.insetBy(dx: 3, dy: 4.5), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if eyeRect.insetBy(dx: -2, dy: -2).contains(p) {
            if let layer = layer_ { document.toggleLayerVisibility(layer) } else { document.toggleBackgroundVisible() }
            return
        }
        if let i = layerIndex {
            document.activeLayerIndex = i
            if event.clickCount == 2 {
                NSApp.sendAction(#selector(MainWindowController.layerProperties(_:)), to: nil, from: nil)
            }
            pressLocation = event.locationInWindow
            dragging = false
        } else {
            NSApp.sendAction(#selector(MainWindowController.editBackgroundColor(_:)), to: nil, from: nil)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard layerIndex != nil, let start = pressLocation else { return }
        if !dragging {
            guard start.distance(to: event.locationInWindow) > 4 else { return }
            dragging = true
            onDrag?(self, .began, event.locationInWindow)
        }
        onDrag?(self, .moved, event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        if dragging { onDrag?(self, .ended, event.locationInWindow) }
        dragging = false
        pressLocation = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        guard let layer = layer_, let i = layerIndex else {
            menu.addItem(withTitle: L("Background color…"), action: #selector(MainWindowController.editBackgroundColor(_:)), keyEquivalent: "")
            menu.addItem(withTitle: document.backgroundVisible ? L("Hide background") : L("Show background"), action: #selector(MainWindowController.toggleBackgroundVisible(_:)), keyEquivalent: "")
            return menu
        }
        document.activeLayerIndex = i
        menu.addItem(withTitle: L("Duplicate layer"), action: #selector(MainWindowController.duplicateLayer(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Merge down"), action: #selector(MainWindowController.mergeDown(_:)), keyEquivalent: "")
        menu.addItem(withTitle: layer.isVisible ? L("Hide layer") : L("Show layer"), action: #selector(MainWindowController.toggleLayerVisibility(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Move layer up"), action: #selector(MainWindowController.moveLayerUp(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Move layer down"), action: #selector(MainWindowController.moveLayerDown(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Layer properties…"), action: #selector(MainWindowController.layerProperties(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Delete layer"), action: #selector(MainWindowController.deleteLayer(_:)), keyEquivalent: "")
        return menu
    }

    override var toolTip: String? {
        get { layer_?.name ?? L("Background") }
        set {}
    }
}

/// Scroll-view document that keeps its content anchored at the top.
final class FlippedContainerView: NSView {
    override var isFlipped: Bool { true }
}
