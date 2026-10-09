import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var fileMenu = NSMenu(title: L("File"))
    private(set) var editMenu = NSMenu(title: L("Edit"))
    private(set) var viewMenu = NSMenu(title: L("View"))
    private(set) var imageMenu = NSMenu(title: L("Image"))
    private(set) var layersMenu = NSMenu(title: L("Layers"))

    static var shared: AppDelegate { NSApp.delegate as! AppDelegate }

    // MARK: - Theme (System / Light / Dark)

    private static let themeKey = "AppearanceTheme"
    private let themeMenu = NSMenu(title: L("Appearance"))
    private var liquidGlassItem: NSMenuItem?

    /// 0 = follow the system, 1 = light, 2 = dark.
    private var theme: Int {
        get { UserDefaults.standard.integer(forKey: Self.themeKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.themeKey); applyTheme() }
    }

    private func applyTheme() {
        switch theme {
        case 1: NSApp.appearance = NSAppearance(named: .aqua)
        case 2: NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
        for item in themeMenu.items where item.tag >= 0 && item !== liquidGlassItem { item.state = item.tag == theme ? .on : .off }
        liquidGlassItem?.state = GlassHost.liquidGlassEnabled ? .on : .off
    }

    @objc private func selectTheme(_ sender: NSMenuItem) { theme = sender.tag }

    @objc private func toggleLiquidGlass(_ sender: NSMenuItem) {
        GlassHost.liquidGlassEnabled.toggle()
        applyTheme()
        for window in NSApp.windows { window.contentView?.needsDisplay = true }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Offscreen snapshots cannot render Liquid Glass; use the fallback materials for that run only.
        if ProcessInfo.processInfo.environment["PAINT_SNAPSHOT"] != nil { GlassHost.forceFallback = true }
        NSApp.mainMenu = buildMainMenu()
        applyTheme()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        DebugSelfTest.runIfRequested()
        scheduleDebugSnapshotIfRequested()
    }

    /// Development aid: `PAINT_SNAPSHOT=/path.png` writes a render of the front window after launch,
    /// `PAINT_SNAPSHOT_DELAY` (seconds) adjusts the wait and `PAINT_QUIT=1` terminates afterwards.
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

    private func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = [.command], tag: Int = 0) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.keyEquivalentModifierMask = key.isEmpty ? [] : mods
        it.tag = tag
        return it
    }

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        // Application menu
        let appMenu = NSMenu()
        appMenu.addItem(item(L("About Paint Again"), #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        appMenu.addItem(.separator())
        let services = NSMenu(title: L("Services"))
        let servicesItem = item(L("Services"), nil)
        servicesItem.submenu = services
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = services
        appMenu.addItem(.separator())
        appMenu.addItem(item(L("Hide Paint Again"), #selector(NSApplication.hide(_:)), "h"))
        appMenu.addItem(item(L("Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        appMenu.addItem(item(L("Show All"), #selector(NSApplication.unhideAllApplications(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(item(L("Quit Paint Again"), #selector(NSApplication.terminate(_:)), "q"))
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        // File
        fileMenu.removeAllItems()
        fileMenu.addItem(item(L("New"), #selector(NSDocumentController.newDocument(_:)), "n"))
        fileMenu.addItem(item(L("Open…"), #selector(NSDocumentController.openDocument(_:)), "o"))
        let recent = NSMenu(title: L("Open Recent"))
        let recentItem = item(L("Open Recent"), nil)
        recentItem.submenu = recent
        recent.addItem(item(L("Clear Menu"), #selector(NSDocumentController.clearRecentDocuments(_:))))
        fileMenu.addItem(recentItem)
        fileMenu.addItem(.separator())
        fileMenu.addItem(item(L("Close"), #selector(NSWindow.performClose(_:)), "w"))
        fileMenu.addItem(item(L("Save"), #selector(NSDocument.save(_:)), "s"))
        fileMenu.addItem(item(L("Save As…"), #selector(NSDocument.saveAs(_:)), "S"))
        fileMenu.addItem(item(L("Revert to Saved"), #selector(NSDocument.revertToSaved(_:))))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item(L("Image Properties…"), #selector(MainWindowController.imageProperties(_:)), "e", [.command, .shift]))
        fileMenu.addItem(item(L("Set as Desktop Background"), #selector(MainWindowController.setAsDesktopBackground(_:))))
        fileMenu.addItem(item(L("Share…"), #selector(MainWindowController.shareImage(_:))))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item(L("Page Setup…"), #selector(NSDocument.runPageLayout(_:)), "P"))
        fileMenu.addItem(item(L("Print…"), #selector(NSDocument.printDocument(_:)), "p"))
        let fileItem = NSMenuItem()
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        // Edit
        editMenu.removeAllItems()
        editMenu.addItem(item(L("Undo"), Selector(("undo:")), "z"))
        editMenu.addItem(item(L("Redo"), Selector(("redo:")), "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(item(L("Cut"), #selector(NSText.cut(_:)), "x"))
        editMenu.addItem(item(L("Copy"), #selector(NSText.copy(_:)), "c"))
        editMenu.addItem(item(L("Paste"), #selector(NSText.paste(_:)), "v"))
        editMenu.addItem(item(L("Paste From File…"), #selector(MainWindowController.pasteFromFile(_:)), "v", [.command, .shift]))
        editMenu.addItem(item(L("Delete"), #selector(NSText.delete(_:))))
        editMenu.addItem(.separator())
        editMenu.addItem(item(L("Select All"), #selector(NSResponder.selectAll(_:)), "a"))
        editMenu.addItem(item(L("Deselect"), #selector(CanvasView.deselect(_:)), "d"))
        editMenu.addItem(item(L("Invert Selection"), #selector(MainWindowController.invertSelection(_:)), "i", [.command, .shift]))
        editMenu.addItem(item(L("Transparent Selection"), #selector(MainWindowController.toggleTransparentSelection(_:))))
        editMenu.addItem(.separator())
        editMenu.addItem(item(L("Crop"), #selector(MainWindowController.cropToSelection(_:)), "x", [.command, .shift]))
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        main.addItem(editItem)

        // View
        viewMenu.removeAllItems()
        viewMenu.addItem(item(L("Zoom In"), #selector(MainWindowController.zoomIn(_:)), "+"))
        viewMenu.addItem(item(L("Zoom Out"), #selector(MainWindowController.zoomOut(_:)), "-"))
        viewMenu.addItem(item(L("Actual Size"), #selector(MainWindowController.zoomActual(_:)), "1"))
        viewMenu.addItem(item(L("Fit to Window"), #selector(MainWindowController.zoomToFit(_:)), "0"))
        viewMenu.addItem(.separator())
        viewMenu.addItem(item(L("Gridlines"), #selector(MainWindowController.toggleGridlines(_:)), "g"))
        viewMenu.addItem(item(L("Rulers"), #selector(MainWindowController.toggleRulers(_:)), "r"))
        viewMenu.addItem(item(L("Guides"), #selector(MainWindowController.toggleGuides(_:)), ";"))
        viewMenu.addItem(item(L("Clear Guides"), #selector(MainWindowController.clearGuides(_:))))
        viewMenu.addItem(item(L("Status Bar"), #selector(MainWindowController.toggleStatusBar(_:))))
        viewMenu.addItem(item(L("Layers Panel"), #selector(MainWindowController.toggleLayersPanel(_:)), "l"))
        viewMenu.addItem(item(L("Show Toolbar on Windows"), #selector(MainWindowController.toggleTopToolbar(_:))))
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
        viewMenu.addItem(item(L("Enter Full Screen"), #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        let viewItem = NSMenuItem()
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        // Image
        imageMenu.removeAllItems()
        imageMenu.addItem(item(L("Crop"), #selector(MainWindowController.cropToSelection(_:))))
        imageMenu.addItem(item(L("Resize and Skew…"), #selector(MainWindowController.resizeAndSkew(_:)), "r", [.command, .shift]))
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
        layersMenu.addItem(item(L("Add Layer"), #selector(MainWindowController.addLayer(_:)), "n", [.command, .shift]))
        layersMenu.addItem(item(L("Duplicate Layer"), #selector(MainWindowController.duplicateLayer(_:)), "j"))
        layersMenu.addItem(item(L("Delete Layer"), #selector(MainWindowController.deleteLayer(_:))))
        layersMenu.addItem(item(L("Merge Down"), #selector(MainWindowController.mergeDown(_:)), "e"))
        layersMenu.addItem(.separator())
        layersMenu.addItem(item(L("Move Layer Up"), #selector(MainWindowController.moveLayerUp(_:)), "]", [.command, .option]))
        layersMenu.addItem(item(L("Move Layer Down"), #selector(MainWindowController.moveLayerDown(_:)), "[", [.command, .option]))
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
        windowMenu.addItem(item(L("Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m"))
        windowMenu.addItem(item(L("Zoom"), #selector(NSWindow.performZoom(_:))))
        windowMenu.addItem(.separator())
        windowMenu.addItem(item(L("Bring All to Front"), #selector(NSApplication.arrangeInFront(_:))))
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        // Help
        let helpMenu = NSMenu(title: L("Help"))
        helpMenu.addItem(item(L("Paint Again Help"), #selector(NSApplication.showHelp(_:)), "?"))
        let helpItem = NSMenuItem()
        helpItem.submenu = helpMenu
        main.addItem(helpItem)
        NSApp.helpMenu = helpMenu

        return main
    }
}
