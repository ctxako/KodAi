//
//  kodai_macosApp.swift
//  kodai_macos
//
//  Created by Charles Thomas Xavier Austin III on 6/9/26.
//


import FoundationModels
import SwiftUI
import SwiftData

@main
struct kodai_macosApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(.clear)
        }
        .windowStyle(.hiddenTitleBar)
        .modelContainer(for: [
            KodaiChatSession.self,
            KodaiChatMessage.self,
            KodaiStream.self
        ])
    }
}
