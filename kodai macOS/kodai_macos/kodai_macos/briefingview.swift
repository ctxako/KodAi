//
//  briefingview.swift
//  kodai_macos
//
//  J1 (jarvis-plan): renders a day's briefing (morning brief or evening
//  debrief). Composes on first open via BriefingEngine — idempotent per
//  (day, kind) — and captures the evening reflection into BriefingRecord.
//

import KodaiCore
import SwiftData
import SwiftUI

struct BriefingView: View {
    @Environment(\.kodaiTheme) private var theme
    @Environment(\.modelContext) private var modelContext

    let engine: BriefingEngine
    let onClose: () -> Void

    @Binding var kind: BriefingKind

    @State private var record: BriefingRecord?
    @State private var reflectionText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let record {
                    KodaiMarkdownText(
                        text: record.content,
                        bodyFont: .system(size: 13.5, design: .rounded),
                        sectionTitleFont: .system(size: 15, weight: .semibold, design: .rounded)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                    .kodaiGlass(cornerRadius: 18)

                    if kind == .evening {
                        reflectionSection(record)
                    }
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Assembling your briefing…")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(40)
                    .kodaiGlass(cornerRadius: 18)
                }
            }
            .padding(34)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("briefing.detail")
        .task(id: kind) {
            record = nil
            let briefing = await engine.briefing(kind: kind, context: modelContext)
            engine.markDelivered(briefing, context: modelContext)
            engine.markOpened(briefing, context: modelContext)
            reflectionText = briefing.reflection ?? ""
            record = briefing
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kind == .morning ? "Morning brief" : "Evening debrief")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.primaryText)

                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer()

            kindTogglePill

            Button(action: onClose) {
                Label("Back to chat", systemImage: "chevron.left")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .accessibilityIdentifier("briefing.backToChat")
            .buttonStyle(.plain)
            .foregroundStyle(theme.secondaryText)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .contentShape(Capsule())
            .background(theme.glassSurface, in: Capsule())
            .overlay {
                Capsule().stroke(theme.glassBorder, lineWidth: 1)
            }
        }
    }

    private var kindTogglePill: some View {
        HStack(spacing: 2) {
            kindButton("Morning", .morning, icon: "sun.horizon.fill")
            kindButton("Evening", .evening, icon: "moon.stars.fill")
        }
        .padding(3)
        .background(theme.glassSurface, in: Capsule())
        .overlay {
            Capsule().stroke(theme.glassBorder, lineWidth: 1)
        }
        .padding(.trailing, 8)
    }

    private func kindButton(_ label: String, _ target: BriefingKind, icon: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                kind = target
            }
        } label: {
            Label(label, systemImage: icon)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(kind == target ? theme.primaryText : theme.secondaryText.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(kind == target ? theme.primaryText.opacity(0.14) : .clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func reflectionSection(_ record: BriefingRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reflection")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.primaryText)

            TextEditor(text: $reflectionText)
                .font(.system(size: 13, design: .rounded))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 72, maxHeight: 140)
                .padding(12)
                .kodaiGlass(cornerRadius: 14)
                .accessibilityIdentifier("briefing.reflection")

            HStack {
                if record.reflection != nil,
                   record.reflection == reflectionText.trimmingCharacters(in: .whitespacesAndNewlines) {
                    Label("Saved", systemImage: "checkmark")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(theme.secondaryText)
                }

                Spacer()

                Button {
                    engine.saveReflection(reflectionText, for: record, context: modelContext)
                } label: {
                    Text("Save reflection")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Capsule())
                .background(theme.primaryText.opacity(0.12), in: Capsule())
                .overlay {
                    Capsule().stroke(theme.glassBorder, lineWidth: 1)
                }
                .disabled(reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
