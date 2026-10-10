import AppKit
import Vision
import CoreImage

/// Root view that lays out the chrome manually (title row, menu strip, ribbon, canvas, panels, status bar).
/// With Liquid Glass off it paints an opaque ground so the window no longer shows the desktop through.
final class RootView: NSView {
    var layoutHandler: ((CGSize) -> Void)?
    private var observer: Any?
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        observer = NotificationCenter.default.addObserver(forName: .liquidGlassSettingChanged, object: nil, queue: .main) { [weak self] _ in
            self?.needsDisplay = true
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let o = observer { NotificationCenter.default.removeObserver(o) } }

    override func layout() {
        super.layout()
        layoutHandler?(bounds.size)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !GlassHost.liquidGlassEnabled else { return }
        Theme.chromeBackground.setFill()
        bounds.fill()
    }
}

/// Title row that behaves like a title bar: drag moves the window.
final class TitleRowView: NSView {
    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 2 { window?.performZoom(nil) }
    }
}

final class MainWindowController: NSWindowController, NSWindowDelegate, CanvasViewDelegate, NSMenuItemValidation {
    let paintDocument: PaintDocument
    var state: ToolState { paintDocument.toolState }

    private let root = RootView()
    /// Transparent strip under the native title bar; the system draws the title and proxy icon over it.
    private let titleRow = TitleRowView()
    private let menuStrip = NSView()
    private var menuButtons: [RibbonButton] = []
    private var stripButtons: [NSView] = []
    private var undoButton: RibbonButton!
    private var redoButton: RibbonButton!
    private var settingsButton: RibbonButton!
    private var sizeSlider: VerticalSliderView!
    private var opacitySlider: VerticalSliderView!
    private var keyMonitor: Any?
    private var ribbon: RibbonView!
    private var textBar: TextOptionsBar!
    private let scrollView = NSScrollView()
    private(set) var canvas: CanvasView!
    private let hRuler = RulerView(horizontal: true)
    private let vRuler = RulerView(horizontal: false)
    private let rulerCorner = RulerCornerView()
    private var layersPanel: LayersPanelView!
    private var colorPanel: ColorPanelView!
    private let statusBar = StatusBarView()

    private var showRulers: Bool { AppSettings.showRulers }
    private var showStatusBar: Bool { AppSettings.showStatusBar }
    private var showLayersPanel: Bool { AppSettings.showLayersPanel }
    private var showColorPanel: Bool { AppSettings.showColorPanel }
    private var showTopToolbar: Bool { AppSettings.showTopToolbar }
    private let toast = ToastView()
    /// Liquid Glass slab behind the Toolbar, Ribbon and Text bar (plain container before macOS 26).
    private let chromeHost = GlassHost(cornerRadius: 0, fallback: .none, veil: Theme.glassBand)
    private var observers: [Any] = []

