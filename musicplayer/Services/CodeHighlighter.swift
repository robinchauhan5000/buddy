import Foundation
import Highlightr

/// Static helper to syntax-highlight code using [Highlightr](https://github.com/raspu/Highlightr).
/// Parses language from content (e.g. ```golang\ncode```) or uses explicit language, then highlights.
enum CodeHighlighter {

    private static let shared: Highlightr? = {
        let h = Highlightr()
        h?.setTheme(to: "paraiso-dark")
        return h
    }()

    /// Map common language names / API values to Highlightr (highlight.js) language IDs.
    private static let languageMap: [String: String] = [
        "golang": "go",
        "go": "go",
        "swift": "swift",
        "python": "python",
        "py": "python",
        "javascript": "javascript",
        "js": "javascript",
        "typescript": "typescript",
        "ts": "typescript",
        "java": "java",
        "kotlin": "kotlin",
        "cpp": "cpp",
        "c++": "cpp",
        "c": "c",
        "csharp": "csharp",
        "c#": "csharp",
        "ruby": "ruby",
        "rb": "ruby",
        "php": "php",
        "rust": "rust",
        "rs": "rust",
        "scala": "scala",
        "sql": "sql",
        "bash": "bash",
        "shell": "bash",
        "sh": "bash",
        "yaml": "yaml",
        "yml": "yaml",
        "json": "json",
        "html": "xml",
        "css": "css",
    ]

    /// Normalize language to Highlightr language ID (lowercased, mapped).
    private static func normalizeLanguage(_ raw: String?) -> String? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        let lower = raw.lowercased().trimmingCharacters(in: .whitespaces)
        return languageMap[lower] ?? lower
    }

    /// Parse optional markdown-style code fence from content: ```lang\n or ```\n
    /// Returns (code, language): extracted code and optional language. Language may come from fence or be nil.
    private static func parseCodeFence(_ content: String) -> (code: String, language: String?) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let fence = "```"
        guard trimmed.hasPrefix(fence) else {
            return (content, nil)
        }
        let afterFence = trimmed.dropFirst(fence.count)
        let lineEnd = afterFence.firstIndex(where: { $0 == "\n" || $0 == "\r" })
        let firstLine: Substring
        let codeStart: String.Index
        if let end = lineEnd {
            firstLine = afterFence[..<end]
            codeStart = afterFence.index(after: end)
        } else {
            firstLine = afterFence
            codeStart = afterFence.endIndex
        }
        let lang = String(firstLine).trimmingCharacters(in: .whitespaces)
        let rest = String(afterFence[codeStart...])
        let codeEnd = rest.range(of: fence, options: .backwards)
        let code = codeEnd.map { String(rest[..<$0.lowerBound]) } ?? rest
        return (code.trimmingCharacters(in: .whitespacesAndNewlines), lang.isEmpty ? nil : lang)
    }

    /// Strip leaked protocol tag fragments (e.g. </SECTION>, </) that can break highlighting.
    private static func stripLeakedTags(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasSuffix("</SECTION") || t.hasSuffix("</SECTION>") || t.hasSuffix("</") {
            if t.hasSuffix("</SECTION>") { t = String(t.dropLast(11)) }
            else if t.hasSuffix("</SECTION") { t = String(t.dropLast(9)) }
            else if t.hasSuffix("</") { t = String(t.dropLast(2)) }
            t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t
    }

    /// Highlight code with dynamic language detection.
    /// - Parameters:
    ///   - content: Raw content (may include ```language\n...\n``` or plain code).
    ///   - explicitLanguage: Optional language from section (e.g. "go", "golang").
    /// - Returns: Highlighted `NSAttributedString`, or nil to fall back to plain text.
    static func highlight(content: String, explicitLanguage: String? = nil) -> NSAttributedString? {
        let sanitized = stripLeakedTags(content)
        let (code, parsedLang) = parseCodeFence(sanitized)
        let effectiveLang = explicitLanguage ?? parsedLang
        let lang = normalizeLanguage(effectiveLang) ?? effectiveLang?.lowercased()
        guard let highlightr = shared else { return nil }
        if let lang = lang, !lang.isEmpty {
            return highlightr.highlight(code, as: lang)
        }
        return highlightr.highlight(code)
    }

    /// Parse and return the language label from content (e.g. from ```golang) for display. Returns nil if none.
    static func parseLanguage(from content: String) -> String? {
        parseCodeFence(content).language
    }
}
