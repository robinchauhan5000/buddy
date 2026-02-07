//
//  AIProvider.swift
//  musicplayer
//
//  Created by Robin Chauhan on 03/02/26.
//

import Foundation

enum AIProvider: String, CaseIterable, Identifiable {
    case openAI = "OpenAI"
    case claude = "Claude"
    case gemini = "Gemini"
    case grok = "Grok"
    case deepseek = "DeepSeek"
    
    var id: String { rawValue }

    var description: String {
        switch self {
        case .openAI:
            return "GPT-4 powered responses with vision support"
        case .claude:
            return "Anthropic's Claude with strong reasoning and long context"
        case .gemini:
            return "Google's multimodal AI model"
        case .grok:
            return "X.AI's Grok-4 with advanced reasoning"
        case .deepseek:
            return "DeepSeek's advanced AI with strong coding capabilities"
        }
    }
}
