import Foundation

struct PromptBuilder {

    // MARK: - Constants
    static let systemDesignMaxPhase = 15
    static let systemDesignOptionalCodePhase = 15

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
        language: ProgrammingLanguage = .golang
    ) -> String {
        let context = (userQuestion?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        ? "USER CONTEXT:\n\(userQuestion!)"
        : ""

        // Same prompt as when sending normally for this category (coding, technical, shortAnswers, systemDesign, etc.)
        let promptForCategory = buildSystemPrompt(for: category, language: language)

        // System design base prompt has no schema; others already include defaultJSONSchema
        let schemaBlock = category == .systemDesign ? defaultJSONSchema : ""

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



    // MARK: - Public System Prompt Builder
    static func buildSystemPrompt(
        for category: Category,
        language: ProgrammingLanguage = .golang,
        useInterviewCounterQuestion: Bool = false
    ) -> String {

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

    // MARK: - Base Rules
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
3. non_functional_requirements
4. high_level_functional_flow
5. system_boundaries_and_assumptions
6. services_we_will_create
7. detailed_service_flow
8. data_model_and_storage_design
9. data_flow_between_services
10. deduplication_and_idempotency
11. reporting_monitoring_observability
12. high_level_design
13. scalability_strategy
14. trade_offs_and_alternatives
15. failure_scenarios_and_recovery

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

    // MARK: - Phase Schema
    private static func getSystemDesignPhaseSchema(_ phase: Int) -> String {
        let types = [
            1: "problem_restatement",
            2: "functional_requirements",
            3: "non_functional_requirements",
            4: "high_level_functional_flow",
            5: "system_boundaries_and_assumptions",
            6: "services_we_will_create",
            7: "detailed_service_flow",
            8: "data_model_and_storage_design",
            9: "data_flow_between_services",
            10: "deduplication_and_idempotency",
            11: "reporting_monitoring_observability",
            12: "high_level_design",
            13: "scalability_strategy",
            14: "trade_offs_and_alternatives",
            15: "failure_scenarios_and_recovery"
        ]

        let type = types[phase] ?? "problem_restatement"
        return #"    { "type": "\#(type)", "content": ["string"] }"#
    }

    // MARK: - Phase Rules (FULL)
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
PHASE 3 — NON-FUNCTIONAL REQUIREMENTS
- Scalability, availability, latency
- Consistency, security, operations
"""

        case 4:
            return """
PHASE 4 — HIGH-LEVEL FUNCTIONAL FLOW
- Step-by-step logical flow
- Technology-agnostic
"""

        case 5:
            return """
PHASE 5 — SYSTEM BOUNDARIES & ASSUMPTIONS
- In-scope
- Out-of-scope
- Assumptions and dependencies
"""

        case 6:
            return """
PHASE 6 — SERVICES WE WILL CREATE
- List services
- Single responsibility per service
"""

        case 7:
            return """
PHASE 7 — DETAILED SERVICE FLOW
- Service interactions
- Error handling
- Sync vs async
"""

        case 8:
            return """
PHASE 8 — DATA MODEL & STORAGE DESIGN
- Entities and relationships
- Storage choices
- Access patterns
"""

        case 9:
            return """
PHASE 9 — DATA FLOW BETWEEN SERVICES

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

        case 10:
            return """
PHASE 10 — DEDUPLICATION & IDEMPOTENCY
- Idempotency strategies
- Handling retries and duplicates
"""

        case 11:
            return """
PHASE 11 — REPORTING, MONITORING & OBSERVABILITY
- Metrics
- Logs
- Alerts
"""

        case 12:
            return """
PHASE 12 — HIGH-LEVEL DESIGN
- Overall architecture
- Component interaction
"""

        case 13:
            return """
PHASE 13 — SCALABILITY STRATEGY
- Bottlenecks
- Horizontal and vertical scaling
"""

        case 14:
            return """
PHASE 14 — TRADE-OFFS & ALTERNATIVES
- Decisions made
- Pros and cons
"""

        case 15:
            return """
PHASE 15 — FAILURE SCENARIOS & RECOVERY
- Failure handling
- Recovery strategies
"""

        default:
            return "Explain clearly and concisely."
        }
    }
}
