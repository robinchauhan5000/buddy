//
//  InterviewCopilotViewModel.swift
//  musicplayer
//
//  Created by Robin Chauhan on 03/02/26.
//

import Foundation
import Combine

@MainActor
class InterviewCopilotViewModel: ObservableObject {
    @Published var selectedProvider: AIProvider = .openAI
    @Published var selectedCategory: Category = .normal
    @Published var sessionState: SessionState = .active
    @Published var isRecording: Bool = false
    
    // MARK: - Computed Properties
    
    // MARK: - Actions
    
    func selectProvider(_ provider: AIProvider) {
        selectedProvider = provider
    }
    
    func selectCategory(_ category: Category) {
        selectedCategory = category
    }
    
    func toggleRecording() {
        isRecording.toggle()
    }
    
    func toggleMicrophone() {
        print("Toggle microphone")
    }
    
    func shareScreen() {
        print("Share screen")
    }
    
    func deleteSession() {
        print("Delete session")
    }
}
