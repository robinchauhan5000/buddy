import Foundation

// MARK: - Streaming Grammar Parser (State Machine)

/// A streaming parser that processes AI responses using a fixed grammar (NOT JSON).
/// Renders content progressively in real-time without blocking on JSON decoding.
///
/// Grammar:
/// ```
/// TITLE:
/// <single line>
///
/// SECTIONS:
/// SECTION:
/// type=<short_answer|details|code>
/// language=<lang>
/// content:
/// <text until next SECTION or CONTEXT>
///
/// CONTEXT:
/// conversation_summary:
/// <text>
/// ai_technical_context:
/// <text>
/// ```
public final class StreamingGrammarParser {
    
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
    
    // MARK: - Events
    
    public enum Event {
        /// Title has been parsed
        case titleParsed(String)
        
        /// Section started with type and language
        case sectionStarted(type: SectionType, language: String?)
        
        /// Content chunk for current section (stream immediately to UI)
        case contentChunk(String)
        
        /// Section completed
        case sectionCompleted(MessageSection)
        
        /// Full response completed with context
        case completed(AIResponse, ConversationContext?)
    }
    
    // MARK: - State
    
    private var state: State = .idle
    private var buffer: String = ""
    
    // Accumulated data
    private var title: String = ""
    private var sections: [MessageSection] = []
    
    // Current section being built
    private var currentSectionType: SectionType?
    private var currentSectionLanguage: String?
    private var currentSectionContent: String = ""
    /// True after we've consumed "content:" for the current section (avoids emitting "content:" as content)
    private var contentMarkerConsumedForCurrentSection: Bool = false
    
    // Context
    private var conversationSummary: String = ""
    private var technicalContext: String = ""
    
    // MARK: - Public API
    
    public init() {}
    
    /// Parse a chunk of text and emit events.
    /// Call this for each token/chunk received from the stream.
    public func parse(chunk: String) -> [Event] {
        buffer.append(chunk)
        return processBuffer()
    }
    
    /// Finalize parsing and emit completion event.
    /// Call this when the stream ends.
    public func finalize() -> [Event] {
        var events: [Event] = []
        
        // Finalize any pending section
        if let sectionType = currentSectionType, !currentSectionContent.isEmpty {
            let section = MessageSection(
                type: sectionType,
                content: parseContent(sanitizeSectionContent(currentSectionContent), type: sectionType),
                language: currentSectionLanguage
            )
            events.append(.sectionCompleted(section))
            sections.append(section)
        }
        
        // Build final response
        let response = AIResponse(title: title, sections: sections)
        
        let context: ConversationContext?
        if !conversationSummary.isEmpty || !technicalContext.isEmpty {
            context = ConversationContext(
                conversationSummary: conversationSummary,
                previousAnswerSummary: PreviousAnswerSummary(
                    aiTechnicalSummary: technicalContext
                ),
                currentIntent: "follow_up",
                relatedToPrevious: true
            )
        } else {
            context = nil
        }
        
        events.append(.completed(response, context))
        state = .completed
        
        return events
    }
    
    // MARK: - Buffer Processing
    
