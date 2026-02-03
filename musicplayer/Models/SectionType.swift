import Foundation

enum SectionType: String, Codable {
    case shortAnswer = "short_answer"
    case details = "details"
    case code = "code"
    case functionalRequirements = "functional_requirements"
    case mainComponentsAndResponsibilities = "main_components_and_responsibilities"
    case highLevelDataFlow = "high_level_data_flow"
    case tradeOffsInDesignDecisions = "trade_offs_in_design_decisions"
    case makeCurrentSystemScalable = "make_current_system_scalable"
    case highLevelCode = "high_level_code"
    case lowLevelCode = "low_level_code"

    var displayName: String {
        switch self {
        case .shortAnswer:
            return "Answer"
        case .details:
            return "Details"
        case .code:
            return "Code"
        case .functionalRequirements:
            return "Functional Requirements"
        case .mainComponentsAndResponsibilities:
            return "Main Components"
        case .highLevelDataFlow:
            return "Data Flow"
        case .tradeOffsInDesignDecisions:
            return "Trade-offs"
        case .makeCurrentSystemScalable:
            return "Scalability"
        case .highLevelCode:
            return "High Level Code"
        case .lowLevelCode:
            return "Low Level Code"
        }
    }
}
