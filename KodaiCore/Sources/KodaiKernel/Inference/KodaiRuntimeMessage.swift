import Foundation

public struct KodaiRuntimeMessage: Sendable {
    public let role: ChatRole
    public let text: String

    public init(role: ChatRole, text: String) {
        self.role = role
        self.text = text
    }
}
