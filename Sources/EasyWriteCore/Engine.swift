import Foundation

/// Which translator produces the text. Both run on the Mac; they differ in what they can be told
/// and in what they are good at, so the choice is the user's rather than the app's.
public enum Engine: String, CaseIterable, Identifiable, Sendable {
    case intelligence
    case translate

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .intelligence: return "Apple Intelligence"
        case .translate:    return "Apple Translate"
        }
    }

    /// What the choice costs, so picking one is not guesswork.
    public var caption: String {
        switch self {
        case .intelligence:
            return "Follows your style guide and writes the answer word by word. Needs Apple "
                 + "Intelligence, and can pick an odd term in a longer sentence."
        case .translate:
            return "The engine behind the Translate app. Steadier wording, and it works without "
                 + "Apple Intelligence — but it cannot be given a style guide, and it answers in "
                 + "one piece instead of streaming."
        }
    }

    /// Falls back to the default rather than returning nil, so a value written by a later build
    /// still yields a usable engine instead of failing.
    public static func named(_ raw: String) -> Engine { Engine(rawValue: raw) ?? .intelligence }
}
