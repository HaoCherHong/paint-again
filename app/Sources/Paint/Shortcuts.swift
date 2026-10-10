import AppKit

/// One way to trigger a command: a key with modifiers, or a modifier + mouse gesture shown by its label.
struct Shortcut {
    /// Key equivalent / unshifted character ("s", "[", "+"); empty for gestures and special keys.
    let key: String
    let modifiers: NSEvent.ModifierFlags
    /// Text shown instead of `key` (gestures such as "Scroll", or keys like ⌫ that are handled by key code).
    let label: String?

    static func key(_ key: String, _ modifiers: NSEvent.ModifierFlags = []) -> Shortcut {
        Shortcut(key: key, modifiers: modifiers, label: nil)
    }

    static func cmd(_ key: String, _ extra: NSEvent.ModifierFlags = []) -> Shortcut {
        Shortcut(key: key, modifiers: extra.union(.command), label: nil)
    }

    /// A modifier + mouse gesture, or a key that is only listed (its handling matches on key codes).
    static func gesture(_ label: String, _ modifiers: NSEvent.ModifierFlags = []) -> Shortcut {
        Shortcut(key: "", modifiers: modifiers, label: label)
    }

    static let relevantModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        if let label { return s.isEmpty ? label : s + " " + label }
        switch key {
        case "-": return s + "−"
        default: return s + key.uppercased()
        }
    }

    /// Whether a key-down event is this key with exactly these modifiers.
    func matches(_ event: NSEvent) -> Bool {
        guard !key.isEmpty, event.modifierFlags.intersection(Self.relevantModifiers) == modifiers else { return false }
        let base = event.characters(byApplyingModifiers: [])?.lowercased() ?? event.charactersIgnoringModifiers?.lowercased()
        return base == key
    }

    /// Whether these gesture modifiers are held (other modifiers may be held too).
    func isHeld(_ flags: NSEvent.ModifierFlags) -> Bool {
        !modifiers.isEmpty && flags.contains(modifiers)
    }
}

/// A command with its shortcuts, the first being the one menus show.
struct ShortcutItem {
    let title: String
    let shortcuts: [Shortcut]
    /// Compact text for long key runs (the opacity digits); otherwise every shortcut is listed.
    private let summary: String?

    init(_ title: String, _ shortcuts: Shortcut..., summary: String? = nil) {
        self.title = title
        self.shortcuts = shortcuts
        self.summary = summary
    }

    var display: String { summary ?? shortcuts.map(\.display).joined(separator: " / ") }

    /// Tooltip text: `name` (the title by default) followed by every shortcut.
    func tip(_ name: String? = nil) -> String { "\(name ?? title) (\(display))" }

    func matches(_ event: NSEvent) -> Bool { shortcuts.contains { $0.matches(event) } }

    func isHeld(_ flags: NSEvent.ModifierFlags) -> Bool { shortcuts.contains { $0.isHeld(flags) } }
}

struct ShortcutSection {
    let title: String
    let items: [ShortcutItem]
}

/// Every keyboard shortcut in the app. Menus, key handling, tooltips and the shortcut cheat sheet all read
/// from here; add or change a binding only in this file.
enum Shortcuts {
    // MARK: App
    static let settings = ShortcutItem(L("Settings…"), .cmd(","))
    static let hide = ShortcutItem(L("Hide Paint Again"), .cmd("h"))
    static let hideOthers = ShortcutItem(L("Hide Others"), .cmd("h", .option))
    static let quit = ShortcutItem(L("Quit Paint Again"), .cmd("q"))
    static let help = ShortcutItem(L("Paint Again Help"), .cmd("?"))

    // MARK: File
    static let new = ShortcutItem(L("New"), .cmd("n"))
    static let open = ShortcutItem(L("Open…"), .cmd("o"))
    static let close = ShortcutItem(L("Close"), .cmd("w"))
    static let save = ShortcutItem(L("Save"), .cmd("s"))
    static let saveAs = ShortcutItem(L("Save As…"), .cmd("s", .shift))
    static let imageProperties = ShortcutItem(L("Image Properties…"), .cmd("e", .shift))
    static let pageSetup = ShortcutItem(L("Page Setup…"), .cmd("p", .shift))
    static let print = ShortcutItem(L("Print…"), .cmd("p"))

    // MARK: Edit
    static let undo = ShortcutItem(L("Undo"), .cmd("z"))
    static let redo = ShortcutItem(L("Redo"), .cmd("z", .shift), .cmd("y"))
    static let cut = ShortcutItem(L("Cut"), .cmd("x"))
    static let copy = ShortcutItem(L("Copy"), .cmd("c"))
    static let paste = ShortcutItem(L("Paste"), .cmd("v"))
    static let pasteFromFile = ShortcutItem(L("Paste From File…"), .cmd("v", .shift))
    static let delete = ShortcutItem(L("Delete"), .gesture("⌫"))
    static let selectAll = ShortcutItem(L("Select All"), .cmd("a"))
    static let deselect = ShortcutItem(L("Deselect"), .cmd("d"))
    static let invertSelection = ShortcutItem(L("Invert Selection"), .cmd("i", .shift))
    static let crop = ShortcutItem(L("Crop"), .cmd("x", .shift))

