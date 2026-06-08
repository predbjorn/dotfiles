import XCTest
@testable import LaunchDashboard

final class IngressConfigParserTests: XCTestCase {
    // Mirrors the real config.yml shape: active host rules, one disabled rule, catch-all.
    let sample = """
    tunnel: d21fa304
    ingress:
      # nors ai-daemon dashboard (always-on)
      - hostname: daemon.prebenhafnor.com
        service: http://localhost:8787
      - hostname: local3000.prebenhafnor.com
        service: http://localhost:3000
      # - hostname: local8001.prebenhafnor.com
        # service: http://localhost:8001
      - service: http_status:404
    """

    func testParseFindsHostRulesWithEnabledState() {
        let rules = IngressConfigParser.parse(sample)
        let hosts = rules.filter { $0.hostname != nil }
        XCTAssertEqual(hosts.map { $0.hostname }, [
            "daemon.prebenhafnor.com", "local3000.prebenhafnor.com", "local8001.prebenhafnor.com"
        ])
        XCTAssertEqual(rules.first { $0.hostname == "daemon.prebenhafnor.com" }?.enabled, true)
        XCTAssertEqual(rules.first { $0.hostname == "daemon.prebenhafnor.com" }?.service, "http://localhost:8787")
        XCTAssertEqual(rules.first { $0.hostname == "local8001.prebenhafnor.com" }?.enabled, false)
    }

    func testParseMarksCatchAll() {
        let rules = IngressConfigParser.parse(sample)
        let catchAll = rules.first { $0.isCatchAll }
        XCTAssertNotNil(catchAll)
        XCTAssertNil(catchAll?.hostname)
        XCTAssertEqual(catchAll?.service, "http_status:404")
    }

    func testParseHostRuleWithoutServiceDoesNotSwallowNextRule() {
        let text = """
        ingress:
          - hostname: broken.example.com
          - hostname: good.example.com
            service: http://localhost:1234
          - service: http_status:404
        """
        let rules = IngressConfigParser.parse(text)
        // The malformed first rule must not consume the following rule.
        XCTAssertEqual(rules.first { $0.hostname == "broken.example.com" }?.service, "")
        XCTAssertEqual(rules.first { $0.hostname == "good.example.com" }?.service, "http://localhost:1234")
        XCTAssertNotNil(rules.first { $0.isCatchAll })
    }

    func testToggleDisablesAnActiveRule() {
        let out = IngressConfigParser.toggle(sample, hostname: "local3000.prebenhafnor.com")
        let rule = IngressConfigParser.parse(out).first { $0.hostname == "local3000.prebenhafnor.com" }
        XCTAssertEqual(rule?.enabled, false)
        // Untouched rules keep their state.
        XCTAssertEqual(IngressConfigParser.parse(out).first { $0.hostname == "daemon.prebenhafnor.com" }?.enabled, true)
    }

    func testToggleEnablesADisabledRule() {
        let out = IngressConfigParser.toggle(sample, hostname: "local8001.prebenhafnor.com")
        let rule = IngressConfigParser.parse(out).first { $0.hostname == "local8001.prebenhafnor.com" }
        XCTAssertEqual(rule?.enabled, true)
    }

    func testToggleRoundTripIsIdentity() {
        let off = IngressConfigParser.toggle(sample, hostname: "local3000.prebenhafnor.com")
        let backOn = IngressConfigParser.toggle(off, hostname: "local3000.prebenhafnor.com")
        XCTAssertEqual(backOn, sample)  // byte-identical after off→on
    }

    func testToggleNeverTouchesCatchAll() {
        let out = IngressConfigParser.toggle(sample, hostname: "http_status:404")
        XCTAssertEqual(out, sample)  // no host rule matches; no-op
        XCTAssertEqual(IngressConfigParser.parse(out).first { $0.isCatchAll }?.enabled, true)
    }
}
