import AppKit

extension NSPasteboard.PasteboardType {
    /// nspasteboard.org convention: the source declared this payload sensitive.
    static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    /// nspasteboard.org convention: the source will replace this payload within seconds.
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
}

/// The app's entire pasteboard surface: one function that reads, one that writes. Keeping it to this
/// file is what makes "Easy Write reads the clipboard and never writes it, except behind the Copy
/// button" a claim anyone can check by counting call sites instead of tracing control flow.
@MainActor
enum Clipboard {

    static var changeCount: Int { NSPasteboard.general.changeCount }

    /// Nil means there is nothing to translate: no text at all, or — when the user leaves the
    /// setting on — text whose source marked it as private or momentary.
    static func read(ignoringPrivateContent ignorePrivate: Bool) -> String? {
        let pb = NSPasteboard.general
        // The markers carry no payload, so honouring them is a type lookup, not a data read.
        if ignorePrivate, pb.availableType(from: [.concealed, .transient]) != nil { return nil }
        return pb.string(forType: .string)
    }

    /// The app's only pasteboard write. Called from the popover's Copy button and nowhere else.
    static func write(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
