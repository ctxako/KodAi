//
//  ModelDownloadView.swift
//  kodai-consumer
//
//  First-run gate shown until the on-device model is present and verified.
//  Bundled builds never see this screen; download builds see a one-time
//  progress flow. Everything here reinforces the product promise: the
//  intelligence lives on the phone.
//

import SwiftUI

struct ModelDownloadView: View {
    let setup: ModelSetupController

    var body: some View {
        ZStack {
            CanvasBackground()

            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "brain")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
                    .accessibilityHidden(true)

                content

                Spacer()

                Text("Everything runs on your iPhone. Nothing you do leaves it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        switch setup.state {
        case .checking:
            ProgressView()
                .tint(.white)

        case .needsDownload:
            stateBlock(
                title: "One-time setup",
                message: "kodai’s intelligence is a small AI model that lives on your phone. It’s a one-time download of about 700 MB — Wi-Fi recommended."
            )
            Button(action: { setup.startDownload() }) {
                Text("Download")
                    .font(.headline)
                    .frame(maxWidth: 220)
                    .padding(.vertical, 14)
                    .background(.white.opacity(0.14), in: Capsule())
                    .foregroundStyle(.white)
            }
            .accessibilityHint("Downloads the on-device AI model, about 700 megabytes")

        case let .downloading(received, total):
            stateBlock(
                title: "Downloading the brain…",
                message: "\(Self.gb(received)) of \(Self.gb(total))"
            )
            ProgressView(value: Double(received), total: Double(max(total, received)))
                .tint(.white)
                .padding(.horizontal, 60)
            Button("Cancel") { setup.cancelDownload() }
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case .verifying:
            stateBlock(title: "Verifying…", message: "Making sure the model arrived intact.")
            ProgressView()
                .tint(.white)

        case let .insufficientDisk(freeGB):
            stateBlock(
                title: "Not enough space",
                message: "kodai needs about 2 GB free to set up its on-device model. You have \(String(format: "%.1f", freeGB)) GB. Free some space, then check again."
            )
            Button("Check again") { setup.recheck() }
                .font(.headline)
                .foregroundStyle(.white)

        case let .failed(message):
            stateBlock(title: "Setup didn’t finish", message: message)
            Button("Try again") { setup.startDownload() }
                .font(.headline)
                .foregroundStyle(.white)

        case .ready:
            EmptyView()
        }
    }

    private func stateBlock(title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
        }
        .accessibilityElement(children: .combine)
    }

    private static func gb(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
