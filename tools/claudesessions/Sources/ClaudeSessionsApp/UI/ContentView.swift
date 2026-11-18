import SwiftUI
import ClaudeSessions

struct ContentView: View {
    @ObservedObject var vm: SessionsViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            filterBar
            Divider()
            if let err = vm.actionError {
                banner(err) { vm.actionError = nil }
            }
            listBody
            Divider()
            footer
        }
        .frame(minWidth: 820, idealWidth: 980, minHeight: 540, idealHeight: 700)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Claude Sessions").font(.headline)
            Spacer()
            Button {
                vm.reload()
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("Status", selection: $vm.filters.status) {
                ForEach(StatusFilter.allCases, id: \.self) { s in
                    Text(s.displayName).tag(s)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 160)

            Picker("Account", selection: $vm.filters.account) {
                Text("All").tag(AccountFilter.all)
                ForEach(SessionStore.allCases, id: \.self) { s in
                    Text(s.displayName).tag(AccountFilter.store(s))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 170)

            Picker("Project", selection: $vm.filters.project) {
                Text("All projects").tag(String?.none)
                ForEach(vm.allProjects, id: \.self) { p in
                    Text(shortName(p)).tag(String?.some(p))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 260)

            Picker("Group", selection: $vm.filters.groupMode) {
                ForEach(GroupMode.allCases, id: \.self) { m in
                    Text(m.displayName).tag(m)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 160)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search title or path", text: $vm.filters.search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var listBody: some View {
        ScrollView {
            switch vm.filters.groupMode {
            case .byProject:
                groupedList
            case .flat:
                flatList
            }
        }
    }

    private var groupedList: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(vm.grouped, id: \.project) { group in
                Section(header: projectHeader(group.project, count: group.sessions.count)) {
                    ForEach(group.sessions) { s in
                        SessionRow(
                            session: s,
                            onResume: { vm.resume(s) },
                            onToggleArchived: { vm.setArchived(s, archived: !s.archived) }
                        )
                        Divider().padding(.leading, 14)
                    }
                }
            }
        }
        .padding(.bottom, 12)
    }

    private var flatList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(vm.filtered) { s in
                SessionRow(
                    session: s,
                    showProject: true,
                    onResume: { vm.resume(s) },
                    onToggleArchived: { vm.setArchived(s, archived: !s.archived) }
                )
                Divider().padding(.leading, 14)
            }
        }
        .padding(.bottom, 12)
    }

    private func projectHeader(_ project: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(shortName(project))
                .font(.subheadline.weight(.semibold))
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.15), in: Capsule())
            Spacer()
            Text(project)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("\(vm.filtered.count) of \(vm.sessions.count) sessions")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if vm.filters.search.isEmpty == false
                || vm.filters.project != nil
                || vm.filters.status != .active
                || vm.filters.account != .all {
                Button("Clear filters") {
                    vm.filters = .initial
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func banner(_ text: String, dismiss: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(text).font(.subheadline)
            Spacer()
            Button("Dismiss", action: dismiss)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.1))
    }

    private func shortName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}
