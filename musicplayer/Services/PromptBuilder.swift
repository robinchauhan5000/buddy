import Foundation

struct PromptBuilder {

    // MARK: - Constants
    static let systemDesignMaxPhase = 7
    static let systemDesignOptionalCodePhase = 7

    /// Image-specific task and rules — append when analyzing an image so the model extracts question/code and answers, instead of describing the screen.
    private static let imageAnalysisTaskAndRules = """
TASK:
Analyze the image and find the question or code snippet. Then provide the full interview answer (e.g. approach, solution, code) for that question in the requested category. Your output must be the interview answer only.

RULES:
- If the image shows a meeting/chat UI, look in the chat or message area for the question or code.
- If the image shows a code editor or snippet, treat that as the question or code to solve/explain.
- If the user provided question text above, that is the question to answer; use the image only for extra context (e.g. code to fix).
- Do NOT describe the screen, presentation, session, or UI (e.g. no "Screen Sharing Session", "Presentation Instructions", "infinity mirror warning"). Output only the technical interview answer in Streaming Block Protocol format.
"""

    // MARK: - Image Analysis Prompt
    /// Builds the same prompt as for the selected category (as when sending text), then appends image TASK and RULES.
    /// Streaming-only mode: prompt output always follows block grammar sections.
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

        let promptForCategory = buildSystemPrompt(
            for: category,
            language: language,
            useInterviewCounterQuestion: useInterviewCounterQuestion,
            realTimeStreamingEnabled: realTimeStreamingEnabled
        )

