//
//  lifehqview.swift
//  kodai_macos
//
//  Life HQ — embeds the ~/life knowledge-base surfaces (The Long Quit journal +
//  accountability dashboard) as a main-content route. v0 renders the existing
//  HTML from ~/life; journal state persists in the app's own WKWebView datastore.
//

import SwiftUI
import WebKit

struct LifeHQView: View {
    private enum Panel: String, CaseIterable, Identifiable {
        case journal = "Journal"
        case dashboard = "Dashboard"

        var id: String { rawValue }

        var fileName: String {
            switch self {
            case .journal: "journal.html"
            case .dashboard: "dashboard.html"
            }
        }
    }

    let onClose: () -> Void

    @State private var panel: Panel = .journal
    @State private var reloadToken = 0
    @State private var lifeDirectory: URL?

    var body: some View {
        VStack(spacing: 0) {
            header

            if let lifeDirectory {
                let pageURL = lifeDirectory.appendingPathComponent(panel.fileName)
                if FileManager.default.fileExists(atPath: pageURL.path) {
                    LifeHQWebView(url: pageURL, readAccessURL: lifeDirectory, reloadToken: reloadToken)
                        .id(panel)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding([.horizontal, .bottom], 12)
                } else {
                    missingFileView(pageURL)
                }
            } else {
                connectView
            }
        }
        .onAppear {
            lifeDirectory = LifeFolderAccess.lifeDirectory
        }
    }

    private var connectView: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("KodAi needs one-time access to your ~/life folder")
                .foregroundStyle(.secondary)
            Text("Sandboxed app — the grant is remembered across launches.")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Button("Choose ~/life Folder…") {
                lifeDirectory = LifeFolderAccess.requestAccess()
            }
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .foregroundStyle(.orange)
            Text("Life HQ")
                .font(.title3.weight(.semibold))

            Picker("", selection: $panel) {
                ForEach(Panel.allCases) { panel in
                    Text(panel.rawValue).tag(panel)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            Spacer()

            Button {
                reloadToken += 1
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Reload from ~/life")

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Back to chat")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func missingFileView(_ pageURL: URL) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.folder")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("\(pageURL.path) not found")
                .foregroundStyle(.secondary)
            Text("Generate it with `life dash` or check that ~/life exists.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LifeHQWebView: NSViewRepresentable {
    let url: URL
    let readAccessURL: URL
    let reloadToken: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastToken = 0
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Persistent default store: the journal keeps its XP/streak state in
        // localStorage, so this datastore is load-bearing — do not make ephemeral.
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.loadFileURL(url, allowingReadAccessTo: readAccessURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let needsReload = context.coordinator.lastToken != reloadToken
            || webView.url?.lastPathComponent != url.lastPathComponent
        if needsReload {
            context.coordinator.lastToken = reloadToken
            webView.loadFileURL(url, allowingReadAccessTo: readAccessURL)
        }
    }
}
