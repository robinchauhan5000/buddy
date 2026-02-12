import Foundation

enum SectionType: String, Codable {
    // Basic section types
    case shortAnswer = "short_answer"
    case details = "details"
    case code = "code"
    
    // System Design - 15 Phases
    case problemRestatement = "problem_restatement"
    case functionalRequirements = "functional_requirements"
    case nonFunctionalRequirements = "non_functional_requirements"
    case highLevelFunctionalFlow = "high_level_functional_flow"
    case systemBoundariesAndAssumptions = "system_boundaries_and_assumptions"
    case servicesWeWillCreate = "services_we_will_create"
    case listOfServicesWeWillCreate = "list_of_services_we_will_create"
    case detailedServiceFlow = "detailed_service_flow"
    case dataModelAndStorageDesign = "data_model_and_storage_design"
    case dataFlowBetweenServices = "data_flow_between_services"
    case deduplicationAndIdempotency = "deduplication_and_idempotency"
    case reportingMonitoringObservability = "reporting_monitoring_observability"
    case highLevelDesign = "high_level_design"
    case scalabilityStrategy = "scalability_strategy"
    case tradeOffsAndAlternatives = "trade_offs_and_alternatives"
    case failureScenariosAndRecovery = "failure_scenarios_and_recovery"
    case mermaidDiagram = "mermaid_diagram"

    var displayName: String {
        switch self {
        // Basic section types
        case .shortAnswer:
            return "Answer"
        case .details:
            return "Details"
        case .code:
            return "Code"
            
        // System Design - 15 Phases
        case .problemRestatement:
            return "Problem Restatement"
        case .functionalRequirements:
            return "Functional Requirements"
        case .nonFunctionalRequirements:
            return "Non-Functional Requirements"
        case .highLevelFunctionalFlow:
            return "High-Level Functional Flow"
        case .systemBoundariesAndAssumptions:
            return "System Boundaries & Assumptions"
        case .servicesWeWillCreate:
            return "Services We Will Create"
        case .listOfServicesWeWillCreate:
            return "List of Services We Will Create"
        case .detailedServiceFlow:
            return "Detailed Service Flow"
        case .dataModelAndStorageDesign:
            return "Data Model & Storage Design"
        case .dataFlowBetweenServices:
            return "Data Flow Between Services"
        case .deduplicationAndIdempotency:
            return "Deduplication & Idempotency"
        case .reportingMonitoringObservability:
            return "Reporting, Monitoring & Observability"
        case .highLevelDesign:
            return "High-Level Design"
        case .scalabilityStrategy:
            return "Scalability Strategy"
        case .tradeOffsAndAlternatives:
            return "Trade-offs & Alternatives"
        case .failureScenariosAndRecovery:
            return "Failure Scenarios & Recovery"
        case .mermaidDiagram:
            return "Mermaid Diagram"
        }
    }
}