        return """
\(promptForCategory)

\(imageAnalysisTaskAndRules)
\(context)
"""
    }


    private static func getInterviewCounterQuestionPrompt() -> String {
    """
CATEGORY: Interview Deep Justification

ROLE:
You are the interviewee (candidate) answering a technical interview question.

GOAL: interview-ready answer and  a complete answer AND proactively address the follow-up questions an interviewer would ask.

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
        realTimeStreamingEnabled _: Bool = false
    ) -> String {
        return getFastStreamingPrompt(
            for: category,
            language: language,
            useInterviewCounterQuestion: useInterviewCounterQuestion
        )
    }

    private static func getFastStreamingPrompt(
        for category: Category,
        language: ProgrammingLanguage,
        useInterviewCounterQuestion: Bool = false
    ) -> String {
        let optionalCounterPrompt = useInterviewCounterQuestion ? "\n\(getInterviewCounterQuestionPrompt())\n" : ""
        let streamingRules = getStreamingSectionRulesForCategory(category, language: language)
        return """
ROLE:
You are a senior fullstack engineer answering technical interview questions.
Strict - interview-ready answer
OUTPUT CONTRACT:
- Strictly follow the streaming rules. <<SECTION:type=short_answer>> <<>>.
- Streaming Block Protocol only.
- No JSON. No markdown.
- No extra text outside tags.
- Interview-ready and concise.

REQUESTED LANGUAGE FOR CODE: \(language.rawValue) (use language=\(language.codeIdentifier) in code section tags).

\(optionalCounterPrompt)

\(streamingRules)
"""
    }

    // MARK: - Streaming: which sections to output per category (so model follows question type)
    private static func getStreamingSectionRulesForCategory(_ category: Category, language: ProgrammingLanguage) -> String {
        switch category {
        case .shortAnswers:
            return commonStreamingFormatRules("""
            CATEGORY RULES (Rapid Interview):
            - short_answer: interview-ready answer
            - details: max 5 bullets with reasoning and trade-offs.
            - code: minimal valid placeholder in \(language.rawValue).
            """)
        case .quickAnswers:
            return commonStreamingFormatRules("""
            CATEGORY RULES (Quick Answers):
            - short_answer: interview-ready answer.
            - details: Brief justification explaining why the answer is correct.
            - No code is required for this category.
            """)
        case .trueFalse:
            return commonStreamingFormatRules("""
            CATEGORY RULES (True/False):
            - short_answer: interview-ready answer, ONLY "True" or "False".
            - details: Brief justification explaining why the answer is correct.
            - code: include only when required by question, else minimal valid placeholder in \(language.rawValue).
            """)
        case .coding:
            return commonStreamingFormatRules("""
            CATEGORY RULES (Coding Interview):
            - code: complete production-ready \(language.rawValue) solution.
            - short_answer: interview-ready answer.
            - details: Approach to solve the problem in simple words, clearly mentioning the technique used (e.g., Sliding Window, HashMap, Two Pointers, Dynamic Programming, etc.).
            - details: Why this is optimal solution and not other approaches.
            - details: Explain how the solution works, key trade-offs, and pitfalls.
            """)
        case .detailedAnswer:
            return commonStreamingFormatRules("""
            CATEGORY RULES (Detailed Answer):
            - short_answer: Provide a direct, interview-ready answer
            - details: how solution works, key trade-offs, and pitfalls.
            - code: complete idiomatic \(language.rawValue) implementation.
            """)
        case .technical:
            return commonStreamingFormatRules("""
            CATEGORY RULES (Technical Deep Dive):
            - short_answer: Provide a direct, interview-ready answer
            - details: why/how, trade-offs, and best practices.
            - code: concise pattern/example in \(language.rawValue) when useful.
            """)
        case .systemDesign:
            return commonStreamingFormatRules("""
            CATEGORY RULES (System Design):
            - short_answer: interview-ready answer, high-level architecture in 2-4 lines.
            - details: requirements, components, bottlenecks, and trade-offs.
            - code: only concrete snippet if essential; otherwise minimal placeholder.
            """)
        case .scenarioBasedSystemDesign:
            return commonStreamingFormatRules("""
            CATEGORY RULES (Scenario-Based Interview Question):
            - short_answer: interview-ready answer, direct plan for the given scenario.
            - code: complete production-ready \(language.rawValue) solution. (only if required; otherwise minimal placeholder.)
            """)
        case .outputType:
            return commonStreamingFormatRules("""
            CATEGORY RULES (Output Type):
            - short_answer: exact output value/text.
            - details: interview-ready answer, Brief justification explaining why the answer is correct.
            """)
        case .mcq:
            return commonStreamingFormatRules("""
            CATEGORY RULES (MCQ):
            - short_answer: interview-ready answer, clearly state one correct option.
            - details: interview-ready answer concise reasoning and why alternatives fail (if helpful).
            """)
        case .codeCorrection:
            return commonStreamingFormatRules("""
            CATEGORY RULES (Code Correction):
            - Input: code or screenshot of code that may be wrong or incorrect. Find the issue and provide the corrected solution.
            - short_answer: interview-ready summary — what was wrong and the fix in 1–2 lines.
            - details: (1) Clear explanation of what was wrong in the original code (bug, logic error, style/security issue, etc.). (2) Explanation of why the corrected solution is correct and how it fixes the issue.
            - code: complete corrected \(language.rawValue) code (production-ready, same language as input when identifiable).
            """)
        case .optimizationCode:
            return commonStreamingFormatRules("""
            CATEGORY RULES (Optimization Code):
            - Input: code or screenshot of code that may need optimization, or where the current implementation could be done in a better way (senior-developer perspective).
            - short_answer: interview-ready summary — current approach vs better approach.
            - details: Current approach: explain what the code does and how it works. (2) What is wrong with it: inefficiencies, readability, maintainability, performance, edge cases, or best-practice gaps. (3) Better approach: explain the optimized strategy and why it is superior (complexity, clarity, idioms, patterns).
            - code: complete optimized \(language.rawValue) code (production-ready, idiomatic; same language as input when identifiable).
            """)
        }
    }

    private static func commonStreamingFormatRules(_ categoryRules: String) -> String {
        """
SECTION ORDER:
1) <<TITLE>> ... <</TITLE>>
2) <<SECTION:type=short_answer>> ... <</SECTION>>
3) <<SECTION:type=details>> ... <</SECTION>>
4) <<SECTION:type=code language=...>> ... <</SECTION>> (ONLY if required by category)
5) <<CONTEXT>> ... <</CONTEXT>>  (MUST be last)

\(categoryRules)

User input may come from speech-to-text and contain incorrect technical spellings
or phonetic substitutions.
Example: - "Cuban eight", "Cuban and", "Kubernate" → Kubernetes
         - "Go routines", "Go routine" → goroutines

CONTEXT FORMAT (keep short):
conversation_summary:
One line.

ai_technical_context:
Assumptions, scale, constraints in 1-2 lines.

Do not output any extra sections or prose outside tags.
"""
    }

    // MARK: - System Design (Full)
    static func buildSystemDesignFullUserPrompt(question: String) -> String {
        """
Question: \(question)

REQUIRED SECTIONS (ORDERED):
1. problem_restatement
2. functional_requirements
3. mermaid_diagram
4. list_of_services_we_will_create
5. high_level_functional_flow
6. detailed_service_flow
7. scalability_strategy