    // MARK: View
    static let zoomIn = ShortcutItem(L("Zoom In"), .cmd("+"))
    static let zoomOut = ShortcutItem(L("Zoom Out"), .cmd("-"))
    static let actualSize = ShortcutItem(L("Actual Size"), .cmd("1"))
    static let fitToWindow = ShortcutItem(L("Fit to Window"), .cmd("0"))
    static let gridlines = ShortcutItem(L("Gridlines"), .cmd("g"))
    static let rulers = ShortcutItem(L("Rulers"), .cmd("r"))
    static let guides = ShortcutItem(L("Guides"), .cmd(";"))
    static let layersPanel = ShortcutItem(L("Layers Panel"), .cmd("l"))
    /// A single key like the tool keys (handled by the window, so typing in a text box is unaffected).
    static let colorPanel = ShortcutItem(L("Color Panel"), .key("p"))
    static let showToolbar = ShortcutItem(L("Show Toolbar"), .cmd("t", .option))
    static let fullScreen = ShortcutItem(L("Enter Full Screen"), .cmd("f", .control))

    // MARK: Image
    static let resizeAndSkew = ShortcutItem(L("Resize and Skew…"), .cmd("r", .shift))

    // MARK: Layers
    static let addLayer = ShortcutItem(L("Add Layer"), .cmd("n", .shift))
    static let duplicateLayer = ShortcutItem(L("Duplicate Layer"), .cmd("j"))
    static let mergeDown = ShortcutItem(L("Merge Down"), .cmd("e"))
    static let moveLayerUp = ShortcutItem(L("Move Layer Up"), .cmd("]", .option))
    static let moveLayerDown = ShortcutItem(L("Move Layer Down"), .cmd("[", .option))

    // MARK: Window
    static let minimize = ShortcutItem(L("Minimize"), .cmd("m"))

    // MARK: Tools (single keys, no modifiers except Shift)
    static let brush = ShortcutItem(L("Brushes"), .key("b"))
    static let toggleBrushPencil = ShortcutItem(L("Brush / Pencil"), .key("b", .shift))
    static let pencil = ShortcutItem(L("Pencil"), .key("n"))
    static let eraser = ShortcutItem(L("Eraser"), .key("e"))
    static let fill = ShortcutItem(L("Fill"), .key("g"))
    static let colorPicker = ShortcutItem(L("Color picker"), .key("i"))
    static let text = ShortcutItem(L("Text"), .key("t"))
    static let rectangleSelect = ShortcutItem(L("Rectangle selection"), .key("m"), .key("s"))
    static let freeformSelect = ShortcutItem(L("Free-form selection"), .key("l"))
    static let magnifier = ShortcutItem(L("Magnifier"), .key("z"))
    static let shapes = ShortcutItem(L("Shapes"), .key("u"))
    static let swapColors = ShortcutItem(L("Swap colors"), .key("x"))
    static let defaultColors = ShortcutItem(L("Default colors"), .key("d"))

    // MARK: Size and opacity
    static let smallerBrush = ShortcutItem(L("Smaller brush"), .key("["))
    static let largerBrush = ShortcutItem(L("Larger brush"), .key("]"))
    static let lessOpacity = ShortcutItem(L("Less opacity"), .key("[", .shift))
    static let moreOpacity = ShortcutItem(L("More opacity"), .key("]", .shift))
    static let opacityDigits = ShortcutItem(L("Opacity 10–100 %"), .key("1"), .key("2"), .key("3"), .key("4"), .key("5"),
                                            .key("6"), .key("7"), .key("8"), .key("9"), .key("0"), summary: "1 … 9, 0")

    // MARK: Canvas (modifier + mouse; the canvas checks `isHeld`)
    static let pan = ShortcutItem(L("Pan"), .gesture(L("Space + Drag")))
    static let zoomAtPointer = ShortcutItem(L("Zoom at pointer"), .gesture(L("Scroll"), .option), .gesture(L("Scroll"), .command))
    static let pickColor = ShortcutItem(L("Pick color while painting"), .gesture(L("Click"), .option))
    static let constrain = ShortcutItem(L("Straight line / keep proportions"), .gesture(L("Drag"), .shift))
    static let moveGuide = ShortcutItem(L("Move guide"), .gesture(L("Drag"), .command))
    static let nudge = ShortcutItem(L("Nudge selection"), .gesture("←↑→↓"), .gesture("←↑→↓", .shift))
    static let commit = ShortcutItem(L("Commit"), .gesture("↩"))
    static let cancel = ShortcutItem(L("Cancel"), .gesture("Esc"))

    /// Cheat sheet layout, in reading order.
    static var sections: [ShortcutSection] {
        [
            ShortcutSection(title: L("File"), items: [new, open, close, save, saveAs, imageProperties, pageSetup, print]),
            ShortcutSection(title: L("Edit"), items: [undo, redo, cut, copy, paste, pasteFromFile, delete, selectAll, deselect, invertSelection, crop]),
            ShortcutSection(title: L("Image"), items: [resizeAndSkew]),
            ShortcutSection(title: L("Layers"), items: [addLayer, duplicateLayer, mergeDown, moveLayerUp, moveLayerDown]),
            ShortcutSection(title: L("View"), items: [zoomIn, zoomOut, actualSize, fitToWindow, gridlines, rulers, guides, layersPanel, colorPanel, showToolbar, fullScreen]),
            ShortcutSection(title: L("Tools"), items: [brush, toggleBrushPencil, pencil, eraser, fill, colorPicker, text, rectangleSelect, freeformSelect, magnifier, shapes, swapColors, defaultColors]),
            ShortcutSection(title: L("Size and opacity"), items: [smallerBrush, largerBrush, lessOpacity, moreOpacity, opacityDigits]),
            ShortcutSection(title: L("Canvas"), items: [pan, zoomAtPointer, pickColor, constrain, moveGuide, nudge, commit, cancel]),
            ShortcutSection(title: "Paint Again", items: [settings, hide, hideOthers, minimize, quit, help]),
        ]
    }
}
