import Foundation

enum ProgrammingLanguage: String, CaseIterable, Identifiable {
    case golang = "Golang"
    case swift = "Swift"
    case python = "Python"
    case javascript = "JavaScript"
    case typescript = "TypeScript"
    case java = "Java"
    case kotlin = "Kotlin"
    case rust = "Rust"
    case cpp = "C++"
    case csharp = "C#"
    case ruby = "Ruby"
    case php = "PHP"
    case go = "Go"
    
    var id: String { rawValue }
    
    var codeIdentifier: String {
        switch self {
        case .golang, .go:
            return "golang"
        case .swift:
            return "swift"
        case .python:
            return "python"
        case .javascript:
            return "javascript"
        case .typescript:
            return "typescript"
        case .java:
            return "java"
        case .kotlin:
            return "kotlin"
        case .rust:
            return "rust"
        case .cpp:
            return "cpp"
        case .csharp:
            return "csharp"
        case .ruby:
            return "ruby"
        case .php:
            return "php"
        }
    }
}
