import AppKit

protocol CanvasViewDelegate: AnyObject {
    func canvasCursorMoved(_ point: CGPoint?)
    func canvasSelectionChanged(_ size: CGSize?)
    func canvasZoomChanged(_ zoom: CGFloat)
    /// A new guide was dragged out of a ruler (not fired when an existing guide is moved).
    func canvasDidAddGuide()
}

/// Renders the document and routes mouse / keyboard input to the active tool.
final class CanvasView: NSView, NSMenuItemValidation {
    static let padding: CGFloat = 24

    let document: PaintDocument
    var state: ToolState { document.toolState }
    weak var delegate: CanvasViewDelegate?

    private(set) var zoom: CGFloat = 1
    var showGrid = false { didSet { needsDisplay = true } }

    var selection: Selection? {
        didSet {
            needsDisplay = true
            delegate?.canvasSelectionChanged(selection?.rect.size)
        }
    }
    var floating: FloatingSelection? { didSet { needsDisplay = true } }

    /// Temporary buffer that brush tools paint into; composited over the active layer while drawing.
    var strokeBuffer: Bitmap? { didSet { needsDisplay = true } }
    var strokeBlend: CGBlendMode = .normal
    var strokeAlpha: CGFloat = 1

    private(set) var tool: Tool!
    /// Tool to return to after a one-shot tool such as the colour picker.
    var previousToolKind: ToolKind = .pencil

    /// While the Size / Opacity sliders are adjusted, a preview of the brush footprint is shown at the
    /// centre of the visible canvas and fades out shortly afterwards.
    private var sizePreviewTimer: Timer?
    private var showingSizePreview = false

    func showSizePreview() {
        showingSizePreview = true
        sizePreviewTimer?.invalidate()
        let timer = Timer(timeInterval: 0.9, repeats: false) { [weak self] _ in self?.hideSizePreview() }
        RunLoop.main.add(timer, forMode: .common)
        sizePreviewTimer = timer
        needsDisplay = true
    }

    private func hideSizePreview() {
        sizePreviewTimer?.invalidate()
        sizePreviewTimer = nil
        if showingSizePreview {
            showingSizePreview = false
            needsDisplay = true
        }
    }

    private func drawSizePreview(_ ctx: CGContext) {
        guard showingSizePreview else { return }
        let center = visibleRect.center
        let w = max(2, max(1, state.lineWidth) * zoom)
        let r = CGRect(x: center.x - w / 2, y: center.y - w / 2, width: w, height: w)
        ctx.saveGState()
        ctx.setFillColor(state.color1.withAlphaComponent(state.opacity).cgColor)
        ctx.setLineWidth(1)
        if state.tool == .eraser {
            ctx.fill(r)
            ctx.setStrokeColor(NSColor.white.cgColor); ctx.stroke(r.insetBy(dx: -0.5, dy: -0.5))
            ctx.setStrokeColor(NSColor.black.cgColor); ctx.stroke(r.insetBy(dx: 0.5, dy: 0.5))
        } else {
            ctx.fillEllipse(in: r)
            ctx.setStrokeColor(NSColor.white.cgColor); ctx.strokeEllipse(in: r.insetBy(dx: -0.5, dy: -0.5))
            ctx.setStrokeColor(NSColor.black.cgColor); ctx.strokeEllipse(in: r.insetBy(dx: 0.5, dy: 0.5))
        }
        ctx.restoreGState()
    }

    /// Space bar held: dragging pans, Cmd-click zooms in, Cmd-Opt-click zooms out (Photoshop behaviour).
    var isSpaceDown = false {
        didSet { if oldValue != isSpaceDown { refreshCursor() } }
    }
    private var panStart: (mouse: CGPoint, origin: CGPoint)?

    /// Samples the flattened image and assigns the colour to Color 1 (primary) or Color 2 (secondary).
    func sampleColor(at p: CGPoint, button: MouseButton) {
        guard document.canvasRect.contains(p), let source = pickSource ?? makePickSource(),
              let picked = pickedColor(in: source, at: p) else { return }
        if button == .primary { state.color1 = picked } else { state.color2 = picked }
    }

    private func makePickSource() -> Bitmap? {
        document.flattenedImage().map { Bitmap(image: $0) }
    }

    /// The colour the eyedropper reads from a flattened-image pixel: transparent pixels read as the
    /// Background (white when it is hidden), everything else as opaque.
    private func pickedColor(in source: Bitmap, at p: CGPoint) -> NSColor? {
        guard let c = source.color(at: p) else { return nil }
        return c.alphaComponent == 0 ? (document.backgroundVisible ? document.backgroundColor : NSColor.white) : c.withAlphaComponent(1)
    }

    // MARK: - Option eyedropper

    /// Flattened image read by the loupe and by Option-click while Option is held; dropped when the
    /// document changes or the eyedropper ends.
    private var pickSource: Bitmap?
    /// Whether the Option eyedropper currently owns the pointer (cursor, loupe, clicks).
    private var optionPickActive = false
    /// Button of an Option-click drag that keeps sampling until the button is released.
    private var optionPickButton: MouseButton?
    /// Pointer position (view coordinates) the loupe is drawn for; nil when the pointer is off the image.
    private var loupePoint: CGPoint?
    /// A tool received a mouse-down and has not seen the matching mouse-up yet.
    private var isToolTracking = false

