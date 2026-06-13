//
//  SideMenuSettingsViews.swift
//  kodAI_chatbot_dev
//

import KodaiKernel
import SwiftUI

struct SideMenuSettingsContent: View {
    let settings: SettingsSnapshot
    @Binding var messageTextSize: MessageTextSize
    @Binding var reduceMotion: Bool
    @Binding var haptics: Bool
    @Binding var compactMessageSpacing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSection(title: "Model / Runtime") {
                SettingsValueRow(title: "Model name", value: settings.modelName, systemImage: "cpu")
                SettingsValueRow(title: "Context size", value: formattedInteger(settings.contextSize), systemImage: "rectangle.expand.vertical")
                SettingsValueRow(title: "Max output tokens", value: optionalInteger(settings.maxOutputTokens), systemImage: "arrow.up.forward")
                SettingsValueRow(title: "Temperature", value: optionalDecimal(settings.temperature), systemImage: "thermometer.medium")
                SettingsValueRow(title: "Top P", value: optionalDecimal(settings.topP), systemImage: "slider.horizontal.3")
                SettingsValueRow(title: "Repeat penalty", value: optionalDecimal(settings.repeatPenalty), systemImage: "repeat")
                SettingsValueRow(title: "Current phase", value: settings.currentPhase ?? "Unavailable", systemImage: "waveform.path.ecg")
                SettingsValueRow(title: "Backend", value: settings.backendName ?? "Unavailable", systemImage: "memorychip")
            }

            SettingsSection(title: "Analytics") {
                SettingsValueRow(title: "Lifetime tokens generated", value: optionalInteger(settings.lifetimeGeneratedTokens), systemImage: "number")
                SettingsValueRow(title: "Lifetime prompt tokens", value: optionalInteger(settings.lifetimePromptTokens), systemImage: "text.badge.plus")
                SettingsValueRow(title: "Lifetime assistant tokens", value: optionalInteger(settings.lifetimeAssistantTokens), systemImage: "text.bubble")
                SettingsValueRow(title: "Current chat estimate", value: formattedInteger(settings.currentChatTokenEstimate), systemImage: "gauge.with.dots.needle.50percent")
                SettingsValueRow(title: "Context usage", value: settings.contextUsagePercentage, systemImage: "chart.pie")
                SettingsValueRow(title: "Total chats", value: formattedInteger(settings.totalChats), systemImage: "bubble.left.and.bubble.right")
                SettingsValueRow(title: "Total streams", value: formattedInteger(settings.totalStreams), systemImage: "folder")
                SettingsValueRow(title: "Total messages", value: formattedInteger(settings.totalMessages), systemImage: "text.bubble")
                SettingsValueRow(title: "Avg tokens / response", value: optionalDecimal(settings.averageTokensPerResponse), systemImage: "divide")
                SettingsValueRow(title: "Last generation speed", value: optionalSpeed(settings.lastGenerationSpeed), systemImage: "speedometer")
                SettingsValueRow(title: "Last duration", value: optionalDuration(settings.lastGenerationDuration), systemImage: "timer")
            }

            SettingsSection(title: "Developer") {
                SettingsValueRow(title: "Show phase timeline", value: "Coming soon", systemImage: "timeline.selection")
                SettingsValueRow(title: "Show token counters", value: "Coming soon", systemImage: "number")
                SettingsValueRow(title: "Show generation speed", value: "Coming soon", systemImage: "speedometer")
                SettingsValueRow(title: "Show model/runtime details", value: "Coming soon", systemImage: "info.circle")
                SettingsValueRow(title: "Verbose logs", value: "Coming soon", systemImage: "terminal")
                SettingsValueRow(title: "Export current chat", value: "Use /export", systemImage: "square.and.arrow.up")
                SettingsValueRow(title: "Runtime diagnostics", value: settings.backendName ?? "Unavailable", systemImage: "stethoscope")
            }

