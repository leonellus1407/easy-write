import EasyWriteCore
import Foundation
import NaturalLanguage
import Translation

/// Everything the app asks about Apple Translate's languages: what a piece of text is, whether a
/// pair can run, and what to say when it cannot. Keeping the three together is what stops
/// availability logic spreading between the engine and Preferences.
@MainActor
enum LanguagePacks {
    private static let availability = LanguageAvailability()

    /// Our codes go straight in. Measured against `supportedLanguages` on macOS 26.6: the
    /// framework ships thirty-eight regional variants, and `Locale.Language` resolves a bare "de",
    /// "zh" or "ar" to the right one, so the thirteen codes need no table of their own.
    static func language(_ code: String) -> Locale.Language { .init(identifier: code) }

    /// Best guess at what the text is, for auto-detect. Nil when the recogniser will not commit —
    /// and note that it can be confidently wrong on the short input the popover often holds.
    static func detect(_ text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return nil }
        return language.rawValue.isEmpty ? nil : .init(identifier: language.rawValue)
    }

    /// `.installed` runs now, `.supported` needs a download first, `.unsupported` never runs.
    static func status(from source: String, to target: String) async -> LanguageAvailability.Status {
        await availability.status(from: language(source), to: language(target))
    }

    /// Apple Translate needs a source language; only the model can be told to work one out. So
    /// auto-detect runs the recogniser first, and says so when it will not commit.
    static func source(_ source: Lang, of text: String, to target: Lang) throws -> String {
        guard source.code == Languages.auto.code else { return source.code }
        guard let detected = detect(text)?.languageCode?.identifier else {
            throw failure(TranslationError.unableToIdentifyLanguage,
                          from: source.code, to: target.code)
        }
        return detected
    }

    /// Turns a framework error into something the user can act on. A timeout or a cancellation is
    /// handed back untouched: the popover already words those, and a superseded run is not a
    /// failure at all.
    static func failure(_ error: Error, from source: String, to target: String) -> Error {
        let pair = "\(Languages.name(of: source)) → \(Languages.name(of: target))"
        switch error {
        case is TimeoutError, is CancellationError, TranslationError.alreadyCancelled:
            return error
        case TranslationError.notInstalled:
            return explain("\(pair) isn’t downloaded yet. Open Preferences to add it.")
        case TranslationError.unsupportedLanguagePairing:
            return explain("Apple Translate can’t translate \(pair). Switch to Apple Intelligence "
                         + "in Preferences to try this pair.")
        case TranslationError.unsupportedSourceLanguage:
            return explain("Apple Translate doesn’t know \(Languages.name(of: source)). Switch to "
                         + "Apple Intelligence in Preferences to try it.")
        case TranslationError.unsupportedTargetLanguage:
            return explain("Apple Translate doesn’t know \(Languages.name(of: target)). Switch to "
                         + "Apple Intelligence in Preferences to try it.")
        case TranslationError.unableToIdentifyLanguage:
            return explain("Apple Translate couldn’t tell what language this is. Pick the source "
                         + "language instead of Auto-detect.")
        default:
            return explain("Apple Translate couldn’t finish \(pair). Try again.")
        }
    }

    private static func explain(_ message: String) -> EngineFailure { .init(message: message) }
}
