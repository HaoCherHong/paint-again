import AppKit

private func makeField(_ value: String, width: CGFloat = 80) -> NSTextField {
    let f = NSTextField(string: value)
    f.alignment = .right
    f.widthAnchor.constraint(equalToConstant: width).isActive = true
    return f
}

private func makeLabel(_ text: String) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.alignment = .right
    return l
}

private func runSheet(_ alert: NSAlert, on window: NSWindow, completion: @escaping (Bool) -> Void) {
    alert.beginSheetModal(for: window) { resp in completion(resp == .alertFirstButtonReturn) }
}

enum ImagePropertiesDialog {
    static func present(on window: NSWindow, document: PaintDocument, completion: @escaping (CGSize?) -> Void) {
        let alert = NSAlert()
        alert.messageText = L("Image Properties")
        alert.informativeText = L("Set the size of the canvas in pixels. Pixels are kept anchored to the top-left corner.")
        alert.addButton(withTitle: L("OK"))
        alert.addButton(withTitle: L("Cancel"))
        let width = makeField("\(Int(document.canvasSize.width))")
        let height = makeField("\(Int(document.canvasSize.height))")
        let grid = NSGridView(views: [
            [makeLabel(L("Width:")), width, NSTextField(labelWithString: L("px"))],
            [makeLabel(L("Height:")), height, NSTextField(labelWithString: L("px"))],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.frame = NSRect(x: 0, y: 0, width: 260, height: 60)
        alert.accessoryView = grid
        alert.window.initialFirstResponder = width
        runSheet(alert, on: window) { ok in
            guard ok, let w = Double(width.stringValue), let h = Double(height.stringValue), w >= 1, h >= 1, w <= 20000, h <= 20000 else {
                completion(nil); return
            }
            completion(CGSize(width: w, height: h))
        }
    }
}

enum ResizeSkewDialog {
    struct Result { let size: CGSize; let skewX: CGFloat; let skewY: CGFloat }

    fileprivate final class Panel: NSView, NSTextFieldDelegate {
        let percentRadio = NSButton(radioButtonWithTitle: L("Percentage"), target: nil, action: nil)
        let pixelRadio = NSButton(radioButtonWithTitle: L("Pixels"), target: nil, action: nil)
        let horizontal = makeField("100")
        let vertical = makeField("100")
        let aspect = NSButton(checkboxWithTitle: L("Maintain aspect ratio"), target: nil, action: nil)
        let skewH = makeField("0")
        let skewV = makeField("0")
        let original: CGSize
        private var updating = false

        init(size: CGSize) {
            original = size
            super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 210))
            percentRadio.state = .on
            aspect.state = .on
            percentRadio.target = self; percentRadio.action = #selector(modeChanged)
            pixelRadio.target = self; pixelRadio.action = #selector(modeChanged)
            horizontal.delegate = self
            vertical.delegate = self
            let resizeTitle = NSTextField(labelWithString: L("Resize"))
            resizeTitle.font = NSFont.boldSystemFont(ofSize: 12)
            let skewTitle = NSTextField(labelWithString: L("Skew (Degrees)"))
            skewTitle.font = NSFont.boldSystemFont(ofSize: 12)
            let radios = NSStackView(views: [percentRadio, pixelRadio])
            radios.orientation = .horizontal
            radios.spacing = 12
            let grid = NSGridView(views: [
                [resizeTitle, NSGridCell.emptyContentView],
                [NSTextField(labelWithString: L("By:")), radios],
                [makeLabel(L("Horizontal:")), horizontal],
                [makeLabel(L("Vertical:")), vertical],
                [NSGridCell.emptyContentView, aspect],
                [skewTitle, NSGridCell.emptyContentView],
                [makeLabel(L("Horizontal:")), skewH],
                [makeLabel(L("Vertical:")), skewV],
            ])
            grid.rowSpacing = 6
            grid.columnSpacing = 10
            grid.translatesAutoresizingMaskIntoConstraints = false
            addSubview(grid)
            NSLayoutConstraint.activate([
                grid.topAnchor.constraint(equalTo: topAnchor),
                grid.leadingAnchor.constraint(equalTo: leadingAnchor),
                grid.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
                grid.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            ])
        }

        required init?(coder: NSCoder) { fatalError() }

        var isPercent: Bool { percentRadio.state == .on }

        @objc private func modeChanged(_ sender: NSButton) {
            let percent = sender === percentRadio
            percentRadio.state = percent ? .on : .off
            pixelRadio.state = percent ? .off : .on
            let size = resultSize()
            updating = true
            if percent {
                horizontal.stringValue = "\(Int((size.width / original.width * 100).rounded()))"
                vertical.stringValue = "\(Int((size.height / original.height * 100).rounded()))"
            } else {
                horizontal.stringValue = "\(Int(size.width.rounded()))"
                vertical.stringValue = "\(Int(size.height.rounded()))"
            }
            updating = false
        }

        func resultSize() -> CGSize {
            let h = CGFloat(Double(horizontal.stringValue) ?? 100), v = CGFloat(Double(vertical.stringValue) ?? 100)
            if isPercent { return CGSize(width: original.width * h / 100, height: original.height * v / 100) }
            return CGSize(width: h, height: v)
        }

        func controlTextDidChange(_ obj: Notification) {
            guard !updating, aspect.state == .on, let field = obj.object as? NSTextField else { return }
            updating = true
            defer { updating = false }
            let ratio = original.height / original.width
            if field === horizontal, let h = Double(horizontal.stringValue) {
                vertical.stringValue = isPercent ? "\(Int(h.rounded()))" : "\(Int((CGFloat(h) * ratio).rounded()))"
            } else if field === vertical, let v = Double(vertical.stringValue) {
                horizontal.stringValue = isPercent ? "\(Int(v.rounded()))" : "\(Int((CGFloat(v) / ratio).rounded()))"
            }
        }
    }

