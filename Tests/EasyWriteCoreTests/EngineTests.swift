import EasyWriteCore
import Testing

struct EngineTests {

    @Test("given a fresh install, when no engine has been chosen, then Apple Intelligence is used")
    func theDefaultIsAppleIntelligence() {
        #expect(Engine.named("") == .intelligence)
    }

    @Test("given a value written by a later build, when it is resolved, then it falls back rather than failing")
    func anUnknownValueFallsBack() {
        #expect(Engine.named("something-newer") == .intelligence)
    }

    @Test("given a stored choice, when it is read back, then the same engine comes out")
    func everyEngineSurvivesARoundTrip() {
        // These strings sit in user defaults, so renaming one would silently reset the user's
        // choice on upgrade. Pinning them is what stops that being a quiet change.
        #expect(Engine.intelligence.rawValue == "intelligence")
        #expect(Engine.translate.rawValue == "translate")
        for engine in Engine.allCases {
            #expect(Engine.named(engine.rawValue) == engine)
        }
    }

    @Test("given the engine picker, when it is built, then every engine says what it is and what it costs")
    func everyEngineExplainsItself() {
        for engine in Engine.allCases {
            #expect(!engine.title.isEmpty)
            #expect(!engine.caption.isEmpty)
        }
        #expect(Set(Engine.allCases.map(\.title)).count == Engine.allCases.count)
    }
}