    init(document: PaintDocument) {
        self.paintDocument = document
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 840),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.minSize = NSSize(width: 900, height: 560)
        window.center()
        window.setFrameAutosaveName("PaintMainWindow")
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        buildViews()
        let backdrop = NSVisualEffectView()
        backdrop.material = Theme.windowMaterial
        backdrop.blendingMode = .behindWindow
        backdrop.state = .followsWindowActiveState
        backdrop.autoresizingMask = [.width, .height]
        root.autoresizingMask = [.width, .height]
        root.frame = backdrop.bounds
        backdrop.addSubview(root)
        window.contentView = backdrop
        root.frame = backdrop.bounds
        shouldCascadeWindows = true
        window.initialFirstResponder = canvas
        observers.append(NotificationCenter.default.addObserver(forName: .toolStateChanged, object: state, queue: .main) { [weak self] _ in self?.toolStateChanged() })
        observers.append(NotificationCenter.default.addObserver(forName: .documentDidChange, object: document, queue: .main) { [weak self] _ in self?.documentChanged() })
        observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak self] _ in self?.updateRulers() })
        observers.append(NotificationCenter.default.addObserver(forName: .NSUndoManagerCheckpoint, object: document.undoManager, queue: .main) { [weak self] _ in self?.refreshUndo() })
        observers.append(NotificationCenter.default.addObserver(forName: .settingsChanged, object: nil, queue: .main) { [weak self] _ in self?.applySettings() })
        applySettings()
        statusBar.setImageSize(document.canvasSize)
        statusBar.setZoom(1)
        refreshUndo()
        syncSliders()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self, let window = self.window, window.isKeyWindow, event.window === window else { return event }
            if event.type == .flagsChanged { // modifier cursors (Cmd on a guide, Option eyedropper), whoever is first responder
                self.canvas.refreshCursor()
                return event
            }
            if self.window?.firstResponder is NSTextView { return event }
            if event.keyCode == 49 { // space: temporary hand tool while held
                self.canvas.isSpaceDown = event.type == .keyDown
                return nil
            }
            guard event.type == .keyDown else { return event }
            return self.handleShortcut(event) ? nil : event
        }
    }

    required init?(coder: NSCoder) { fatalError() }
    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
    }

    /// Photoshop-style single-key shortcuts (no Cmd / Ctrl / Opt): `[` `]` brush size, Shift+`[` `]` opacity,
    /// digits opacity 10–100 %, and tool keys handled by `handleToolKey`.
    private func handleShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let chars = event.charactersIgnoringModifiers, chars.count == 1 else { return false }
        let shift = event.modifierFlags.contains(.shift)
        switch chars {
        case "[", "{":
            if shift { state.opacity -= 0.1 } else { state.lineWidth -= Self.sizeStep(state.lineWidth, up: false) }
        case "]", "}":
            if shift { state.opacity += 0.1 } else { state.lineWidth += Self.sizeStep(state.lineWidth, up: true) }
        case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
            let n = Int(chars)!
            state.opacity = n == 0 ? 1 : CGFloat(n) / 10
        default:
            return handleToolKey(chars.lowercased(), shift: shift)
        }
        canvas.showSizePreview()
        return true
    }

    /// B brush (Shift+B toggles brush / pencil), N pencil, E eraser, G fill, I eyedropper, T text,
    /// M rectangle selection, L free-form selection, Z zoom, U shapes, X swap colours, D default colours.
    private func handleToolKey(_ key: String, shift: Bool) -> Bool {
        switch key {
        case "b":
            if shift, state.tool.isBrush { state.tool = .pencil } else { state.tool = .brush(state.lastBrush) }
        case "n": state.tool = .pencil
        case "e": state.tool = .eraser
        case "g": state.tool = .fill
        case "i": state.tool = .colorPicker
        case "t": state.tool = .text
        case "m", "s": state.tool = .selectRectangle
        case "l": state.tool = .selectFreeform
        case "z": state.tool = .magnifier
        case "u": state.tool = .shape(state.lastShape)
        case "x": swap(&state.color1, &state.color2)
        case "d": state.color1 = .black; state.color2 = .white
        default: return false
        }
        return true
    }

    private static func sizeStep(_ w: CGFloat, up: Bool) -> CGFloat {
        let ref = up ? w : w - 1
        if ref < 10 { return 1 }
        if ref < 50 { return 5 }
        return 10
    }

    private func refreshUndo() {
        undoButton.isEnabled = paintDocument.undoManager?.canUndo ?? false
        redoButton.isEnabled = paintDocument.undoManager?.canRedo ?? false
    }

    private func syncSliders() {
        sizeSlider.value = Double(state.lineWidth)
        opacitySlider.value = Double(state.opacity * 100)
    }


    // MARK: - View construction

    private func buildViews() {
        root.layoutHandler = { [weak self] size in self?.layoutChrome(size) }

        // The title row shares the glass slab with the Toolbar and Ribbon so there is no seam under the title bar.
        root.addSubview(chromeHost)
        chromeHost.content.addSubview(titleRow)

        let menuDefs: [(String, () -> NSMenu)] = [
            (L("File"), { AppDelegate.shared.fileMenu }),
            (L("Edit"), { AppDelegate.shared.editMenu }),
            (L("View"), { AppDelegate.shared.viewMenu }),
        ]
        for (title, menu) in menuDefs {
            let b = RibbonButton(title: title, style: .wide, tooltip: title)
            b.image = nil
            b.onClick = { [weak b] in
                guard let b else { return }
                let m = menu()
                m.popUp(positioning: nil, at: NSPoint(x: 0, y: b.bounds.maxY + 4), in: b)
            }
            menuStrip.addSubview(b)
            menuButtons.append(b)
            stripButtons.append(b)
        }
        func stripSeparator() -> NSView {
            let v = RibbonSeparator()
            v.translatesAutoresizingMaskIntoConstraints = true
            menuStrip.addSubview(v)
            stripButtons.append(v)
            return v
        }
        func stripButton(_ symbol: String, _ tip: String, _ action: @escaping () -> Void) -> RibbonButton {
            let b = RibbonButton(symbol: symbol, tooltip: tip, onClick: action)
            b.preferredSize = NSSize(width: 30, height: 26)
            menuStrip.addSubview(b)
            stripButtons.append(b)
            return b
        }
        _ = stripSeparator()
        _ = stripButton("square.and.arrow.down", Theme.tip(L("Save"), "⌘S")) { NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil) }
        _ = stripButton("square.and.arrow.up", L("Share")) { [weak self] in self?.shareImage(nil) }
        _ = stripSeparator()
        undoButton = stripButton("arrow.uturn.backward", Theme.tip(L("Undo"), "⌘Z")) { [weak self] in self?.paintDocument.undoManager?.undo() }
        redoButton = stripButton("arrow.uturn.forward", Theme.tip(L("Redo"), "⇧⌘Z / ⌘Y")) { [weak self] in self?.paintDocument.undoManager?.redo() }
        settingsButton = RibbonButton(symbol: "gearshape", tooltip: Theme.tip(L("Settings"), "⌘,"))
        settingsButton.preferredSize = NSSize(width: 30, height: 26)
        settingsButton.onClick = { PreferencesWindowController.shared.show() }
        menuStrip.addSubview(settingsButton)
        chromeHost.content.addSubview(menuStrip)

        ribbon = RibbonView(document: paintDocument)
        ribbon.controller = self
        chromeHost.content.addSubview(ribbon)

        textBar = TextOptionsBar(state: state)
        textBar.isHidden = true
        chromeHost.content.addSubview(textBar)

        canvas = CanvasView(document: paintDocument)
        canvas.delegate = self
        scrollView.contentView = CenteringClipView()
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.allowsMagnification = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        root.addSubview(scrollView)

        hRuler.canvas = canvas; vRuler.canvas = canvas
        root.addSubview(hRuler); root.addSubview(vRuler); root.addSubview(rulerCorner)

        sizeSlider = VerticalSliderView(symbol: "line.3.horizontal", tooltip: Theme.tip(L("Size"), "[ ]"), min: 1, max: 100) { "\(Int($0))" }
        sizeSlider.onChange = { [weak self] v in
            self?.state.lineWidth = CGFloat(v)
            self?.canvas.showSizePreview()
        }
        opacitySlider = VerticalSliderView(symbol: "drop.halffull", tooltip: Theme.tip(L("Opacity"), "⇧[ ] · 1–0"), min: 0, max: 100) { "\(Int($0))%" }
        opacitySlider.onChange = { [weak self] v in
            self?.state.opacity = CGFloat(v) / 100
            self?.canvas.showSizePreview()
        }
        root.addSubview(sizeSlider)
        root.addSubview(opacitySlider)

        layersPanel = LayersPanelView(document: paintDocument)
        root.addSubview(layersPanel)
        colorPanel = ColorPanelView(state: state)
        root.addSubview(colorPanel)

        root.addSubview(toast)

        statusBar.onZoomChanged = { [weak self] z in self?.canvas.setZoom(z) }
        statusBar.onZoomIn = { [weak self] in self?.zoomIn(nil) }
        statusBar.onZoomOut = { [weak self] in self?.zoomOut(nil) }
        root.addSubview(statusBar)
    }

    private func layoutChrome(_ size: CGSize) {
        let w = size.width
        var y: CGFloat = 0

        // Title row, Toolbar, Ribbon and Text bar share one glass slab; positions inside it are relative.
        let chromeTop = y
        var cy: CGFloat = 0
        titleRow.frame = CGRect(x: 0, y: cy, width: w, height: 28)
        cy += 28
        menuStrip.isHidden = !showTopToolbar
        menuStrip.frame = CGRect(x: 0, y: cy, width: w, height: showTopToolbar ? 32 : 0)
        var x: CGFloat = 8
        for v in stripButtons {
            if let b = v as? RibbonButton {
                let s = b.intrinsicContentSize
                b.frame = CGRect(x: x, y: 3, width: s.width, height: s.height)
                x += s.width + 2
            } else {
                v.frame = CGRect(x: x + 4, y: 4, width: 1, height: 24)
                x += 10
            }
        }
        settingsButton.frame = CGRect(x: w - 40, y: 3, width: 30, height: 26)
        if showTopToolbar { cy += 32 }

        ribbon.frame = CGRect(x: 0, y: cy, width: w, height: Theme.ribbonHeight)
        cy += Theme.ribbonHeight
        if !textBar.isHidden {
            textBar.frame = CGRect(x: 0, y: cy, width: w, height: 40)
            cy += 40
        }
        chromeHost.frame = CGRect(x: 0, y: chromeTop, width: w, height: cy)
        y = chromeTop + cy

        let statusH: CGFloat = showStatusBar ? Theme.statusBarHeight : 0
        statusBar.isHidden = !showStatusBar
        statusBar.frame = CGRect(x: 0, y: size.height - statusH, width: w, height: statusH)

        let middleH = size.height - y - statusH
        let middleW = w
        // The Color and Layers cards float over the canvas (like the slider cards) instead of narrowing it,
        // stacked against the right edge with the Color card on top.
        var columnY = y
        if showColorPanel {
            colorPanel.frame = CGRect(x: w - Theme.colorPanelWidth, y: columnY, width: Theme.colorPanelWidth, height: ColorPanelView.height)
            columnY += ColorPanelView.height
        }
        if showLayersPanel {
            layersPanel.frame = CGRect(x: w - Theme.layersPanelWidth, y: columnY, width: Theme.layersPanelWidth,
                                       height: max(0, middleH - (columnY - y)))
        }
        let rulerT: CGFloat = showRulers ? 20 : 0
        rulerCorner.frame = CGRect(x: 0, y: y, width: rulerT, height: rulerT)
        hRuler.frame = CGRect(x: rulerT, y: y, width: middleW - rulerT, height: rulerT)
        vRuler.frame = CGRect(x: 0, y: y + rulerT, width: rulerT, height: middleH - rulerT)
        let newScrollFrame = CGRect(x: rulerT, y: y + rulerT, width: middleW - rulerT, height: middleH - rulerT)
        if scrollView.frame != newScrollFrame {
            scrollView.frame = newScrollFrame
            canvas.updateFrameSize()
        }
        let toastSize = toast.size(for: toast.text, maxWidth: max(200, middleW - 80))
        toast.frame = CGRect(x: rulerT + (middleW - rulerT - toastSize.width) / 2, y: y + middleH - toastSize.height - 16,
                             width: toastSize.width, height: toastSize.height)
        let sliderH = max(80, (middleH - rulerT - 36) / 2)
        sizeSlider.frame = CGRect(x: rulerT + 12, y: y + rulerT + 12, width: 36, height: sliderH)
        opacitySlider.frame = CGRect(x: rulerT + 12, y: y + rulerT + 12 + sliderH + 12, width: 36, height: sliderH)
        updateRulers()
    }

    private func updateRulers() {
        guard showRulers, let canvas else { return }
        let clipOrigin = scrollView.contentView.bounds.origin
        hRuler.zoom = canvas.zoom
        vRuler.zoom = canvas.zoom
        hRuler.origin = canvas.canvasOrigin.x - clipOrigin.x
        vRuler.origin = canvas.canvasOrigin.y - clipOrigin.y
    }

    // MARK: - Observers

    private func toolStateChanged() {
        syncSliders()
        let wantsTextBar = state.tool == .text
        if textBar.isHidden == wantsTextBar {
            textBar.isHidden = !wantsTextBar
            root.needsLayout = true
        }
    }

    private func documentChanged() {
        statusBar.setImageSize(paintDocument.canvasSize)
        updateRulers()
        refreshUndo()
    }

    @objc func shareImage(_ sender: Any?) {
        guard let cg = paintDocument.flattenedImage(background: paintDocument.backgroundVisible ? nil : .white) else { return }
        let image = NSImage(cgImage: cg, size: paintDocument.canvasSize)
        let picker = NSSharingServicePicker(items: [image])
        if let anchor = stripButtons.compactMap({ $0 as? RibbonButton }).first(where: { $0.toolTip == L("Share") }) {
            picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        }
    }

    @objc func editBackgroundColor(_ sender: Any?) {
        guard let window else { return }
        ColorEditorPanel.present(on: window, initial: paintDocument.backgroundColor, state: state) { [weak self] color in
            guard let self, let c = color else { return }
            self.paintDocument.setBackgroundColor(c)
        }
    }

    @objc func toggleBackgroundVisible(_ sender: Any?) {
        paintDocument.toggleBackgroundVisible()
    }

    // MARK: - CanvasViewDelegate

    func canvasCursorMoved(_ point: CGPoint?) {
        statusBar.setCursor(point)
        hRuler.cursor = point?.x
        vRuler.cursor = point?.y
    }

    func canvasSelectionChanged(_ size: CGSize?) {
        statusBar.setSelection(size)
    }

    func canvasZoomChanged(_ zoom: CGFloat) {
        statusBar.setZoom(zoom)
        updateRulers()
    }

    func canvasDidAddGuide() {
        showToast(L("Hold ⌘ to move a guide."))
    }

    // MARK: - View actions

    @objc func zoomIn(_ sender: Any?) {
        let z = canvas.zoom
        canvas.setZoom(Theme.zoomLevels.first(where: { $0 > z + 0.001 }) ?? Theme.zoomLevels.last!)
    }

    @objc func zoomOut(_ sender: Any?) {
        let z = canvas.zoom
        canvas.setZoom(Theme.zoomLevels.last(where: { $0 < z - 0.001 }) ?? Theme.zoomLevels.first!)
    }

    @objc func zoomActual(_ sender: Any?) { canvas.setZoom(1) }
    @objc func zoomToFit(_ sender: Any?) { canvas.zoomToFit(in: scrollView.contentView.bounds.size) }

    @objc func toggleGridlines(_ sender: Any?) { AppSettings.showGridlines.toggle() }
    @objc func toggleGuides(_ sender: Any?) { AppSettings.showGuides.toggle() }
    @objc func clearGuides(_ sender: Any?) { canvas.guides.removeAll() }

    @objc func toggleRulers(_ sender: Any?) {
        AppSettings.showRulers.toggle()
        if showRulers { showToast(L("Drag from a ruler onto the canvas to add a guide.")) }
    }

    @objc func toggleTopToolbar(_ sender: Any?) { AppSettings.showTopToolbar.toggle() }

    /// Mirrors every `AppSettings` view option into this window.
    private func applySettings() {
        hRuler.isHidden = !showRulers; vRuler.isHidden = !showRulers; rulerCorner.isHidden = !showRulers
        layersPanel.isHidden = !showLayersPanel
        ribbon.setLayersPanelVisible(showLayersPanel)
        colorPanel.isHidden = !showColorPanel
        ribbon.setColorPanelVisible(showColorPanel)
        ribbon.setHistoryVisible(!showTopToolbar)
        canvas.showGrid = AppSettings.showGridlines
        canvas.showGuides = AppSettings.showGuides
        root.needsLayout = true
    }

    /// Development aid: chrome frames in window coordinates, for headless layout checks.
    func layoutDebugSummary() -> String {
        func f(_ v: NSView) -> String {
            let r = v.convert(v.bounds, to: nil)
            return "y=\(Int(r.minY))..\(Int(r.maxY))"
        }
        return "flipped=\(chromeHost.content.isFlipped) toolbar \(f(menuStrip)) ribbon \(f(ribbon)) canvas \(f(scrollView)) sizeSlider \(f(sizeSlider)) status \(f(statusBar)) (window coords, y up)"
    }

    /// Shows a transient hint at the bottom of the canvas area.
    func showToast(_ text: String) {
        toast.show(text)
        root.needsLayout = true
    }

    @objc func toggleStatusBar(_ sender: Any?) { AppSettings.showStatusBar.toggle() }

    @objc func toggleLayersPanel(_ sender: Any?) { AppSettings.showLayersPanel.toggle() }

    @objc func toggleColorPanel(_ sender: Any?) { AppSettings.showColorPanel.toggle() }

    // MARK: - Edit actions

    @objc func pasteFromFile(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .OK, let url = panel.url, let img = NSImage(contentsOf: url),
                  let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            self?.canvas.pasteImage(cg)
        }
    }

    @objc func invertSelection(_ sender: Any?) { canvas.invertSelection() }
    @objc func toggleTransparentSelection(_ sender: Any?) { state.transparentSelection.toggle() }
    @objc func cropToSelection(_ sender: Any?) {
        guard canvas.selection != nil || canvas.floating != nil else {
            showToast(L("Select an area first, then crop."))
            return
        }
        canvas.cropToSelection()
    }

    // MARK: - Image actions

    @objc func rotateRight(_ sender: Any?) { finishPending(); paintDocument.rotate(.right90) }
    @objc func rotateLeft(_ sender: Any?) { finishPending(); paintDocument.rotate(.left90) }
    @objc func rotate180(_ sender: Any?) { finishPending(); paintDocument.rotate(.half) }
    @objc func flipVertical(_ sender: Any?) { finishPending(); paintDocument.flip(horizontal: false) }
    @objc func flipHorizontal(_ sender: Any?) { finishPending(); paintDocument.flip(horizontal: true) }

    private func finishPending() {
        canvas.tool.commit()
        canvas.commitFloating()
        canvas.selection = nil
    }

    @objc func resizeAndSkew(_ sender: Any?) {
        guard let window else { return }
        finishPending()
        ResizeSkewDialog.present(on: window, currentSize: paintDocument.canvasSize) { [weak self] result in
            guard let self, let r = result else { return }
            self.paintDocument.resizeImage(to: r.size, skewX: r.skewX, skewY: r.skewY)
        }
    }

    @objc func imageProperties(_ sender: Any?) {
        guard let window else { return }
        finishPending()
        ImagePropertiesDialog.present(on: window, document: paintDocument) { [weak self] size in
            guard let self, let size else { return }
            self.paintDocument.resizeCanvas(to: size)
        }
    }

    @objc func setAsDesktopBackground(_ sender: Any?) {
        guard let cg = paintDocument.flattenedImage(background: paintDocument.backgroundVisible ? nil : .white) else { return }
        do {
            let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Paint Again", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("desktop-\(Int(Date().timeIntervalSince1970)).png")
            guard let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
            try data.write(to: url)
            for screen in NSScreen.screens {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            }
        } catch {
            presentError(error)
        }
    }

    @objc func removeBackground(_ sender: Any?) {
        canvas.tool.commit()
        canvas.commitFloating()
        let layer = paintDocument.activeLayer
        let selection = canvas.selection
        let region = selection?.rect.integral.intersection(paintDocument.canvasRect) ?? paintDocument.canvasRect
        guard !region.isEmpty, let source = layer.bitmap.cropped(to: region) else { return }
        let before = paintDocument.beginLayerEdit(layer)
        window?.contentView?.alphaValue = 1
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let mask = BackgroundRemoval.foregroundMask(for: source)
            DispatchQueue.main.async {
                guard let self else { return }
                guard let mask else {
                    self.showToast(L("No subject found to keep."))
                    return
                }
                let region_ = region
                // Apply the mask to the region only.
                let regionBitmap = Bitmap(image: source)
                regionBitmap.applyAlphaMask(mask)
                if let sel = selection, !sel.isRectangular {
                    let ctx = layer.bitmap.context
                    ctx.saveGState()
                    ctx.addPath(sel.path)
                    if sel.evenOdd { ctx.clip(using: .evenOdd) } else { ctx.clip() }
                    if let img = regionBitmap.makeImage() { layer.bitmap.draw(img, in: region_, blend: .copy, interpolate: false) }
                    ctx.restoreGState()
                } else if let img = regionBitmap.makeImage() {
                    layer.bitmap.draw(img, in: region_, blend: .copy, interpolate: false)
                }
                self.paintDocument.commitLayerEdit(before, name: L("Remove background"))
            }
        }
    }

    // MARK: - Layer actions

    @objc func addLayer(_ sender: Any?) { finishPendingKeepSelection(); paintDocument.addLayer() }
    @objc func duplicateLayer(_ sender: Any?) { finishPendingKeepSelection(); paintDocument.duplicateLayer() }
    @objc func deleteLayer(_ sender: Any?) { finishPendingKeepSelection(); paintDocument.deleteLayer() }
    @objc func mergeDown(_ sender: Any?) { finishPendingKeepSelection(); paintDocument.mergeLayerDown() }
    @objc func moveLayerUp(_ sender: Any?) { finishPendingKeepSelection(); paintDocument.moveLayer(up: true) }
    @objc func moveLayerDown(_ sender: Any?) { finishPendingKeepSelection(); paintDocument.moveLayer(up: false) }
    @objc func toggleLayerVisibility(_ sender: Any?) { paintDocument.toggleLayerVisibility(paintDocument.activeLayer) }

    private func finishPendingKeepSelection() {
        canvas.tool.commit()
        canvas.commitFloating()
    }

    @objc func layerProperties(_ sender: Any?) {
        guard let window else { return }
        let layer = paintDocument.activeLayer
        LayerPropertiesDialog.present(on: window, layer: layer) { [weak self] result in
            guard let self, let r = result else { return }
            self.paintDocument.performStructuralChange(L("Layer properties")) {
                layer.name = r.name
                layer.opacity = r.opacity
                layer.isVisible = r.visible
            }
        }
    }

    // MARK: - Validation

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let doc = paintDocument
        switch item.action {
        case #selector(toggleGridlines(_:)): item.state = canvas.showGrid ? .on : .off
        case #selector(toggleTopToolbar(_:)): item.state = showTopToolbar ? .on : .off
        case #selector(toggleGuides(_:)): item.state = canvas.showGuides ? .on : .off
        case #selector(clearGuides(_:)): return !canvas.guides.isEmpty
        case #selector(toggleRulers(_:)): item.state = showRulers ? .on : .off
        case #selector(toggleStatusBar(_:)): item.state = showStatusBar ? .on : .off
        case #selector(toggleLayersPanel(_:)): item.state = showLayersPanel ? .on : .off
        case #selector(toggleColorPanel(_:)): item.state = showColorPanel ? .on : .off
        case #selector(toggleTransparentSelection(_:)): item.state = state.transparentSelection ? .on : .off
        case #selector(cropToSelection(_:)), #selector(invertSelection(_:)): return canvas.selection != nil
        case #selector(deleteLayer(_:)): return doc.layers.count > 1
        case #selector(mergeDown(_:)), #selector(moveLayerDown(_:)): return doc.activeLayerIndex > 0
        case #selector(moveLayerUp(_:)): return doc.activeLayerIndex < doc.layers.count - 1
        case #selector(toggleLayerVisibility(_:)): item.title = doc.activeLayer.isVisible ? L("Hide Layer") : L("Show Layer")
        case #selector(toggleBackgroundVisible(_:)): item.title = doc.backgroundVisible ? L("Hide Background") : L("Show Background")
        default: break
        }
        return true
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        if window?.firstResponder === window { window?.makeFirstResponder(canvas) }
    }
}

/// On-device subject isolation using Vision, behind the "Remove background" command.
enum BackgroundRemoval {
    static func foregroundMask(for image: CGImage) -> CGImage? {
        guard #available(macOS 14.0, *) else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            guard let result = request.results?.first else { return nil }
            let buffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
            let ci = CIImage(cvPixelBuffer: buffer)
            let context = CIContext(options: nil)
            return context.createCGImage(ci, from: ci.extent)
        } catch {
            return nil
        }
    }
}
