import AppKit
import SwiftUI
import Keymapper

struct CheatsheetPanel: View {
    @ObservedObject var vm: KeymapperViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var markdown: String {
        guard let km = vm.keymap else { return "No keymap loaded." }
        return Cheatsheet.markdown(bindings: km.bindings, conflicts: km.conflicts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar.
            HStack {
                Text("Keymap Cheatsheet").font(.headline)
                Spacer()
                Button(copied ? "Copied!" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                .buttonStyle(.bordered)
                Button("Save\u{2026}") {
                    saveMarkdown()
                }
                .buttonStyle(.bordered)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Scrollable markdown preview.
            ScrollView {
                Text(markdown)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(width: 560, height: 480)
    }

    private func saveMarkdown() {
        let panel = NSSavePanel()
        panel.title = "Save Cheatsheet"
        panel.nameFieldStringValue = "keymap-cheatsheet.md"
        panel.allowedContentTypes = [.text]
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
