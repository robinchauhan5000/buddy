//
//  SessionInfoView.swift
//  musicplayer
//
//  Created by Robin Chauhan on 03/02/26.
//

import SwiftUI

struct SessionInfoView: View {
    @ObservedObject var chatViewModel: ChatViewModel
    
    var body: some View {
        ChatView(
            viewModel: chatViewModel
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SessionInfoView(
        chatViewModel: ChatViewModel()
    )
}
