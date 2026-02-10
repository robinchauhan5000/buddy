import Foundation

public struct AIResponse: Codable, Equatable {
    public let title: String
    public let sections: [MessageSection]
    
    public init(title: String, sections: [MessageSection]) {
        self.title = title
        self.sections = sections
    }
}
