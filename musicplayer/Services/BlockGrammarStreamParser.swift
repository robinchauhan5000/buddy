import Foundation

final class BlockGrammarStreamParser {
    private enum State {
        case idle
        case readingTitle
        case readingSectionHeader
        case readingSectionContent
        case readingContext
    }

    private var buffer: String = ""
    private var state: State = .idle
    private var title: String = ""
    private var sections: [MessageSection] = []
    private var currentSectionType: SectionType?
    private var currentSectionLanguage: String?
    private var currentSectionContent: String = ""
    private var parsedContextPayload: String?
    private var contextBuffer: String = ""

    func addChunk(_ chunk: String) -> StreamingResponse? {
        buffer.append(chunk)
        let fromParse = processBuffer()
        if fromParse != nil { return fromParse }
        return partialResponse()
    }

    func finalize() -> StreamingResponse? {
        flushCurrentSection()
        guard !title.isEmpty || !sections.isEmpty else { return nil }
        return StreamingResponse(
            title: title,
            sections: sections,
            isComplete: true,
            contextPayload: parsedContextPayload
        )
    }

    private static let maxProcessIterations = 50

    /// Accepts both "<</TAG>>" and "</TAG>>" so we parse correctly when the model (e.g. Gemini) drops a leading "<".
    private func rangeOfClosingTag(_ tag: String, in buffer: String) -> Range<String.Index>? {
        let doubleAngle = "<</\(tag)>>"
        let singleAngle = "</\(tag)>>"
        let r1 = buffer.range(of: doubleAngle, options: .caseInsensitive)
        let r2 = buffer.range(of: singleAngle, options: .caseInsensitive)
        switch (r1, r2) {
        case let (.some(a), .some(b)):
            return a.lowerBound < b.lowerBound ? a : b
        case (.some(let a), .none), (.none, .some(let a)):
            return a
        case (.none, .none):
            return nil
        }
    }

    /// Section content can end with <</SECTION>>, </SECTION>>, <<END_SECTION>>, or </END_SECTION>>.
    private func rangeOfSectionClosingTag(in buffer: String) -> Range<String.Index>? {
        var earliest: Range<String.Index>?
        if let r = rangeOfClosingTag("SECTION", in: buffer) {
            earliest = r
        }
        for tag in ["<<END_SECTION>>", "</END_SECTION>>"] {
            if let r = buffer.range(of: tag, options: .caseInsensitive) {
                if let e = earliest {
                    if r.lowerBound < e.lowerBound { earliest = r }
                } else {
                    earliest = r
                }
            }
        }
        return earliest
    }

