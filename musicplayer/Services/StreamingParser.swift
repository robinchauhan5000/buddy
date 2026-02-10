import Foundation

// MARK: - Streaming Parser (Grammar-Based, State Machine)

/// A streaming-first parser that treats the model output as a **fixed, known grammar** (NOT JSON).
/// Renders content progressively so the UI updates in real time. Never uses JSONDecoder for streaming.
///
/// **Grammar (order guaranteed):**
/// ```
/// TITLE:
/// <single line title>
///
/// SECTIONS:
/// SECTION:
/// type=<short_answer|details|code>
/// language=<language name | empty>
/// content:
/// <content until next SECTION: or CONTEXT:>
///
/// CONTEXT:
/// conversation_summary:
/// <text>
/// ai_technical_context:
/// <text>
/// ```
///
/// **Chunk-boundary resilient:** markers are matched only when complete; partial tokens (e.g. "SEC" + "TION:")
/// are never misinterpreted as content.
///
/// **Example usage with AsyncThrowingStream:**
/// ```swift
/// var parser = StreamingParser()
/// var currentTitle = ""
/// var currentSections: [MessageSection] = []
///
/// for try await chunk in apiStream {
///     let events = parser.parse(chunk: chunk)
///     for event in events {
///         switch event {
///         case .titleParsed(let title):
///             currentTitle = title
///         case .contentChunk(let text):
///             // Append to last section and yield immediately for UI
///             appendToLastSection(text)
///             continuation.yield(StreamingResponse(title: currentTitle, sections: currentSections, isComplete: false))
///         case .sectionCompleted(let section):
///             currentSections.append(section)
///             continuation.yield(StreamingResponse(title: currentTitle, sections: currentSections, isComplete: false))
///         case .completed(let response, let context):
///             continuation.yield(StreamingResponse(title: response.title, sections: response.sections, isComplete: true))
///             // context is parsed but not rendered; use for follow-up if needed
///         }
///     }
/// }
/// let finalEvents = parser.finalize()
/// // ... handle final .completed if stream ended without emitting it
/// ```
public final class StreamingParser {

    // MARK: - State Machine

    private enum State {
        case idle
        case readingTitle
        case expectingSections
        case expectingSection
        case readingSectionType
        case readingSectionLanguage
        case readingSectionContent
        case expectingContext
        case readingConversationSummary
        case readingTechnicalContext
        case completed
    }

    // MARK: - Events (same shape as StreamingGrammarParser for drop-in use)

    public enum Event {
        /// Title parsed — update UI title.
        case titleParsed(String)
        /// Content chunk for current section — stream immediately to UI.
        case contentChunk(String)
        /// Section completed — finalize and append to sections.
        case sectionCompleted(MessageSection)
        /// Full response and optional context (context is not rendered).
        case completed(AIResponse, ConversationContext?)
    }

    // MARK: - State

    private var state: State = .idle
    /// Incoming data; we only consume when we have a complete marker or known content.
    private var buffer: String = ""

    private var title: String = ""
    private var sections: [MessageSection] = []

    private var currentSectionType: SectionType?
    private var currentSectionLanguage: String?
    private var currentSectionContent: String = ""

    private var conversationSummary: String = ""
    private var technicalContext: String = ""

    /// When true, we're at start of line in section content and may be seeing "SECTION:" or "CONTEXT:".
    private var atContentLineStart: Bool = true
    /// Line buffer used to disambiguate marker vs content when at line start.
    private var contentLineBuffer: String = ""

    private static let sectionMarker = "SECTION:"
    private static let contextMarker = "CONTEXT:"

    // MARK: - Public API

    public init() {}

    /// Parse a chunk. Call for each token/chunk from the stream.
    /// Events are emitted as soon as content or structure is known; content streams without waiting for section end.
    public func parse(chunk: String) -> [Event] {
        buffer.append(chunk)
        return processBuffer()
    }