    static func present(on window: NSWindow, currentSize: CGSize, completion: @escaping (Result?) -> Void) {
        let alert = NSAlert()
        alert.messageText = L("Resize and Skew")
        alert.addButton(withTitle: L("OK"))
        alert.addButton(withTitle: L("Cancel"))
        let panel = Panel(size: currentSize)
        alert.accessoryView = panel
        alert.window.initialFirstResponder = panel.horizontal
        runSheet(alert, on: window) { ok in
            guard ok else { completion(nil); return }
            let size = panel.resultSize()
            guard size.width >= 1, size.height >= 1, size.width <= 20000, size.height <= 20000 else { completion(nil); return }
            let sx = max(-89, min(89, CGFloat(Double(panel.skewH.stringValue) ?? 0)))
            let sy = max(-89, min(89, CGFloat(Double(panel.skewV.stringValue) ?? 0)))
            completion(Result(size: size, skewX: sx, skewY: sy))
        }
    }
}


enum LayerPropertiesDialog {
    struct Result { let name: String; let opacity: CGFloat; let visible: Bool }

    static func present(on window: NSWindow, layer: Layer, completion: @escaping (Result?) -> Void) {
        let alert = NSAlert()
        alert.messageText = L("Layer Properties")
        alert.addButton(withTitle: L("OK"))
        alert.addButton(withTitle: L("Cancel"))
        let name = NSTextField(string: layer.name)
        name.widthAnchor.constraint(equalToConstant: 200).isActive = true
        let opacity = NSSlider(value: Double(layer.opacity * 100), minValue: 0, maxValue: 100, target: nil, action: nil)
        opacity.widthAnchor.constraint(equalToConstant: 200).isActive = true
        let visible = NSButton(checkboxWithTitle: L("Visible"), target: nil, action: nil)
        visible.state = layer.isVisible ? .on : .off
        let grid = NSGridView(views: [
            [makeLabel(L("Name:")), name],
            [makeLabel(L("Opacity:")), opacity],
            [NSGridCell.emptyContentView, visible],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.frame = NSRect(x: 0, y: 0, width: 280, height: 90)
        alert.accessoryView = grid
        alert.window.initialFirstResponder = name
        runSheet(alert, on: window) { ok in
            guard ok else { completion(nil); return }
            let trimmed = name.stringValue.trimmingCharacters(in: .whitespaces)
            completion(Result(name: trimmed.isEmpty ? layer.name : trimmed, opacity: CGFloat(opacity.doubleValue / 100), visible: visible.state == .on))
        }
    }
}