IMPORTANT:
- Context must summarize decisions made in this answer
- In a interview-ready response.
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
        language: ProgrammingLanguage,
        mermaidDiagramCode: String? = nil
    ) -> String {

        let schema = getSystemDesignPhaseSchema(phase)
        let rules = getSystemDesignPhaseRules(phase)
        let mermaidBlock: String
        if phase >= 4, let code = mermaidDiagramCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
            mermaidBlock = """
REFERENCE — MERMAID FLOWCHART FROM PHASE 3 (use this to know which services and flows were designed; your answer must be consistent with this):
```
\(code)
```

"""
        } else {
            mermaidBlock = ""
        }

        return """
Question: \(question)
\(mermaidBlock)
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

    /// Extracts mermaid diagram source from phase 3 sections (for passing into phases 4–7).
    static func extractMermaidFromSections(_ sections: [MessageSection]?) -> String? {
        guard let sections = sections else { return nil }
        guard let mermaid = sections.first(where: { $0.type == .mermaidDiagram }) else { return nil }
        switch mermaid.content {
        case .text(let s): return s.isEmpty ? nil : s
        case .list(let items): let j = items.joined(separator: "\n"); return j.isEmpty ? nil : j
        }
    }

    // MARK: - Phase Schema (phase number → section type; order 1–7)
    private static func getSystemDesignPhaseSchema(_ phase: Int) -> String {
        let types: [Int: String] = [
            1: "problem_restatement",
            2: "functional_requirements",
            3: "mermaid_diagram",
            4: "list_of_services_we_will_create",
            5: "high_level_functional_flow",
            6: "detailed_service_flow",
            7: "scalability_strategy"
        ]
        let type = types[phase] ?? "problem_restatement"
        return #"    { "type": "\#(type)", "content": ["string"] }"#
    }

    // MARK: - Phase Rules — Order 1–7 matches schema
    private static func getSystemDesignPhaseRules(_ phase: Int) -> String {
        switch phase {
        case 1:
            return """
PHASE 1 — PROBLEM RESTATEMENT
- Explain the problem in simple, non-technical terms
- Describe what is being built and why
- Separate into:
  1. Core requirements (must-have)
  2. Optional requirements (nice-to-have)
"""
        case 2:
            return """
PHASE 2 — FUNCTIONAL REQUIREMENTS
- List user-facing requirements
- Describe what the system must do
- Separate into:
  1. Core requirements (must-have)
  2. Optional requirements (nice-to-have)
"""
        case 3:
            return """
PHASE 3 — MERMAID FLOWCHART

Generate a Mermaid flowchart for the system design described above.
Must Follow These Rules:
- Assume a 45–60 minute system design interview.
- Focus on core functionality first.
- Design only the minimum viable system as per requirment
- Mention optional improvements separately, but do NOT include them in the main diagram.


CRITICAL RULES (follow strictly):
Provide syntax error free Mermaid code.

1. Use: flowchart TD
2. Use only:
   - Nodes as: ID[Label]
   - Database nodes as: ID[(Label)]
3. Edges must be:
   - A --> B
   - A -->|label| B
4. Edge labels:
   - Must NOT contain:
     - Angle brackets < >
     - Curly braces { }
     - Parentheses ( )
   - If needed, rewrite them safely.
     Example:
       Instead of: GET /<code>
       Use: GET short_code
5. Node labels:
   - Do NOT use parentheses ( )
   - Do NOT use parentheses ( 
   - Do NOT use parentheses  )
   - Do NOT use brackets inside labels
   - Do NOT use special characters except dash (-) or slash (/)
6. Subgraphs:
   - Use: subgraph Name
   - Do NOT use brackets in subgraph titles
7. Do NOT include explanations.
8. Output ONLY the Mermaid source.
9. The diagram must render without syntax errors.

Output inside section:
<<SECTION:type=mermaid_diagram>>
<mermaid code only>
<<END_SECTION>>

"""
        case 4:
            return """
PHASE 4 — LIST OF SERVICES WE WILL CREATE
- In a interview-ready response.
- List services
"""
        case 5:
            return """
PHASE 5 — HIGH-LEVEL FUNCTIONAL FLOW
- In a interview-ready response.
- Step-by-step logical flow
- Technology-agnostic
"""
        case 6:
            return """
PHASE 6 — DETAILED SERVICE FLOW
- In a interview-ready response.
- Service interactions
- Error handling
- Sync vs async
"""
        case 7:
            return """
PHASE 7 — SCALABILITY STRATEGY
- In a interview-ready response.
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
