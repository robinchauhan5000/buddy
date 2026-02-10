import Foundation

// MARK: - Stream event (streaming UI + structured parse)

/// Events emitted by the stream parser: immediate tokens for UI and final structured result.
/// Use when the model streams a single JSON object (e.g. `{"title":"...","sections":[...]}`).
///
/// Consumer example:
/// ```swift
/// for await chunk in contentStream {
///     for event in parser.parse(chunk: chunk) {
///         switch event {
///         case .token(let text): streamedText.append(text)
///         case .completed(let response): structuredResponse = response
///         }
///     }
/// }
/// ```
public enum StreamEvent {
    /// Raw token chunk — emit to UI immediately for real-time streaming.
    case token(String)
    /// Full JSON decoded — emit once when the complete object has been received.
    case completed(AIResponse)
}

public struct StreamParser {
    private var buffer = ""
    private var bracketCount = 0
    private var isInString = false
    private var isEscaped = false

    public init() {}
    
    public mutating func parse(chunk: String) -> [StreamEvent] {
        var events: [StreamEvent] = []

        // Always stream tokens immediately so UI is not blocked.
        events.append(.token(chunk))

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

        // Decode only once when the full JSON object is closed.
        if bracketCount == 0, buffer.first == "{" {
            if let response = tryParse() {
                events.append(.completed(response))
                reset()
            }
        }

        return events
    }

    private mutating func reset() {
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
