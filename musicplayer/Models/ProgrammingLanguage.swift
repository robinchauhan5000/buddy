import Foundation

enum ProgrammingLanguage: String, CaseIterable, Identifiable {
    case golang = "Golang"
    case javascript = "JavaScript"
    case typescript = "TypeScript"
    case react = "React + TypeScript"
    case java = "Java"
    case sql = "SQL"
    case kubernetes = "Kubernetes"
    case css = "HTML + CSS"
    case shellScripting = "Shell Scripting"
    case kafka = "Kafka"
    case docker = "Docker"
    
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
        case .kubernetes:
            return "kubernetes"
        case .react:
            return "react + typescript"
        case .css:
            return "html+css"
        case .shellScripting:
            return "shell scripting"
        case .kafka:
            return "kafka"
        case .docker:
            return "docker"
        }
    }
}
