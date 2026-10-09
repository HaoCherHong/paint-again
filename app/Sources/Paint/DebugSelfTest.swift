import AppKit

/// Development aid triggered by `PAINT_SELFTEST=1`: drives the front document with synthetic
/// mouse events so rendering of every tool can be checked from a snapshot without a human.
enum DebugSelfTest {
    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        if env["PAINT_SELFTEST_COLORS"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard let window = NSApp.mainWindow else { return }
                ColorEditorPanel.present(on: window, initial: NSColor(hex: "#3F48CC"), state: ToolState()) { _ in }
            }
        }
        guard env["PAINT_SELFTEST"] == "1" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { run() }
    }

    private static func run() {
        guard let doc = NSDocumentController.shared.documents.first as? PaintDocument,
              let wc = doc.windowControllers.first as? MainWindowController else { return }
        let canvas = wc.canvas!
        let state = doc.toolState
        let window = canvas.window!

        func event(_ type: NSEvent.EventType, _ p: CGPoint, clicks: Int = 1, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            let vp = canvas.viewPoint(fromImage: p)
            let wp = canvas.convert(vp, to: nil)
            return NSEvent.mouseEvent(with: type, location: wp, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        func drag(_ points: [CGPoint], right: Bool = false, flags: NSEvent.ModifierFlags = []) {
            guard let first = points.first, let last = points.last else { return }
            if right {
                canvas.rightMouseDown(with: event(.rightMouseDown, first, flags: flags))
                for p in points.dropFirst() { canvas.rightMouseDragged(with: event(.rightMouseDragged, p, flags: flags)) }
                canvas.rightMouseUp(with: event(.rightMouseUp, last, flags: flags))
            } else {
                canvas.mouseDown(with: event(.leftMouseDown, first, flags: flags))
                for p in points.dropFirst() { canvas.mouseDragged(with: event(.leftMouseDragged, p, flags: flags)) }
                canvas.mouseUp(with: event(.leftMouseUp, last, flags: flags))
            }
        }
        func click(_ p: CGPoint, clicks: Int = 1) { drag([p, p]) }
        func wave(y: CGFloat, x0: CGFloat, x1: CGFloat, amp: CGFloat = 12) -> [CGPoint] {
            stride(from: x0, through: x1, by: 6).map { x in CGPoint(x: x, y: y + sin((x - x0) / 30) * amp) }
        }

        // Pencil
        state.tool = .pencil
        state.lineWidth = 1
        state.color1 = .black
        drag([CGPoint(x: 40, y: 40), CGPoint(x: 200, y: 60), CGPoint(x: 320, y: 40)])
        state.lineWidth = 4
        drag([CGPoint(x: 40, y: 70), CGPoint(x: 320, y: 90)])

        // Brushes
        let palette = ToolState.paletteColors
        for (i, kind) in BrushKind.allCases.enumerated() {
            state.tool = .brush(kind)
            state.lineWidth = 14
            state.color1 = palette[[2, 3, 4, 5, 6, 7, 8, 9, 12][i]]
            drag(wave(y: 130 + CGFloat(i) * 42, x0: 40, x1: 480))
        }

        // Shapes: outline colour 1 = dark red, fill colour 2 = gold
        state.color1 = NSColor(hex: "#880015")
        state.color2 = NSColor(hex: "#FFC90E")
        state.lineWidth = 3
        state.shapeFill = .solid
        let shapeKinds = ShapeKind.allCases
        for (i, kind) in shapeKinds.enumerated() {
            state.tool = .shape(kind)
            let col = CGFloat(i % 6), row = CGFloat(i / 6)
            let origin = CGPoint(x: 540 + col * 100, y: 40 + row * 90)
            if kind == .polygon {
                drag([origin, CGPoint(x: origin.x + 70, y: origin.y + 10)])
                click(CGPoint(x: origin.x + 60, y: origin.y + 70))
                click(CGPoint(x: origin.x + 10, y: origin.y + 60))
                canvas.tool.commit()
            } else if kind == .curve {
                drag([origin, CGPoint(x: origin.x + 80, y: origin.y + 70)])
                drag([CGPoint(x: origin.x + 40, y: origin.y + 35), CGPoint(x: origin.x + 70, y: origin.y)])
                canvas.tool.commit()
            } else {
                drag([origin, CGPoint(x: origin.x + 80, y: origin.y + 70)])
                canvas.tool.commit()
            }
        }
        state.shapeFill = .none

        // Fill inside the rectangle shape (index 3 -> col 3, row 0) with green.
        state.tool = .fill
        state.color1 = NSColor(hex: "#22B14C")
        click(CGPoint(x: 540 + 3 * 100 + 40, y: 40 + 35))

        // Text
        state.tool = .text
        state.fontSize = 28
        state.bold = true
        state.color1 = NSColor(hex: "#3F48CC")
        drag([CGPoint(x: 540, y: 420), CGPoint(x: 1000, y: 470)])
        if let tv = window.firstResponder as? NSTextView { tv.insertText("Hello from Paint Again", replacementRange: NSRange(location: 0, length: 0)) }
        canvas.tool.commit()
        state.bold = false

        // Selection: move the six-point star (grid cell 17) down into the free area below the gallery.
        state.tool = .selectRectangle
        drag([CGPoint(x: 1035, y: 215), CGPoint(x: 1125, y: 295)])
        drag([CGPoint(x: 1080, y: 255), CGPoint(x: 1060, y: 400), CGPoint(x: 1030, y: 535)])
        canvas.commitFloating()
        canvas.selection = nil

        // Underline the text with a brush, then erase a gap in the middle of the line.
        state.tool = .brush(.brush)
        state.lineWidth = 5
        state.color1 = NSColor(hex: "#3F48CC")
        drag([CGPoint(x: 545, y: 486), CGPoint(x: 995, y: 486)])
        state.tool = .eraser
        state.lineWidth = 20
        drag([CGPoint(x: 735, y: 486), CGPoint(x: 805, y: 486)])

        // Second layer with a marker stroke, and open the layers panel.
        doc.addLayer()
        state.tool = .brush(.marker)
        state.color1 = NSColor(hex: "#ED1C24")
        state.lineWidth = 30
        drag([CGPoint(x: 60, y: 600), CGPoint(x: 1100, y: 600)])
        wc.toggleLayersPanel(nil)
        canvas.tool.mouseExited()   // drop the hover outline so the snapshot shows only the artwork

        // Checks that rely on undo run in later run-loop turns so each edit gets its own undo group.
        afterRunLoopTurn {
            let namesBefore = doc.layers.map { $0.name }
            doc.moveLayer(from: 1, to: 0)
            let namesMoved = doc.layers.map { $0.name }
            afterRunLoopTurn {
                doc.undoManager?.undo()
                log("reorder: \(namesBefore) -> \(namesMoved) -> restored \(doc.layers.map { $0.name } == namesBefore)")
                let before = doc.activeLayer.bitmap.snapshot()
                doc.undoManager?.undo()
                doc.undoManager?.redo()
                let after = doc.activeLayer.bitmap.snapshot()
                log("undo/redo stable: \(before == after)  layers: \(doc.layers.count)  canUndo: \(doc.undoManager?.canUndo ?? false)")
                let fillColor = doc.layers[0].bitmap.color(at: CGPoint(x: 540 + 3 * 100 + 40, y: 40 + 35))
                log("fill colour: \(fillColor?.hexString ?? "nil") (expected #22B14C)")

                // Save / load round trip through the document's own reader and writer.
                do {
                    let png = try doc.data(ofType: "public.png")
                    let jpg = try doc.data(ofType: "public.jpeg")
                    let bmp = try doc.data(ofType: "com.microsoft.bmp")
                    let reloaded = try PaintDocument(type: "public.png")
                    try reloaded.read(from: png, ofType: "public.png")
                    log("saved png=\(png.count)B jpeg=\(jpg.count)B bmp=\(bmp.count)B; reloaded size=\(reloaded.canvasSize)")
                } catch {
                    log("save/load FAILED: \(error)")
                }

                // Geometry operations, each undone in its own turn.
                let sizeBefore = doc.canvasSize
                doc.rotate(.right90)
                let rotated = doc.canvasSize
                afterRunLoopTurn {
                    doc.undoManager?.undo()
                    doc.resizeImage(to: CGSize(width: sizeBefore.width / 2, height: sizeBefore.height / 2))
                    let halved = doc.canvasSize
                    afterRunLoopTurn {
                        doc.undoManager?.undo()
                        doc.resizeCanvas(to: CGSize(width: 1400, height: 700))
                        let grown = doc.canvasSize
                        afterRunLoopTurn {
                            doc.undoManager?.undo()
                            log("rotate=\(rotated) half=\(halved) canvas=\(grown) restored=\(doc.canvasSize == sizeBefore)")
                        }
                    }
                }
            }
        }
        canvas.setZoom(2)
        canvas.setZoom(1)
        if ProcessInfo.processInfo.environment["PAINT_APPEARANCE"] == "light" { NSApp.appearance = NSAppearance(named: .aqua) }
    }

    /// Runs `block` on a later run-loop turn, once NSUndoManager has closed the current undo group,
    /// so that the next edit is undoable on its own.
    private static func afterRunLoopTurn(_ block: @escaping () -> Void) {
        let timer = Timer(timeInterval: 0.1, repeats: true) { t in
            guard let doc = NSDocumentController.shared.documents.first as? PaintDocument else { t.invalidate(); return }
            let level = doc.undoManager?.groupingLevel ?? 0
            if level == 0 {
                t.invalidate()
                block()
            } else if let ev = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                                  windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                // AppKit closes the implicit undo group at the end of an event; with no user input, post one.
                NSApp.postEvent(ev, atStart: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(("SELFTEST " + message + "\n").data(using: .utf8)!)
    }
}
