import Foundation
import KodaiPersistence
import SwiftData
import Testing

@testable import kodAI_chatbot_dev

struct WorkspaceModelContainerTests {
    @Test func inMemoryContainerInitializes() throws {
        let container = try WorkspaceModelContainer.makeInMemory()
        let context = ModelContext(container)

        let project = KodaiProject(title: "Scaffold check")
        let task = KodaiTask(title: "Verify container", project: project)
        context.insert(project)
        context.insert(task)
        try context.save()

        let projects = try context.fetch(FetchDescriptor<KodaiProject>())
        #expect(projects.count == 1)
        #expect(projects.first?.tasks.count == 1)
    }

    // K2E: the workspace schema is Project → Task only. The chat models must
    // not be pulled in — neither registered explicitly nor dragged in through
    // a relationship closure.
    @Test func schemaRegistersOnlyWorkspaceModels() throws {
        let entityNames = Set(WorkspaceModelContainer.schema.entities.map(\.name))
        #expect(entityNames == ["KodaiProject", "KodaiTask"])
    }

    @Test func schemaContainsNoChatEntities() throws {
        let entityNames = Set(WorkspaceModelContainer.schema.entities.map(\.name))
        for chatEntity in ["KodaiChatSession", "KodaiChatMessage", "KodaiSummary", "KodaiStream"] {
            #expect(!entityNames.contains(chatEntity))
        }
    }
}
