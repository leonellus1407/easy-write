import EasyWriteCore
import Foundation
import Translation

/// Apple's Translation framework — the engine behind the Translate app — as a second translator.
/// It takes no instructions, so the style guide and the per-language note are ignored here, and it
/// answers in one piece rather than word by word.
@MainActor
final class AppleTranslator: TranslationEngine {
    /// The framework ships with macOS, so the engine itself is always there. What can be missing
    /// is a language pack, which depends on the pair and is reported per translation.
    let unavailableReason: String? = nil

    private struct Pair: Equatable { let source: String; let target: String }

    /// A session already loaded for one pair, waiting for the next turn.
    private var warm: (pair: Pair, session: TranslationSession)?

    /// Loads the pair so the next translation does not pay for it — measured on this Mac at 5.6 s
    /// cold against 0.9 s once loaded. Auto-detect has no source until the text arrives, and a
    /// pack that is not installed is left alone rather than fetched behind the user's back.
    func prewarm(from source: Lang, to target: Lang, styleGuide: String) {
        guard source.code != Languages.auto.code else { return }
        let pair = Pair(source: source.code, target: target.code)
        guard warm?.pair != pair else { return }
        warm = nil
        Task { [weak self] in
            guard await LanguagePacks.status(from: pair.source, to: pair.target) == .installed,
                  let session = self?.session(for: pair) else { return }
            try? await session.prepareTranslation()
            self?.warm = (pair, session)
        }
    }

    /// One snapshot, holding the whole translation. The popover renders it the same way it renders
    /// the model's last snapshot, so nothing about the layout changes between engines.
    func translate(_ text: String, from source: Lang, to target: Lang,
                   styleGuide: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor [weak self] in
                guard let self else { return continuation.finish() }
                do {
                    continuation.yield(try await self.run(text, from: source, to: target))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ text: String, from source: Lang, to target: Lang) async throws -> String {
        let pair = Pair(source: try LanguagePacks.source(source, of: text, to: target),
                        target: target.code)
        let session = takeSession(for: pair)
        do {
            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { @MainActor in try await session.translate(text).targetText }
                group.addTask {
                    try await Task.sleep(nanoseconds: 20_000_000_000)    // 20s
                    throw TimeoutError()
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
        } catch {
            // Unlike a model session, this one keeps working unless it is told to stop, so a
            // superseded or timed-out turn has to cancel it explicitly.
            session.cancel()
            throw LanguagePacks.failure(error, from: pair.source, to: pair.target)
        }
    }

    /// Spends the loaded session when its pair matches. One session per turn: holding one across a
    /// language change would keep the wrong pair loaded.
    private func takeSession(for pair: Pair) -> TranslationSession {
        if let warm, warm.pair == pair {
            self.warm = nil
            return warm.session
        }
        return session(for: pair)
    }

    private func session(for pair: Pair) -> TranslationSession {
        // .highFidelity is the trade to make for a translation a person reads; .lowLatency exists
        // and is the wrong one here.
        TranslationSession(installedSource: LanguagePacks.language(pair.source),
                           target: LanguagePacks.language(pair.target),
                           preferredStrategy: .highFidelity)
    }
}
