import Foundation

struct StreamingResponse {
    let title: String
    let sections: [MessageSection]
    let isComplete: Bool
    let contextPayload: String?

    init(title: String, sections: [MessageSection], isComplete: Bool, contextPayload: String? = nil) {
        self.title = title
        self.sections = sections
        self.isComplete = isComplete
        self.contextPayload = contextPayload
    }
}
