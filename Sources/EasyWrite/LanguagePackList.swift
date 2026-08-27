import EasyWriteCore
import SwiftUI
import Translation

/// The Apple Translate language list in Preferences: what each language can do against the current
/// target, and the one route the framework offers for downloading a pack that is missing.
struct LanguagePackList: View {
    let targetCode: String

    @State private var rows: [Row] = []
    @State private var download: TranslationSession.Configuration?
    @State private var downloadsRefused = false

    private struct Row: Identifiable {
        let id: String
        let name: String
        let status: LanguageAvailability.Status
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            caption("Status of each language translated into \(Languages.name(of: targetCode)). "
                  + "macOS downloads a pack the first time a pair is used.")
            if downloadsRefused {
                caption("macOS won’t let Easy Write ask for a download right now. Add the language "
                      + "in the Translate app instead.")
            }
            ForEach(rows) { row in
                HStack {
                    Text(row.name)
                    Spacer()
                    control(for: row)
                }
            }
        }
        // `init(installedSource:)` refuses a pair that is not installed, so a download cannot be
        // started from plain code in exactly the case where it is needed. This is the way in.
        .translationTask(download) { session in
            guard session.canRequestDownloads else {
                await MainActor.run { downloadsRefused = true }
                return
            }
            try? await session.prepareTranslation()
            await load()
        }
        .task(id: targetCode) { await load() }
    }

    @ViewBuilder private func control(for row: Row) -> some View {
        switch row.status {
        case .installed:   caption("Downloaded")
        case .supported:   Button("Download") { startDownload(for: row.id) }
        case .unsupported: caption("Not supported")
        @unknown default:  caption("Unknown")
        }
    }

    private func startDownload(for code: String) {
        var configuration = TranslationSession.Configuration(source: LanguagePacks.language(code),
                                                             target: LanguagePacks.language(targetCode))
        // A configuration equal to the last one would not run the task again, so a second attempt
        // at the same pair needs its version bumped.
        if download == configuration { configuration.invalidate() }
        download = configuration
    }

    @MainActor private func load() async {
        var loaded: [Row] = []
        for language in Languages.all where language.code != targetCode {
            loaded.append(Row(id: language.code, name: language.name,
                              status: await LanguagePacks.status(from: language.code,
                                                                 to: targetCode)))
        }
        rows = loaded
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}