    /// Painting tools sample on Option-click; tools that use the click for something else keep it.
    private var toolAllowsOptionPick: Bool {
        !tool.kind.isSelection && tool.kind != .magnifier && tool.kind != .text && !tool.hasPendingObject
    }

    private var wantsOptionPick: Bool {
        if optionPickButton != nil { return true }
        return mouseInside && !isSpaceDown && !isToolTracking && !isDraggingCanvasHandle && !isMovingGuide
            && panStart == nil && NSEvent.modifierFlags.contains(.option) && toolAllowsOptionPick
    }

    /// Re-evaluates the Option eyedropper for a pointer at `viewPoint` (nil when the pointer left the canvas).
    private func updateOptionPick(at viewPoint: CGPoint?) {
        let active = viewPoint != nil && wantsOptionPick
        var point = active ? viewPoint : nil
        if let q = point, !document.canvasRect.contains(imagePoint(fromView: q)) { point = nil }
        if active != optionPickActive {
            optionPickActive = active
            if active { pickSource = makePickSource() } else { pickSource = nil }
            needsDisplay = true
        } else if point != loupePoint {
            if let r = loupeFrame(at: loupePoint) { setNeedsDisplay(r) }
            if let r = loupeFrame(at: point) { setNeedsDisplay(r) }
        }
        loupePoint = point
    }

    private static let loupeCells = 11
    private static let loupeCell: CGFloat = 9
    private static let loupeInset: CGFloat = 6
    private static let loupeInfoHeight: CGFloat = 22
    private static let loupeOffset: CGFloat = 18

    /// Loupe panel for a pointer at `p`: below-right of the pointer, flipped to the other side when it
    /// would leave the visible area. Includes room for the drop shadow.
    private func loupeFrame(at p: CGPoint?) -> CGRect? {
        guard let p else { return nil }
        let grid = CGFloat(Self.loupeCells) * Self.loupeCell
        let size = CGSize(width: grid + Self.loupeInset * 2, height: grid + Self.loupeInset * 2 + Self.loupeInfoHeight)
        let visible = visibleRect
        var x = p.x + Self.loupeOffset, y = p.y + Self.loupeOffset
        if x + size.width > visible.maxX { x = p.x - Self.loupeOffset - size.width }
        if y + size.height > visible.maxY { y = p.y - Self.loupeOffset - size.height }
        return CGRect(origin: CGPoint(x: x, y: y), size: size).insetBy(dx: -8, dy: -8)
    }

    /// Magnified pixels around the pointer with the sampled centre pixel outlined, plus its colour and hex value.
    private func drawLoupe(_ ctx: CGContext) {
        guard let p = loupePoint, let source = pickSource, let outer = loupeFrame(at: p) else { return }
        let panel = outer.insetBy(dx: 8, dy: 8)
        let center = imagePoint(fromView: p).floored
        let half = Self.loupeCells / 2
        let cell = Self.loupeCell
        let grid = CGRect(x: panel.minX + Self.loupeInset, y: panel.minY + Self.loupeInset,
                          width: CGFloat(Self.loupeCells) * cell, height: CGFloat(Self.loupeCells) * cell)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            ctx.saveGState()
            let shape = CGPath(roundedRect: panel, cornerWidth: 8, cornerHeight: 8, transform: nil)
            ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: NSColor.black.withAlphaComponent(0.3).cgColor)
            ctx.setFillColor(NSColor.controlBackgroundColor.cgColor)
            ctx.addPath(shape)
            ctx.fillPath()
            ctx.restoreGState()

            ctx.saveGState()
            ctx.clip(to: grid)
            ctx.setFillColor(NSColor.gray.withAlphaComponent(0.35).cgColor)
            ctx.fill(grid)
            for row in 0..<Self.loupeCells {
                for col in 0..<Self.loupeCells {
                    let ip = CGPoint(x: center.x + CGFloat(col - half), y: center.y + CGFloat(row - half))
                    guard let c = pickedColor(in: source, at: ip) else { continue }
                    ctx.setFillColor(c.cgColor)
                    ctx.fill(CGRect(x: grid.minX + CGFloat(col) * cell, y: grid.minY + CGFloat(row) * cell, width: cell, height: cell))
                }
            }
            ctx.restoreGState()

            let mark = CGRect(x: grid.minX + CGFloat(half) * cell, y: grid.minY + CGFloat(half) * cell, width: cell, height: cell)
            ctx.setLineWidth(1)
            ctx.setStrokeColor(NSColor.white.cgColor); ctx.stroke(mark.insetBy(dx: -0.5, dy: -0.5))
            ctx.setStrokeColor(NSColor.black.cgColor); ctx.stroke(mark.insetBy(dx: 0.5, dy: 0.5))
            ctx.setStrokeColor(NSColor.separatorColor.cgColor); ctx.stroke(grid.insetBy(dx: -0.5, dy: -0.5))