    /// Call when the stream ends to finalize the last section and emit .completed.
    public func finalize() -> [Event] {
        var events: [Event] = []

        // Flush any pending content line (might be partial)
        if !contentLineBuffer.isEmpty {
            currentSectionContent.append(contentLineBuffer)
            events.append(.contentChunk(contentLineBuffer))
            contentLineBuffer = ""
        }

        // Finalize current section if any
        if let sectionType = currentSectionType, !currentSectionContent.isEmpty {
            let section = MessageSection(
                type: sectionType,
                content: parseContent(currentSectionContent, type: sectionType),
                language: currentSectionLanguage
            )
            events.append(.sectionCompleted(section))
            sections.append(section)
        }

        let response = AIResponse(title: title, sections: sections)
        let context: ConversationContext? = buildContextIfPresent()
        events.append(.completed(response, context))
        state = .completed

        return events
    }

    // MARK: - Buffer Processing (chunk-boundary safe)

    private func processBuffer() -> [Event] {
        var events: [Event] = []

        while true {
            let (consumed, newEvents) = processOneStep()
            events.append(contentsOf: newEvents)
            if !consumed || state == .completed {
                break
            }
        }

        return events
    }

    /// Returns (didConsumeSomething, events). Only consumes when we have a complete marker or safe content.
    private func processOneStep() -> (Bool, [Event]) {
        switch state {
        case .idle:
            return stepIdle()
        case .readingTitle:
            return stepReadingTitle()
        case .expectingSections:
            return stepExpectingMarker("SECTIONS:")
        case .expectingSection:
            return stepExpectingSectionOrContext()
        case .readingSectionType:
            return stepReadingSectionType()
        case .readingSectionLanguage:
            return stepReadingSectionLanguage()
        case .readingSectionContent:
            return stepReadingSectionContent()
        case .expectingContext:
            return stepExpectingContext()
        case .readingConversationSummary:
            return stepReadingConversationSummary()
        case .readingTechnicalContext:
            return stepReadingTechnicalContext()
        case .completed:
            return (false, [])
        }
    }

    // MARK: - Idle → TITLE:

    private func stepIdle() -> (Bool, [Event]) {
        trimLeadingWhitespaceAndNewlines()
        guard buffer.count >= 6 else { return (false, []) }
        if buffer.hasPrefix("TITLE:") {
            buffer.removeFirst(6)
            state = .readingTitle
            return (true, [])
        }
        // Optional: skip one invalid char and retry (e.g. leading BOM)
        buffer.removeFirst()
        return (true, [])
    }

    // MARK: - Reading title (until newline)

