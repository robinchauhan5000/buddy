import Foundation

enum ProgrammingLanguage: String, CaseIterable, Identifiable {
    case golang = "Golang"
    case javascript = "JavaScript"
    case typescript = "TypeScript"
    case react = "React + TypeScript"
    case java = "Java"
    case sql = "SQL"
    case csharp = "C#"
    case dotnet = "Dotnet"
    
    var id: String { rawValue }
    
    var codeIdentifier: String {
        switch self {
        case .golang:
            return "golang"
        case .javascript:
            return "javascript"
        case .typescript:
            return "typescript"
        case .java:
            return "java"
        case .sql:
            return "sql"
        case .csharp:
            return "csharp"
        case .react:
            return "react"
        case .dotnet:
            return "dotnet"
        }
    }
}
