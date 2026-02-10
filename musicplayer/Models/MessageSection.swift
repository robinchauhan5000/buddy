import Foundation

public struct MessageSection: Codable, Identifiable, Equatable {
    public let id: UUID
    public let type: SectionType
    public let content: SectionContent
    public let language: String?
    
    public static func == (lhs: MessageSection, rhs: MessageSection) -> Bool {
        lhs.id == rhs.id &&
        lhs.type == rhs.type &&
        lhs.content == rhs.content &&
        lhs.language == rhs.language
    }
    
    public init(id: UUID = UUID(), type: SectionType, content: SectionContent, language: String? = nil) {
        self.id = id
        self.type = type
        self.content = content
        self.language = language
    }
    
    enum CodingKeys: String, CodingKey {
        case type
        case content
        case language
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.type = try container.decode(SectionType.self, forKey: .type)
        self.language = try container.decodeIfPresent(String.self, forKey: .language)
        
        if let stringContent = try? container.decode(String.self, forKey: .content) {
            self.content = .text(stringContent)
        } else if let arrayContent = try? container.decode([String].self, forKey: .content) {
            self.content = .list(arrayContent)
        } else {
            self.content = .text("")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(language, forKey: .language)
        
        switch content {
        case .text(let string):
            try container.encode(string, forKey: .content)
        case .list(let array):
            try container.encode(array, forKey: .content)
        }
    }
}

public enum SectionContent: Codable, Equatable {
    case text(String)
    case list([String])
    
    public var displayText: String {
        switch self {
        case .text(let string):
            return string
        case .list(let array):
            return array.joined(separator: "\n")
        }
    }
    
    public var asList: [String] {
        switch self {
        case .text(let string):
            return [string]
        case .list(let array):
            return array
        }
    }
}
