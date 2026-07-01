//
//  ModelSetupController.swift
//  kodai-consumer
//
//  Owns first-run model availability: is the GGUF on disk (downloaded or
//  bundled), is there room to fetch it, and is the file actually a GGUF?
//  The main UI is gated on `isReady` so the runtime never hits a missing or
//  corrupt model. Downloads report live progress; a corrupt file is deleted
//  and re-fetched rather than crashing the runtime.
//
//  The runtime keeps its own implicit download path (LocalModelRuntime
//  prewarm) as a fallback — this controller just makes the same fetch
//  visible, guarded, and recoverable.
//

import Foundation
import KodaiKernel
import KodaiRuntime
import Observation

@Observable
final class ModelSetupController {
    enum SetupState: Equatable {
        case checking
        case needsDownload
        case insufficientDisk(freeGB: Double)
        case downloading(received: Int64, total: Int64)
        case verifying
        case ready
        case failed(message: String)
    }

    private(set) var state: SetupState = .checking

    /// ~700 MB weights need staging room plus llama.cpp's mmap headroom.
    static let requiredFreeBytes: Int64 = 2_000_000_000
    /// Fallback expected size when the server doesn't send Content-Length.
    static let expectedModelBytes: Int64 = 731_000_000

    private let configuration = LocalModelConfiguration.lfm2_5_1_2B_Instruct_Q4_K_M
    private let downloader = ModelDownloader()
    @ObservationIgnored private var session: URLSession?
    @ObservationIgnored private var delegate: DownloadDelegate?

    var isReady: Bool { state == .ready }

    // MARK: - Launch check

    func checkOnLaunch() {
        guard state == .checking else { return }

        if Bundle.main.url(
            forResource: configuration.modelResourceName,
            withExtension: configuration.modelResourceExtension
        ) != nil {
            state = .ready
            return
        }

        guard let localURL = try? downloader.localModelURL(
            fileName: configuration.expectedModelFileName
        ) else {
            state = .failed(message: "Couldn’t access the app’s storage.")
            return
        }

        if FileManager.default.fileExists(atPath: localURL.path) {
            if Self.isValidGGUF(at: localURL) {
                state = .ready
            } else {
                // Corrupt or truncated download — remove it and fetch again.
                try? FileManager.default.removeItem(at: localURL)
                state = diskGuardState(for: localURL)
            }
            return
        }

        state = diskGuardState(for: localURL)
    }

    private func diskGuardState(for localURL: URL) -> SetupState {
        let free = Self.freeBytes(near: localURL)
        if free < Self.requiredFreeBytes {
            return .insufficientDisk(freeGB: Double(free) / 1_000_000_000)
        }
        return .needsDownload
    }

    /// Re-run the disk guard (after the user frees space) or retry a failure.
    func recheck() {
        state = .checking
        checkOnLaunch()
    }

    // MARK: - Download

    func startDownload() {
        guard state == .needsDownload || isRetryableFailure else { return }
        guard let source = configuration.downloadURL,
              let destination = try? downloader.localModelURL(
                  fileName: configuration.expectedModelFileName
              ) else {
            state = .failed(message: "No download source is configured.")
            return
        }

        state = .downloading(received: 0, total: Self.expectedModelBytes)

        let delegate = DownloadDelegate(
            destination: destination,
            onProgress: { [weak self] received, total in
                guard let self else { return }
                Task { @MainActor in
                    guard case .downloading = self.state else { return }
                    self.state = .downloading(
                        received: received,
                        total: total > 0 ? total : Self.expectedModelBytes
                    )
                }
            },
            onCompletion: { [weak self] result in
                guard let self else { return }
                Task { @MainActor in
                    self.finishDownload(result, destination: destination)
                }
            }
        )
        self.delegate = delegate
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        self.session = session
        session.downloadTask(with: source).resume()
    }

    func cancelDownload() {
        session?.invalidateAndCancel()
        session = nil
        delegate = nil
        state = .needsDownload
    }

    private var isRetryableFailure: Bool {
        if case .failed = state { return true }
        return false
    }

    private func finishDownload(_ result: Result<Void, Error>, destination: URL) {
        session?.finishTasksAndInvalidate()
        session = nil
        delegate = nil

        switch result {
        case .success:
            state = .verifying
            if Self.isValidGGUF(at: destination) {
                state = .ready
            } else {
                try? FileManager.default.removeItem(at: destination)
                state = .failed(message: "The downloaded file was damaged. Check your connection and try again.")
            }
        case .failure(let error):
            if (error as? URLError)?.code == .cancelled { return }
            state = .failed(message: "Download failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Integrity + disk helpers

    /// A real GGUF starts with the 4-byte magic "GGUF". Catches truncated
    /// downloads and HTML error pages saved as the model file.
    static func isValidGGUF(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let magic = try? handle.read(upToCount: 4) else { return false }
        try? handle.close()
        return magic == Data("GGUF".utf8)
    }

    static func freeBytes(near url: URL) -> Int64 {
        let values = try? url.deletingLastPathComponent().resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}

// MARK: - URLSession delegate (background queue → MainActor callbacks)

private nonisolated final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    private let onProgress: @Sendable (Int64, Int64) -> Void
    private let onCompletion: @Sendable (Result<Void, Error>) -> Void

    init(
        destination: URL,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void,
        onCompletion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        self.destination = destination
        self.onProgress = onProgress
        self.onCompletion = onCompletion
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The temp file is deleted when this method returns — move it now.
        do {
            if let http = downloadTask.response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            onCompletion(.success(()))
        } catch {
            onCompletion(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            onCompletion(.failure(error))
        }
    }
}
