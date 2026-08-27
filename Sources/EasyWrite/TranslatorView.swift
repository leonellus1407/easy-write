import EasyWriteCore
import SwiftUI

/// The popover's content: pick the two languages, edit the source text on the left, read the
/// translation as it streams in on the right.
struct TranslatorView: View {
    @ObservedObject var model: TranslatorModel
    @Binding var launchesAtLogin: Bool
    let onPreferences: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            languageRow
            HStack(spacing: 10) {
                inputPane
                outputPane
            }
            footer
        }
        .padding(14)
        .frame(width: 620, height: 340)
    }

    private var languageRow: some View {
        HStack(spacing: 8) {
            Picker("Source language", selection: $model.sourceCode) {
                ForEach(Languages.sources) { Text($0.name).tag($0.code) }
            }
            .labelsHidden()

            Button(action: model.swap) {
                Image(systemName: "arrow.left.arrow.right")
            }
            .disabled(!model.canSwap)
            .help(model.canSwap
                  ? "Swap the two languages"
                  : "Pick a source language to swap")

            Picker("Target language", selection: $model.targetCode) {
                ForEach(Languages.all) { Text($0.name).tag($0.code) }
            }
            .labelsHidden()

            Spacer()
            gearMenu
        }
    }

    private var gearMenu: some View {
        Menu {
            Text("Easy Write \(appVersion)")
            Divider()
            Button("Preferences…", action: onPreferences)
            Toggle("Launch at login", isOn: $launchesAtLogin)
            Divider()
            Button("Quit Easy Write", action: onQuit)
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Settings")
    }

    private var inputPane: some View {
        TextEditor(text: $model.input)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(pane)
    }

    private var outputPane: some View {
        ScrollView {
            Text(model.failure ?? model.output)
                .font(.body)
                .foregroundStyle(model.failure == nil ? .primary : .secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pane)
        .overlay(alignment: .topTrailing) {
            if model.isTranslating {
                ProgressView().controlSize(.small).padding(10)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Retranslate", action: model.retranslate)
                .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Copy", action: model.copyOutput)
                .disabled(model.output.isEmpty)
        }
    }

    private var pane: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
    }
}
