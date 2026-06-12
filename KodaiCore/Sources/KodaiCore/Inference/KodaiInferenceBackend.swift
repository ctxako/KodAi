import Foundation

@MainActor
public protocol KodaiInferenceBackend: AnyObject {
    /// Whether the underlying model is ready to accept requests.
    var isAvailable: Bool { get async }

    /// Begin streaming a response. The returned AsyncStream emits InferenceEvents
    /// until the response completes, is cancelled, or errors out.
    /// - Parameters:
    ///   - prompt: The user turn text.
    ///   - instructions: System instructions for the turn (used for token estimation
    ///     and as the fallback configuration for stateless backends).
    func stream(prompt: String, instructions: String) -> AsyncStream<InferenceEvent>

    /// Cancel the in-flight stream, if any.
    func cancel()

    /// Drop all session state (used on full conversation reset).
    func reset()
}
