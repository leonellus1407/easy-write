import Foundation

public struct Lang: Identifiable {
    public var id: String { code }
    public let code: String
    public let name: String
    /// Optional per-language guidance appended to the model instruction (e.g. dialect choice).
    public var note: String? = nil
}

public enum Languages {
    public static let all: [Lang] = [
        Lang(code: "de", name: "German"),
        Lang(code: "fr", name: "French"),
        Lang(code: "es", name: "Spanish"),
        Lang(code: "it", name: "Italian"),
        Lang(code: "pt", name: "Portuguese"),
        Lang(code: "nl", name: "Dutch"),
        Lang(code: "tr", name: "Turkish"),
        Lang(code: "pl", name: "Polish"),
        Lang(code: "ru", name: "Russian"),
        Lang(code: "en", name: "English"),
        Lang(code: "ja", name: "Japanese"),
        Lang(code: "zh", name: "Chinese"),
        Lang(code: "ar", name: "Arabic",
             note: "Use clear Modern Standard Arabic (الفصحى); do not mix in colloquial dialect."),
    ]

    /// Source-only sentinel: the model is told to detect the language instead of being given one.
    /// It never appears in `all`, so it can never become a target.
    public static let auto = Lang(code: "auto", name: "Auto-detect")

    public static var sources: [Lang] { [auto] + all }

    /// Falls back to the first language rather than returning nil, so a code persisted by an
    /// older build (or a hand-edited default) still yields a usable target instead of failing.
    public static func named(_ code: String) -> Lang { all.first { $0.code == code } ?? all[0] }

    /// Resolves a stored source code, where `auto` is a legitimate answer rather than a miss.
    public static func source(_ code: String) -> Lang { code == auto.code ? auto : named(code) }

    /// The English name for a code that need not be one we list — auto-detect can resolve to any
    /// language the recogniser knows. Falls back to the code rather than to a wrong name.
    public static func name(of code: String) -> String { all.first { $0.code == code }?.name ?? code }
}
