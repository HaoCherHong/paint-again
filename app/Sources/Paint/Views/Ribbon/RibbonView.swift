import AppKit

/// The command bar: Selection, Image, Tools, Brushes, Shapes, Colors, Layers.
final class RibbonView: NSView {
    let document: PaintDocument
    var state: ToolState { document.toolState }
    weak var controller: MainWindowController?

    private let stack = NSStackView()
    private let scroll = NSScrollView()
    private var toolButtons: [ToolKind: RibbonButton] = [:]
    private var historyGroup: RibbonGroup!
    private var historySeparator: RibbonSeparator!
    private var undoButton: RibbonButton!
    private var redoButton: RibbonButton!
    private var selectionButton: RibbonButton!
    private var brushButton: RibbonButton!
    private var shapeButtons: [ShapeKind: RibbonButton] = [:]
    private var outlineButton: RibbonButton!
    private var fillButton: RibbonButton!
    private var layersButton: RibbonButton!
    private var colorPanelButton: RibbonButton!
    private var palette: ColorPaletteView!
    private var observers: [Any] = []
    private var popover: NSPopover?

    init(document: PaintDocument) {
        self.document = document
        super.init(frame: .zero)
        wantsLayer = true
        build()
        observers.append(NotificationCenter.default.addObserver(forName: .toolStateChanged, object: state, queue: .main) { [weak self] _ in self?.refresh() })
        observers.append(NotificationCenter.default.addObserver(forName: .liquidGlassSettingChanged, object: nil, queue: .main) { [weak self] _ in self?.needsDisplay = true })
        observers.append(NotificationCenter.default.addObserver(forName: .NSUndoManagerCheckpoint, object: document.undoManager, queue: .main) { [weak self] _ in self?.refreshUndo() })
        observers.append(NotificationCenter.default.addObserver(forName: .documentDidChange, object: document, queue: .main) { [weak self] _ in self?.refreshUndo() })
        refresh()
        refreshUndo()
    }

    private func refreshUndo() {
        undoButton.isEnabled = document.undoManager?.canUndo ?? false
        redoButton.isEnabled = document.undoManager?.canRedo ?? false
    }

    /// Shows the Undo / Redo group; used when the window's top toolbar is hidden.
    func setHistoryVisible(_ visible: Bool) {
        historyGroup.isHidden = !visible
        historySeparator.isHidden = !visible
    }

