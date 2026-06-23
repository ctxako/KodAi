public nonisolated struct LlamaPromptBuildResult: Sendable {
    public let prompt: String
    public let includedMessageCount: Int
    public let historyIncluded: Bool

    public init(prompt: String, includedMessageCount: Int, historyIncluded: Bool) {
        self.prompt = prompt
        self.includedMessageCount = includedMessageCount
        self.historyIncluded = historyIncluded
    }
}