    private func processBuffer() -> StreamingResponse? {
        var yielded: StreamingResponse?
        var iterations = 0
        while iterations < Self.maxProcessIterations {
            iterations += 1
            switch state {
            case .idle:
                if let range = buffer.range(of: "<<TITLE>>", options: .caseInsensitive) {
                    buffer.removeSubrange(range)
                    state = .readingTitle
                } else if let range = buffer.range(of: "<<SECTION:", options: .caseInsensitive) {
                    buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                    state = .readingSectionHeader
                } else if let range = buffer.range(of: "<<CONTEXT>>", options: .caseInsensitive) {
                    buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                    contextBuffer = ""
                    state = .readingContext
                } else {
                    if let idx = buffer.firstIndex(of: "<") {
                        let drop = buffer.distance(from: buffer.startIndex, to: idx)
                        if drop > 0 { buffer.removeFirst(drop) }
                    } else {
                        buffer.removeAll()
                    }
                    break
                }
            case .readingTitle:
                if let range = rangeOfClosingTag("TITLE", in: buffer) {
                    title = String(buffer[..<range.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                    state = .idle
                    yielded = StreamingResponse(title: title, sections: [], isComplete: false)
                } else {
                    yielded = partialResponse()
                    break
                }
            case .readingSectionHeader:
                guard let sectionRange = buffer.range(of: ">>", options: []) else { break }
                let header = String(buffer[..<sectionRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                buffer.removeSubrange(buffer.startIndex..<sectionRange.upperBound)
                parseSectionHeader(header)
                state = .readingSectionContent
                currentSectionContent = ""
            case .readingSectionContent:
                if let range = rangeOfSectionClosingTag(in: buffer) {
                    let content = String(buffer[..<range.lowerBound])
                    buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                    if let type = currentSectionType {
                        currentSectionContent += content
                        var text = currentSectionContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        if type == .mermaidDiagram { text = Self.stripMermaidSectionTags(text) }
                        sections.append(MessageSection(
                            type: type,
                            content: .text(text),
                            language: currentSectionLanguage
                        ))
                        yielded = StreamingResponse(title: title, sections: sections, isComplete: false)
                    }
                    state = .idle
                    currentSectionType = nil
                    currentSectionLanguage = nil
                    currentSectionContent = ""
                } else {
                    let safeCount = buffer.count - 16
                    if safeCount > 0 {
                        let toTake = buffer.prefix(safeCount)
                        currentSectionContent += toTake
                        buffer.removeFirst(safeCount)
                        if let type = currentSectionType {
                            var partialText = currentSectionContent
                            if type == .mermaidDiagram { partialText = Self.stripMermaidSectionTags(partialText) }
                            let partial = MessageSection(
                                type: type,
                                content: .text(partialText),
                                language: currentSectionLanguage
                            )
                            yielded = StreamingResponse(
                                title: title,
                                sections: sections + [partial],
                                isComplete: false
                            )
                        }
                    }
                    if yielded == nil { yielded = partialResponse() }
                    break
                }
            case .readingContext:
                if let range = rangeOfClosingTag("CONTEXT", in: buffer) {
                    contextBuffer += String(buffer[..<range.lowerBound])
                    let content = contextBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !content.isEmpty { parsedContextPayload = content }
                    contextBuffer = ""
                    buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                    state = .idle
                } else {
                    let keep = 14
                    if buffer.count > keep {
                        let toTake = buffer.count - keep
                        contextBuffer += String(buffer.prefix(toTake))
                        buffer.removeFirst(toTake)
                    }
                    break
                }
            }
        }
        return yielded ?? partialResponse()
    }

    private func flushCurrentSection() {
        guard let type = currentSectionType else { return }
        var text = currentSectionContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if type == .mermaidDiagram { text = Self.stripMermaidSectionTags(text) }
        if !text.isEmpty {
            sections.append(MessageSection(
                type: type,
                content: .text(text),
                language: currentSectionLanguage
            ))
        }
        currentSectionType = nil
        currentSectionLanguage = nil
        currentSectionContent = ""
    }

    private func parseSectionHeader(_ header: String) {
        let lower = header.lowercased()
        if lower.contains("type=") {
            if let start = lower.range(of: "type=")?.upperBound {
                let rest = String(header[start...])
                let endIndex = rest.firstIndex(where: { $0 == " " || $0 == ">" }) ?? rest.endIndex
                let typeVal = String(rest[..<endIndex]).trimmingCharacters(in: .whitespaces)
                currentSectionType = sectionTypeFromGrammar(typeVal)
            }
        }
        if lower.contains("language=") {
            if let start = lower.range(of: "language=")?.upperBound {
                let rest = String(header[start...])
                let endIndex = rest.firstIndex(where: { $0 == " " || $0 == ">" }) ?? rest.endIndex
                currentSectionLanguage = String(rest[..<endIndex]).trimmingCharacters(in: .whitespaces)
            }
        }
    }

    /// Removes literal opening/closing section tags from mermaid content so they are not rendered.
    /// Strips from start (opening tags) and end (closing tags); then removes any remaining tag occurrences so echoed tags in the middle are gone.
    private static func stripMermaidSectionTags(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let openTags = ["<<SECTION:type=mermaid_diagram>>", "</SECTION:type=mermaid_diagram>>"]
        for tag in openTags {
            while result.count >= tag.count, result.prefix(tag.count).lowercased() == tag.lowercased() {
                result = String(result.dropFirst(tag.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let closeTags = ["<<END_SECTION>>", "</END_SECTION>>", "<</SECTION>>", "</SECTION>>"]
        for tag in closeTags {
            while result.count >= tag.count, result.suffix(tag.count).lowercased() == tag.lowercased() {
                result = String(result.dropLast(tag.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // Remove any tag that appears in the middle (model echoed the tag inside content)
        for tag in openTags + closeTags {
            while let range = result.range(of: tag, options: .caseInsensitive) {
                result.removeSubrange(range)
                result = result.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return result
    }

    private func sectionTypeFromGrammar(_ raw: String) -> SectionType? {
        switch raw.lowercased() {
        case "short_answer": return .shortAnswer
        case "details": return .details
        case "code": return .code
        case "mermaid_diagram": return .mermaidDiagram
        default: return nil
        }
    }

    private func partialResponse() -> StreamingResponse? {
        if !title.isEmpty {
            return StreamingResponse(title: title, sections: sections, isComplete: false)
        }
        if let type = currentSectionType, !currentSectionContent.isEmpty {
            let partial = MessageSection(
                type: type,
                content: .text(currentSectionContent),
                language: currentSectionLanguage
            )
            return StreamingResponse(title: title, sections: sections + [partial], isComplete: false)
        }
        if !sections.isEmpty {
            return StreamingResponse(title: title, sections: sections, isComplete: false)
        }
        let titleSoFar = (state == .readingTitle && !buffer.isEmpty)
            ? String(buffer).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        if !titleSoFar.isEmpty {
            return StreamingResponse(title: titleSoFar, sections: [], isComplete: false)
        }
        return nil
    }
}
