//
//  kodai_consumerApp.swift
//  kodai-consumer
//
//  On-device agentic assistant. Phase 0: engine integration only.
//

import SwiftUI
import SwiftData

@main
struct kodai_consumerApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                AssistantView()
            } else {
                OnboardingView(isComplete: $hasCompletedOnboarding)
            }
        }
        .modelContainer(for: ActionLogEntry.self)
    }
}
