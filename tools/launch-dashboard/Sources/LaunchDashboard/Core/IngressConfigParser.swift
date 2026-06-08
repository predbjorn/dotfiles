import Foundation

/// Pure, IO-free parsing/editing of a cloudflared config.yml `ingress:` section.
/// "Off" is represented by commenting a rule's lines; "on" by uncommenting them.
enum IngressConfigParser {

    private struct AnalyzedLine {
        let indent: String     // leading whitespace
        let commented: Bool
        let content: String    // trimmed text after optional leading "# "
    }

    private static func analyze(_ raw: String) -> AnalyzedLine {
        let ws = raw.prefix { $0 == " " || $0 == "\t" }
        var rest = String(raw.dropFirst(ws.count))
        var commented = false
        if rest.first == "#" {
            commented = true
            rest.removeFirst()
            if rest.first == " " { rest.removeFirst() }
        }
        return AnalyzedLine(indent: String(ws), commented: commented,
                            content: rest.trimmingCharacters(in: .whitespaces))
    }

    static func parse(_ text: String) -> [IngressRule] {
        let lines = text.components(separatedBy: "\n")
        var rules: [IngressRule] = []
        var inIngress = false
        var i = 0
        while i < lines.count {
            let ln = analyze(lines[i])
            if !ln.commented && ln.content == "ingress:" { inIngress = true; i += 1; continue }
            // Leaving the ingress block: a new unindented top-level key (e.g. originRequest:).
            if inIngress && !ln.commented && ln.indent.isEmpty
                && ln.content.hasSuffix(":") && !ln.content.hasPrefix("-") {
                inIngress = false
            }
            guard inIngress else { i += 1; continue }

            if ln.content.hasPrefix("- service:") {
                let svc = ln.content.dropFirst("- service:".count).trimmingCharacters(in: .whitespaces)
                rules.append(IngressRule(hostname: nil, service: svc,
                                         enabled: !ln.commented,
                                         isCatchAll: svc.hasPrefix("http_status"),
                                         lineRange: i...i))
                i += 1; continue
            }

            if ln.content.hasPrefix("- hostname:") {
                let host = ln.content.dropFirst("- hostname:".count).trimmingCharacters(in: .whitespaces)
                var j = i + 1
                var svc = ""
                var svcCommented = ln.commented
                var serviceLine: Int? = nil
                while j < lines.count {
                    let nx = analyze(lines[j])
                    if nx.content.hasPrefix("service:") {
                        svc = nx.content.dropFirst("service:".count).trimmingCharacters(in: .whitespaces)
                        svcCommented = nx.commented
                        serviceLine = j
                        break
                    }
                    if nx.content.hasPrefix("- ") { break }  // next rule began; this rule has no service
                    j += 1
                }
                let end = serviceLine ?? i   // no service found → rule spans only the hostname line
                rules.append(IngressRule(hostname: host, service: svc,
                                         enabled: !ln.commented && !svcCommented,
                                         isCatchAll: false,
                                         lineRange: i...end))
                i = end + 1                  // resume after the rule's real last line (never skips the next rule)
                continue
            }
            i += 1
        }
        return rules
    }
}
