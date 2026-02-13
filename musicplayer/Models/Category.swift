//
//  Category.swift
//  musicplayer
//
//  Created by Robin Chauhan on 03/02/26.
//

import Foundation

enum Category: String, CaseIterable, Identifiable {
    case normal = "Normal"
    case shortAnswers = "Short Answers interview"
    case quickAnswers = "Quick Answers interview"
    case trueFalse = "True/False interview"
    case systemDesign = "System Design interview"
    case scenarioBasedSystemDesign = "Scenario-Based System Design interview"
    case technical = "Technical Discussion interview"
    case coding = "Coding Round interview"
    case outputType = "Output Type interview"
    case mcq = "MCQ interview"
    
    var id: String { rawValue }
}
