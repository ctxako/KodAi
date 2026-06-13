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
    private let container: ModelContainer = {
        let schema = Schema(versionedSchema: KodaiLocalStoreSchemaV3.self)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: KodaiLocalStoreMigrationPlan.self,
                configurations: ModelConfiguration(
                    schema: schema,
                    cloudKitDatabase: .none
                )
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
