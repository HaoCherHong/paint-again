import AppKit

extension Notification.Name {
    /// Posted after any `AppSettings` value changes; windows and menus re-read every value.
    static let settingsChanged = Notification.Name("PaintSettingsChanged")
}

/// App-wide, persisted settings shared by the View menu and the Settings window.
enum AppSettings {
    private static let defaults = UserDefaults.standard

    private static func bool(_ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? value
    }

    private static func set(_ value: Any?, forKey key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }

    /// 0 = follow the system, 1 = light, 2 = dark.
    static var theme: Int {
        get { defaults.integer(forKey: "AppearanceTheme") }
        set { set(newValue, forKey: "AppearanceTheme") }
    }

    static var showTopToolbar: Bool {
        get { bool("ShowTopToolbar", default: true) }
        set { set(newValue, forKey: "ShowTopToolbar") }
    }

    static var showStatusBar: Bool {
        get { bool("ShowStatusBar", default: true) }
        set { set(newValue, forKey: "ShowStatusBar") }
    }

    static var showLayersPanel: Bool {
        get { bool("ShowLayersPanel", default: false) }
        set { set(newValue, forKey: "ShowLayersPanel") }
    }

    static var showRulers: Bool {
        get { bool("ShowRulers", default: false) }
        set { set(newValue, forKey: "ShowRulers") }
    }

    static var showGridlines: Bool {
        get { bool("ShowGridlines", default: false) }
        set { set(newValue, forKey: "ShowGridlines") }
    }

    static var showGuides: Bool {
        get { bool("ShowGuides", default: true) }
        set { set(newValue, forKey: "ShowGuides") }
    }

    // MARK: - Language

    /// Languages the app ships; `nil` means "follow the system".
    static let languages: [(code: String, name: String)] = [("en", "English"), ("zh-Hant", "繁體中文")]

    /// Per-app language override stored under `AppleLanguages` in the app's own defaults domain; the same key
    /// System Settings › Language & Region writes. Foundation reads it at launch only, so a change needs a relaunch.
    static var language: String? {
        get {
            guard let id = Bundle.main.bundleIdentifier,
                  let stored = defaults.persistentDomain(forName: id)?["AppleLanguages"] as? [String],
                  let first = stored.first else { return nil }
            return languages.first { first.hasPrefix($0.code) }?.code ?? first
        }
        set { set(newValue.map { [$0] }, forKey: "AppleLanguages") }
    }

    /// The override that was in effect when this process started; differs from `language` after a pending change.
    static let languageAtLaunch: String? = language

    /// Quits and starts a fresh instance so a language change takes effect. A detached shell waits for this
    /// process to exit (up to ten seconds, in case a save sheet is cancelled) before reopening the bundle.
    static func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", "for i in $(seq 1 100); do kill -0 \(pid) 2>/dev/null || { open -n \"$0\"; exit 0; }; sleep 0.1; done", Bundle.main.bundlePath]
        try? helper.run()
        NSApp.terminate(nil)
    }
}
