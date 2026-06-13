//
//  kodaisettings.swift
//  kodai_macos
//

import SwiftUI
import FoundationModels

private enum SettingsTab: Hashable {
    case general, diagnostics
}

struct KodaiSettingsView: View {
    @Environment(\.kodaiTheme) private var theme
    @AppStorage(KodaiTheme.storageKey) private var selectedThemeRawValue = KodaiTheme.blueGradient.rawValue

    @Binding var selectedMode: OutputMode
    let telemetryStore: TelemetryStore
    let onResetSession: () -> Void

    @State private var modelAvailable = false
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                settingsTabPill("General", tab: .general)
                settingsTabPill("Diagnostics", tab: .diagnostics)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().opacity(0.15)

            if selectedTab == .general {
                generalContent
            } else {
                DiagnosticsTabView(telemetryStore: telemetryStore)
            }

            Divider().opacity(0.15)

            HStack {
                Text("Kodai")
                Spacer()
                Text(appVersion)
                    .font(.system(size: 12, design: .monospaced))
            }
            .font(.system(size: 12, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 360)
        .background(.ultraThinMaterial)
        .background(theme.glassSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.glassBorder, lineWidth: 1)
        }
        .presentationBackground(.clear)
        .onAppear {
            if case .available = SystemLanguageModel.default.availability {
                modelAvailable = true
            }
        }
    }

    @ViewBuilder
    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Circle()
                    .fill(modelAvailable ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text("Apple Intelligence")
                    .font(.system(size: 13, design: .rounded))
                Spacer()
                Text(modelAvailable ? "Ready" : "Unavailable")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 38)

            Divider()
                .opacity(0.10)
                .padding(.horizontal, 16)

            HStack {
                Text("Theme")
                    .font(.system(size: 13, design: .rounded))
                Spacer()
                Picker("Theme", selection: $selectedThemeRawValue) {
                    ForEach(KodaiTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .padding(.horizontal, 16)
            .frame(height: 38)

            Divider()
                .opacity(0.10)
                .padding(.horizontal, 16)

            HStack {
                Text("Style")
                    .font(.system(size: 13, design: .rounded))
                Spacer()
                Picker("Style", selection: $selectedMode) {
                    ForEach(OutputMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
        }
        .padding(.vertical, 4)

        Divider().opacity(0.15)

        Button {
            onResetSession()
        } label: {
            Label("Reset context", systemImage: "arrow.counterclockwise")
                .font(.system(size: 13, design: .rounded))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red.opacity(0.8))
        .padding(.horizontal, 16)
        .frame(height: 38)
    }

    private func settingsTabPill(_ label: String, tab: SettingsTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(selectedTab == tab ? theme.primaryText : theme.secondaryText.opacity(0.82))
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(selectedTab == tab ? theme.primaryText.opacity(0.14) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    if selectedTab == tab {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(theme.glassBorder, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
