import SwiftUI
import Keymapper

// MARK: - ContentView

struct ContentView: View {
    @ObservedObject var vm: KeymapperViewModel
    @State private var showCheatsheet = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let err = vm.loadError {
                InlineBanner(text: err, style: .error) { vm.loadError = nil }
            }
            if let err = vm.saveError {
                InlineBanner(text: err, style: .error) { vm.saveError = nil }
            }
            if !vm.skhdInSync {
                DriftBanner {
                    do { try vm.makeItLive() }
                    catch { vm.saveError = error.localizedDescription }
                }
            }
            Divider()
            scrollBody
        }
        .frame(minWidth: 680, idealWidth: 820, minHeight: 480, idealHeight: 620)
        // First-run migration sheet (D26). Sheet cannot be dismissed; user must migrate.
        .sheet(isPresented: Binding(get: { vm.needsMigration }, set: { _ in })) {
            MigrationSheet {
                do { try vm.migrate() } catch { vm.saveError = error.localizedDescription }
            }
        }
        // Cheatsheet export sheet (D15).
        .sheet(isPresented: $showCheatsheet) {
            CheatsheetPanel(vm: vm)
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Keymapper").font(.headline)
            Spacer()
            // Conflict badge (D15, D31): shown only when conflicts exist.
            let conflicts = vm.keymap?.conflicts ?? []
            if !conflicts.isEmpty {
                Label("\(conflicts.count) conflict\(conflicts.count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.subheadline.weight(.semibold))
            }
            Button("Cheatsheet") {
                showCheatsheet = true
            }
            .buttonStyle(.bordered)
            Button("Save") {
                vm.saveReportingError()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!vm.isDirty)
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: Scroll body

    private var scrollBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24, pinnedViews: [.sectionHeaders]) {
                Section(header: SectionHeader(title: "Managed", count: vm.editedManaged.count)) {
                    ManagedSection(vm: vm)
                }
                let ref = vm.keymap?.reference ?? []
                Section(header: SectionHeader(title: "Reference (read-only)", count: ref.count)) {
                    ReferenceSection(vm: vm)
                }
            }
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text("\(title)  (\(count))").font(.subheadline.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.thickMaterial)
    }
}

// MARK: - Inline Banner

enum BannerStyle { case error, info }

struct InlineBanner: View {
    let text: String
    let style: BannerStyle
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: style == .error ? "xmark.octagon.fill" : "info.circle.fill")
                .foregroundStyle(style == .error ? Color.red : Color.blue)
            Text(text).font(.callout)
            Spacer()
            Button("Dismiss", action: onDismiss).buttonStyle(.plain).font(.callout)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(style == .error ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
    }
}

// MARK: - Drift Banner (D28)

struct DriftBanner: View {
    let onMakeItLive: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
            Text("skhdrc repo file is ahead of the deployed copy.")
                .font(.callout)
            Spacer()
            Button("Make it live", action: onMakeItLive)
                .buttonStyle(.bordered)
                .font(.callout)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }
}

// MARK: - Migration Sheet (D26)

struct MigrationSheet: View {
    let onMigrate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "wand.and.stars").font(.largeTitle).foregroundColor(.accentColor)
                Text("First-run setup").font(.title2.bold())
            }
            Text("Keymapper found existing launcher bindings in your config files. Tap \"Adopt bindings\" to import them into Keymapper's managed regions. This is a one-time step. A backup of both files is taken first.")
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Spacer()
                Button("Adopt bindings", action: onMigrate)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
