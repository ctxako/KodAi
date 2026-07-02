import SwiftUI

/// In-app guide: what the agent can do, example prompts, and tips for
/// getting good results from a small on-device model.
struct HowToView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("kodai is a private agent that runs entirely on your phone.")
                        .font(.subheadline)
                    Text("Type what you want done in plain language. kodai figures out which tool to use — calendar, reminders, contacts, files, or clipboard — and asks you to confirm before it changes anything.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("What you can ask") {
                exampleRow(icon: "calendar", color: .red,
                           title: "Calendar",
                           examples: ["Schedule lunch with Sam Friday at noon",
                                      "What's on my calendar tomorrow?"])
                exampleRow(icon: "checklist", color: .blue,
                           title: "Reminders",
                           examples: ["Remind me to call the dentist at 3pm",
                                      "Add milk to my groceries list"])
                exampleRow(icon: "person.crop.circle", color: .green,
                           title: "Contacts",
                           examples: ["What's Maria's phone number?",
                                      "Add a contact named Alex Chen"])
                exampleRow(icon: "doc.text", color: .orange,
                           title: "Files & notes",
                           examples: ["Save a note about the meeting",
                                      "Read back my note from yesterday"])
                exampleRow(icon: "doc.on.clipboard", color: .purple,
                           title: "Clipboard",
                           examples: ["Copy that address to my clipboard"])
            }

            Section("Tips for better results") {
                tipRow(icon: "text.magnifyingglass",
                       title: "Be specific",
                       detail: "Include names, dates, and times. \"Dinner with Kim Thursday 7pm\" works better than \"set up dinner\".")
                tipRow(icon: "1.circle",
                       title: "One task at a time",
                       detail: "kodai handles one action per request. Split \"add an event and remind me\" into two asks.")
                tipRow(icon: "checkmark.shield",
                       title: "Review before confirming",
                       detail: "Nothing is created or changed until you approve the confirmation card. Check the details there.")
                tipRow(icon: "arrow.counterclockwise",
                       title: "Rephrase if it misses",
                       detail: "It's a small on-device model. If it picks the wrong tool, try again with simpler, more direct wording.")
                tipRow(icon: "mic",
                       title: "Use Siri & Shortcuts",
                       detail: "kodai actions are available from Siri, Shortcuts, and Spotlight — no need to open the app.")
            }

            Section("Privacy") {
                tipRow(icon: "iphone.and.arrow.forward.inward",
                       title: "Everything stays on your phone",
                       detail: "The model runs on-device and works fully offline. No account, no cloud, no tracking.")
            }
        }
        .navigationTitle("How to Use kodai")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func exampleRow(icon: String, color: Color, title: String, examples: [String]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                ForEach(examples, id: \.self) { example in
                    Text("“\(example)”")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func tipRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
