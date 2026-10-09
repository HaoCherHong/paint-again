import Foundation

enum Localization {
    /// The resource bundle produced by SwiftPM, located next to the executable or inside the app bundle.
    static let bundle: Bundle = {
        let name = "Paint_Paint.bundle"
        var candidates: [URL] = []
        if let r = Bundle.main.resourceURL { candidates.append(r.appendingPathComponent(name)) }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent(name))
        candidates.append(Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent(name))
        for url in candidates {
            if let b = Bundle(url: url) { return b }
        }
        return Bundle.main
    }()
}

/// Looks up a user-facing string; the key doubles as the English text.
func L(_ key: String) -> String {
    Localization.bundle.localizedString(forKey: key, value: key, table: nil)
}
