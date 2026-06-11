//
//  kodaisettings.swift
//  kodai_macos
//

import SwiftUI
import FoundationModels

struct KodaiSettingsView: View {
    @Binding var selectedMode: OutputMode
    let onResetSession: () -> Void

    @State private var modelAvailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider().opacity(0.15)

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
        .frame(width: 280)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .presentationBackground(.clear)
        .onAppear {
            if case .available = SystemLanguageModel.default.availability {
                modelAvailable = true
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
