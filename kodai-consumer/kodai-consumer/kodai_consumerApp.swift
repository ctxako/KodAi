import SwiftUI
import SwiftData

@main
struct kodai_consumerApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    let container: ModelContainer

    init() {
        let schema = Schema([ActionCard.self, SessionGroup.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        container = try! ModelContainer(for: schema, configurations: config)
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                AssistantView()
            } else {
                OnboardingView(isComplete: $hasCompletedOnboarding)
            }
        }
        .modelContainer(container)
    }
}
