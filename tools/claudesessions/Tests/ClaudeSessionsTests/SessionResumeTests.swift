import XCTest
@testable import ClaudeSessions

final class SessionResumeTests: XCTestCase {
    private func session(cwd: String, cliSessionId: String?, id: String) -> Session {
        Session(
            id: id,
            cliSessionId: cliSessionId,
            store: .personal,
            title: "t",
            cwd: cwd,
            project: SessionLoader.projectFor(cwd: cwd),
            branch: nil,
            worktreeName: nil,
            archived: false,
            lastFocusedAt: nil,
            lastActivityAt: nil,
            createdAt: nil,
            path: URL(fileURLWithPath: "/tmp/local_\(id).json")
        )
    }

    /// Regression: a deleted worktree cwd must not stop `claude` from running.
    /// The command recreates the directory (`mkdir -p`) before `cd`, because
    /// `claude --resume <id>` locates the transcript purely by the encoded cwd path.
    func testResumeCommandRecreatesCwdBeforeResuming() {
        let s = session(
            cwd: "/Users/me/proj/.claude/worktrees/gone-abc123",
            cliSessionId: "0ae28d24-4ee9-4c30-a375-3f81ce85cb31",
            id: "local_x"
        )
        let cmd = SessionResume().resumeCommand(for: s)
        XCTAssertEqual(
            cmd,
            "mkdir -p '/Users/me/proj/.claude/worktrees/gone-abc123' && "
            + "cd '/Users/me/proj/.claude/worktrees/gone-abc123' && "
            + "claude --resume '0ae28d24-4ee9-4c30-a375-3f81ce85cb31'"
        )
    }

    /// `mkdir -p` must precede `cd` so the `cd` cannot fail on a missing directory.
    func testMkdirPrecedesCd() {
        let s = session(cwd: "/a/b", cliSessionId: "sid", id: "local_x")
        let cmd = SessionResume().resumeCommand(for: s)
        guard let mkdirRange = cmd.range(of: "mkdir -p"),
              let cdRange = cmd.range(of: "&& cd ") else {
            return XCTFail("command missing mkdir/cd: \(cmd)")
        }
        XCTAssertTrue(mkdirRange.lowerBound < cdRange.lowerBound)
    }

    /// Falls back to the desktop id when no cliSessionId is recorded (`resumeId`).
    func testUsesDesktopIdWhenNoCliSessionId() {
        let s = session(cwd: "/a/b", cliSessionId: nil, id: "local_fallback")
        XCTAssertTrue(SessionResume().resumeCommand(for: s).hasSuffix("claude --resume 'local_fallback'"))
    }

    /// Single quotes in a path are escaped so the shell command stays well-formed.
    func testEscapesSingleQuotesInCwd() {
        let s = session(cwd: "/a/it's here", cliSessionId: "sid", id: "local_x")
        let cmd = SessionResume().resumeCommand(for: s)
        XCTAssertTrue(cmd.contains("'/a/it'\\''s here'"), "unexpected escaping: \(cmd)")
    }
}
