import Foundation

struct PromptBuilder {

    // MARK: - Constants
    static let systemDesignMaxPhase = 8
    static let systemDesignOptionalCodePhase = 8

    // MARK: - Core System Rules (Single Source of Truth)
    private static let coreSystemRules = """
ROLE:
You are a senior fullstack engineer and this is all about technical interview questions and answers.

GLOBAL RULES (NON-NEGOTIABLE):
1. Output VALID JSON only
2. Start with { and end with }
3. No markdown, prose, or extra fields
4. Follow the provided schema exactly
5. Be interview-focused and production-oriented
6. Make reasonable assumptions if data is missing and state them

CONTEXT RULES:
- Always populate the context object
- conversation_summary:
  * Brief summary of discussion so far
  * No implementation detail
- current_answer_summary.ai_technical_context:
  * Key technical assumptions and decisions
  * Constraints, scale, and architecture choices
  * Information required to continue next question
"""

    /// Streaming grammar template – code example uses dynamic language in getBaseRulesStreaming.
    private static func coreSystemRules2Streaming(language: ProgrammingLanguage) -> String {
        let langId = language.codeIdentifier
        let langName = language.rawValue
        return """
ROLE:
You are a senior fullstack engineer answering technical interview questions.

CRITICAL OUTPUT CONTRACT (NON-NEGOTIABLE):
You MUST follow the EXACT streaming grammar below.
Do NOT output JSON.
Do NOT output markdown.
Do NOT explain the format.
Do NOT wrap in backticks.
Do NOT escape newlines.

The response is a STREAMING BLOCK PROTOCOL.

REQUESTED LANGUAGE FOR CODE: \(langName) (use language=\(langId) in code section tags).

GRAMMAR:

<<TITLE>>
Single line title here
<</TITLE>>

<<SECTION:type=short_answer>>
Plain text paragraph here.
Can contain multiple lines.
Supports normal punctuation.
<</SECTION>>

<<SECTION:type=details>>
Text block.
- Bullet points allowed
- Natural newlines allowed
Indentation allowed.
<</SECTION>>

<<SECTION:type=code language=\(langId)>>
Example code in \(langName) here.
<</SECTION>>

<<CONTEXT>>
conversation_summary:
One short summary.

ai_technical_context:
Key assumptions, scale, constraints.
<</CONTEXT>>

IMPORTANT RULES:
- Tags must be EXACT.
- Tags must be UPPERCASE.
- No JSON anywhere.
- No markdown anywhere.
- Code must be raw and unescaped.
- Indentation must be preserved.
- Never escape quotes inside code.
- Never compress whitespace.
- Never remove leading spaces in code.
- CONTEXT must appear LAST.
- You will see "STREAMING SECTIONS FOR THIS CATEGORY" below: output ONLY the sections listed for that category; do not add extra section types (e.g. do not add code if the category says omit code).
"""
    }


    // MARK: - Global JSON Schema (Used Everywhere Except Phased SD)
    private static let defaultJSONSchema = """
RESPONSE SCHEMA:
{
  "title": "string",
  "sections": [
    {
      "type": "short_answer | details | code",
      "content": "string (for short_answer and details use a string; for code use a single string with \\n for newlines, NOT an array of lines)",
      "language": "string (only for code sections, e.g. \"go\", \"python\")"
    }
  ],
  "context": {
    "conversation_summary": "string",
    "current_answer_summary": {
      "ai_technical_context": "string"
    }
  }
}

CONTENT RULES:
- short_answer, details: content must be a single string.
- code: content must be a single string containing the full source code; use \\n for line breaks. Do NOT use an array of lines for code.
"""

    /// Image-specific task and rules — append when analyzing an image so the model extracts question/code and answers, instead of describing the screen.
    private static let imageAnalysisTaskAndRules = """
TASK:
Analyze the image and find the question or code snippet. Then provide the full interview answer (e.g. approach, solution, code) for that question in the requested category. Your output must be the interview answer only.

RULES:
- If the image shows a meeting/chat UI, look in the chat or message area for the question or code.
- If the image shows a code editor or snippet, treat that as the question or code to solve/explain.
- If the user provided question text above, that is the question to answer; use the image only for extra context (e.g. code to fix).
- Do NOT describe the screen, presentation, session, or UI (e.g. no "Screen Sharing Session", "Presentation Instructions", "infinity mirror warning"). Output only the technical interview answer (short_answer, details, code as per schema).
"""

