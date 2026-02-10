# Streaming Architecture Fix

## Problem

The previous `StreamingResponseParser` was blocking UI updates because it:

- Accumulated all chunks in a buffer
- Only emitted responses after the full JSON was received
- Mixed two responsibilities: UI streaming and structured parsing

## Solution

Implemented proper event-based streaming with `StreamParser`:

### Architecture

```
Token Stream
    ↓
StreamParser
    ↓
┌─────────────────┬──────────────────┐
│  .token(String) │ .completed(AIResponse) │
│  (immediate UI) │ (final structured)     │
└─────────────────┴──────────────────┘
```

### Key Changes

1. **StreamEvent enum** - Two distinct events:
   - `.token(String)` - Emitted immediately for real-time UI updates
   - `.completed(AIResponse)` - Emitted once when full JSON is decoded

2. **StreamParser** - Separates concerns:
   - Always emits tokens immediately (no blocking)
   - Accumulates buffer in background
   - Decodes JSON only when complete (bracket count = 0)

3. **Service Integration** - Updated:
   - OpenAIService ✅
   - ClaudeAIService ✅
   - GeminiService ✅
   - GrokService (no streaming needed)
   - DeepSeekService (no streaming needed)

### Usage Pattern

```swift
var parser = StreamParser()
var streamedText = ""

for try await chunk in stream {
    let events = parser.parse(chunk: chunk)

    for event in events {
        switch event {
        case .token(let text):
            // Update UI immediately
            streamedText.append(text)
            yield StreamingResponse(...)

        case .completed(let aiResponse):
            // Use structured data
            yield StreamingResponse(
                title: aiResponse.title,
                sections: aiResponse.sections,
                isComplete: true
            )
        }
    }
}
```

## Benefits

- ✅ Real-time UI streaming (no blocking)
- ✅ Safe JSON decoding (respects Swift Codable)
- ✅ Clean separation of concerns
- ✅ Production-ready architecture
