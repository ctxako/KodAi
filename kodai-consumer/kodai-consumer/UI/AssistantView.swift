import SwiftUI
import SwiftData
import KodaiKernel

enum AppTab: Hashable {
    case feed, upcoming, archive
}

struct AssistantView: View {
    @State private var selectedTab: AppTab = .feed

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Feed", systemImage: "house.fill", value: .feed) {
                FeedView()
            }
            Tab("Upcoming", systemImage: "calendar", value: .upcoming) {
                UpcomingView()
            }
            Tab("Archive", systemImage: "clock.arrow.circlepath", value: .archive) {
                ArchiveView()
            }
        }
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackgroundVisibility(.visible, for: .tabBar)
        .preferredColorScheme(.dark)
        .onOpenURL { url in
            guard url.scheme == "kodai", url.host == "task" else { return }
            selectedTab = .feed
        }
    }
}
