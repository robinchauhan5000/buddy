import Foundation

struct StreamingResponse {
    let title: String
    let sections: [MessageSection]
    let isComplete: Bool
}

// MARK: - Streaming chunk join (preserve spaces/newlines across token boundaries)

extension String {
    /// Appends a streamed chunk, inserting a space when the boundary would glue two words (APIs often drop spaces at token boundaries).
    /// Exception: if existing is a single uppercase letter (e.g. "T"), don't add space so "T" + "uning" → "Tuning".
    func appendingStreamingChunk(_ chunk: String) -> String {
        guard !isEmpty, !chunk.isEmpty else { return self + chunk }
        let last = self.last!, first = chunk.first!
        if last.isWhitespace || first.isWhitespace || last == "\n" || first == "\n" { return self + chunk }
        guard last.isLetter || last.isNumber, first.isLetter || first.isNumber else { return self + chunk }
        // Don't add space when existing is single uppercase (e.g. "T" + "uning" → "Tuning")
        if count == 1, last.isUppercase { return self + chunk }
        return self + " " + chunk
    }

    /// Appends a code chunk with spaces only at safe boundaries so identifiers stay intact (EncodeToString, RWMutex).
    /// Adds space when: chunk starts with lowercase ("package " + "main"), or chunk starts with ( ) = , ; : { }
    /// Does NOT add space when chunk starts with uppercase (keeps "Encode" + "ToString" → "EncodeToString").
    func appendingCodeChunk(_ chunk: String) -> String {
        guard !isEmpty, !chunk.isEmpty else { return self + chunk }
        let last = self.last!, first = chunk.first!
        if last.isWhitespace || first.isWhitespace || last == "\n" || first == "\n" { return self + chunk }
        // Add space after ) } ] when next is letter so ") " + "string" type
        if (last == ")" || last == "}" || last == "]") && (first.isLetter || first.isNumber) { return self + " " + chunk }
        // Add space before ( ) = , ; : { } when preceded by letter/digit so "import" + "(" → "import ("
        if first == "(" || first == ")" || first == "=" || first == "," || first == ";" || first == ":" || first == "{" || first == "}" {
            if last.isLetter || last.isNumber || last == "]" || last == ")" { return self + " " + chunk }
            return self + chunk
        }
        // Add space between words only when chunk starts with lowercase (so "var" + "urlStore" → "var urlStore", but "Encode" + "ToString" stays)
        if last.isLetter || last.isNumber {
            if first.isLowercase || first.isNumber { return self + " " + chunk }
            return self + chunk
        }
        return self + chunk
    }
}
