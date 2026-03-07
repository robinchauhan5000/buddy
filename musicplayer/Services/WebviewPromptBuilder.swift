//
//  WebViewPromptBuilder.swift
//  musicplayer
//
//  Structured Interview Prompt Builder
//  No XML. No context.
//  All categories supported including full System Design.
//

import Foundation

enum WebViewPromptBuilder {

    // MARK: - Public Builder

    /// Builds the full prompt to send to the webview (ChatGPT). Uses category rules and optional counter-question instructions.
    /// Call this when webview is active so the injected message includes role, category rules, and user question.
    static func buildPromptForWebView(
        userInput: String,
        category: Category,
        language: ProgrammingLanguage,
        useInterviewCounterQuestion: Bool = false
    ) -> String {
        let categoryRules = getStreamingSectionRulesForCategory(category, language: language)
        let counterBlock = useInterviewCounterQuestion ? "\n\(getInterviewCounterQuestionPromptForWebView())\n" : ""
        return """
        You are a senior fullstack engineer answering technical interview questions. 
        Important: if you are using short forms then add full form like API (application programming interface) instead of API.

        Important: whenever there is explaination of something then provide interview-ready answer only so that i can read text directly to the interviewer.

        Requested language for code: \(language.rawValue).
        \(counterBlock)
        \(categoryRules)

        User input may come from speech-to-text and contain incorrect technical spellings or phonetic substitutions.
        Examples: "Kubernate" → Kubernetes, "Go routines" → goroutines, "geml" → yaml, "DHSP" → DHCP.

        User Question:
        \(userInput)
        """
    }

    /// Legacy: build prompt when caller supplies categoryRules string (e.g. from elsewhere). Prefer buildPromptForWebView.
    static func buildPrompt(
        category: Category,
        userInput: String,
        language: ProgrammingLanguage,
        categoryRules: String
    ) -> String {
        let streamingRules = getStreamingSectionRulesForCategory(category, language: language)
        return """
        \(categoryRules)

        if you are using short forms then add full form like API (application programming interface) instead of API.
        You are answering as a senior technical interviewer. Provide interview-ready answer in the requested category.
        \(streamingRules)

        User input may come from speech-to-text and contain incorrect technical spellings
        or phonetic substitutions.

        Example corrections:
        - "Cuban eight", "Cuates", "Cuban and", "Kubernate" → Kubernetes
        - "Go routines", "Go routine" → goroutines
        - "A PAN", "IPM" → IPAM
        - "DHSP", "DHS" → DHCP
        - "trash loop back", "loop back" → CrashLoopBackOff
        - "geml", "gem" → yaml

        User Question:
        \(userInput)
        """
    }

    private static func getInterviewCounterQuestionPromptForWebView() -> String {
        """
        CATEGORY: Interview Deep Justification
        - Explain WHY a particular approach or technology was chosen.
        - Explain the ROLE of each major component and what PROBLEM each choice solves.
        - Discuss ALTERNATIVES and why they were not chosen.
        - Explain BENEFITS, TRADE-OFFS, and how the choice behaves at SCALE and under FAILURE.
        - Confident, senior-level, interview-style. No rhetorical questions. Justify every major decision.
        """
    }

    // MARK: - Streaming Rules Per Category

