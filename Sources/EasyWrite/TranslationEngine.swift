import EasyWriteCore
import Foundation

/// What the popover needs from a translator, so `TranslatorModel` never branches on which one is
/// running. A stream of cumulative snapshots fits both engines: one writes the answer word by
/// word, the other yields the whole answer as a single element.
@MainActor
protocol TranslationEngine {
    /// Why this engine cannot run at all — nil when it can. A missing language pack is not this:
    /// it depends on the language pair, so it is reported per translation instead.
    var unavailableReason: String? { get }

    /// Loads whatever the next translation would otherwise pay for. Worth calling at launch, when
    /// a language changes, and again once a turn finishes.
    func prewarm(from source: Lang, to target: Lang, styleGuide: String)

    func translate(_ text: String, from source: Lang, to target: Lang,
                   styleGuide: String) -> AsyncThrowingStream<String, Error>
}

/// Both engines race their work against a timeout and throw this, so the popover's message for a
/// stalled translation does not depend on which engine stalled.
struct TimeoutError: Error {}

/// A failure the engine can already explain. The popover shows the message as it stands, which is
/// what keeps a missing language pack from reading like a generic breakdown.
struct EngineFailure: Error { let message: String }
