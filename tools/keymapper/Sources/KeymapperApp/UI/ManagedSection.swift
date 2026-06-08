import SwiftUI
import Keymapper

// MARK: - ManagedSection

/// The editable list of managed launcher bindings (D30). Karabiner and skhd bindings are shown
/// in a unified list — the dual-file mechanism is hidden from the user (D33).
struct ManagedSection: View {
    @ObservedObject var vm: KeymapperViewModel
    @State private var editingBinding: KeymapBinding? = nil
    @State private var showAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if vm.editedManaged.isEmpty {
                emptyState
            } else {
                ForEach(vm.editedManaged.indices, id: \.self) { idx in
                    let b = vm.editedManaged[idx]
                    ManagedRow(binding: b, conflicted: isConflicted(b)) {
                        editingBinding = KeymapBinding(b)
                    }
                    if idx < vm.editedManaged.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            addButton
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .sheet(item: $editingBinding) { item in
            BindingEditSheet(binding: item.binding, isNew: false) { updated in
                vm.updateBinding(updated)
                editingBinding = nil
            } onCancel: {
                editingBinding = nil
            } onDelete: {
                if let idx = vm.editedManaged.firstIndex(where: {
                    $0.chord == item.binding.chord && $0.source == item.binding.source
                }) {
                    vm.removeBinding(at: IndexSet(integer: idx))
                }
                editingBinding = nil
            }
        }
        .sheet(isPresented: $showAddSheet) {
            BindingEditSheet(
                binding: Keymapper.Binding(
                    chord: Chord(layer: .skhdModifier, modifiers: ["hyper"], key: ""),
                    source: .skhd, managed: true, launcher: nil, rawText: "", displayName: ""
                ),
                isNew: true
            ) { newBinding in
                vm.addBinding(newBinding)
                showAddSheet = false
            } onCancel: {
                showAddSheet = false
            } onDelete: {
                showAddSheet = false
            }
        }
    }

    private var emptyState: some View {
        Text("No managed bindings yet. Tap + to add one.")
            .foregroundStyle(.secondary)
            .padding()
    }

    private var addButton: some View {
        Button {
            showAddSheet = true
        } label: {
            Label("Add binding", systemImage: "plus")
                .font(.callout)
        }
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func isConflicted(_ b: Keymapper.Binding) -> Bool {
        let conflicts = vm.keymap?.conflicts ?? []
        return conflicts.contains { $0.chord == b.chord }
    }
}

// MARK: - KeymapBinding (Identifiable wrapper for sheet(item:))

/// Identifiable wrapper around `Keymapper.Binding` so `sheet(item:)` works.
/// (Keymapper.Binding cannot be made Identifiable in the library target without adding AppKit/SwiftUI dependency.)
struct KeymapBinding: Identifiable {
    let id: String
    let binding: Keymapper.Binding

    init(_ b: Keymapper.Binding) {
        self.id = b.chord.canonical + b.source.rawValue
        self.binding = b
    }
}

// MARK: - ManagedRow

struct ManagedRow: View {
    let binding: Keymapper.Binding
    let conflicted: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if conflicted {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                Text(chordLabel)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Image(systemName: "arrow.right").foregroundStyle(.secondary).font(.caption)
                VStack(alignment: .leading, spacing: 2) {
                    Text(binding.displayName).font(.body)
                    Text(mechanismLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var chordLabel: String {
        switch binding.chord.layer {
        case .spaceLeader: return "space \(binding.chord.key)"
        case .spaceFLeader: return "space f \(binding.chord.key)"
        case .karabinerModifier, .skhdModifier: return SkhdChord.render(binding.chord)
        }
    }

    private var mechanismLabel: String {
        switch binding.launcher?.mechanism {
        case .toggle: return "toggle"
        case .focus: return "focus"
        case .open: return "open folder"
        case nil: return "custom"
        }
    }
}

// MARK: - BindingEditSheet

/// Edit or add a single managed binding. Shows chord (read-only for existing, editable for new)
/// and editable target + mechanism.
struct BindingEditSheet: View {
    let binding: Keymapper.Binding
    let isNew: Bool
    let onSave: (Keymapper.Binding) -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    @State private var targetText: String
    @State private var mechanism: LauncherMechanism
    @State private var keyText: String
    @State private var bringToCurrent: Bool

    init(binding: Keymapper.Binding, isNew: Bool,
         onSave: @escaping (Keymapper.Binding) -> Void,
         onCancel: @escaping () -> Void,
         onDelete: @escaping () -> Void) {
        self.binding = binding
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
        _targetText = State(initialValue: binding.launcher?.target ?? "")
        _mechanism = State(initialValue: binding.launcher?.mechanism ?? .toggle)
        _keyText = State(initialValue: binding.chord.key)
        _bringToCurrent = State(initialValue: binding.launcher?.focusBringToCurrent ?? false)
    }

    private var isValid: Bool {
        !targetText.trimmingCharacters(in: .whitespaces).isEmpty &&
        (isNew ? !keyText.trimmingCharacters(in: .whitespaces).isEmpty : true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isNew ? "Add Binding" : "Edit Binding")
                .font(.title2.bold())

            if isNew {
                LabeledContent("Layer") {
                    Text("hyper (skhd modifier)").foregroundStyle(.secondary)
                }
                LabeledContent("Key") {
                    TextField("e.g. m", text: $keyText)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                LabeledContent("Chord") {
                    Text(chordLabel).font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("Mechanism") {
                Picker("", selection: $mechanism) {
                    Text("Toggle app").tag(LauncherMechanism.toggle)
                    Text("Focus app").tag(LauncherMechanism.focus)
                    Text("Open folder").tag(LauncherMechanism.open)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }

            LabeledContent(mechanism == .open ? "Path" : "App name") {
                TextField(mechanism == .open ? "~/Downloads" : "Safari", text: $targetText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
            }

            if mechanism == .focus {
                LabeledContent("Bring to current space") {
                    Toggle("", isOn: $bringToCurrent).labelsHidden()
                }
            }

            Divider()

            HStack {
                if !isNew {
                    Button("Delete", role: .destructive, action: onDelete)
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save") { onSave(buildBinding()) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private var chordLabel: String {
        switch binding.chord.layer {
        case .spaceLeader: return "space \(binding.chord.key)"
        case .spaceFLeader: return "space f \(binding.chord.key)"
        case .karabinerModifier, .skhdModifier: return SkhdChord.render(binding.chord)
        }
    }

    private func buildBinding() -> Keymapper.Binding {
        let target = targetText.trimmingCharacters(in: .whitespaces)
        let action = LauncherAction(mechanism: mechanism, target: target,
                                    focusBringToCurrent: bringToCurrent, rawCommand: "")
        let chord = isNew
            ? Chord(layer: .skhdModifier, modifiers: ["hyper"],
                    key: keyText.trimmingCharacters(in: .whitespaces).lowercased())
            : binding.chord
        return Keymapper.Binding(
            chord: chord, source: isNew ? .skhd : binding.source,
            managed: true, launcher: action,
            rawText: LauncherCommand.render(action),
            displayName: target
        )
    }
}