    required init?(coder: NSCoder) { fatalError() }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.divider.setFill()
        CGRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill(using: .sourceOver)
    }

    // MARK: - Construction

    private func build() {
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.horizontalScrollElasticity = .none
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack
        addSubview(scroll)
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .top
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 0, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.contentView.heightAnchor),
        ])

        // Undo / Redo (only when the top toolbar is hidden)
        historyGroup = RibbonGroup(title: "")
        undoButton = RibbonButton(symbol: "arrow.uturn.backward", tooltip: Theme.tip(L("Undo"), "⌘Z")) { [weak self] in self?.document.undoManager?.undo() }
        redoButton = RibbonButton(symbol: "arrow.uturn.forward", tooltip: Theme.tip(L("Redo"), "⇧⌘Z / ⌘Y")) { [weak self] in self?.document.undoManager?.redo() }
        let historyColumn = NSStackView(views: [undoButton, redoButton])
        historyColumn.orientation = .vertical
        historyColumn.spacing = 2
        historyGroup.content.addArrangedSubview(historyColumn)
        historySeparator = RibbonSeparator()
        historyGroup.isHidden = true
        historySeparator.isHidden = true
        stack.addArrangedSubview(historyGroup)
        stack.addArrangedSubview(historySeparator)

        // Selection
        let selection = RibbonGroup(title: L("Selection"))
        selectionButton = RibbonButton(symbol: "rectangle.dashed", style: .large, tooltip: Theme.tip(L("Select"), "M / S / L"))
        selectionButton.showsChevron = true
        selectionButton.onClick = { [weak self] in
            guard let self else { return }
            self.state.tool = self.state.tool == .selectFreeform ? .selectFreeform : .selectRectangle
        }
        selectionButton.onChevron = { [weak self] in self?.showSelectionMenu() }
        selection.content.addArrangedSubview(selectionButton)
        stack.addArrangedSubview(selection)
        stack.addArrangedSubview(RibbonSeparator())

        // Image: crop / remove background · rotate / flip · resize
        let image = RibbonGroup(title: L("Image"))
        let crop = RibbonButton(symbol: "crop", tooltip: Theme.tip(L("Crop"), "⇧⌘X")) { NSApp.sendAction(#selector(MainWindowController.cropToSelection(_:)), to: nil, from: nil) }
        let removeBg = RibbonButton(symbol: "person.crop.rectangle", tooltip: L("Remove background")) { NSApp.sendAction(#selector(MainWindowController.removeBackground(_:)), to: nil, from: nil) }
        let rotate = RibbonButton(symbol: "rotate.right", tooltip: L("Rotate"))
        rotate.showsChevron = true
        rotate.preferredSize = NSSize(width: 44, height: 28)
        rotate.onClick = { [weak self, weak rotate] in if let rotate { self?.showRotateMenu(from: rotate) } }
        let flip = RibbonButton(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", tooltip: L("Flip"))
        flip.showsChevron = true
        flip.preferredSize = NSSize(width: 44, height: 28)
        flip.onClick = { [weak self, weak flip] in if let flip { self?.showFlipMenu(from: flip) } }
        let resize = RibbonButton(symbol: "arrow.up.left.and.arrow.down.right", style: .large, tooltip: Theme.tip(L("Resize and skew"), "⇧⌘R")) {
            NSApp.sendAction(#selector(MainWindowController.resizeAndSkew(_:)), to: nil, from: nil)
        }
        resize.preferredSize = NSSize(width: 40, height: 60)
        image.addGrid([crop, removeBg, rotate, flip], rows: 2)
        image.content.addArrangedSubview(resize)
        stack.addArrangedSubview(image)
        stack.addArrangedSubview(RibbonSeparator())

        // Tools
        let tools = RibbonGroup(title: L("Tools"))
        let toolDefs: [(ToolKind, String, String)] = [
            (.pencil, "pencil", Theme.tip(L("Pencil"), "N")), (.fill, "", Theme.tip(L("Fill"), "G")), (.text, "", Theme.tip(L("Text"), "T")),
            (.eraser, "eraser", Theme.tip(L("Eraser"), "E")), (.colorPicker, "eyedropper", Theme.tip(L("Color picker"), "I") + "\n" + L("Hold ⌥ while painting to pick a color")),
            (.magnifier, "magnifyingglass", Theme.tip(L("Magnifier"), "Z")),
        ]
        var buttons: [RibbonButton] = []
        for (kind, symbol, title) in toolDefs {
            let b = RibbonButton(symbol: symbol.isEmpty ? nil : symbol, tooltip: title) { [weak self] in self?.state.tool = kind }
            if kind == .text {
                b.customIcon = { [weak b] ctx, rect in
                    let color = (b?.isSelected ?? false) ? Theme.accent : Theme.text
                    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 17, weight: .medium), .foregroundColor: color]
                    let size = ("A" as NSString).size(withAttributes: attrs)
                    ("A" as NSString).draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
                }
            } else if kind == .fill {
                b.customIcon = { [weak b] ctx, rect in
                    Theme.drawBucket(in: rect.insetBy(dx: -1, dy: -1), ctx, color: (b?.isSelected ?? false) ? Theme.accent : Theme.text)
                }
            }
            toolButtons[kind] = b
            buttons.append(b)
        }
        tools.addGrid([buttons[0], buttons[3], buttons[1], buttons[4], buttons[2], buttons[5]], rows: 2)
        stack.addArrangedSubview(tools)
        stack.addArrangedSubview(RibbonSeparator())

        // Brushes
        let brushes = RibbonGroup(title: L("Brushes"))
        brushButton = RibbonButton(style: .large, tooltip: Theme.tip(L("Brushes"), "B"))
        brushButton.showsChevron = true
        brushButton.onClick = { [weak self] in
            guard let self else { return }
            self.state.tool = .brush(self.state.lastBrush)
        }
        brushButton.onChevron = { [weak self] in self?.showBrushPopover() }
        brushButton.customIcon = { [weak self] ctx, rect in
            guard let self else { return }
            let img = BrushPainter.preview(for: self.state.lastBrush, size: CGSize(width: 44, height: 20), color: Theme.text)
            img.draw(in: CGRect(x: rect.midX - 22, y: rect.midY - 10, width: 44, height: 20), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        brushes.content.addArrangedSubview(brushButton)
        stack.addArrangedSubview(brushes)
        stack.addArrangedSubview(RibbonSeparator())

        // Shapes: inline gallery + outline / fill dropdowns
        let shapes = RibbonGroup(title: L("Shapes"))
        var shapeBtns: [RibbonButton] = []
        for kind in ShapeKind.allCases {
            let b = RibbonButton(tooltip: Theme.tip(kind.title, "U")) { [weak self] in
                self?.state.lastShape = kind
                self?.state.tool = .shape(kind)
            }
            b.preferredSize = NSSize(width: 22, height: 19)
            b.customIcon = { [weak b] ctx, rect in
                ShapeIcons.draw(kind, in: rect.insetBy(dx: -2, dy: -2), ctx, color: (b?.isSelected ?? false) ? Theme.accent : Theme.text)
            }
            shapeButtons[kind] = b
            shapeBtns.append(b)
        }
        // Fill the 3-row grid column by column so it reads in gallery order across rows.
        var ordered: [RibbonButton] = []
        let rows = 3, cols = Int(ceil(Double(shapeBtns.count) / Double(rows)))
        for c in 0..<cols { for r in 0..<rows { let i = r * cols + c; if i < shapeBtns.count { ordered.append(shapeBtns[i]) } } }
        shapes.addGrid(ordered, rows: rows, spacing: 1)
        outlineButton = RibbonButton(symbol: "pencil.line", tooltip: L("Outline"))
        outlineButton.showsChevron = true
        outlineButton.preferredSize = NSSize(width: 44, height: 28)
        outlineButton.onClick = { [weak self] in self?.showOutlineMenu() }
        fillButton = RibbonButton(symbol: "paintbrush.fill", tooltip: L("Fill"))
        fillButton.showsChevron = true
        fillButton.preferredSize = NSSize(width: 44, height: 28)
        fillButton.onClick = { [weak self] in self?.showFillMenu() }
        let optionColumn = NSStackView(views: [outlineButton, fillButton])
        optionColumn.orientation = .vertical
        optionColumn.spacing = 2
        shapes.content.spacing = 6
        shapes.content.addArrangedSubview(optionColumn)
        stack.addArrangedSubview(shapes)
        stack.addArrangedSubview(RibbonSeparator())

        // Colors
        let colors = RibbonGroup(title: L("Colors"))
        palette = ColorPaletteView(state: state)
        palette.onEditColors = { [weak self] in self?.editColors() }
        colors.content.addArrangedSubview(palette)
        stack.addArrangedSubview(colors)
        stack.addArrangedSubview(RibbonSeparator())

        // Color panel
        let colorPanelGroup = RibbonGroup(title: L("Palette"))
        colorPanelButton = RibbonButton(symbol: "paintpalette", style: .large, tooltip: L("Color Panel")) {
            NSApp.sendAction(#selector(MainWindowController.toggleColorPanel(_:)), to: nil, from: nil)
        }
        colorPanelGroup.content.addArrangedSubview(colorPanelButton)
        stack.addArrangedSubview(colorPanelGroup)

        // Layers
        let layers = RibbonGroup(title: L("Layers"))
        layersButton = RibbonButton(symbol: "square.3.layers.3d", style: .large, tooltip: Theme.tip(L("Layers"), "⌘L")) {
            NSApp.sendAction(#selector(MainWindowController.toggleLayersPanel(_:)), to: nil, from: nil)
        }
        layers.content.addArrangedSubview(layersButton)
        stack.addArrangedSubview(layers)
    }

    // MARK: - State

    func refresh() {
        for (kind, b) in toolButtons { b.isSelected = state.tool == kind }
        selectionButton.isSelected = state.tool.isSelection
        selectionButton.image = Theme.symbol(state.tool == .selectFreeform ? "lasso" : "rectangle.dashed", size: 22)
        brushButton.isSelected = state.tool.isBrush
        brushButton.needsDisplay = true
        for (kind, b) in shapeButtons { b.isSelected = state.tool == .shape(kind) }
    }

    func setLayersPanelVisible(_ visible: Bool) {
        layersButton.isSelected = visible
    }

    func setColorPanelVisible(_ visible: Bool) {
        colorPanelButton.isSelected = visible
    }

    // MARK: - Menus & popovers

    private func showMenu(_ menu: NSMenu, from view: NSView) {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.maxY + 4), in: view)
    }

    private func showSelectionMenu() {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector?, key: String = "", mods: NSEvent.ModifierFlags = [], target: AnyObject? = nil, image: String? = nil, on: Bool = false) {
            let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
            it.keyEquivalentModifierMask = mods
            it.target = target
            if let image { it.image = Theme.symbol(image, size: 14) }
            it.state = on ? .on : .off
            menu.addItem(it)
        }
        add(L("Rectangle"), #selector(selectRectangle), key: "m", target: self, image: "rectangle.dashed", on: state.tool == .selectRectangle)
        add(L("Free-form"), #selector(selectFreeform), key: "l", target: self, image: "lasso", on: state.tool == .selectFreeform)
        menu.addItem(.separator())
        add(L("Select all"), #selector(NSResponder.selectAll(_:)), key: "a", mods: [.command])
        add(L("Deselect"), #selector(CanvasView.deselect(_:)), key: "d", mods: [.command])
        add(L("Invert selection"), #selector(MainWindowController.invertSelection(_:)), key: "i", mods: [.command, .shift])
        add(L("Delete"), #selector(NSText.delete(_:)), key: "\u{8}")
        menu.addItem(.separator())
        add(L("Transparent selection"), #selector(MainWindowController.toggleTransparentSelection(_:)), on: state.transparentSelection)
        showMenu(menu, from: selectionButton)
    }

    @objc private func selectRectangle() { state.tool = .selectRectangle }
    @objc private func selectFreeform() { state.tool = .selectFreeform }

    private func showRotateMenu(from view: NSView) {
        let menu = NSMenu()
        menu.addItem(withTitle: L("Rotate right 90°"), action: #selector(MainWindowController.rotateRight(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Rotate left 90°"), action: #selector(MainWindowController.rotateLeft(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Rotate 180°"), action: #selector(MainWindowController.rotate180(_:)), keyEquivalent: "")
        showMenu(menu, from: view)
    }

    private func showFlipMenu(from view: NSView) {
        let menu = NSMenu()
        menu.addItem(withTitle: L("Flip vertical"), action: #selector(MainWindowController.flipVertical(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L("Flip horizontal"), action: #selector(MainWindowController.flipHorizontal(_:)), keyEquivalent: "")
        showMenu(menu, from: view)
    }

    private func showOutlineMenu() {
        let menu = NSMenu()
        for s in ShapeStrokeStyle.allCases {
            let it = NSMenuItem(title: s.title, action: #selector(outlineChosen(_:)), keyEquivalent: "")
            it.target = self; it.tag = s.rawValue; it.state = state.shapeStroke == s ? .on : .off
            menu.addItem(it)
        }
        showMenu(menu, from: outlineButton)
    }

    private func showFillMenu() {
        let menu = NSMenu()
        for s in ShapeFillStyle.allCases {
            let it = NSMenuItem(title: s.title, action: #selector(fillChosen(_:)), keyEquivalent: "")
            it.target = self; it.tag = s.rawValue; it.state = state.shapeFill == s ? .on : .off
            menu.addItem(it)
        }
        showMenu(menu, from: fillButton)
    }

    @objc private func outlineChosen(_ sender: NSMenuItem) { state.shapeStroke = ShapeStrokeStyle(rawValue: sender.tag) ?? .solid }
    @objc private func fillChosen(_ sender: NSMenuItem) { state.shapeFill = ShapeFillStyle(rawValue: sender.tag) ?? .none }

    private func present(_ content: NSView, from view: NSView) {
        popover?.close()
        let vc = NSViewController()
        vc.view = content
        let p = NSPopover()
        p.behavior = .transient
        p.contentViewController = vc
        p.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
        popover = p
    }

    private func showBrushPopover() {
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.spacing = 4
        grid.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        let kinds = BrushKind.allCases
        for row in 0..<3 {
            let h = NSStackView()
            h.orientation = .horizontal
            h.spacing = 4
            for col in 0..<3 {
                let kind = kinds[row * 3 + col]
                let b = RibbonButton(title: kind.title, style: .large, tooltip: kind.title) { [weak self] in
                    self?.state.lastBrush = kind
                    self?.state.tool = .brush(kind)
                    self?.popover?.close()
                }
                b.preferredSize = NSSize(width: 110, height: 72)
                b.isSelected = state.tool == .brush(kind)
                b.customIcon = { ctx, rect in
                    let img = BrushPainter.preview(for: kind, size: CGSize(width: 72, height: 30), color: Theme.text)
                    img.draw(in: CGRect(x: rect.midX - 36, y: rect.midY - 15, width: 72, height: 30), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
                h.addArrangedSubview(b)
            }
            grid.addArrangedSubview(h)
        }
        grid.frame = NSRect(x: 0, y: 0, width: 360, height: 245)
        present(grid, from: brushButton)
    }

    private func editColors() {
        guard let window else { return }
        let target = palette.target
        ColorEditorPanel.present(on: window, initial: state.color(for: target), state: state) { [weak self] color in
            guard let self, let c = color else { return }
            if target == .primary { self.state.color1 = c } else { self.state.color2 = c }
        }
    }
}

/// Renders shape glyphs for the gallery and the ribbon button.
enum ShapeIcons {
    static func draw(_ kind: ShapeKind, in rect: CGRect, _ ctx: CGContext, color: NSColor) {
        let r = rect.insetBy(dx: 3, dy: 3)
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1.2)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        let path: CGPath
        switch kind {
        case .line:
            path = ShapePaths.path(points: [CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.minY)], controls: [], kind: .line)
        case .curve:
            path = ShapePaths.path(points: [CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.minY)],
                                   controls: [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY)], kind: .curve)
        case .polygon:
            path = ShapePaths.path(points: [CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX + r.width * 0.3, y: r.minY),
                                            CGPoint(x: r.maxX, y: r.minY + r.height * 0.3), CGPoint(x: r.maxX - r.width * 0.2, y: r.maxY)], controls: [], kind: .polygon)
        default:
            path = ShapePaths.path(for: kind, in: r)
        }
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }
}
