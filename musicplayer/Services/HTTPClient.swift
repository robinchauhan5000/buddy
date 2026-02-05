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
        onEvent: @escaping (String) -> Void
    ) async throws {
        guard let url = URL(string: baseURL + endpoint) else {
            throw HTTPError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Merge headers with SSE-specific headers
        var streamHeaders = mergeHeaders(headers)
        streamHeaders["Accept"] = "text/event-stream"
        streamHeaders["Cache-Control"] = "no-cache"
        request.allHTTPHeaderFields = streamHeaders
        
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
        
        var buffer = ""
        
        // Stream line-by-line, not byte-by-byte
        for try await byte in asyncBytes {
            try Task.checkCancellation()
            
            buffer.append(Character(UnicodeScalar(byte)))
            
            // Process complete lines (SSE events end with \n)
            while buffer.contains("\n") {
                let parts = buffer.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                let line = String(parts[0])
                buffer = parts.count > 1 ? String(parts[1]) : ""
                
                // Skip empty lines and non-data lines
                guard line.hasPrefix("data: ") else { continue }
                
                let payload = line.replacingOccurrences(of: "data: ", with: "").trimmingCharacters(in: .whitespaces)
                
                // Check for stream termination
                if payload == "[DONE]" {
                    return
                }
                
                // Emit complete JSON payload to caller
                await MainActor.run {
                    onEvent(payload)
                }
            }
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
