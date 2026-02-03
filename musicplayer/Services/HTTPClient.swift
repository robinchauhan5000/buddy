import Foundation

final class HTTPClient {
    private let baseURL: String
    private let defaultHeaders: [String: String]
    private let timeout: TimeInterval
    private let session: URLSession
    
    init(
        baseURL: String,
        defaultHeaders: [String: String] = [:],
        timeout: TimeInterval = 30
    ) {
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
        self.timeout = timeout
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: configuration)
    }
    
    func post<T: Decodable>(
        _ endpoint: String,
        body: [String: Any]? = nil,
        headers: [String: String]? = nil
    ) async throws -> T {
        guard let url = URL(string: baseURL + endpoint) else {
            throw HTTPError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = mergeHeaders(headers)
        
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        return try await execute(request)
    }
    
    func postRaw(
        _ endpoint: String,
        body: [String: Any]? = nil,
        headers: [String: String]? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: baseURL + endpoint) else {
            throw HTTPError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = mergeHeaders(headers)
        
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        return try await executeRaw(request)
    }
    
    func get<T: Decodable>(
        _ endpoint: String,
        headers: [String: String]? = nil
    ) async throws -> T {
        guard let url = URL(string: baseURL + endpoint) else {
            throw HTTPError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = mergeHeaders(headers)
        
        return try await execute(request)
    }
    
    func getRaw(
        _ endpoint: String,
        headers: [String: String]? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: baseURL + endpoint) else {
            throw HTTPError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = mergeHeaders(headers)
        
        return try await executeRaw(request)
    }
    
    func stream(
        _ endpoint: String,
        body: [String: Any]? = nil,
        headers: [String: String]? = nil,
        onChunk: @escaping (Data) -> Void
    ) async throws {
        guard let url = URL(string: baseURL + endpoint) else {
            throw HTTPError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = mergeHeaders(headers)
        
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        let (asyncBytes, response) = try await session.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw HTTPError.statusCode(httpResponse.statusCode)
        }
        
        for try await byte in asyncBytes {
            onChunk(Data([byte]))
        }
    }
    
    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await executeRaw(request)
        
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw HTTPError.decodingFailed(error)
        }
    }
    
    private func executeRaw(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HTTPError.invalidResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw HTTPError.statusCode(httpResponse.statusCode)
            }
            
            return (data, httpResponse)
        } catch let error as HTTPError {
            throw error
        } catch {
            throw HTTPError.requestFailed(error)
        }
    }
    
    private func mergeHeaders(_ additional: [String: String]?) -> [String: String] {
        var merged = defaultHeaders
        additional?.forEach { merged[$0.key] = $0.value }
        return merged
    }
}