    private func stepReadingTitle() -> (Bool, [Event]) {
        guard let newlineIndex = buffer.firstIndex(of: "\n") else {
            return (false, [])
        }
        let line = String(buffer[..<newlineIndex])
        buffer.removeSubrange(buffer.startIndex...newlineIndex)
        title = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            state = .expectingSections
            return (true, [.titleParsed(title)])
        }
        state = .expectingSections
        return (true, [])
    }

    // MARK: - Expecting a single marker (e.g. SECTIONS:)

    private func stepExpectingMarker(_ marker: String) -> (Bool, [Event]) {
        trimLeadingWhitespaceAndNewlines()
        guard buffer.count >= marker.count else { return (false, []) }
        if buffer.hasPrefix(marker) {
            buffer.removeFirst(marker.count)
            if marker == "SECTIONS:" {
                state = .expectingSection
            }
            return (true, [])
        }
        buffer.removeFirst()
        return (true, [])
    }

    // MARK: - Expecting SECTION: or CONTEXT:

    private func stepExpectingSectionOrContext() -> (Bool, [Event]) {
        trimLeadingWhitespaceAndNewlines()
        let sectionLen = Self.sectionMarker.count
        let contextLen = Self.contextMarker.count
        let need = max(sectionLen, contextLen)
        guard buffer.count >= need else { return (false, []) }

        if buffer.hasPrefix(Self.sectionMarker) {
            buffer.removeFirst(sectionLen)
            state = .readingSectionType
            return (true, [])
        }
        if buffer.hasPrefix(Self.contextMarker) {
            buffer.removeFirst(contextLen)
            finalizeCurrentSectionInto(&sections)
            state = .expectingContext
            return (true, [])
        }
        buffer.removeFirst()
        return (true, [])
    }

    // MARK: - Section type line: type=short_answer|details|code

    private func stepReadingSectionType() -> (Bool, [Event]) {
        guard let line = tryReadLine() else { return (false, []) }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("type=") {
            let value = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            currentSectionType = parseSectionType(value)
            state = .readingSectionLanguage
        }
        return (true, [])
    }

    // MARK: - Section language line: language=swift | language=

    private func stepReadingSectionLanguage() -> (Bool, [Event]) {
        guard let line = tryReadLine() else { return (false, []) }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("language=") {
            let value = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespacesAndNewlines)
            currentSectionLanguage = value.isEmpty ? nil : value
            state = .readingSectionContent
            atContentLineStart = true
            contentLineBuffer = ""
        }
        return (true, [])
    }

    // MARK: - Section content: stream until SECTION: or CONTEXT: (resilient to chunk boundaries)

    private func stepReadingSectionContent() -> (Bool, [Event]) {
        // Consume "content:" if we haven't yet (optional line after language=)
        trimLeadingWhitespaceAndNewlines()
        if buffer.hasPrefix("content:") {
            buffer.removeFirst(8)
            trimLeadingWhitespaceAndNewlines()
            atContentLineStart = true
            contentLineBuffer = ""
            return (true, [])
        }

        // At line start we must not emit until we know if this line is SECTION: or CONTEXT:
        if atContentLineStart {
            return stepContentAtLineStart()
        }

        // Not at line start: consume until next newline or end of buffer
        if let newlineIndex = buffer.firstIndex(of: "\n") {
            let chunk = String(buffer[..<newlineIndex])
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
            currentSectionContent += chunk + "\n"
            return (true, [.contentChunk(chunk + "\n")])
        }
        // No newline: emit everything we have (cannot be start of marker)
        if !buffer.isEmpty {
            let chunk = buffer
            buffer = ""
            currentSectionContent += chunk
            return (true, [.contentChunk(chunk)])
        }
        return (false, [])
    }

    /// When at line start, we may be seeing "SECTION:" or "CONTEXT:" split across chunks.
    /// Use combined = contentLineBuffer + buffer; only decide when we have a full line (newline).
    private func stepContentAtLineStart() -> (Bool, [Event]) {
        let sectionM = Self.sectionMarker
        let contextM = Self.contextMarker
        let combined = contentLineBuffer + buffer
        contentLineBuffer = ""
        buffer = ""

        guard let newlineIdx = combined.firstIndex(of: "\n") else {
            // No newline yet — hold everything (could be "SEC" + "TION:" in next chunk)
            contentLineBuffer = combined
            return (false, [])
        }

        let line = String(combined[..<newlineIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
        let afterNewline = combined.index(after: newlineIdx)
        buffer = String(combined[afterNewline...])

        if line == sectionM {
            let evts = finalizeCurrentSectionAndEmit()
            state = .readingSectionType
            atContentLineStart = true
            return (true, evts)
        }
        if line == contextM {
            let evts = finalizeCurrentSectionAndEmit()
            state = .expectingContext
            atContentLineStart = true
            return (true, evts)
        }
        currentSectionContent += line + "\n"
        atContentLineStart = true
        return (true, [.contentChunk(line + "\n")])
    }

    private func finalizeCurrentSectionInto(_ into: inout [MessageSection]) {
        guard let sectionType = currentSectionType else { return }
        let section = MessageSection(
            type: sectionType,
            content: parseContent(currentSectionContent, type: sectionType),
            language: currentSectionLanguage
        )
        into.append(section)
        currentSectionType = nil
        currentSectionLanguage = nil
        currentSectionContent = ""
    }

    private func finalizeCurrentSectionAndEmit() -> [Event] {
        var evts: [Event] = []
        if let sectionType = currentSectionType, !currentSectionContent.isEmpty {
            let section = MessageSection(
                type: sectionType,
                content: parseContent(currentSectionContent, type: sectionType),
                language: currentSectionLanguage
            )
            sections.append(section)
            evts.append(.sectionCompleted(section))
        }
        currentSectionType = nil
        currentSectionLanguage = nil
        currentSectionContent = ""
        return evts
    }

    // MARK: - Context (parsed but not rendered)

    private func stepExpectingContext() -> (Bool, [Event]) {
        trimLeadingWhitespaceAndNewlines()
        let marker = "conversation_summary:"
        guard buffer.count >= marker.count else { return (false, []) }
        if buffer.hasPrefix(marker) {
            buffer.removeFirst(marker.count)
            state = .readingConversationSummary
            return (true, [])
        }
        buffer.removeFirst()
        return (true, [])
    }

    private func stepReadingConversationSummary() -> (Bool, [Event]) {
        let marker = "ai_technical_context:"
        if buffer.hasPrefix(marker) {
            buffer.removeFirst(marker.count)
            state = .readingTechnicalContext
            return (true, [])
        }
        guard let newlineIndex = buffer.firstIndex(of: "\n") else {
            if buffer.count > 500 {
                let chunk = String(buffer.prefix(500))
                buffer.removeFirst(500)
                conversationSummary.append(chunk)
                return (true, [])
            }
            return (false, [])
        }
        let line = String(buffer[..<newlineIndex])
        buffer.removeSubrange(buffer.startIndex...newlineIndex)
        conversationSummary += line + "\n"
        return (true, [])
    }

    private func stepReadingTechnicalContext() -> (Bool, [Event]) {
        // Consume rest of buffer into technicalContext (no UI events)
        if !buffer.isEmpty {
            technicalContext.append(buffer)
            buffer = ""
        }
        return (false, [])
    }

    // MARK: - Helpers

    private func trimLeadingWhitespaceAndNewlines() {
        buffer = buffer.drop(while: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }).map(String.init).joined()
    }

    private func tryReadLine() -> String? {
        guard let newlineIndex = buffer.firstIndex(of: "\n") else { return nil }
        let line = String(buffer[..<newlineIndex])
        buffer.removeSubrange(buffer.startIndex...newlineIndex)
        return line
    }

    private func parseSectionType(_ value: String) -> SectionType {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "short_answer": return .shortAnswer
        case "details": return .details
        case "code": return .code
        case "problem_restatement": return .problemRestatement
        case "functional_requirements": return .functionalRequirements
        case "non_functional_requirements": return .nonFunctionalRequirements
        case "high_level_functional_flow": return .highLevelFunctionalFlow
        case "system_boundaries_and_assumptions": return .systemBoundariesAndAssumptions
        case "services_we_will_create": return .servicesWeWillCreate
        case "detailed_service_flow": return .detailedServiceFlow
        case "data_model_and_storage_design": return .dataModelAndStorageDesign
        case "data_flow_between_services": return .dataFlowBetweenServices
        case "deduplication_and_idempotency": return .deduplicationAndIdempotency
        case "reporting_monitoring_observability": return .reportingMonitoringObservability
        case "high_level_design": return .highLevelDesign
        case "scalability_strategy": return .scalabilityStrategy
        case "trade_offs_and_alternatives": return .tradeOffsAndAlternatives
        case "failure_scenarios_and_recovery": return .failureScenariosAndRecovery
        default: return .shortAnswer
        }
    }

    private func parseContent(_ text: String, type: SectionType) -> SectionContent {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.components(separatedBy: .newlines)
        let listLines = lines.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("-") || t.hasPrefix("*") || t.range(of: #"^\d+\."#, options: .regularExpression) != nil
        }
        if listLines.count > lines.count / 2, listLines.count > 0 {
            let items = listLines.map { line in
                var l = line.trimmingCharacters(in: .whitespaces)
                if l.hasPrefix("-") || l.hasPrefix("*") {
                    l = String(l.dropFirst()).trimmingCharacters(in: .whitespaces)
                } else if let range = l.range(of: #"^\d+\.\s*"#, options: .regularExpression) {
                    l = String(l[range.upperBound...])
                }
                return l
            }
            return .list(items)
        }
        return .text(trimmed)
    }

    private func buildContextIfPresent() -> ConversationContext? {
        guard !conversationSummary.isEmpty || !technicalContext.isEmpty else { return nil }
        return ConversationContext(
            conversationSummary: conversationSummary.trimmingCharacters(in: .whitespacesAndNewlines),
            previousAnswerSummary: PreviousAnswerSummary(aiTechnicalSummary: technicalContext.trimmingCharacters(in: .whitespacesAndNewlines)),
            currentIntent: "follow_up",
            relatedToPrevious: true
        )
    }
}

