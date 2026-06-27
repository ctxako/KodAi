import SwiftUI

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
    }
}
