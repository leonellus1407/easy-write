import EasyWriteCore
import Testing

@Test("given a target language code, when looked up, then it resolves to that language or falls back to German")
func languageLookupResolvesKnownCodesAndFallsBack() {
    // A known code has to return the whole record, not just a matching name: the menu renders
    // the register hints and the model instruction is built from the same row.
    let russian = Languages.named("ru")
    #expect(russian.name == "Russian")
    #expect(russian.formal == "вы")
    #expect(russian.informal == "ты")

    // Store returns whatever is in UserDefaults, which can be a code this build no longer ships
    // or an empty string. Both must degrade to the first language rather than trap.
    #expect(Languages.named("xx").code == "de")
    #expect(Languages.named("").code == "de")

    // Every language must stay reachable by its own code. A duplicate code would silently shadow
    // an entry here, and would also break SwiftUI's identity in the Preferences picker, which
    // keys the list on `Lang.id`.
    for language in Languages.all {
        #expect(Languages.named(language.code).name == language.name,
                "\(language.code) does not resolve to its own entry")
    }
}