    private func processBuffer() -> [Event] {
        var events: [Event] = []
        
        while !buffer.isEmpty {
            let previousState = state
            
            switch state {
            case .idle:
                if tryConsume("TITLE:") {
                    state = .readingTitle
                }
                
            case .readingTitle:
                if let line = tryReadLine() {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        title = trimmed
                        events.append(.titleParsed(title))
                        state = .expectingSections
                    }
                }
                
            case .expectingSections:
                skipWhitespace()
                if tryConsume("SECTIONS:") {
                    state = .expectingSection
                }
                
            case .expectingSection:
                skipWhitespace()
                if tryConsume("SECTION:") {
                    state = .readingSectionType
                } else if tryConsume("CONTEXT:") {
                    // Finalize current section if any
                    if let sectionType = currentSectionType {
                        let section = MessageSection(
                            type: sectionType,
                            content: parseContent(currentSectionContent, type: sectionType),
                            language: currentSectionLanguage
                        )
                        events.append(.sectionCompleted(section))
                        sections.append(section)
                        currentSectionType = nil
                        currentSectionLanguage = nil
                        currentSectionContent = ""
                    }
                    state = .expectingContext
                }
                
            case .readingSectionType:
                if let line = tryReadLine() {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("type=") {
                        // Handle "type=details" or "type=detailslanguage=" (model omitted newline)
                        let afterType = String(trimmed.dropFirst(5))
                        let typeStr = afterType
                            .components(separatedBy: "language")
                            .first?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
                            ?? afterType.trimmingCharacters(in: .whitespacesAndNewlines)
                        currentSectionType = parseSectionType(typeStr)
                        state = .readingSectionLanguage
                    }
                }
                
            case .readingSectionLanguage:
                if let line = tryReadLine() {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("language=") {
                        let lang = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespacesAndNewlines)
                        currentSectionLanguage = lang.isEmpty ? nil : lang
                        
                        // Emit section started event with type and language
                        if let sectionType = currentSectionType {
                            events.append(.sectionStarted(type: sectionType, language: currentSectionLanguage))
                        }
                        
                        state = .readingSectionContent
                        contentMarkerConsumedForCurrentSection = false
                    }
                }
                
            case .readingSectionContent:
                skipWhitespace()
                // Consume SECTION: or CONTEXT: so they never appear in content
                if buffer.hasPrefix("SECTION:") {
                    if let sectionType = currentSectionType {
                        let section = MessageSection(
                            type: sectionType,
                            content: parseContent(sanitizeSectionContent(currentSectionContent), type: sectionType),
                            language: currentSectionLanguage
                        )
                        events.append(.sectionCompleted(section))
                        sections.append(section)
                        currentSectionType = nil
                        currentSectionLanguage = nil
                        currentSectionContent = ""
                    }
                    _ = tryConsume("SECTION:")
                    state = .expectingSection
                    continue
                }
                if buffer.hasPrefix("CONTEXT:") {
                    if let sectionType = currentSectionType {
                        let section = MessageSection(
                            type: sectionType,
                            content: parseContent(sanitizeSectionContent(currentSectionContent), type: sectionType),
                            language: currentSectionLanguage
                        )
                        events.append(.sectionCompleted(section))
                        sections.append(section)
                        currentSectionType = nil
                        currentSectionLanguage = nil
                        currentSectionContent = ""
                    }
                    _ = tryConsume("CONTEXT:")
                    state = .expectingContext
                    continue
                }
                if tryConsume("content:") {
                    contentMarkerConsumedForCurrentSection = true
                    if buffer.first == "\n" {
                        buffer.removeFirst()
                    }
                    continue
                }
                // Don't emit content that could be the start of "content:" (chunk boundary)
                if !contentMarkerConsumedForCurrentSection {
                    let t = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty && ("content:".hasPrefix(t) || t.hasPrefix("content")) {
                        break
                    }
                }
                // Check if content contains CONTEXT: marker
                if let contextRange = buffer.range(of: "CONTEXT:") {
                    let chunk = String(buffer[..<contextRange.lowerBound])
                    buffer.removeSubrange(..<contextRange.lowerBound)
                    if !chunk.isEmpty {
                        if currentSectionType == .code {
                            currentSectionContent = currentSectionContent.appendingCodeChunk(chunk)
                        } else {
                            currentSectionContent = currentSectionContent.appendingStreamingChunk(chunk)
                        }
                        let forUI = sanitizeSectionContent(chunk)
                        if !forUI.isEmpty { events.append(.contentChunk(forUI)) }
                    }
                    if let sectionType = currentSectionType {
                        let section = MessageSection(
                            type: sectionType,
                            content: parseContent(sanitizeSectionContent(currentSectionContent), type: sectionType),
                            language: currentSectionLanguage
                        )
                        events.append(.sectionCompleted(section))
                        sections.append(section)
                        currentSectionType = nil
                        currentSectionLanguage = nil
                        currentSectionContent = ""
                    }
                    state = .expectingContext
                    _ = tryConsume("CONTEXT:")
                    continue
                }
                let chunk = consumeUntilMarker()
                if !chunk.isEmpty {
                    let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Don't emit prefix of SECTION: or CONTEXT: (e.g. "CON" from "CONTEXT:" split across chunks)
                    if ("SECTION:".hasPrefix(trimmed) || trimmed.hasPrefix("SECTION")) || ("CONTEXT:".hasPrefix(trimmed) || trimmed.hasPrefix("CONTEXT")) {
                        buffer = chunk + buffer
                        break
                    }
                    if currentSectionType == .code {
                        currentSectionContent = currentSectionContent.appendingCodeChunk(chunk)
                    } else {
                        currentSectionContent = currentSectionContent.appendingStreamingChunk(chunk)
                    }
                    let forUI = sanitizeSectionContent(chunk)
                    if !forUI.isEmpty { events.append(.contentChunk(forUI)) }
                }
                
            case .expectingContext:
                skipWhitespace()
                if tryConsume("conversation_summary:") {
                    state = .readingConversationSummary
                }
                
            case .readingConversationSummary:
                skipWhitespace()
                if buffer.hasPrefix("ai_technical_context:") {
                    state = .readingTechnicalContext
                } else {
                    let chunk = consumeUntilMarker()
                    conversationSummary.append(chunk)
                }
                
            case .readingTechnicalContext:
                if tryConsume("ai_technical_context:") {
                    // Marker consumed
                    continue
                } else {
                    let chunk = consumeAll()
                    technicalContext.append(chunk)
                }
                
            case .completed:
                return events
            }
            
