import Foundation

struct StreamParser {
    private var buffer: String = ""
    private var bracketCount: Int = 0
    private var isInString: Bool = false
    private var isEscaped: Bool = false
    
    mutating func parse(chunk: String) -> AIResponse? {
        buffer.append(chunk)
        
        for char in chunk {
            if isEscaped {
                isEscaped = false
                continue
            }
            
            if char == "\\" {
                isEscaped = true
                continue
            }
            
            if char == "\"" {
                isInString.toggle()
                continue
            }
            
            if !isInString {
                if char == "{" {
                    bracketCount += 1
                } else if char == "}" {
                    bracketCount -= 1
                }
            }
        }
        
        if bracketCount == 0 && buffer.contains("{") {
            return tryParse()
        }
        
        return nil
    }
    
    mutating func reset() {
        buffer = ""
        bracketCount = 0
        isInString = false
        isEscaped = false
    }
    
    private func tryParse() -> AIResponse? {
        guard let data = buffer.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AIResponse.self, from: data)
    }
}
