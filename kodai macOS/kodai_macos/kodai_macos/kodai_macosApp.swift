//
//  kodai_macosApp.swift
//  kodai_macos
//
//  Created by Charles Thomas Xavier Austin III on 6/9/26.
//


import FoundationModels
import SwiftUI
import SwiftData
import KodaiCore

@main
struct kodai_macosApp: App {
    // K2E: the container is built through KodaiLocalStoreMigrationPlan so
    // existing stores migrate their session→project relationship data into
    // the scalar projectID fields instead of silently dropping it.
    let container: ModelContainer = {
        let schema = Schema(versionedSchema: KodaiLocalStoreSchemaV2.self)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: KodaiLocalStoreMigrationPlan.self,
                configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            )
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(.clear)
        }
        .windowStyle(.hiddenTitleBar)
        .modelContainer(container)
    }
}
