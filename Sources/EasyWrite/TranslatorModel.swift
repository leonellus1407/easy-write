import EasyWriteCore
import SwiftUI

/// State behind the popover: the text on both sides, the two languages, and how the current
/// request is going.
@MainActor
final class TranslatorModel: ObservableObject {
    enum Phase: Equatable { case idle, translating, failed(String) }

    @Published var input = "" {
        didSet { if input != oldValue { schedule(after: Self.debounce) } }
    }
    @Published private(set) var output = ""
    @Published private(set) var phase: Phase = .idle
    @Published var sourceCode: String {
        didSet {
            guard sourceCode != oldValue else { return }
            Store.shared.sourceCode = sourceCode
            if !isSwapping { languagesChanged() }
        }
    }
    @Published var targetCode: String {
        didSet {
            guard targetCode != oldValue else { return }
            Store.shared.targetCode = targetCode
            if !isSwapping { languagesChanged() }
        }
    }

    /// Set by AppDelegate so the status icon can show that a translation is running.
    var onBusyChange: ((Bool) -> Void)?

    var isTranslating: Bool { phase == .translating }
    var canSwap: Bool { sourceCode != Languages.auto.code }
    var failure: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    private static let debounce = Duration.milliseconds(300)
    private let llm: LLMTranslator
    private let cache = TranslationCache()
    private var task: Task<Void, Never>?
    /// Bumped for every request so a superseded one cannot write over a newer one's state.
    private var generation = 0
    /// Guards `swap()` against retranslating once per assignment instead of once per press.
    private var isSwapping = false
    /// No pasteboard has this change count, so the first open always reads.
    private var lastClipboardChange = -1

    init(llm: LLMTranslator) {
        self.llm = llm
        sourceCode = Store.shared.sourceCode
        targetCode = Store.shared.targetCode
    }

    private var source: Lang { Languages.source(sourceCode) }
    private var target: Lang { Languages.named(targetCode) }

    // MARK: Actions
    /// Fills the left pane from the clipboard and translates. The clipboard is re-read only when
    /// it changed since the last read, so an edit in the pane survives closing and reopening.
    func open() {
        let changeCount = Clipboard.changeCount
        if changeCount != lastClipboardChange {
            lastClipboardChange = changeCount
            input = Clipboard.read(ignoringPrivateContent: Store.shared.ignoresPrivateClipboard) ?? ""
        }
        schedule(after: .zero)
    }

    /// Always produces a fresh run, so a cached answer still has a way to be regenerated.
    func retranslate() {
        cache.remove(key(for: trimmedInput))
        schedule(after: .zero)
    }

    /// Exchanges the two languages, keeps the input text, and retranslates once rather than twice.
    func swap() {
        guard canSwap else { return }
        let previousSource = sourceCode
        isSwapping = true
        sourceCode = targetCode
        targetCode = previousSource
        isSwapping = false
        languagesChanged()
    }

    func copyOutput() {
        guard !output.isEmpty else { return }
        Clipboard.write(output)
        // Our own write must not look like new clipboard content on the next open.
        lastClipboardChange = Clipboard.changeCount
    }

    func prewarm() {
        llm.prewarm(from: source, to: target, styleGuide: Store.shared.styleGuide)
    }

    // MARK: Translation
    private func languagesChanged() {
        prewarm()
        schedule(after: .zero)
    }

    private func schedule(after delay: Duration) {
        task?.cancel()
        generation += 1
        let mine = generation
        task = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard let self, !Task.isCancelled else { return }
            await self.run(mine)
        }
    }

    private func run(_ mine: Int) async {
        let text = trimmedInput
        guard !text.isEmpty else { output = ""; setPhase(.idle); return }
        if let reason = llm.unavailableReason { output = ""; setPhase(.failed(reason.message)); return }

        let key = key(for: text)
        if let cached = cache.value(for: key) { output = cached; setPhase(.idle); return }

        output = ""
        setPhase(.translating)
        let styleGuide = Store.shared.styleGuide
        do {
            var latest = ""
            for try await snapshot in llm.translate(text, from: source, to: target,
                                                    styleGuide: styleGuide) {
                guard mine == generation else { return }
                latest = snapshot
                output = snapshot
            }
            guard mine == generation else { return }
            guard !latest.isEmpty else {
                setPhase(.failed("The model returned nothing. Try again."))
                return
            }
            cache.store(latest, for: key)
            setPhase(.idle)
            llm.prewarm(from: source, to: target, styleGuide: styleGuide)
        } catch is LLMTranslator.TimeoutError {
            guard mine == generation else { return }
            setPhase(.failed("The translation took too long and was stopped. Try again."))
        } catch {
            guard mine == generation else { return }
            setPhase(.failed("The translation didn’t finish. Try again."))
        }
    }

    private func setPhase(_ new: Phase) {
        phase = new
        onBusyChange?(new == .translating)
    }

    // MARK: Helpers
    private var trimmedInput: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func key(for text: String) -> TranslationCache.Key {
        .init(text: text, sourceCode: sourceCode, targetCode: targetCode,
              styleGuide: Store.shared.styleGuide)
    }
}
