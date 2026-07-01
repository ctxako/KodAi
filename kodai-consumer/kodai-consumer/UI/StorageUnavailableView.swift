import SwiftUI

struct StorageUnavailableView: View {
    var body: some View {
        ZStack {
            CanvasBackground()

            VStack(spacing: 24) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 52))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    Text("Storage Unavailable")
                        .font(.title2.weight(.semibold))

                    Text("KodAi couldn't initialize its local database. Try force-quitting and reopening the app. If the problem persists, reinstalling will resolve it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
    }
}
