import AppKit
import SwiftUI
import Keymapper

// MARK: - ReferenceSection

/// Read-only audit view for all non-managed bindings (D30, D35, D36).
/// Shows the full keymap including opaque yabai pipelines so the user can audit
/// conflicts and navigate to source lines (D29). No structural editing here.
struct ReferenceSection: View {
    @ObservedObject var vm: KeymapperViewModel

    var referenceBindings: [Keymapper.Binding] { vm.keymap?.reference ?? [] }
    var conflicts: [Conflict] { vm.keymap?.conflicts ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // D36: set audit-only expectation up front.
            HStack {
                Image(systemName: "info.circle").foregroundStyle(.secondary).font(.caption)
                Text("Reference bindings are read-only. Use \u{201c}Open in $EDITOR\u{201d} to edit them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)

            if referenceBindings.isEmpty {
                Text("No unmanaged bindings found.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(referenceBindings.indices, id: \.self) { idx in
                    let b = referenceBindings[idx]
                    ReferenceRow(
                        binding: b,
                        conflicted: isConflicted(b),
                        skhdURL: vm.skhdURL
                    )
                    if idx < referenceBindings.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
    }

    private func isConflicted(_ b: Keymapper.Binding) -> Bool {
        conflicts.contains { $0.chord == b.chord }
    }
}

// MARK: - ReferenceRow

struct ReferenceRow: View {
    let binding: Keymapper.Binding
    let conflicted: Bool
    let skhdURL: URL

    var body: some View {
        HStack(spacing: 12) {
            if conflicted {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            Text(chordLabel)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Image(systemName: "arrow.right").foregroundStyle(.secondary).font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(binding.displayName).font(.body).foregroundStyle(.primary)
                Text(sourceLabel).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // Open-in-editor button for skhd bindings (D29).
            if binding.source == .skhd {
                Button {
                    EditorLauncher.open(url: skhdURL, line: binding.sourceLine)
                } label: {
                    Label("Open in $EDITOR", systemImage: "pencil.and.outline")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var chordLabel: String {
        switch binding.chord.layer {
        case .spaceLeader: return "space \(binding.chord.key)"
        case .spaceFLeader: return "space f \(binding.chord.key)"
        case .karabinerModifier, .skhdModifier: return SkhdChord.render(binding.chord)
        }
    }

    private var sourceLabel: String {
        switch binding.source {
        case .karabiner: return "karabiner \u{00b7} read-only"
        case .skhd: return binding.launcher == nil
            ? "skhd \u{00b7} multi-line (audit only)"
            : "skhd \u{00b7} read-only"
        }
    }
}

// MARK: - EditorLauncher (D29)

/// Opens a file in the user's preferred editor, jumping to a specific line when possible.
/// Prefers `$VISUAL` (GUI editors) over `$EDITOR` (often terminal-based).
/// Supports line-jumping for VSCode (`code --goto file:line`).
/// Terminal editors (vim, nvim, etc.) fall back to NSWorkspace.
enum EditorLauncher {
    static func open(url: URL, line: Int?) {
        let env = ProcessInfo.processInfo.environment
        for editorPath in [env["VISUAL"], env["EDITOR"]].compactMap({ $0 }).filter({ !$0.isEmpty }) {
            if tryLaunch(editorPath, url: url, line: line) { return }
        }
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    private static func tryLaunch(_ editor: String, url: URL, line: Int?) -> Bool {
        let name = URL(fileURLWithPath: editor).lastPathComponent
        let args: [String]

        switch name {
        case "code":
            args = line.map { ["--goto", "\(url.path):\($0)"] } ?? [url.path]
        case "vim", "nvim", "vi", "nano", "emacs", "pico":
            // Terminal editors need a terminal; fall back to NSWorkspace.
            return false
        default:
            args = [url.path]
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: editor)
        p.arguments = args
        return (try? p.run()) != nil
    }
}
