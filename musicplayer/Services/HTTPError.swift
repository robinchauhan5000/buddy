import Foundation

enum HTTPError: Error {
    case invalidURL
    case invalidResponse
    case requestFailed(Error)
    case decodingFailed(Error)
    case statusCode(Int)
    case timeout
    case unknown
    
    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Decoding failed: \(error.localizedDescription)"
        case .statusCode(let code):
            return "HTTP status code: \(code)"
        case .timeout:
            return "Request timeout"
        case .unknown:
            return "Unknown error"
        }
    }
}