            // Prevent infinite loop if state doesn't change
            if state == previousState && !buffer.isEmpty {
                // Don't consume when we might be in the middle of a marker or waiting for a full line
                if shouldWaitForMoreData() {
                    break
                }
                buffer.removeFirst()
            }
        }
        
        return events
    }
    
    /// True when we must not consume input yet (chunk boundary or waiting for newline).
    private func shouldWaitForMoreData() -> Bool {
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        // States that need a full line (newline) before we can proceed
        switch state {
        case .readingTitle, .readingSectionType, .readingSectionLanguage:
            return true
        case .idle:
            return !trimmed.isEmpty && ("TITLE:".hasPrefix(trimmed) || trimmed.hasPrefix("TITLE"))
        case .expectingSections:
            return !trimmed.isEmpty && ("SECTIONS:".hasPrefix(trimmed) || trimmed.hasPrefix("SECTIONS"))
        case .expectingSection:
            return !trimmed.isEmpty && (("SECTION:".hasPrefix(trimmed) || trimmed.hasPrefix("SECTION"))
                || ("CONTEXT:".hasPrefix(trimmed) || trimmed.hasPrefix("CONTEXT")))
        case .readingSectionContent:
            if !contentMarkerConsumedForCurrentSection && !trimmed.isEmpty && ("content:".hasPrefix(trimmed) || trimmed.hasPrefix("content")) {
                return true
            }
            return !trimmed.isEmpty && (("SECTION:".hasPrefix(trimmed) || trimmed.hasPrefix("SECTION"))
                || ("CONTEXT:".hasPrefix(trimmed) || trimmed.hasPrefix("CONTEXT")))
        case .expectingContext:
            return !trimmed.isEmpty && ("conversation_summary:".hasPrefix(trimmed) || trimmed.hasPrefix("conversation_summary"))
        case .readingConversationSummary:
            return !trimmed.isEmpty && ("ai_technical_context:".hasPrefix(trimmed) || trimmed.hasPrefix("ai_technical_context"))
        case .readingTechnicalContext:
            return !trimmed.isEmpty && ("ai_technical_context:".hasPrefix(trimmed) || trimmed.hasPrefix("ai_technical_context"))
        default:
            return false
        }
    }
    
    // MARK: - Buffer Helpers
    
    private func skipWhitespace() {
        while !buffer.isEmpty && (buffer.first == "\n" || buffer.first == "\r" || buffer.first == " ") {
            buffer.removeFirst()
        }
    }
    
    private func tryConsume(_ marker: String) -> Bool {
        // Try to find marker at start of buffer (after trimming leading whitespace)
        let trimmedBuffer = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBuffer.hasPrefix(marker) {
            // Find the marker in original buffer and remove everything up to and including it
            if let range = buffer.range(of: marker) {
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                // Also skip any trailing newline after the marker
                if buffer.first == "\n" {
                    buffer.removeFirst()
                }
                return true
            }
        }
        return false
    }
    
    private func tryReadLine() -> String? {
        guard let newlineIndex = buffer.firstIndex(of: "\n") else {
            return nil
        }
        
        let line = String(buffer[..<newlineIndex])
        buffer.removeSubrange(...newlineIndex)
        return line
    }
    
    private func consumeUntilMarker() -> String {
        let markers = ["SECTION:", "CONTEXT:", "conversation_summary:", "ai_technical_context:"]
        
        var minIndex: String.Index?
        for marker in markers {
            if let range = buffer.range(of: marker) {
                if minIndex == nil || range.lowerBound < minIndex! {
                    minIndex = range.lowerBound
                }
            }
        }
        
        if let index = minIndex {
            let chunk = String(buffer[..<index])
            buffer.removeSubrange(..<index)
            return chunk
        } else {
            // No marker found, consume all
            let chunk = buffer
            buffer = ""
            return chunk
        }
    }
    
    private func consumeAll() -> String {
        let chunk = buffer
        buffer = ""
        return chunk
    }
    
    // MARK: - Parsing Helpers
    
    private func parseSectionType(_ typeStr: String) -> SectionType {
        switch typeStr {
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
    
    /// Remove grammar markers that leaked into section content (never show in UI).
    private func sanitizeSectionContent(_ text: String) -> String {
        let grammarMarkers: Set<String> = [
            "TITLE:", "SECTIONS:", "SECTION:", "CONTEXT:",
            "content:", "conversation_summary:", "ai_technical_context:",
            "CON", "TEXT:", "CONT", "CONTEX", "SECT", "SECTIO"  // fragments from chunk-split markers
        ]
        let lines = text.components(separatedBy: .newlines)
        let filtered = lines.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return true }
            if grammarMarkers.contains(t) { return false }
            if grammarMarkers.contains(t.replacingOccurrences(of: " ", with: "")) { return false }  // e.g. "CON TEXT:"
            if t.hasPrefix("type=") || t.hasPrefix("language=") { return false }
            return true
        }
        return filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func parseContent(_ text: String, type: SectionType) -> SectionContent {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if content looks like a list
        let lines = trimmed.components(separatedBy: .newlines)
        let listLines = lines.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("-") || t.hasPrefix("*") || t.range(of: #"^\d+\."#, options: .regularExpression) != nil
        }
        
        // If most lines are list items, treat as list
        if listLines.count > lines.count / 2 && listLines.count > 0 {
            let items = listLines.map { line in
                var l = line.trimmingCharacters(in: .whitespaces)
                // Remove list markers; ensure space after "-" so "-Item" -> "Item"
                if l.hasPrefix("-") || l.hasPrefix("*") {
                    l = String(l.dropFirst())
                    if l.first?.isWhitespace == true {
                        l = l.trimmingCharacters(in: .whitespaces)
                    }
                    // "-Usea" stays "Usea"; we don't insert spaces mid-word
                } else if let range = l.range(of: #"^\d+\.\s*"#, options: .regularExpression) {
                    l = String(l[range.upperBound...])
                }
                return l.trimmingCharacters(in: .whitespaces)
            }
            return .list(items)
        }
        
        return .text(trimmed)
    }
}
