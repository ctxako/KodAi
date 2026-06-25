import Foundation
import SwiftData

@Model
final class ActionLogEntry {
    var id: UUID
    var timestamp: Date
    var originalInput: String
    var toolName: String
    var parameters: String
    var status: String
    var errorMessage: String?

    init(
        originalInput: String,
        toolName: String,
        parameters: String,
        status: String,
        errorMessage: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.originalInput = originalInput
        self.toolName = toolName
        self.parameters = parameters
        self.status = status
        self.errorMessage = errorMessage
    }
}

actor ActionLogger {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    @MainActor
    func log(
        originalInput: String,
        toolName: String,
        parameters: [String: String],
        status: String,
        errorMessage: String? = nil
    ) {
        let paramsJSON = (try? JSONSerialization.data(withJSONObject: parameters, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        let entry = ActionLogEntry(
            originalInput: originalInput,
            toolName: toolName,
            parameters: paramsJSON,
            status: status,
            errorMessage: errorMessage
        )
        let context = container.mainContext
        context.insert(entry)
        pruneIfNeeded(context: context)
    }

    @MainActor
    private func pruneIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<ActionLogEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        guard let all = try? context.fetch(descriptor), all.count > 100 else { return }
        for entry in all.dropFirst(100) {
            context.delete(entry)
        }
    }
}
