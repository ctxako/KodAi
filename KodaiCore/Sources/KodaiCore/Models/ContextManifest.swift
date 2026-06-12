import Foundation

public struct ContextManifest: Codable, Sendable {
    public var blocks: [ContextBlockRecord]
    public var totalTokens: Int
    public var budgetLimit: Int
    public var promptVersion: String

    public init(
        blocks: [ContextBlockRecord],
        totalTokens: Int,
        budgetLimit: Int,
        promptVersion: String = "1.0"
    ) {
        self.blocks = blocks
        self.totalTokens = totalTokens
        self.budgetLimit = budgetLimit
        self.promptVersion = promptVersion
    }
}