            guard let picked = pickedColor(in: source, at: center) else { return }
            let info = CGRect(x: grid.minX, y: grid.maxY + 4, width: grid.width, height: Self.loupeInfoHeight - 4)
            let swatch = CGRect(x: info.minX, y: info.midY - 7, width: 14, height: 14)
            ctx.setFillColor(picked.cgColor)
            ctx.fill(swatch)
            ctx.setStrokeColor(NSColor.separatorColor.cgColor); ctx.stroke(swatch.insetBy(dx: 0.5, dy: 0.5))
            let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
            let text = NSAttributedString(string: picked.hexString, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
            let ts = text.size()
            text.draw(at: CGPoint(x: swatch.maxX + 6, y: info.midY - ts.height / 2))
        }
    }

    /// Moves the selection (lifting it first) by a pixel offset; used by the arrow keys.
    func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        if floating == nil {
            guard selection != nil else { return }
            liftSelection()
        }
        guard var f = floating else { return }
        f.rect = f.rect.offsetBy(dx: dx, dy: dy)
        floating = f
        selection = Selection.rectangle(f.rect)
    }

    // MARK: - Guides (Photoshop-style: dragged out of the rulers)

    enum GuideAxis { case horizontal, vertical }
    struct Guide: Equatable {
        var axis: GuideAxis
        /// Image-pixel coordinate (y for horizontal guides, x for vertical ones).
        var position: CGFloat
    }

    var guides: [Guide] = [] { didSet { needsDisplay = true } }
    var showGuides = true { didSet { needsDisplay = true } }
    /// Guide being dragged from a ruler or moved with Cmd-drag; drawn but not yet in `guides`.
    var draggingGuide: Guide? { didSet { needsDisplay = true } }
    private var isMovingGuide = false

    static let guideColor = NSColor(hex: "#1FB6FF")

    /// Index of a guide within 4 view points of `viewPoint`.
    func guideIndex(near vp: CGPoint) -> Int? {
        guard showGuides else { return nil }
        for (i, g) in guides.enumerated() {
            let v = viewPoint(fromImage: g.axis == .horizontal ? CGPoint(x: 0, y: g.position) : CGPoint(x: g.position, y: 0))
            let d = g.axis == .horizontal ? abs(v.y - vp.y) : abs(v.x - vp.x)
            if d <= 4 { return i }
        }
        return nil
    }

    /// Updates the guide preview for a pointer at `windowPoint` (called by rulers and by Cmd-drag).
    func updateGuideDrag(axis: GuideAxis, windowPoint: CGPoint) {
        let p = imagePoint(fromView: convert(windowPoint, from: nil)).rounded
        draggingGuide = Guide(axis: axis, position: axis == .horizontal ? p.y : p.x)
    }

    /// Ends a guide drag: the guide is kept when dropped inside the canvas viewport, discarded otherwise
    /// (dragging a guide back onto a ruler removes it, like Photoshop).
    func finishGuideDrag(windowPoint: CGPoint) {
        defer { draggingGuide = nil; isMovingGuide = false }
        guard let g = draggingGuide, let clip = enclosingScrollView?.contentView else { return }
        let inViewport = clip.bounds.contains(clip.convert(windowPoint, from: nil))
        if inViewport {
            guides.append(g)
            if !isMovingGuide { delegate?.canvasDidAddGuide() }
        }
    }

    private func drawGuides(_ ctx: CGContext) {
        guard showGuides else { return }
        let visible = visibleRect
        ctx.saveGState()
        ctx.setLineWidth(1)
        for g in guides + (draggingGuide.map { [$0] } ?? []) {
            let dragging = draggingGuide == g
            ctx.setStrokeColor(Self.guideColor.withAlphaComponent(dragging ? 0.6 : 1).cgColor)
            if g.axis == .horizontal {
                let y = viewPoint(fromImage: CGPoint(x: 0, y: g.position)).y.rounded() + 0.5
                ctx.move(to: CGPoint(x: visible.minX, y: y)); ctx.addLine(to: CGPoint(x: visible.maxX, y: y))
            } else {
                let x = viewPoint(fromImage: CGPoint(x: g.position, y: 0)).x.rounded() + 0.5
                ctx.move(to: CGPoint(x: x, y: visible.minY)); ctx.addLine(to: CGPoint(x: x, y: visible.maxY))
            }
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private var canvasResizeHandle: Handle?
    /// Proposed canvas rect (in current image coordinates) while a canvas handle is dragged.
    private var canvasResizePreview: CGRect?
    private var trackingArea: NSTrackingArea?
    private var observers: [Any] = []

    init(document: PaintDocument) {
        self.document = document
        super.init(frame: .zero)
        wantsLayer = true
        tool = Tool.make(state.tool, canvas: self)
        previousToolKind = state.tool
        updateFrameSize()
        observers.append(NotificationCenter.default.addObserver(forName: .documentDidChange, object: document, queue: .main) { [weak self] _ in
            self?.documentChanged()
        })
        observers.append(NotificationCenter.default.addObserver(forName: .toolStateChanged, object: state, queue: .main) { [weak self] _ in
            self?.toolStateChanged()
        })
    }

    required init?(coder: NSCoder) { fatalError() }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    private static let eventLogEnabled = ProcessInfo.processInfo.environment["PAINT_EVENT_LOG"] == "1"
    private var eventCounts: [String: Int] = [:]

    /// Development aid: counts tracking events so real-mouse delivery can be checked from a log.
    private func logEvent(_ name: String) {
        guard Self.eventLogEnabled else { return }
        eventCounts[name, default: 0] += 1
        let n = eventCounts[name]!
        if n == 1 || n % 20 == 0 {
            FileHandle.standardError.write("EVENT \(name) #\(n) tool=\(tool.kind) accepts=\(window?.acceptsMouseMovedEvents ?? false) key=\(window?.isKeyWindow ?? false)\n".data(using: .utf8)!)
        }
    }

    // MARK: - Geometry

    /// Extra room on the left so the floating Size / Opacity sliders never cover the canvas.
    static let leftInset: CGFloat = 52
    /// How much of the canvas must stay visible when it is pushed off-screen (Photoshop-style overscroll).
    static let overscrollKeep: CGFloat = 48

    /// Margin around the canvas so it can be panned until only `overscrollKeep` points remain visible.
    private var margins: CGSize {
        let viewport = enclosingScrollView?.contentView.bounds.size ?? .zero
        return CGSize(width: max(Self.padding, viewport.width - Self.overscrollKeep),
                      height: max(Self.padding, viewport.height - Self.overscrollKeep))
    }

    var canvasOrigin: CGPoint { CGPoint(x: margins.width + Self.leftInset, y: margins.height) }
    var canvasViewRect: CGRect { viewRect(fromImage: document.canvasRect) }

    /// Transform from image coordinates to view coordinates.
    var viewTransform: CGAffineTransform {
        CGAffineTransform(translationX: canvasOrigin.x, y: canvasOrigin.y).scaledBy(x: zoom, y: zoom)
    }

    func imagePoint(fromView p: CGPoint) -> CGPoint { (p - canvasOrigin) / zoom }
    func viewPoint(fromImage p: CGPoint) -> CGPoint { p * zoom + canvasOrigin }

    /// Moves the system pointer onto an image point (used to keep it on a Shift-locked stroke line).
    func warpPointer(toImage p: CGPoint) {
        guard let window, let primary = NSScreen.screens.first else { return }
        let screen = window.convertPoint(toScreen: convert(viewPoint(fromImage: p), to: nil))
        CGWarpMouseCursorPosition(CGPoint(x: screen.x, y: primary.frame.maxY - screen.y))
        // Re-associating right after a warp drops the short input freeze macOS applies to warps.
        CGAssociateMouseAndMouseCursorPosition(1)
    }
    func viewRect(fromImage r: CGRect) -> CGRect {
        CGRect(x: r.minX * zoom + canvasOrigin.x, y: r.minY * zoom + canvasOrigin.y, width: r.width * zoom, height: r.height * zoom)
    }
    func imageRect(fromView r: CGRect) -> CGRect {
        CGRect(x: (r.minX - canvasOrigin.x) / zoom, y: (r.minY - canvasOrigin.y) / zoom, width: r.width / zoom, height: r.height / zoom)
    }

    private var hasCenteredOnce = false

    /// Recomputes the scrollable area. With `preserveView` the image point at the viewport centre stays put;
    /// the first call centres the canvas in the viewport.
    func updateFrameSize(preserveView: Bool = true) {
        let anchor = visibleImageCenter
        let size = document.canvasSize
        let m = margins
        let w = size.width * zoom + m.width * 2 + Self.leftInset
        let h = size.height * zoom + m.height * 2
        if frame.size != CGSize(width: w, height: h) {
            setFrameSize(CGSize(width: w, height: h))
        }
        if !hasCenteredOnce, enclosingScrollView != nil, m.width > Self.padding {
            hasCenteredOnce = true
            centerCanvas()
        } else if preserveView {
            scrollImagePoint(anchor, toVisible: visibleRect.center)
        }
        needsDisplay = true
    }

    /// Scrolls so that the canvas centre sits at the viewport centre, shifted right to clear the
    /// floating Size / Opacity sliders.
    func centerCanvas() {
        scrollImagePoint(document.canvasRect.center, toVisible: visibleRect.center + CGPoint(x: Self.leftInset / 2, y: 0))
    }

    /// Scrolls so that image point `p` appears at `visiblePoint` (view coordinates inside the visible rect).
    private func scrollImagePoint(_ p: CGPoint, toVisible visiblePoint: CGPoint) {
        let target = viewPoint(fromImage: p)
        let offset = visiblePoint - visibleRect.origin
        scroll(target - offset)
    }

    /// Image point currently at the center of the visible area.
    var visibleImageCenter: CGPoint {
        imagePoint(fromView: visibleRect.center)
    }

    func setZoom(_ newZoom: CGFloat, anchor: CGPoint? = nil) {
        let z = max(0.05, min(64, newZoom))
        guard z != zoom else { return }
        let anchorImage = anchor ?? visibleImageCenter
        let anchorViewBefore = viewPoint(fromImage: anchorImage)
        let offsetInVisible = anchorViewBefore - visibleRect.origin
        zoom = z
        updateFrameSize(preserveView: false)
        scrollImagePoint(anchorImage, toVisible: visibleRect.origin + offsetInVisible)
        delegate?.canvasZoomChanged(zoom)
        tool.settingsChanged()
        needsDisplay = true
    }

    func zoomToFit(in visibleSize: CGSize) {
        let s = document.canvasSize
        let avail = CGSize(width: max(50, visibleSize.width - Self.padding * 2 - Self.leftInset), height: max(50, visibleSize.height - Self.padding * 2))
        let z = min(avail.width / s.width, avail.height / s.height)
        setZoom(z)
        centerCanvas()
    }

    // MARK: - Document / tool state

    private func documentChanged() {
        updateFrameSize()
        if optionPickActive { pickSource = makePickSource() }
        if let sel = selection, !document.canvasRect.contains(sel.rect), floating == nil {
            let clipped = sel.rect.intersection(document.canvasRect)
            selection = clipped.isEmpty ? nil : (sel.isRectangular ? Selection.rectangle(clipped) : sel)
        }
        needsDisplay = true
    }

    private func toolStateChanged() {
        if state.tool != tool.kind {
            switchTool(to: state.tool)
        } else {
            tool.settingsChanged()
        }
        needsDisplay = true
    }

    private func switchTool(to kind: ToolKind) {
        tool.deactivate()
        if !kind.isSelection { commitFloating() }
        isToolTracking = false
        if tool.kind != .colorPicker && tool.kind != .magnifier { previousToolKind = tool.kind }
        tool = Tool.make(kind, canvas: self)
        refreshCursor()
        needsDisplay = true
    }

    /// Selects a tool without going through the ribbon.
    func selectTool(_ kind: ToolKind) {
        if state.tool != kind { state.tool = kind }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let cr = canvasViewRect

        // Drop shadow around the canvas.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 6, color: NSColor.black.withAlphaComponent(0.25).cgColor)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(cr)
        ctx.restoreGState()

        drawCheckerboard(in: cr, ctx)

        ctx.saveGState()
        ctx.clip(to: cr)
        if document.backgroundVisible {
            ctx.setFillColor(document.backgroundColor.cgColor)
            ctx.fill(cr)
        }
        for (i, layer) in document.layers.enumerated() where layer.isVisible {
            var image = layer.bitmap.makeImage()
            if i == document.activeLayerIndex, let buf = strokeBuffer, let bufImg = buf.makeImage() {
                let tmp = Bitmap(copying: layer.bitmap)
                tmp.draw(bufImg, in: tmp.bounds, blend: strokeBlend, alpha: strokeAlpha, interpolate: false)
                image = tmp.makeImage()
            }
            if let img = image { drawImage(img, in: cr, ctx, alpha: layer.opacity) }
        }
        if let f = floating {
            drawImage(f.image, in: viewRect(fromImage: f.rect), ctx)
        }
        if showGrid { drawGrid(in: cr, ctx) }
        ctx.restoreGState()

        if !optionPickActive { tool.drawOverlay(in: ctx) }

        if let sel = selection {
            var t = viewTransform
            if let p = sel.path.copy(using: &t) { OverlayDrawing.drawMarchingAnts(p, in: ctx) }
        }
        if let f = floating {
            OverlayDrawing.drawHandles(for: viewRect(fromImage: f.rect), in: ctx)
        }

        drawCanvasHandles(cr, ctx)
        drawGuides(ctx)
        drawSizePreview(ctx)
        drawLoupe(ctx)
        if let preview = canvasResizePreview {
            let r = viewRect(fromImage: preview)
            ctx.saveGState()
            ctx.setStrokeColor(NSColor(hex: "#0067C0").cgColor)
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.setLineWidth(1)
            ctx.stroke(r)
            ctx.restoreGState()
        }
    }

    /// Draws a CGImage into the flipped view context without inverting it.
    func drawImage(_ image: CGImage, in rect: CGRect, _ ctx: CGContext, alpha: CGFloat = 1) {
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.interpolationQuality = zoom >= 1 ? .none : .high
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    private func drawCheckerboard(in rect: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(rect)
        ctx.setFillColor(NSColor(white: 0.8, alpha: 1).cgColor)
        let s: CGFloat = 8
        let visible = rect.intersection(visibleRect)
        guard !visible.isEmpty else { ctx.restoreGState(); return }
        let x0 = floor((visible.minX - rect.minX) / s), y0 = floor((visible.minY - rect.minY) / s)
        var y = y0
        while rect.minY + y * s < visible.maxY {
            var x = x0
            while rect.minX + x * s < visible.maxX {
                if Int(x + y) % 2 == 0 {
                    ctx.fill(CGRect(x: rect.minX + x * s, y: rect.minY + y * s, width: s, height: s))
                }
                x += 1
            }
            y += 1
        }
        ctx.restoreGState()
    }

    private func drawGrid(in rect: CGRect, _ ctx: CGContext) {
        let step: CGFloat = zoom >= 4 ? 1 : (zoom >= 2 ? 5 : 10)
        let px = step * zoom
        guard px >= 4 else { return }
        ctx.saveGState()
        ctx.setStrokeColor(NSColor(white: 0.5, alpha: 0.5).cgColor)
        ctx.setLineWidth(1)
        let visible = rect.intersection(visibleRect)
        var x = rect.minX + floor((visible.minX - rect.minX) / px) * px
        while x <= visible.maxX {
            ctx.move(to: CGPoint(x: x + 0.5, y: visible.minY))
            ctx.addLine(to: CGPoint(x: x + 0.5, y: visible.maxY))
            x += px
        }
        var y = rect.minY + floor((visible.minY - rect.minY) / px) * px
        while y <= visible.maxY {
            ctx.move(to: CGPoint(x: visible.minX, y: y + 0.5))
            ctx.addLine(to: CGPoint(x: visible.maxX, y: y + 0.5))
            y += px
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawCanvasHandles(_ cr: CGRect, _ ctx: CGContext) {
        let outer = cr.insetBy(dx: -2, dy: -2)
        for h in Handle.allCases {
            let p = h.point(in: outer)
            let r = CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(r)
            ctx.setStrokeColor(NSColor(white: 0.35, alpha: 1).cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(r)
        }
    }

    private func canvasHandle(at p: CGPoint) -> Handle? {
        OverlayDrawing.handle(at: p, for: canvasViewRect.insetBy(dx: -2, dy: -2))
    }

    // MARK: - Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    private var mouseInside = false

    /// Tracking areas ignore overlapping siblings (the Size / Opacity and Layers cards float over the scroll
    /// view, and `cursorUpdate` can arrive for a pointer that has already left), so the view under the pointer
    /// decides whether the canvas owns the cursor.
    private func pointerIsOverCanvas(windowPoint: CGPoint) -> Bool {
        guard let window, window.isKeyWindow, let content = window.contentView else { return false }
        var hit = content.hitTest(windowPoint)
        while let v = hit {
            if v === self { return true }
            hit = v.superview
        }
        return false
    }

    /// Re-evaluates the hover state and the cursor for a pointer position in window coordinates.
    private func pointerMoved(toWindowPoint wp: CGPoint) {
        let over = pointerIsOverCanvas(windowPoint: wp)
        if over != mouseInside {
            mouseInside = over
            if !over { pointerLeft() }
        }
        guard over else { return }
        let p = convert(wp, from: nil)
        updateOptionPick(at: p)
        updateCursor(at: p)
    }

    private func pointerLeft() {
        updateOptionPick(at: nil)
        delegate?.canvasCursorMoved(nil)
        tool.mouseExited()
        NSCursor.arrow.set()
    }

    /// Applies the cursor for the tool at the given view point.
    private func updateCursor(at viewPoint: CGPoint) {
        guard mouseInside, !isDraggingCanvasHandle else { return }
        if isSpaceDown {
            (panStart != nil ? NSCursor.closedHand : NSCursor.openHand).set()
            return
        }
        if NSEvent.modifierFlags.contains(.command), let i = guideIndex(near: viewPoint) {
            (guides[i].axis == .horizontal ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).set()
            return
        }
        if optionPickActive {
            Theme.cursor(symbol: "eyedropper", anchor: .bottomLeft).set()
            return
        }
        if let h = canvasHandle(at: viewPoint) {
            h.cursor.set()
            return
        }
        tool.cursor(at: imagePoint(fromView: viewPoint)).set()
    }

    private var isDraggingCanvasHandle: Bool { canvasResizeHandle != nil }

    /// Re-applies the cursor after the tool or its state changed while the mouse is over the canvas.
    func refreshCursor() {
        guard let window else { return }
        pointerMoved(toWindowPoint: window.mouseLocationOutsideOfEventStream)
    }

    override func cursorUpdate(with event: NSEvent) {
        logEvent("cursorUpdate")
        pointerMoved(toWindowPoint: event.locationInWindow)
    }

    override func mouseEntered(with event: NSEvent) {
        logEvent("mouseEntered")
        pointerMoved(toWindowPoint: event.locationInWindow)
    }

    override func mouseMoved(with event: NSEvent) {
        logEvent("mouseMoved")
        hideSizePreview()
        pointerMoved(toWindowPoint: event.locationInWindow)
        guard mouseInside else { return }
        let p = convert(event.locationInWindow, from: nil)
        let ip = imagePoint(fromView: p)
        delegate?.canvasCursorMoved(document.canvasRect.contains(ip) ? ip.floored : nil)
        tool.mouseMoved(to: ip)
    }

    override func mouseExited(with event: NSEvent) {
        logEvent("mouseExited")
        guard mouseInside else { return }
        mouseInside = false
        pointerLeft()
    }

    override func mouseDown(with event: NSEvent) {
        logEvent("mouseDown")
        hideSizePreview()
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.command), !isSpaceDown, let i = guideIndex(near: p) {
            draggingGuide = guides.remove(at: i)
            isMovingGuide = true
            return
        }
        if isSpaceDown {
            if event.modifierFlags.contains(.command) {
                let ip = imagePoint(fromView: p)
                let levels = Theme.zoomLevels
                let target = event.modifierFlags.contains(.option)
                    ? (levels.last(where: { $0 < zoom - 0.001 }) ?? levels.first!)
                    : (levels.first(where: { $0 > zoom + 0.001 }) ?? levels.last!)
                setZoom(target, anchor: ip)
            } else {
                panStart = (event.locationInWindow, visibleRect.origin)
                NSCursor.closedHand.set()
            }
            return
        }
        if event.modifierFlags.contains(.option), toolAllowsOptionPick {
            optionPickButton = .primary
            sampleColor(at: imagePoint(fromView: p), button: .primary)
            updateOptionPick(at: p)
            return
        }
        if let h = canvasHandle(at: p) {
            canvasResizeHandle = h
            canvasResizePreview = document.canvasRect
            return
        }
        isToolTracking = true
        tool.mouseDown(at: imagePoint(fromView: p), button: .primary, event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let ip = imagePoint(fromView: p)
        delegate?.canvasCursorMoved(document.canvasRect.contains(ip) ? ip.floored : nil)
        if optionPickButton == .primary {
            sampleColor(at: ip, button: .primary)
            updateOptionPick(at: p)
            return
        }
        if isMovingGuide, let g = draggingGuide {
            updateGuideDrag(axis: g.axis, windowPoint: event.locationInWindow)
            return
        }
        if let start = panStart {
            let d = event.locationInWindow - start.mouse
            scroll(CGPoint(x: start.origin.x - d.x, y: start.origin.y + d.y))
            return
        }
        if let h = canvasResizeHandle {
            let r = h.resize(document.canvasRect, to: ip.rounded)
            canvasResizePreview = r
            delegate?.canvasSelectionChanged(r.size)
            needsDisplay = true
            return
        }
        autoscroll(with: event)
        tool.mouseDragged(to: ip, button: .primary, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if optionPickButton == .primary {
            optionPickButton = nil
            pointerMoved(toWindowPoint: event.locationInWindow)
            return
        }
        if isMovingGuide {
            finishGuideDrag(windowPoint: event.locationInWindow)
            refreshCursor()
            return
        }
        if panStart != nil {
            panStart = nil
            refreshCursor()
            return
        }
        if canvasResizeHandle != nil {
            canvasResizeHandle = nil
            if let r = canvasResizePreview, r != document.canvasRect {
                commitFloating()
                document.resizeCanvas(to: r.size, offset: CGPoint(x: -r.minX, y: -r.minY))
            }
            canvasResizePreview = nil
            delegate?.canvasSelectionChanged(selection?.rect.size)
            needsDisplay = true
            return
        }
        isToolTracking = false
        tool.mouseUp(at: imagePoint(fromView: p), button: .primary, event: event)
        pointerMoved(toWindowPoint: event.locationInWindow)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.option), !isSpaceDown, toolAllowsOptionPick {
            optionPickButton = .secondary
            sampleColor(at: imagePoint(fromView: p), button: .secondary)
            updateOptionPick(at: p)
            return
        }
        isToolTracking = true
        tool.mouseDown(at: imagePoint(fromView: p), button: .secondary, event: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if optionPickButton == .secondary {
            sampleColor(at: imagePoint(fromView: p), button: .secondary)
            updateOptionPick(at: p)
            return
        }
        autoscroll(with: event)
        tool.mouseDragged(to: imagePoint(fromView: p), button: .secondary, event: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if optionPickButton == .secondary {
            optionPickButton = nil
            pointerMoved(toWindowPoint: event.locationInWindow)
            return
        }
        isToolTracking = false
        tool.mouseUp(at: imagePoint(fromView: p), button: .secondary, event: event)
    }

    /// Option + scroll zooms around the pointer (Photoshop); plain scrolling pans.
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            let p = imagePoint(fromView: convert(event.locationInWindow, from: nil))
            let factor = pow(1.0025, -event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 10))
            setZoom(zoom * factor, anchor: p)
            return
        }
        super.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        let p = imagePoint(fromView: convert(event.locationInWindow, from: nil))
        setZoom(zoom * (1 + event.magnification), anchor: p)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if tool.keyDown(event) { return }
        switch event.keyCode {
        case 51, 117: // delete, forward delete
            delete(nil)
        case 53: // escape
            if tool.hasPendingObject { tool.cancel() } else { cancelFloating() }
        case 36, 76: // return
            if tool.hasPendingObject { tool.commit() } else { commitFloating() }
        case 123, 124, 125, 126: // arrows nudge the selection by 1 px (10 px with Shift)
            guard selection != nil || floating != nil else { super.keyDown(with: event); return }
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            switch event.keyCode {
            case 123: nudgeSelection(dx: -step, dy: 0)
            case 124: nudgeSelection(dx: step, dy: 0)
            case 126: nudgeSelection(dx: 0, dy: -step)
            default: nudgeSelection(dx: 0, dy: step)
            }
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Selection operations

    /// Lifts the selected pixels of the active layer into a floating image.
    func liftSelection() {
        guard floating == nil, let sel = selection else { return }
        let rect = sel.rect.integral.intersection(document.canvasRect)
        guard !rect.isEmpty else { return }
        let layer = document.activeLayer
        let lifted = Bitmap(width: Int(rect.width), height: Int(rect.height))
        let ctx = lifted.context
        // Draw the layer through the selection clip.
        ctx.saveGState()
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        ctx.addPath(sel.path)
        if sel.evenOdd { ctx.clip(using: .evenOdd) } else { ctx.clip() }
        if let img = layer.bitmap.makeImage() {
            lifted.draw(img, in: CGRect(origin: CGPoint(x: 0, y: 0), size: layer.bitmap.size), interpolate: false)
        }
        ctx.restoreGState()
        guard let image = lifted.makeImage() else { return }
        clearRegion(sel, name: L("Move selection"))
        floating = FloatingSelection(image: image, rect: rect)
        selection = Selection.rectangle(rect)
    }

    /// Fills a region with the layer's clear colour (or transparency) on the active layer.
    func clearRegion(_ sel: Selection, name: String) {
        document.performLayerChange(name) { layer in
            let ctx = layer.bitmap.context
            ctx.saveGState()
            ctx.addPath(sel.path)
            if sel.evenOdd { ctx.clip(using: .evenOdd) } else { ctx.clip() }
            ctx.setBlendMode(.copy)
            ctx.clear(layer.bitmap.bounds)
            ctx.restoreGState()
        }
    }

    /// Stamps the floating image back onto the active layer.
    func commitFloating() {
        guard let f = floating else { return }
        var image = f.image
        if state.transparentSelection {
            let bmp = Bitmap(image: f.image)
            bmp.makeTransparent(matching: state.color2)
            if let masked = bmp.makeImage() { image = masked }
        }
        document.performLayerChange(L("Paste")) { layer in
            layer.bitmap.draw(image, in: f.rect, interpolate: f.rect.size != CGSize(width: image.width, height: image.height))
        }
        floating = nil
        selection = Selection.rectangle(f.rect.integral)
    }

    func cancelFloating() {
        if floating != nil { floating = nil }
        selection = nil
    }

    func selectionImage() -> CGImage? {
        if let f = floating { return f.image }
        let layer = document.activeLayer
        guard let sel = selection else { return layer.bitmap.makeImage() }
        let rect = sel.rect.integral.intersection(document.canvasRect)
        guard !rect.isEmpty else { return nil }
        let out = Bitmap(width: Int(rect.width), height: Int(rect.height))
        out.context.saveGState()
        out.context.translateBy(x: -rect.minX, y: -rect.minY)
        out.context.addPath(sel.path)
        if sel.evenOdd { out.context.clip(using: .evenOdd) } else { out.context.clip() }
        if let img = layer.bitmap.makeImage() {
            out.draw(img, in: CGRect(origin: .zero, size: layer.bitmap.size), interpolate: false)
        }
        out.context.restoreGState()
        return out.makeImage()
    }

    /// Places an image as a floating selection near the top-left of the visible area.
    func pasteImage(_ image: CGImage) {
        tool.commit()
        commitFloating()
        let size = CGSize(width: image.width, height: image.height)
        if size.width > document.canvasSize.width || size.height > document.canvasSize.height {
            document.resizeCanvas(to: CGSize(width: max(size.width, document.canvasSize.width),
                                             height: max(size.height, document.canvasSize.height)))
        }
        selectTool(.selectRectangle)
        var origin = imagePoint(fromView: visibleRect.origin).rounded
        origin.x = max(0, origin.x); origin.y = max(0, origin.y)
        floating = FloatingSelection(image: image, rect: CGRect(origin: origin, size: size))
        selection = Selection.rectangle(CGRect(origin: origin, size: size))
        needsDisplay = true
    }

    // MARK: - Standard edit actions

    override func selectAll(_ sender: Any?) {
        tool.commit()
        commitFloating()
        selectTool(.selectRectangle)
        selection = Selection.rectangle(document.canvasRect)
    }

    @objc func copy(_ sender: Any?) {
        guard let img = selectionImage() else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        let rep = NSBitmapImageRep(cgImage: img)
        if let png = rep.representation(using: .png, properties: [:]) { pb.setData(png, forType: .png) }
        pb.setData(rep.tiffRepresentation, forType: .tiff)
    }

    @objc func cut(_ sender: Any?) {
        guard selection != nil || floating != nil else { return }
        copy(sender)
        delete(sender)
    }

    @objc func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        guard let img = NSImage(pasteboard: pb), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        pasteImage(cg)
    }

    @objc func delete(_ sender: Any?) {
        if floating != nil {
            floating = nil
            selection = nil
            return
        }
        guard let sel = selection else { return }
        clearRegion(sel, name: L("Delete"))
        selection = nil
    }

    @objc func deselect(_ sender: Any?) {
        tool.commit()
        commitFloating()
        selection = nil
    }

    func invertSelection() {
        commitFloating()
        guard let sel = selection else { return }
        selection = sel.inverted(in: document.canvasRect)
    }

    func cropToSelection() {
        tool.commit()
        commitFloating()
        guard let sel = selection else { return }
        document.crop(to: sel.rect)
        selection = nil
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)), #selector(delete(_:)), #selector(deselect(_:)):
            return selection != nil || floating != nil
        case #selector(paste(_:)):
            return NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil)
        default:
            return true
        }
    }
}
