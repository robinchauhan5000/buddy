import Foundation

final class StreamingResponseParser {
    private var buffer: String = ""
    private var currentTitle: String = ""
    private var currentSections: [MessageSection] = []
    
    func addChunk(_ chunk: String) -> StreamingResponse? {
        buffer.append(chunk)
        
        // Don't try to parse during streaming - wait for finalize()
        // This avoids trying to parse incomplete JSON
        return nil
    }
    
    func finalize() -> StreamingResponse? {
        print("\n🏁 Finalize called:")
        print("   Buffer size: \(buffer.count) chars")
        print("   Current title: '\(currentTitle)'")
        print("   Current sections: \(currentSections.count)")
        
        // Try one last parse
        if currentTitle.isEmpty && currentSections.isEmpty {
            print("   Attempting final parse...")
            if let parsedResponse = tryParse() {
                print("   ✅ Final parse succeeded!")
                currentTitle = parsedResponse.title
                currentSections = parsedResponse.sections
            } else {
                print("   ❌ Final parse failed")
                print("   📄 Full buffer content:")
                print(buffer)
                return nil
            }
        }
        
        guard !currentTitle.isEmpty || !currentSections.isEmpty else {
            print("⚠️ Finalize: No data to return after all attempts")
            return nil
        }
        
        print("🏁 Finalizing response:")
        print("   Title: \(currentTitle)")
        print("   Sections: \(currentSections.count)")
        for (idx, section) in currentSections.enumerated() {
            print("   [\(idx)] \(section.type)")
        }
        
        return StreamingResponse(
            title: currentTitle,
            sections: currentSections,
            isComplete: true
        )
    }
    
    private func tryParse() -> AIResponse? {
        guard let data = buffer.data(using: .utf8) else {
            print("⚠️ Failed to convert buffer to UTF8 data")
            return nil
        }
        
        do {
            let response = try JSONDecoder().decode(AIResponse.self, from: data)
            print("✅ JSON parsed successfully!")
            print("   Title: \(response.title)")
            print("   Sections: \(response.sections.count)")
            for (idx, section) in response.sections.enumerated() {
                print("   [\(idx)] \(section.type)")
            }
            return response
        } catch {
            print("❌ JSON parsing failed: \(error)")
            print("📄 Buffer length: \(buffer.count) chars")
            print("📄 Buffer content (first 500 chars):")
            print(String(buffer.prefix(500)))
            print("📄 Buffer content (last 500 chars):")
            print(String(buffer.suffix(500)))
            return nil
        }
    }
}