    private static func getStreamingSectionRulesForCategory(
        _ category: Category,
        language: ProgrammingLanguage
    ) -> String {

        switch category {

        case .shortAnswers:
            return """
            CATEGORY RULES (Rapid Interview):
            - short_answer: interview-ready answer.
            - details: interview-ready answer, max 5 bullets with reasoning and trade-offs.
            - code: minimal valid placeholder in \(language.rawValue).
            """

        case .quickAnswers:
            return """
            CATEGORY RULES (Quick Answers):
            - short_answer: interview-ready answer.
            - details: interview-ready answer, brief justification.
            - code: minimal valid placeholder in \(language.rawValue).
            """

        case .trueFalse:
            return """
            CATEGORY RULES (True/False):
            - short_answer: ONLY "True" or "False".
            - details: brief justification.
            - code: only if required; else minimal placeholder in \(language.rawValue).
            """

        case .coding:
            return """
            CATEGORY RULES (Coding Interview):
            - code:
                Fully function Code, clean, interview-ready solution in \(language.rawValue).
                Solve ONLY what is asked. Dont just define but Show me also how to use it
                No CLI handling, file I/O, logging, or production extras unless required.
                Focus strictly on core logic.
            - short_answer: Interview-ready answer, explain the approach in layman language. dont mention about screenshot.
            - details (Answer the below questions so i can read text directly to the interviewer):
                - Approach:Explain technique used In layman language and interview-ready answer .
                - How it works:In layman language,interview-ready answer, Explain how this technique works in detail.
                - Code:In layman language,Interview-ready answer, explain code step by step with code snippet and explain the logic behind the code with comments.
                - Why optimal:In layman language,Interview-ready answer, Why this is optimal solution and not other approaches.
            """

        case .detailedAnswer:
            return """
            CATEGORY RULES (Detailed Answer):
            - short_answer: direct interview-ready answer.
            - details: deep explanation, trade-offs, and pitfalls.
            - code: idiomatic \(language.rawValue) implementation if relevant.
            """

        case .devops:
            return """
            CATEGORY RULES (DevOps Interview):
            - short_answer: direct answer (CI/CD, Kubernetes, infra, monitoring).
            - details: production reasoning, trade-offs, reliability considerations.
            - code: concise example (Dockerfile, YAML, script, config) in \(language.rawValue) if useful.
            """

        // 🔥 FULL SYSTEM DESIGN (FAANG STRUCTURE)

        case .systemDesign:
    return """
    You MUST produce all 7 sections in this exact logical order and provide interview-ready answer:

    1) problem_restatement
    2) mermaid_diagram
    3) how_this_current_approach_works
    4) list_of_services_we_will_create
    5) issues_with_current_implementation
    6) better_approach
    7) how_this_better_approach_works

    SECTION RULES:

    - short_answer:
        High-level architecture summary in 2–4 lines.

    - details:
        Must include ALL 7 structured sections as described above.
        Each section must be clear, interview-ready, and senior-level.

    STRUCTURE EXPECTATION (inside details):

    problem_restatement:
        - interview-ready answer, Restate scope, constraints, and success criteria.

    mermaid_diagram:
        - Provide valid Mermaid flowchart (flowchart TD).
        - Must render without syntax errors.
        - No explanation text inside diagram section.

    how_this_current_approach_works:
        - interview-ready answer, Explain request/data flow.
        - interview-ready answer, Clarify ownership of data.
        - interview-ready answer, Mention one trade-off.

    list_of_services_we_will_create:
        - interview-ready answer, List services with one-line responsibility.
        - Order by request flow.

    issues_with_current_implementation:
        - 3–5 concrete scaling or reliability issues.
        - Be specific (e.g., bottleneck, SPOF, consistency risk).

    better_approach:
        - Propose improved architecture.
        - Justify improvements.
        - Mention trade-offs.

    how_this_better_approach_works:
        - Explain improved flow.
        - Show how earlier issues are solved.
        - Mention remaining trade-offs.

    Must sound like a senior software engineer in a system design round.
    """

        // 🔥 SCENARIO-BASED DESIGN (REAL-WORLD PROBLEM SOLVING)

        case .scenarioBasedSystemDesign:
            return """
            CATEGORY RULES (Scenario-Based System Design):

            - short_answer:
                Direct implementation plan for the scenario.

            - details:
                1) Understand Constraints & Edge Cases
                2) Identify Failure Points
                3) Proposed Architecture
                4) Scaling & Resilience Plan
                5) Data Consistency Model
                6) Monitoring & Observability
                7) Trade-offs & Alternatives

            - code:
                Provide concrete \(language.rawValue) snippet only if the scenario requires it.
            """

        case .outputType:
            return """
            CATEGORY RULES (Output Type):
            - short_answer: exact output only.
            - details:
                - interview-ready answer, Why this output occurs.
                - interview-ready answer, Underlying concept.
                - interview-ready answer, Example explanation.
            """

        case .mcq:
            return """
            CATEGORY RULES (MCQ):
            - short_answer: clearly state ONE correct option.
            - details: interview-ready answer, concise reasoning and why others are incorrect.
            """

        case .codeCorrection:
            return """
            CATEGORY RULES (Code Correction):
            - short_answer: interview-ready answer, summary of bug and fix.
            - details:
                - What was wrong
                - interview-ready answer, Exact problematic line
                - interview-ready answer, Why it fails
                - interview-ready answer, Why fix works
            - code: complete corrected \(language.rawValue) solution.
            """

        case .optimizationCode:
            return """
            CATEGORY RULES (Optimization Code):
            - short_answer: interview-ready answer, current vs improved approach summary.
            - details:
                - What current code does
                - interview-ready answer, Inefficiencies
                - interview-ready answer, Better approach and complexity comparison
            - code: optimized idiomatic \(language.rawValue) solution.
            """
        }
    }
}