import SwiftUI
import SwiftData

struct AgentNoteView: View {
    let card: ActionCard

    var body: some View {
        Text(card.summary)
            .font(.callout)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .padding(.leading, 4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
