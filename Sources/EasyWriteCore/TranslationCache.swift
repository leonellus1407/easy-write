import Foundation

/// The last few translations, so reopening the popover on unchanged text costs nothing.
/// In memory only, capped, and never written anywhere — that is what keeps the promise that
/// translated text is not persisted.
@MainActor
public final class TranslationCache {

    /// Everything that changes the output is part of the key, so editing the style guide or
    /// swapping languages can never be answered with a stale result.
    public struct Key: Hashable {
        public let text: String
        public let sourceCode: String
        public let targetCode: String
        public let styleGuide: String
        /// Two engines word the same sentence differently, so switching between them must not be
        /// answered with the other one's result. The style guide stays in the key even though only
        /// one engine reads it, for the same reason.
        public let engine: Engine

        public init(text: String, sourceCode: String, targetCode: String, styleGuide: String,
                    engine: Engine) {
            self.text = text
            self.sourceCode = sourceCode
            self.targetCode = targetCode
            self.styleGuide = styleGuide
            self.engine = engine
        }
    }

    private let capacity: Int
    /// Oldest use first, so eviction is a `removeFirst()` and a hit is a move to the end.
    private var entries: [(key: Key, value: String)] = []

    public init(capacity: Int = 20) { self.capacity = max(1, capacity) }

    public var count: Int { entries.count }

    public func value(for key: Key) -> String? {
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
        let entry = entries.remove(at: index)
        entries.append(entry)
        return entry.value
    }

    public func store(_ value: String, for key: Key) {
        entries.removeAll { $0.key == key }
        entries.append((key, value))
        while entries.count > capacity { entries.removeFirst() }
    }

    public func remove(_ key: Key) {
        entries.removeAll { $0.key == key }
    }
}
