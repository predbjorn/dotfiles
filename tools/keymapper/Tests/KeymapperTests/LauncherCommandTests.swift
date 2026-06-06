import XCTest
@testable import Keymapper

final class LauncherCommandTests: XCTestCase {
    func testParsesToggleAppCommand() {
        let a = LauncherCommand.parse("$HOME/.dotfiles/bin/toggle_app.sh Safari")
        XCTAssertEqual(a?.mechanism, .toggle)
        XCTAssertEqual(a?.target, "Safari")
    }

    func testParsesFocusWrapperWithQuotedAppAndFlag() {
        let a = LauncherCommand.parse(#"~/.dotfiles/bin/focus_window_wrapper.sh "Google Chrome" true"#)
        XCTAssertEqual(a?.mechanism, .focus)
        XCTAssertEqual(a?.target, "Google Chrome")
        XCTAssertEqual(a?.focusBringToCurrent, true)
    }

    func testParsesOpenFolder() {
        let a = LauncherCommand.parse("open ~/Downloads")
        XCTAssertEqual(a?.mechanism, .open)
        XCTAssertEqual(a?.target, "~/Downloads")
    }

    func testNonLauncherCommandReturnsNil() {
        XCTAssertNil(LauncherCommand.parse("yabai -m space --create && echo hi"))
    }

    func testRenderRoundTripsToggle() {
        let a = LauncherAction(mechanism: .toggle, target: "Safari", focusBringToCurrent: false,
                               rawCommand: "$HOME/.dotfiles/bin/toggle_app.sh Safari")
        XCTAssertEqual(LauncherCommand.render(a), "$HOME/.dotfiles/bin/toggle_app.sh Safari")
    }

    func testRenderQuotesAppWithSpaces() {
        let a = LauncherAction(mechanism: .focus, target: "Google Chrome", focusBringToCurrent: true,
                               rawCommand: "")
        XCTAssertEqual(LauncherCommand.render(a),
                       "$HOME/.dotfiles/bin/focus_window_wrapper.sh 'Google Chrome' true")
    }

    func testRenderNeutralizesInjection() {
        let a = LauncherAction(mechanism: .toggle, target: "evil; rm -rf ~", focusBringToCurrent: false,
                               rawCommand: "")
        XCTAssertEqual(LauncherCommand.render(a),
                       "$HOME/.dotfiles/bin/toggle_app.sh 'evil; rm -rf ~'")
    }
}
