import AppKit

/// The Settings window (⌘,): language, appearance and the persisted window options. Every control writes to
/// `AppSettings`; open windows and the View menu follow through `.settingsChanged`.
final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private let languagePopup = NSPopUpButton()
    private let relaunchRow = NSStackView()
    private let themePopup = NSPopUpButton()
    private let liquidGlass = NSButton(checkboxWithTitle: L("Liquid Glass"), target: nil, action: nil)
    private var windowOptions: [(button: NSButton, shortcut: String?, get: () -> Bool, set: (Bool) -> Void)] = []
    private var relaunchGrid: NSGridView?
    private var observer: Any?

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L("Settings")
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("PaintSettingsWindow")
        super.init(window: window)
        window.contentView = buildContent()
        window.setContentSize(window.contentView!.fittingSize)
        if !window.setFrameUsingName("PaintSettingsWindow") { window.center() }
        observer = NotificationCenter.default.addObserver(forName: .settingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Layout

    private func buildContent() -> NSView {
        languagePopup.addItem(withTitle: L("System"))
        for language in AppSettings.languages { languagePopup.addItem(withTitle: language.name) }
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))

        let relaunchNote = NSTextField(wrappingLabelWithString: L("The language changes after Paint Again is relaunched."))
        relaunchNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        relaunchNote.textColor = .secondaryLabelColor
        relaunchNote.preferredMaxLayoutWidth = 220
        let relaunchButton = NSButton(title: L("Relaunch Now"), target: self, action: #selector(relaunch(_:)))
        relaunchButton.controlSize = .small
        relaunchRow.orientation = .horizontal
        relaunchRow.alignment = .firstBaseline
        relaunchRow.spacing = 8
        relaunchRow.addArrangedSubview(relaunchNote)
        relaunchRow.addArrangedSubview(relaunchButton)

        for title in [L("System"), L("Light"), L("Dark")] { themePopup.addItem(withTitle: title) }
        themePopup.target = self
        themePopup.action = #selector(themeChanged(_:))
        liquidGlass.target = self
        liquidGlass.action = #selector(liquidGlassChanged(_:))

        windowOptions = [
            (NSButton(checkboxWithTitle: L("Show Toolbar"), target: nil, action: nil), "⌥ + ⌘ + T", { AppSettings.showTopToolbar }, { AppSettings.showTopToolbar = $0 }),
            (NSButton(checkboxWithTitle: L("Status Bar"), target: nil, action: nil), nil, { AppSettings.showStatusBar }, { AppSettings.showStatusBar = $0 }),
            (NSButton(checkboxWithTitle: L("Layers Panel"), target: nil, action: nil), "⌘ + L", { AppSettings.showLayersPanel }, { AppSettings.showLayersPanel = $0 }),
            (NSButton(checkboxWithTitle: L("Rulers"), target: nil, action: nil), "⌘ + R", { AppSettings.showRulers }, { AppSettings.showRulers = $0 }),
            (NSButton(checkboxWithTitle: L("Gridlines"), target: nil, action: nil), "⌘ + G", { AppSettings.showGridlines }, { AppSettings.showGridlines = $0 }),
            (NSButton(checkboxWithTitle: L("Guides"), target: nil, action: nil), "⌘ + ;", { AppSettings.showGuides }, { AppSettings.showGuides = $0 }),
        ]
        for (i, option) in windowOptions.enumerated() {
            option.button.tag = i
            option.button.target = self
            option.button.action = #selector(windowOptionChanged(_:))
        }

        /// A control followed by its menu key equivalent in the secondary colour, like a menu item.
        func withShortcut(_ control: NSView, _ shortcut: String?) -> NSView {
            guard let shortcut else { return control }
            let key = NSTextField(labelWithString: shortcut)
            key.textColor = .tertiaryLabelColor
            key.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            let row = NSStackView(views: [control, key])
            row.orientation = .horizontal
            row.alignment = .firstBaseline
            row.spacing = 10
            return row
        }
        func label(_ text: String) -> NSTextField {
            let l = NSTextField(labelWithString: text)
            l.alignment = .right
            return l
        }
        var rows: [[NSView]] = [
            [label(L("Language:")), languagePopup],
            [NSGridCell.emptyContentView, relaunchRow],
            [label(L("Appearance:")), themePopup],
        ]
        if GlassHost.supportsLiquidGlass { rows.append([NSGridCell.emptyContentView, liquidGlass]) }
        for (i, option) in windowOptions.enumerated() {
            rows.append([i == 0 ? label(L("Window:")) : NSGridCell.emptyContentView, withShortcut(option.button, option.shortcut)])
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 120
        grid.column(at: 1).width = 280
        grid.row(at: 2).topPadding = 12
        grid.row(at: GlassHost.supportsLiquidGlass ? 4 : 3).topPadding = 12
        grid.translatesAutoresizingMaskIntoConstraints = false
        relaunchGrid = grid

        let container = NSView()
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
        ])
        return container
    }

    // MARK: - State

    private func refresh() {
        let index = AppSettings.languages.firstIndex { $0.code == AppSettings.language }.map { $0 + 1 } ?? 0
        languagePopup.selectItem(at: index)
        relaunchGrid?.row(at: 1).isHidden = AppSettings.language == AppSettings.languageAtLaunch
        themePopup.selectItem(at: AppSettings.theme)
        liquidGlass.state = GlassHost.liquidGlassEnabled ? .on : .off
        for option in windowOptions { option.button.state = option.get() ? .on : .off }
        fitWindow()
    }

    /// Resizes the window to the grid's fitting size (the Relaunch row comes and goes), keeping the top-left corner.
    private func fitWindow() {
        guard let window, let view = window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: view.fittingSize))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        if frame.size != window.frame.size { window.setFrame(frame, display: true) }
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        AppSettings.language = index == 0 ? nil : AppSettings.languages[index - 1].code
    }

    @objc private func relaunch(_ sender: Any?) { AppSettings.relaunch() }

    @objc private func themeChanged(_ sender: NSPopUpButton) { AppSettings.theme = sender.indexOfSelectedItem }

    @objc private func liquidGlassChanged(_ sender: NSButton) { AppDelegate.shared.setLiquidGlass(sender.state == .on) }

    @objc private func windowOptionChanged(_ sender: NSButton) { windowOptions[sender.tag].set(sender.state == .on) }
}