            SettingsSection(title: "Accessibility") {
                SettingsToggleRow(title: "Reduce motion", isOn: $reduceMotion, systemImage: "figure.walk.motion")
                SettingsPickerRow(title: "Chat text size", selection: $messageTextSize, systemImage: "textformat.size")
                SettingsValueRow(title: "High contrast bubbles", value: "Coming soon", systemImage: "circle.lefthalf.filled")
                SettingsToggleRow(title: "Haptics", isOn: $haptics, systemImage: "iphone.radiowaves.left.and.right")
                SettingsValueRow(title: "Keep input controls reachable", value: "Coming soon", systemImage: "keyboard")
                SettingsToggleRow(title: "Compact message spacing", isOn: $compactMessageSpacing, systemImage: "rectangle.compress.vertical")
            }

            SettingsSection(title: "Appearance") {
                SettingsValueRow(title: "Theme", value: "System · Coming soon", systemImage: "circle.lefthalf.filled")
                SettingsValueRow(title: "Glass intensity", value: "Default · Coming soon", systemImage: "sparkles")
                SettingsValueRow(title: "Message density", value: "Default · Coming soon", systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            SettingsSection(title: "About") {
                SettingsValueRow(title: "App name", value: appName, systemImage: "app")
                SettingsValueRow(title: "Version", value: appVersionText, systemImage: "number.square")
                SettingsValueRow(title: "Privacy", value: "Local-only", systemImage: "lock")
                SettingsValueRow(title: "Runtime safety", value: "On-device model", systemImage: "shield")
            }
        }
        .padding(.bottom, 4)
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "kodAI"
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (version?, build?):
            return "\(version) (\(build))"
        case let (version?, nil):
            return version
        case let (nil, build?):
            return build
        default:
            return "Unavailable"
        }
    }

    private func formattedInteger(_ value: Int) -> String {
        value.formatted()
    }

    private func optionalInteger(_ value: Int?) -> String {
        value.map { formattedInteger($0) } ?? "Unavailable"
    }

    private func optionalDecimal(_ value: Double?) -> String {
        value.map { String(format: "%.2f", $0) } ?? "Unavailable"
    }

    private func optionalSpeed(_ value: Double?) -> String {
        value.map { String(format: "%.1f tok/s", $0) } ?? "Unavailable"
    }

    private func optionalDuration(_ value: TimeInterval?) -> String {
        guard let value else { return "Unavailable" }
        return "\(max(1, Int(value.rounded())))s"
    }
}

struct SideMenuGlassBoxContent: View {
    let recentActivityEvents: [ActivityEventLite]
    let latestContextSnapshot: ContextSnapshotLite?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSection(title: "Latest Context") {
                if let snapshot = latestContextSnapshot {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.reason)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.88))
                        Text(snapshot.createdAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .drawerGlassRow(verticalPadding: 7)

                    ForEach(snapshot.blocks, id: \.kind) { block in
                        SettingsValueRow(
                            title: block.kind,
                            value: block.tokenEstimate > 0 ? "\(block.content) · ~\(block.tokenEstimate) tok" : block.content,
                            systemImage: "square.stack.3d.up"
                        )
                    }
                } else {
                    DrawerEmptyRow(text: "No context snapshot yet — send a message")
                }
            }

            SettingsSection(title: "Recent Activity") {
                if recentActivityEvents.isEmpty {
                    DrawerEmptyRow(text: "No local activity yet")
                } else {
                    ForEach(recentActivityEvents.prefix(30)) { event in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: event.kind.systemImage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.88))

                                if let detail = event.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                Text("\(event.source.displayName) · \(event.createdAt.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary.opacity(0.7))
                            }

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .drawerGlassRow(verticalPadding: 6)
                    }
                }
            }
        }
        .padding(.bottom, 4)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary.opacity(0.72))

            VStack(spacing: 2) {
                content
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .liquidGlassPanel(tint: ChatPalette.inputField, cornerRadius: 16)
        }
    }
}

private struct SettingsValueRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 10)

            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 6)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let systemImage: String

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
        }
        .toggleStyle(.switch)
        .tint(ChatPalette.accentBlue)
        .padding(.vertical, 4)
    }
}

private struct SettingsPickerRow: View {
    let title: String
    @Binding var selection: MessageTextSize
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            }

            Picker(title, selection: $selection) {
                ForEach(MessageTextSize.allCases) { size in
                    Text(size.title)
                        .tag(size)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 6)
    }
}
