import Foundation
import KodaiPersistence
import SwiftData
import Testing

@testable import KodAi

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
}
