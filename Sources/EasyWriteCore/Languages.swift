import Foundation

public struct Lang: Identifiable {
    public var id: String { code }
    public let code: String
    public let name: String
    public let formal: String?
    public let informal: String?
    /// Optional per-language guidance appended to the model instruction (e.g. dialect choice).
    public var note: String? = nil
}

public enum Languages {
    public static let all: [Lang] = [
        Lang(code: "de", name: "German",     formal: "Sie",      informal: "du"),
        Lang(code: "fr", name: "French",     formal: "vous",     informal: "tu"),
        Lang(code: "es", name: "Spanish",    formal: "usted",    informal: "tú"),
        Lang(code: "it", name: "Italian",    formal: "Lei",      informal: "tu"),
        Lang(code: "pt", name: "Portuguese", formal: "o senhor", informal: "você"),
        Lang(code: "nl", name: "Dutch",      formal: "u",        informal: "je"),
        Lang(code: "tr", name: "Turkish",    formal: "siz",      informal: "sen"),
        Lang(code: "pl", name: "Polish",     formal: "Pan/Pani", informal: "ty"),
        Lang(code: "ru", name: "Russian",    formal: "вы",       informal: "ты"),
        Lang(code: "en", name: "English",    formal: nil,        informal: nil),
        Lang(code: "ja", name: "Japanese",   formal: nil,        informal: nil),
        Lang(code: "zh", name: "Chinese",    formal: nil,        informal: nil),
        Lang(code: "ar", name: "Arabic",     formal: nil,        informal: nil,
             note: "Use clear Modern Standard Arabic (الفصحى); do not mix in colloquial dialect."),
    ]

    /// Falls back to the first language rather than returning nil, so a code persisted by an
    /// older build (or a hand-edited default) still yields a usable target instead of failing.
    public static func named(_ code: String) -> Lang { all.first { $0.code == code } ?? all[0] }
}
