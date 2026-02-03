//
//  SessionInfoView.swift
//  musicplayer
//
//  Created by Robin Chauhan on 03/02/26.
//

import SwiftUI

struct SessionInfoView: View {
    @ObservedObject var chatViewModel: ChatViewModel
    let isRecording: Bool
    let onRecord: () -> Void
    
    var body: some View {
        ChatView(
            viewModel: chatViewModel,
            isRecording: isRecording,
            onRecord: onRecord
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SessionInfoView(
        chatViewModel: ChatViewModel(),
        isRecording: false,
        onRecord: {}
    )
}