    // MARK: - Image Analysis Prompt
    /// Builds the same prompt as for the selected category (as when sending text), then appends the image TASK and RULES.
    /// For system design, use the phased flow from the service with imageData in phase 1; this is used for non–system design or as base for phase 1.
    static func buildImageAnalysisPrompt(
        userQuestion: String?,
        category: Category = .coding,
        language: ProgrammingLanguage = .golang,
        useInterviewCounterQuestion: Bool = false,
        realTimeStreamingEnabled: Bool = false
    ) -> String {
        let context = (userQuestion?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        ? "USER CONTEXT:\n\(userQuestion!)"
        : ""

        let promptForCategory = buildSystemPrompt(for: category, language: language, useInterviewCounterQuestion: useInterviewCounterQuestion, realTimeStreamingEnabled: realTimeStreamingEnabled)
        let schemaBlock: String
        if realTimeStreamingEnabled {
            schemaBlock = ""
        } else {
            schemaBlock = category == .systemDesign ? "" : defaultJSONSchema
        }

        return """
\(promptForCategory)

\(imageAnalysisTaskAndRules)
\(schemaBlock.isEmpty ? "" : "\n\(schemaBlock)\n")
\(context)
"""
    }


    private static func getInterviewCounterQuestionPrompt() -> String {
    """
CATEGORY: Interview Deep Justification

ROLE:
You are the interviewee (candidate) answering a technical interview question.

GOAL:
Provide a complete answer AND proactively address the follow-up questions an interviewer would ask.

BEHAVIOR:
- Clearly explain WHY a particular approach or technology was chosen
- Explain the ROLE of each major component or pattern
- Explain what PROBLEM each choice solves
- Discuss what happens if a component is REMOVED or REPLACED
- Present ALTERNATIVES or substitute technologies
- Explain WHY alternatives were not chosen
- Compare chosen approach with at least one alternative
- Explain BENEFITS and TRADE-OFFS
- Mention scenarios where another approach might be better
- Explain how the choice behaves at SCALE and under FAILURE

ANSWER STYLE:
- Confident, interview-style explanations
- Structured and concise
- No rhetorical questions
- No generic textbook definitions
- Focus on decision-making and reasoning

RULES:
- Answer the original question fully
- Do NOT ask questions back
- Do NOT assume interviewer agreement
- Every major decision must be justified

TONE:
- Professional
- Clear
- Senior-level
"""
}



    static func buildSystemPrompt(
        for category: Category,
        language: ProgrammingLanguage = .golang,
        useInterviewCounterQuestion: Bool = false,
        realTimeStreamingEnabled: Bool = false
    ) -> String {
        if realTimeStreamingEnabled {
            let base = getBaseRulesStreaming(language: language)
            let categoryPrompt = useInterviewCounterQuestion
                ? getInterviewCounterQuestionPrompt()
                : getCategoryPrompt(for: category, language: language)
            let streamingSectionRules = getStreamingSectionRulesForCategory(category, language: language)
            return """
\(base)

\(categoryPrompt)

\(streamingSectionRules)
"""
        }
        let base = getBaseRules(language: language)
        let categoryPrompt: String
        let schema: String
        if useInterviewCounterQuestion {
            categoryPrompt = getInterviewCounterQuestionPrompt()
            schema = defaultJSONSchema
        } else {
            categoryPrompt = getCategoryPrompt(for: category, language: language)
            schema = category == .systemDesign ? "" : defaultJSONSchema
        }
        return """
\(base)

\(schema)

\(categoryPrompt)
"""
    }

    private static func getBaseRules(language: ProgrammingLanguage) -> String {
        """
\(coreSystemRules)

EXPERTISE:
- Distributed systems & microservices
- Kafka, async processing, retries, idempotency
- Databases: Postgres, MongoDB, Redis
- Containers and production operations
- System design interviews

LANGUAGE:
- Use \(language.rawValue) for all code
- Code must be production-ready and idiomatic
"""
    }

    private static func getBaseRulesStreaming(language: ProgrammingLanguage) -> String {
        """
\(coreSystemRules2Streaming(language: language))

EXPERTISE:
- Distributed systems & microservices
- Kafka, async processing, retries, idempotency
- Databases: Postgres, MongoDB, Redis
- Containers and production operations
- System design interviews

LANGUAGE:
- Use \(language.rawValue) for all code
- Code must be production-ready and idiomatic
"""
    }

    // MARK: - Category Prompts
    private static func getCategoryPrompt(
        for category: Category,
        language: ProgrammingLanguage
    ) -> String {

        switch category {
        case .normal:
            return getNormalPrompt()
        case .coding:
            return getCodingPrompt(language: language)
        case .technical:
            return getTechnicalPrompt()
        case .quickAnswers:
            return getQuickAnswersPrompt()
        case .shortAnswers:
            return getShortAnswersPrompt()
        case .trueFalse:
            return getTrueFalsePrompt()
        case .systemDesign:
            return getSystemDesignPrompt()
        case .scenarioBasedSystemDesign:
            return getScenarioSystemDesignPrompt()
        }
    }

    private static func getNormalPrompt() -> String {
        """
CATEGORY: Standard Interview Question

STRUCTURE:
- short_answer: Direct explanation
- details: Key points or examples
- code: Only if it improves clarity

STYLE:
Clear, practical, interview-ready
"""
    }

    private static func getCodingPrompt(language: ProgrammingLanguage) -> String {
        """
CATEGORY: Coding Interview

STRUCTURE:
- short_answer: Approach and reasoning
- code: Complete working solution in \(language.rawValue); content must be one string with \\n for newlines (not an array of lines)
- details: Complexity, edge cases, alternatives

RULES:
- No pseudocode
- No TODOs
- Handle edge cases
"""
    }

    private static func getTechnicalPrompt() -> String {
        """
CATEGORY: Technical Deep Dive

FOCUS:
- Explain WHY and HOW

STRUCTURE:
- short_answer: Core concept
- details: Trade-offs and best practices
- code: Patterns or examples when useful
"""
    }

   private static func getTrueFalsePrompt() -> String {
        """
CATEGORY: True/False Interview Questions

RULES:
- True/False answer only
- Why the answer is true/false should be in the details section
STYLE:
Precise and confident
"""
    }



   private static func getQuickAnswersPrompt() -> String {
        """
CATEGORY: Quick Answers Interview Questions

RULES:
- Quick answer only
- Quick answer should be in the short_answer section
- Quick answer should be in the details section
STYLE:
Precise and confident
"""
    }

    private static func getShortAnswersPrompt() -> String {
        """
CATEGORY: Rapid Interview Questions

RULES:
- short_answer only (1–3 sentences)
- details only if unavoidable (≤5 bullets)
- complete code solution code
- Code explanation should be in the details section
STYLE:
Precise and confident
"""
    }

    // MARK: - Streaming: which sections to output per category (so model follows question type)
    private static func getStreamingSectionRulesForCategory(_ category: Category, language: ProgrammingLanguage) -> String {
        switch category {
        case .shortAnswers:
            return """
STREAMING SECTIONS FOR THIS CATEGORY (Rapid Interview – follow exactly):
- Output ONLY <<SECTION:type=short_answer>> (required; 1–3 sentences).
- Output ONLY <<SECTION:type=details>> (required; Highlight important keywords or phrases from the answer).
- Optionally <<SECTION:type=details>> only if truly needed (≤5 bullets). Omit if the answer fits in short_answer.
- Output ONLY <<SECTION:type=code>> code in selected language \(language.rawValue).
"""
        case .quickAnswers:
            return """
STREAMING SECTIONS FOR THIS CATEGORY (Quick Answers – follow exactly):
- Output <<SECTION:type=short_answer>> with the quick answer (required).
- Output ONLY <<SECTION:type=details>> (required; Highlight important keywords or phrases from the answer).
- Optionally <<SECTION:type=details>> for a brief expansion. Keep both short.
- Do NOT output code unless the question explicitly requires it.
"""
        case .trueFalse:
            return """
STREAMING SECTIONS FOR THIS CATEGORY (True/False – follow exactly):
- Output <<SECTION:type=short_answer>> with only "True" or "False" (required).
- Output ONLY <<SECTION:type=details>> (required; Highlight important keywords or phrases from the answer).
- Output <<SECTION:type=details>> with why the answer is true/false. Do NOT output code unless the question asks for it.
"""
        case .coding:
            return """
STREAMING SECTIONS FOR THIS CATEGORY (Coding – follow exactly):
- Output <<SECTION:type=short_answer>> with approach and reasoning (required).
- Output <<SECTION:type=code language=\(language.codeIdentifier)>> with the complete working solution (required). Use \(language.rawValue).
- Output <<SECTION:type=details>> with complexity, edge cases, alternatives. Order: short_answer then code then details.
"""
        case .normal:
            return """
STREAMING SECTIONS FOR THIS CATEGORY (Standard – follow exactly):
- Output <<SECTION:type=short_answer>> (direct explanation).
- Output <<SECTION:type=details>> for key points or examples.
- Output <<SECTION:type=code>> only if it improves clarity; omit code if not needed.
"""
        case .technical:
            return """
STREAMING SECTIONS FOR THIS CATEGORY (Technical Deep Dive – follow exactly):
- Output <<SECTION:type=short_answer>> (core concept).
- Output <<SECTION:type=details>> for trade-offs and best practices.
- Output ONLY <<SECTION:type=details>> (required; Highlight important keywords or phrases from the answer).
- Output <<SECTION:type=code>> only for patterns or examples when useful; omit if not needed.
"""
        case .systemDesign:
            return """
STREAMING SECTIONS FOR THIS CATEGORY (System Design – follow exactly):
- Output <<SECTION:type=short_answer>> for the high-level approach or problem statement.
- Output <<SECTION:type=details>> for requirements, components, trade-offs (main content). Use bullets; one idea per bullet.
- Output <<SECTION:type=code>> only if you are showing a concrete snippet (e.g. config, interface); omit otherwise.
"""
        case .scenarioBasedSystemDesign:
            return """
STREAMING SECTIONS FOR THIS CATEGORY (Scenario-Based System Design – follow exactly):
- Output <<SECTION:type=short_answer>> for the high-level approach or problem statement.
- Output ONLY <<SECTION:type=details>> (required; Highlight important keywords or phrases from the answer).
- Output <<SECTION:type=details>> for requirements, components, trade-offs (main content). Use bullets; one idea per bullet.
- Output <<SECTION:type=code>> only if you are showing a concrete snippet (e.g. config, interface); omit otherwise.
"""
        }
    }

    private static func getSystemDesignPrompt() -> String {
        """
CATEGORY: System Design Interview

RULES:
- Follow required section order exactly
- One idea per bullet
- No nested bullets
- Explain simply before technical depth
- State assumptions explicitly

GOAL:
Design a scalable, fault-tolerant, production-ready system
"""
    }

    private static func getScenarioSystemDesignPrompt() -> String {
        """
CATEGORY: Scenario-Based System Design

ASSUMPTIONS:
- High traffic
- Finite resources
- Real-world failures

RULES:
- Do NOT ask clarifying questions
- State assumptions first
- Design for production
- Focus on scalability and operations
"""
    }

    // MARK: - System Design (Full)
    static func buildSystemDesignFullUserPrompt(question: String) -> String {
        """
Question: \(question)

Return VALID JSON only.

REQUIRED SECTIONS (ORDERED):
1. problem_restatement
2. functional_requirements
3. mermaid_diagram
4. list_of_services_we_will_create
5. high_level_functional_flow
6. detailed_service_flow
7. data_flow_between_services
8. scalability_strategy

IMPORTANT:
- Context must summarize decisions made in this answer
"""
    }

    // MARK: - System Design (Phased)
    /// Use when the question comes only from the image (no user text).
    static func buildSystemDesignPhase1UserPromptWithImage(language: ProgrammingLanguage) -> String {
        buildSystemDesignPhaseUserPrompt(
            phase: 1,
            question: "Analyze the image and extract the system design question. Then perform Phase 1 (Problem Restatement) for that question.",
            language: language
        )
    }

    /// Use when the user provided the question in text and an image is attached for context. Ensures the model answers the text question, not an interpretation of the image.
    static func buildSystemDesignPhase1UserPromptWithImageAndQuestion(question: String, language: ProgrammingLanguage) -> String {
        buildSystemDesignPhaseUserPrompt(
            phase: 1,
            question: "The system design question to answer is given below. Use the attached image only for additional context if relevant. Do NOT derive the question from the image.\n\n\(question)",
            language: language
        )
    }

    static func buildSystemDesignPhaseUserPrompt(
        phase: Int,
        question: String,
        language: ProgrammingLanguage
    ) -> String {

        let schema = getSystemDesignPhaseSchema(phase)
        let rules = getSystemDesignPhaseRules(phase)

        return """
Question: \(question)

Return VALID JSON only.

RESPONSE SCHEMA:
{
  "title": "string",
  "sections": [
\(schema)
  ],
  "context": {
    "conversation_summary": "string",
    "current_answer_summary": {
      "ai_technical_context": "string"
    }
  }
}

PHASE \(phase) ONLY:
\(rules)

IMPORTANT:
- Update context using completed phases only
- Do NOT repeat full answers in context
"""
    }

    // MARK: - Phase Schema (phase number → section type; order 1–8)
    private static func getSystemDesignPhaseSchema(_ phase: Int) -> String {
        let types: [Int: String] = [
            1: "problem_restatement",
            2: "functional_requirements",
            3: "mermaid_diagram",
            4: "list_of_services_we_will_create",
            5: "high_level_functional_flow",
            6: "detailed_service_flow",
            7: "data_flow_between_services",
            8: "scalability_strategy"
        ]
        let type = types[phase] ?? "problem_restatement"
        return #"    { "type": "\#(type)", "content": ["string"] }"#
    }

    // MARK: - Phase Rules — Order 1–8 matches schema
    private static func getSystemDesignPhaseRules(_ phase: Int) -> String {
        switch phase {
        case 1:
            return """
PHASE 1 — PROBLEM RESTATEMENT
- Explain the problem in simple, non-technical terms
- Describe what is being built and why
"""
        case 2:
            return """
PHASE 2 — FUNCTIONAL REQUIREMENTS
- List user-facing requirements
- Describe what the system must do
"""
        case 3:
            return """
PHASE 3 — MERMAID DIAGRAM FLOWCHART

- Create a Mermaid flowchart for the system design based on the problem and requirements above.
- Output the diagram in a section with type "mermaid_diagram" (content: the Mermaid source only).

- Use correct Mermaid flowchart syntax so the diagram renders: graph TD or flowchart LR, nodes as [Label] or ID[Label], edges as --> or -->|edge label|. For path or parameter placeholders use angle brackets only, e.g. |GET /<code>| not |GET /{code}|.
- Do not use parentheses (), angle brackets <> inside the Pipes || — they break Mermaid parsing. If such text is required, wrap the whole label in double quotes, e.g. -->|"read after write (optional)"| or ["label with (parens)"].
- Write only valid Mermaid that will parse and display without errors.
"""
        case 4:
            return """
PHASE 4 — LIST OF SERVICES WE WILL CREATE
- List services
- Single responsibility per service
"""
        case 5:
            return """
PHASE 5 — HIGH-LEVEL FUNCTIONAL FLOW
- Step-by-step logical flow
- Technology-agnostic
"""
        case 6:
            return """
PHASE 6 — DETAILED SERVICE FLOW
- Service interactions
- Error handling
- Sync vs async
"""
        case 7:
            return """
PHASE 7 — DATA FLOW BETWEEN SERVICES

STRICT RULES:
- Bullets only
- No sentences
- Use arrows (->) only

FORMAT:
Flow Name:
ServiceA -> ServiceB -> ServiceC

Include:
- Normal flow
- Failure flow
"""
        case 8:
            return """
PHASE 8 — SCALABILITY STRATEGY
- Bottlenecks
- Horizontal and vertical scaling
"""
        default:
            return "Explain clearly and concisely."
        }
    }

    // MARK: - Debug: final prompt logging
    static func printFinalPromptSent(
        provider: String,
        systemPrompt: String,
        userPrompt: String,
        conversationContextCount: Int = 0,
        hasImage: Bool = false
    ) {
        let systemLimit = 2500
        let userLimit = 1500
        let systemPreview = systemPrompt.count <= systemLimit
            ? systemPrompt
            : String(systemPrompt.prefix(systemLimit)) + "\n... [truncated, total \(systemPrompt.count) chars]"
        let userPreview = userPrompt.count <= userLimit
            ? userPrompt
            : String(userPrompt.prefix(userLimit)) + "\n... [truncated, total \(userPrompt.count) chars]"
        print("📤 Final prompt sent to AI (\(provider))")
        print("   System: \(systemPrompt.count) chars | User: \(userPrompt.count) chars | Contexts: \(conversationContextCount) | Image: \(hasImage)")
        print("--- SYSTEM ---")
        print(systemPreview)
        print("--- USER ---")
        print(userPreview)
        print("--- END PROMPT ---")
    }
}
