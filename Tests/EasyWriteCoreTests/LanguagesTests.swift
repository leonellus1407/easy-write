import EasyWriteCore
import Testing

@Test("given a target language code, when looked up, then it resolves to that language or falls back to German")
func languageLookupResolvesKnownCodesAndFallsBack() {
    #expect(Languages.named("ru").name == "Russian")

    // Store returns whatever is in UserDefaults, which can be a code this build no longer ships
    // or an empty string. Both must degrade to the first language rather than trap.
    #expect(Languages.named("xx").code == "de")
    #expect(Languages.named("").code == "de")

    // Every language must stay reachable by its own code. A duplicate code would silently shadow
    // an entry here, and would also break SwiftUI's identity in the language pickers, which key
    // their lists on `Lang.id`.
    for language in Languages.all {
        #expect(Languages.named(language.code).name == language.name,
                "\(language.code) does not resolve to its own entry")
    }
}

@Test("given the auto sentinel, when the language lists are built, then it can be a source but never a target")
func autoDetectIsASourceOnly() {
    #expect(Languages.sources.first?.code == Languages.auto.code)
    #expect(Languages.sources.count == Languages.all.count + 1)
    #expect(!Languages.all.contains { $0.code == Languages.auto.code })

    // The popover stores the source code like any other, so reading it back has to return the
    // sentinel rather than falling through to German the way an unknown target code does.
    #expect(Languages.source(Languages.auto.code).code == "auto")
    #expect(Languages.source("fr").name == "French")
    #expect(Languages.named(Languages.auto.code).code == "de")
}
