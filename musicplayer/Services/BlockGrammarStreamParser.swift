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
            isComplete: true
        )
    }

    private static let maxProcessIterations = 50

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
                if let range = buffer.range(of: "<</TITLE>>", options: .caseInsensitive) {
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
                if let range = buffer.range(of: "<</SECTION>>", options: .caseInsensitive) {
                    let content = String(buffer[..<range.lowerBound])
                    buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                    if let type = currentSectionType {
                        currentSectionContent += content
                        let text = currentSectionContent.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    let safeCount = buffer.count - 14
                    if safeCount > 0 {
                        let toTake = buffer.prefix(safeCount)
                        currentSectionContent += toTake
                        buffer.removeFirst(safeCount)
                        if let type = currentSectionType {
                            let partial = MessageSection(
                                type: type,
                                content: .text(currentSectionContent),
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
                if let range = buffer.range(of: "<</CONTEXT>>", options: .caseInsensitive) {
                    buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                    state = .idle
                } else {
                    let drop = min(buffer.count, 100)
                    if drop > 0 { buffer.removeFirst(drop) }
                    break
                }
            }
        }
        return yielded ?? partialResponse()
    }

    private func flushCurrentSection() {
        guard let type = currentSectionType else { return }
        let text = currentSectionContent.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func sectionTypeFromGrammar(_ raw: String) -> SectionType? {
        switch raw.lowercased() {
        case "short_answer": return .shortAnswer
        case "details": return .details
        case "code": return .code
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
