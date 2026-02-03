//
//  SessionState.swift
//  musicplayer
//
//  Created by Robin Chauhan on 03/02/26.
//

import Foundation

enum SessionState {
    case active
    case inactive
    case paused
    
    var displayText: String {
        switch self {
        case .active:
            return "ACTIVE"
        case .inactive:
            return "INACTIVE"
        case .paused:
            return "PAUSED"
        }
    }
}
