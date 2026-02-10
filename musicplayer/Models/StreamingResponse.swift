import Foundation

struct StreamingResponse {
    let title: String
    let sections: [MessageSection]
    let isComplete: Bool
}

// MARK: - Streaming chunk join (preserve spaces/newlines across token boundaries)

extension String {
    /// Appends a streamed chunk, inserting a space only when we're clearly at a word boundary.
    /// Avoids splitting words like "Refactor"→"Ref actor" or "Tuning"→"T uning" (chunk starts with lowercase = continuation).
    /// Inserts space when: chunk starts with uppercase (new word), or chunk is a short standalone word ("a", "to", "or", etc.).
    func appendingStreamingChunk(_ chunk: String) -> String {
        guard !isEmpty, !chunk.isEmpty else { return self + chunk }
        let last = self.last!, first = chunk.first!
        if last.isWhitespace || first.isWhitespace || last == "\n" || first == "\n" { return self + chunk }
        guard last.isLetter || last.isNumber, first.isLetter || first.isNumber else { return self + chunk }
        // New chunk starts new word (uppercase) -> add space
        if first.isUppercase { return self + " " + chunk }
        // Very short chunk that's usually a standalone word -> add space (e.g. "Use" + "a" -> "Use a")
        if chunk.count <= 2 && chunk.allSatisfy({ $0.isLetter }) {
            let shortWords = ["a", "i", "an", "to", "or", "in", "on", "of", "is", "it", "as", "be", "by", "we", "so", "no", "up", "if", "at", "do", "go", "my", "me", "us"]
            if shortWords.contains(chunk.lowercased()) { return self + " " + chunk }
        }
        // Chunk starts with lowercase (e.g. "actor", "uning") -> likely same word, no space
        return self + chunk
    }
}
