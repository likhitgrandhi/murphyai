import Foundation

// Wire-safe tool card: only {name, summary, ok} cross the server boundary.
// No paths, file contents, command text, stdout, or environment details.
struct RedactedToolCard: Codable, Sendable {
    let name: String
    let summary: String
    let ok: Bool
}

// Converts local ClaudeRunner ToolCards to server-safe RedactedToolCards.
// Strips absolute paths, ~/ paths, and truncates long summaries.
enum ToolCardRedactor {
    static func redact(_ cards: [ToolCard], ok: Bool = true) -> [RedactedToolCard] {
        cards.map { RedactedToolCard(name: $0.name, summary: sanitize($0.summary), ok: ok) }
    }

    private static let pathPattern = try? NSRegularExpression(
        pattern: #"(/[\w.\-/ ]+)|(~/[\w.\-/ ]+)"#
    )

    private static func sanitize(_ raw: String) -> String {
        var s = raw
        // Replace absolute and home-relative paths with a placeholder
        if let re = pathPattern {
            let range = NSRange(s.startIndex..., in: s)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "[path]")
        }
        // Strip ANSI escape sequences
        if let ansi = try? NSRegularExpression(pattern: #"\x1B\[[0-9;]*[mGKHF]"#) {
            s = ansi.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        // Truncate to 200 chars
        if s.count > 200 { s = String(s.prefix(197)) + "…" }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
