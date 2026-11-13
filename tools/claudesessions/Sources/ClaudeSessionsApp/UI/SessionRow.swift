import SwiftUI
import ClaudeSessions

struct SessionRow: View {
    let session: Session
    var showProject: Bool = false
    let onResume: () -> Void
    let onToggleArchived: () -> Void

    @State private var hovering = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(session.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if session.archived {
                        badge("archived", color: .secondary)
                    }
                    if let wt = session.worktreeName {
                        badge(wt, color: .blue)
                    }
                }
                HStack(spacing: 8) {
                    badge(session.store.displayName.lowercased(),
                          color: session.store == .work ? .orange : .purple)
                    if showProject {
                        Text(session.project.split(separator: "/").last.map(String.init) ?? session.project)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if let branch = session.branch {
                        Label(branch, systemImage: "arrow.triangle.branch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(session.cwd)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(Self.formatted(session.bestDate))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Button {
                        onToggleArchived()
                    } label: {
                        Label(
                            session.archived ? "Unarchive" : "Archive",
                            systemImage: session.archived ? "tray.and.arrow.up" : "archivebox"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(session.archived
                        ? "Restore from archive"
                        : "Mark as archived (apps must be closed for the change to stick)")

                    Button {
                        onResume()
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(hovering ? Color.secondary.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Resume in iTerm") { onResume() }
            Button(session.archived ? "Unarchive" : "Archive") { onToggleArchived() }
            Divider()
            Button("Copy CLI session ID") { copyToClipboard(session.resumeId) }
            Button("Copy desktop session ID") { copyToClipboard(session.id) }
            Button("Copy cwd") { copyToClipboard(session.cwd) }
            Button("Copy resume command") {
                copyToClipboard("cd \(shellQuote(session.cwd)) && claude --resume \(shellQuote(session.resumeId))")
            }
            Divider()
            Button("Reveal JSON in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([session.path])
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private static func formatted(_ date: Date?) -> String {
        guard let date else { return "—" }
        return dateFormatter.string(from: date)
    }

    private func copyToClipboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
