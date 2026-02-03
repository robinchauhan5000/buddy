//
//  AIProvider.swift
//  musicplayer
//
//  Created by Robin Chauhan on 03/02/26.
//

import Foundation

enum AIProvider: String, CaseIterable, Identifiable {
    case openAI = "OpenAI"
    case gemini = "Gemini"
    case streaming = "Streaming"
    
    var id: String { rawValue }
}
