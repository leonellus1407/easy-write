import EasyWriteCore
import Testing

@MainActor
struct TranslationCacheTests {

    private func key(_ text: String, source: String = "auto", target: String = "de",
                     styleGuide: String = "") -> TranslationCache.Key {
        .init(text: text, sourceCode: source, targetCode: target, styleGuide: styleGuide)
    }

    @Test("given a stored translation, when the same request arrives again, then the cached text comes back")
    func aRepeatedRequestHits() {
        let cache = TranslationCache()
        cache.store("Guten Morgen", for: key("Good morning"))
        #expect(cache.value(for: key("Good morning")) == "Guten Morgen")
        #expect(cache.value(for: key("Good evening")) == nil)
    }

    @Test("given a stored translation, when anything that shapes the output differs, then the request misses")
    func everyInputIsPartOfTheKey() {
        let cache = TranslationCache()
        cache.store("Guten Morgen", for: key("Good morning"))

        // Editing the style guide has to invalidate the entry, or the user would keep seeing a
        // result produced under their old instructions.
        #expect(cache.value(for: key("Good morning", styleGuide: "Be brief.")) == nil)
        #expect(cache.value(for: key("Good morning", source: "en")) == nil)
        #expect(cache.value(for: key("Good morning", target: "fr")) == nil)
    }

    @Test("given a full cache, when one more translation is stored, then the least recently used one is dropped")
    func overflowEvictsTheLeastRecentlyUsed() {
        let cache = TranslationCache(capacity: 3)
        for text in ["one", "two", "three"] { cache.store(text.uppercased(), for: key(text)) }

        cache.store("FOUR", for: key("four"))

        #expect(cache.count == 3)
        #expect(cache.value(for: key("one")) == nil)
        #expect(cache.value(for: key("two")) == "TWO")
        #expect(cache.value(for: key("four")) == "FOUR")
    }

    @Test("given a full cache, when the oldest entry is read, then the next overflow drops a different one")
    func readingAnEntryMakesItRecent() {
        let cache = TranslationCache(capacity: 3)
        for text in ["one", "two", "three"] { cache.store(text.uppercased(), for: key(text)) }

        #expect(cache.value(for: key("one")) == "ONE")
        cache.store("FOUR", for: key("four"))

        #expect(cache.value(for: key("one")) == "ONE")
        #expect(cache.value(for: key("two")) == nil)
    }

    @Test("given a cached translation, when it is removed, then the same request misses")
    func removeForcesAFreshRun() {
        let cache = TranslationCache()
        cache.store("Guten Morgen", for: key("Good morning"))

        cache.remove(key("Good morning"))

        #expect(cache.value(for: key("Good morning")) == nil)
        #expect(cache.count == 0)
    }

    @Test("given a cached translation, when the same request is stored again, then it replaces rather than duplicates")
    func storingTwiceKeepsOneEntry() {
        let cache = TranslationCache()
        cache.store("Guten Morgen", for: key("Good morning"))
        cache.store("Guten Tag", for: key("Good morning"))

        #expect(cache.count == 1)
        #expect(cache.value(for: key("Good morning")) == "Guten Tag")
    }
}
