import EasyWriteCore
import Foundation
import SwiftUI

/// Single source of truth for user settings. ObservableObject so SwiftUI prefs bind to it.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()
    private let d = UserDefaults.standard

    /// Set by AppDelegate to re-register hot-keys when the binding changes.
    var onChange: (() -> Void)?

    struct Shortcut: Codable, Equatable { var keyCode: UInt32; var modifiers: UInt32 }

    static let defaultShortcuts: [String: Shortcut] = [
        "translate": .init(keyCode: 6, modifiers: 4608),  // ⇧⌃Z
    ]

    @Published var sourceCode: String { didSet { d.set(sourceCode, forKey: "sourceLanguageCode") } }
    @Published var targetCode: String { didSet { d.set(targetCode, forKey: "targetLanguageCode") } }
    @Published var styleGuide: String { didSet { d.set(styleGuide, forKey: "styleGuide") } }
    /// No `onChange?()`: the popover is transient, so opening Preferences dismisses it and the
    /// next open reads this afresh.
    @Published var engine: String { didSet { d.set(engine, forKey: "translationEngine") } }
    @Published var ignoresPrivateClipboard: Bool {
        didSet { d.set(ignoresPrivateClipboard, forKey: "ignoresPrivateClipboard") }
    }
    @Published private var shortcuts: [String: Shortcut] { didSet { saveShortcuts(); onChange?() } }

    private init() {
        sourceCode = d.string(forKey: "sourceLanguageCode") ?? "auto"
        targetCode = d.string(forKey: "targetLanguageCode") ?? "de"
        styleGuide = d.string(forKey: "styleGuide") ?? ""
        // Absent for everyone upgrading, so they keep the engine they already had.
        engine = d.string(forKey: "translationEngine") ?? Engine.intelligence.rawValue
        // Defaults to on, so a fresh install protects a copied password without being asked.
        ignoresPrivateClipboard = d.object(forKey: "ignoresPrivateClipboard") as? Bool ?? true
        if let data = d.data(forKey: "shortcuts"),
           let decoded = try? JSONDecoder().decode([String: Shortcut].self, from: data) {
            var merged = Store.defaultShortcuts
            for (k, v) in decoded { merged[k] = v }
            shortcuts = merged
        } else {
            shortcuts = Store.defaultShortcuts
        }
    }

    func shortcut(for action: String) -> Shortcut {
        shortcuts[action] ?? Store.defaultShortcuts[action] ?? .init(keyCode: 6, modifiers: 4608)
    }

    func setShortcut(_ s: Shortcut, for action: String) { shortcuts[action] = s }

    private func saveShortcuts() {
        if let data = try? JSONEncoder().encode(shortcuts) { d.set(data, forKey: "shortcuts") }
    }
}
