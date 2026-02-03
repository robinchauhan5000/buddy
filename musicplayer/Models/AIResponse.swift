import Foundation

struct AIResponse: Codable, Equatable {
    let title: String
    let sections: [MessageSection]
}
