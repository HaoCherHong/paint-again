import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var fileMenu = NSMenu(title: L("File"))
    private(set) var editMenu = NSMenu(title: L("Edit"))
    private(set) var viewMenu = NSMenu(title: L("View"))
    private(set) var imageMenu = NSMenu(title: L("Image"))
    private(set) var layersMenu = NSMenu(title: L("Layers"))

    static var shared: AppDelegate { NSApp.delegate as! AppDelegate }

    // MARK: - Theme (System / Light / Dark)

    private let themeMenu = NSMenu(title: L("Appearance"))
    private var liquidGlassItem: NSMenuItem?
    private var settingsObserver: Any?

    private func applyTheme() {
        let theme = AppSettings.theme
        switch theme {
        case 1: NSApp.appearance = NSAppearance(named: .aqua)
        case 2: NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
        for item in themeMenu.items where item.tag >= 0 && item !== liquidGlassItem { item.state = item.tag == theme ? .on : .off }
        liquidGlassItem?.state = GlassHost.liquidGlassEnabled ? .on : .off
    }

    @objc private func selectTheme(_ sender: NSMenuItem) { AppSettings.theme = sender.tag }

    @objc private func toggleLiquidGlass(_ sender: NSMenuItem) { setLiquidGlass(!GlassHost.liquidGlassEnabled) }

    func setLiquidGlass(_ enabled: Bool) {
        GlassHost.liquidGlassEnabled = enabled
        applyTheme()
        for window in NSApp.windows { window.contentView?.needsDisplay = true }
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }

    @objc private func showSettings(_ sender: Any?) { PreferencesWindowController.shared.show() }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Offscreen snapshots cannot render Liquid Glass; use the fallback materials for that run only.
        if ProcessInfo.processInfo.environment["PAINT_SNAPSHOT"] != nil { GlassHost.forceFallback = true }
        _ = AppSettings.languageAtLaunch
        NSApp.mainMenu = buildMainMenu()
        applyTheme()
        settingsObserver = NotificationCenter.default.addObserver(forName: .settingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.applyTheme()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        DebugSelfTest.runIfRequested()
        if ProcessInfo.processInfo.environment["PAINT_OPEN_SETTINGS"] == "1" { PreferencesWindowController.shared.show() }
        scheduleDebugSnapshotIfRequested()
    }

    /// Development aid: `PAINT_SNAPSHOT=/path.png` writes a render of the front window after launch,
    /// `PAINT_SNAPSHOT_DELAY` (seconds) adjusts the wait, `PAINT_SNAPSHOT_KEYWINDOW=1` captures the key window
    /// (`PAINT_OPEN_SETTINGS=1` opens the Settings window first) and `PAINT_QUIT=1` terminates afterwards.
    private func scheduleDebugSnapshotIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["PAINT_SNAPSHOT"] else { return }
        let delay = Double(env["PAINT_SNAPSHOT_DELAY"] ?? "") ?? 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let target = env["PAINT_SNAPSHOT_KEYWINDOW"] == "1" ? NSApp.keyWindow : nil
            if env["PAINT_TOGGLE_GLASS"] == "1" { GlassHost.liquidGlassEnabled.toggle() }
            if let appMenu = NSApp.mainMenu?.items.first?.submenu {
                FileHandle.standardError.write("APPMENU \(appMenu.items.map { $0.title }.filter { !$0.isEmpty })\n".data(using: .utf8)!)
            }
            if let wc = (NSApp.mainWindow?.windowController as? MainWindowController), let root = wc.window?.contentView {
                FileHandle.standardError.write(("GLASS enabled=\(GlassHost.liquidGlassEnabled)\n" + GlassHost.debugReport(in: root) + "\n").data(using: .utf8)!)
                let c = wc.canvas!
                let clip = c.enclosingScrollView?.contentView.bounds ?? .zero
                FileHandle.standardError.write("SNAPSHOT zoom=\(c.zoom) frame=\(c.frame) visible=\(c.visibleRect) clip=\(clip) canvasOrigin=\(c.canvasOrigin)\nLAYOUT \(wc.layoutDebugSummary())\n".data(using: .utf8)!)
            }
            if let window = target ?? NSApp.mainWindow ?? NSApp.windows.first, let view = window.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                }
            }
            if env["PAINT_QUIT"] == "1" { exit(0) }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Menu construction

    private func item(_ title: String, _ action: Selector?, tag: Int = 0) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.tag = tag
        return it
    }

    /// Adds a menu item for a `Shortcuts` command: its first key shortcut on the visible item, every other one
    /// on a hidden item that only answers the key. Returns the visible item.
    @discardableResult
    private func add(_ shortcut: ShortcutItem, _ action: Selector?, to menu: NSMenu, title: String? = nil) -> NSMenuItem {
        let keys = shortcut.shortcuts.filter { !$0.key.isEmpty }
        let visible = item(title ?? shortcut.title, action)
        for (i, key) in keys.enumerated() {
            let it = i == 0 ? visible : item(title ?? shortcut.title, action)
            it.keyEquivalent = key.key
            it.keyEquivalentModifierMask = key.modifiers
            if i > 0 {
                it.isHidden = true
                it.allowsKeyEquivalentWhenHidden = true
            }
            menu.addItem(it)
        }
        if keys.isEmpty { menu.addItem(visible) }
        return visible
    }

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        // Application menu
        let appMenu = NSMenu()
        appMenu.addItem(item(L("About Paint Again"), #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        appMenu.addItem(.separator())
        add(Shortcuts.settings, #selector(showSettings(_:)), to: appMenu).target = self
        appMenu.addItem(.separator())
        let services = NSMenu(title: L("Services"))
        let servicesItem = item(L("Services"), nil)
        servicesItem.submenu = services
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = services
        appMenu.addItem(.separator())
        add(Shortcuts.hide, #selector(NSApplication.hide(_:)), to: appMenu)
        add(Shortcuts.hideOthers, #selector(NSApplication.hideOtherApplications(_:)), to: appMenu)
        appMenu.addItem(item(L("Show All"), #selector(NSApplication.unhideAllApplications(_:))))
        appMenu.addItem(.separator())
        add(Shortcuts.quit, #selector(NSApplication.terminate(_:)), to: appMenu)
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        // File
        fileMenu.removeAllItems()
        add(Shortcuts.new, #selector(NSDocumentController.newDocument(_:)), to: fileMenu)
        add(Shortcuts.open, #selector(NSDocumentController.openDocument(_:)), to: fileMenu)
        let recent = NSMenu(title: L("Open Recent"))
        let recentItem = item(L("Open Recent"), nil)
        recentItem.submenu = recent
        recent.addItem(item(L("Clear Menu"), #selector(NSDocumentController.clearRecentDocuments(_:))))
        fileMenu.addItem(recentItem)
        fileMenu.addItem(.separator())
        add(Shortcuts.close, #selector(NSWindow.performClose(_:)), to: fileMenu)
        add(Shortcuts.save, #selector(NSDocument.save(_:)), to: fileMenu)
        add(Shortcuts.saveAs, #selector(NSDocument.saveAs(_:)), to: fileMenu)
        fileMenu.addItem(item(L("Revert to Saved"), #selector(NSDocument.revertToSaved(_:))))
        fileMenu.addItem(.separator())
        add(Shortcuts.imageProperties, #selector(MainWindowController.imageProperties(_:)), to: fileMenu)
        fileMenu.addItem(item(L("Set as Desktop Background"), #selector(MainWindowController.setAsDesktopBackground(_:))))
        fileMenu.addItem(item(L("Share…"), #selector(MainWindowController.shareImage(_:))))
        fileMenu.addItem(.separator())
        add(Shortcuts.pageSetup, #selector(NSDocument.runPageLayout(_:)), to: fileMenu)
        add(Shortcuts.print, #selector(NSDocument.printDocument(_:)), to: fileMenu)
        let fileItem = NSMenuItem()
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        // Edit
        editMenu.removeAllItems()
        add(Shortcuts.undo, Selector(("undo:")), to: editMenu)
        add(Shortcuts.redo, Selector(("redo:")), to: editMenu)
        editMenu.addItem(.separator())
        add(Shortcuts.cut, #selector(NSText.cut(_:)), to: editMenu)
        add(Shortcuts.copy, #selector(NSText.copy(_:)), to: editMenu)
        add(Shortcuts.paste, #selector(NSText.paste(_:)), to: editMenu)
        add(Shortcuts.pasteFromFile, #selector(MainWindowController.pasteFromFile(_:)), to: editMenu)
        editMenu.addItem(item(L("Delete"), #selector(NSText.delete(_:))))
        editMenu.addItem(.separator())
        add(Shortcuts.selectAll, #selector(NSResponder.selectAll(_:)), to: editMenu)
        add(Shortcuts.deselect, #selector(CanvasView.deselect(_:)), to: editMenu)
        add(Shortcuts.invertSelection, #selector(MainWindowController.invertSelection(_:)), to: editMenu)
        editMenu.addItem(item(L("Transparent Selection"), #selector(MainWindowController.toggleTransparentSelection(_:))))
        editMenu.addItem(.separator())
        add(Shortcuts.crop, #selector(MainWindowController.cropToSelection(_:)), to: editMenu)
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        main.addItem(editItem)

        // View
        viewMenu.removeAllItems()
        add(Shortcuts.zoomIn, #selector(MainWindowController.zoomIn(_:)), to: viewMenu)
        add(Shortcuts.zoomOut, #selector(MainWindowController.zoomOut(_:)), to: viewMenu)
        add(Shortcuts.actualSize, #selector(MainWindowController.zoomActual(_:)), to: viewMenu)
        add(Shortcuts.fitToWindow, #selector(MainWindowController.zoomToFit(_:)), to: viewMenu)
        viewMenu.addItem(.separator())
        add(Shortcuts.gridlines, #selector(MainWindowController.toggleGridlines(_:)), to: viewMenu)
        add(Shortcuts.rulers, #selector(MainWindowController.toggleRulers(_:)), to: viewMenu)
        add(Shortcuts.guides, #selector(MainWindowController.toggleGuides(_:)), to: viewMenu)
        viewMenu.addItem(item(L("Clear Guides"), #selector(MainWindowController.clearGuides(_:))))
        viewMenu.addItem(item(L("Status Bar"), #selector(MainWindowController.toggleStatusBar(_:))))
        add(Shortcuts.layersPanel, #selector(MainWindowController.toggleLayersPanel(_:)), to: viewMenu)
        viewMenu.addItem(item(L("Color Panel"), #selector(MainWindowController.toggleColorPanel(_:))))
        add(Shortcuts.showToolbar, #selector(MainWindowController.toggleTopToolbar(_:)), to: viewMenu)
        viewMenu.addItem(item(L("Keyboard Shortcuts"), #selector(MainWindowController.toggleCheatSheet(_:))))
        viewMenu.addItem(.separator())
        themeMenu.removeAllItems()
        for (tag, title) in [(0, L("System")), (1, L("Light")), (2, L("Dark"))] {
            let it = NSMenuItem(title: title, action: #selector(selectTheme(_:)), keyEquivalent: "")
            it.target = self
            it.tag = tag
            themeMenu.addItem(it)
        }
        if GlassHost.supportsLiquidGlass {
            themeMenu.addItem(.separator())
            let glass = NSMenuItem(title: L("Liquid Glass"), action: #selector(toggleLiquidGlass(_:)), keyEquivalent: "")
            glass.target = self
            glass.tag = -1
            themeMenu.addItem(glass)
            liquidGlassItem = glass
        }
        let themeItem = item(L("Appearance"), nil)
        themeItem.submenu = themeMenu
        viewMenu.addItem(themeItem)
        viewMenu.addItem(.separator())
        add(Shortcuts.fullScreen, #selector(NSWindow.toggleFullScreen(_:)), to: viewMenu)
        let viewItem = NSMenuItem()
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        // Image
        imageMenu.removeAllItems()
        imageMenu.addItem(item(L("Crop"), #selector(MainWindowController.cropToSelection(_:))))
        add(Shortcuts.resizeAndSkew, #selector(MainWindowController.resizeAndSkew(_:)), to: imageMenu)
        imageMenu.addItem(.separator())
        imageMenu.addItem(item(L("Rotate Right 90°"), #selector(MainWindowController.rotateRight(_:))))
        imageMenu.addItem(item(L("Rotate Left 90°"), #selector(MainWindowController.rotateLeft(_:))))
        imageMenu.addItem(item(L("Rotate 180°"), #selector(MainWindowController.rotate180(_:))))
        imageMenu.addItem(item(L("Flip Vertical"), #selector(MainWindowController.flipVertical(_:))))
        imageMenu.addItem(item(L("Flip Horizontal"), #selector(MainWindowController.flipHorizontal(_:))))
        imageMenu.addItem(.separator())
        imageMenu.addItem(item(L("Remove Background"), #selector(MainWindowController.removeBackground(_:))))
        let imageItem = NSMenuItem()
        imageItem.submenu = imageMenu
        main.addItem(imageItem)

        // Layers
        layersMenu.removeAllItems()
        add(Shortcuts.addLayer, #selector(MainWindowController.addLayer(_:)), to: layersMenu)
        add(Shortcuts.duplicateLayer, #selector(MainWindowController.duplicateLayer(_:)), to: layersMenu)
        layersMenu.addItem(item(L("Delete Layer"), #selector(MainWindowController.deleteLayer(_:))))
        add(Shortcuts.mergeDown, #selector(MainWindowController.mergeDown(_:)), to: layersMenu)
        layersMenu.addItem(.separator())
        add(Shortcuts.moveLayerUp, #selector(MainWindowController.moveLayerUp(_:)), to: layersMenu)
        add(Shortcuts.moveLayerDown, #selector(MainWindowController.moveLayerDown(_:)), to: layersMenu)
        layersMenu.addItem(item(L("Hide Layer"), #selector(MainWindowController.toggleLayerVisibility(_:))))
        layersMenu.addItem(item(L("Layer Properties…"), #selector(MainWindowController.layerProperties(_:))))
        layersMenu.addItem(.separator())
        layersMenu.addItem(item(L("Background Color…"), #selector(MainWindowController.editBackgroundColor(_:))))
        layersMenu.addItem(item(L("Hide Background"), #selector(MainWindowController.toggleBackgroundVisible(_:))))
        let layersItem = NSMenuItem()
        layersItem.submenu = layersMenu
        main.addItem(layersItem)

        // Window
        let windowMenu = NSMenu(title: L("Window"))
        add(Shortcuts.minimize, #selector(NSWindow.performMiniaturize(_:)), to: windowMenu)
        windowMenu.addItem(item(L("Zoom"), #selector(NSWindow.performZoom(_:))))
        windowMenu.addItem(.separator())
        windowMenu.addItem(item(L("Bring All to Front"), #selector(NSApplication.arrangeInFront(_:))))
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        // Help
        let helpMenu = NSMenu(title: L("Help"))
        add(Shortcuts.help, #selector(NSApplication.showHelp(_:)), to: helpMenu)
        let helpItem = NSMenuItem()
        helpItem.submenu = helpMenu
        main.addItem(helpItem)
        NSApp.helpMenu = helpMenu

        return main
    }
}
