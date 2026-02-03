import Foundation

final class StreamingResponseParser {
    private var buffer: String = ""
    private var currentTitle: String = ""
    private var currentSections: [MessageSection] = []
    
    func addChunk(_ chunk: String) -> StreamingResponse? {
        buffer.append(chunk)
        
        guard let parsedResponse = tryParse() else {
            return nil
        }
        
        currentTitle = parsedResponse.title
        currentSections = parsedResponse.sections
        
        return StreamingResponse(
            title: currentTitle,
            sections: currentSections,
            isComplete: false
        )
    }
    
    func finalize() -> StreamingResponse? {
        guard !currentTitle.isEmpty || !currentSections.isEmpty else {
            return nil
        }
        
        return StreamingResponse(
            title: currentTitle,
            sections: currentSections,
            isComplete: true
        )
    }
    
    private func tryParse() -> AIResponse? {
        guard let data = buffer.data(using: .utf8) else {
            return nil
        }
        
        return try? JSONDecoder().decode(AIResponse.self, from: data)
    }
}
