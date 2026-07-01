import SwiftUI
import SwiftData

struct PromptRow: View {
    let card: ActionCard

    var body: some View {
        Text(card.summary)
            .font(.subheadline)
            .foregroundStyle(.secondary.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }
}
