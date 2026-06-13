import Foundation
import KodaiKernel

extension InferenceProcessSummary {
    var compactText: String {
        "Thought for \(elapsedText ?? "1s")"
    }

    var elapsedText: String? {
        guard let elapsedSeconds else { return nil }

        let roundedSeconds = max(1, Int(elapsedSeconds.rounded()))
        return "\(roundedSeconds)s"
    }

    var tokensPerSecondText: String? {
        guard generatedTokenCount > 0 else { return nil }
        guard let elapsedSeconds, elapsedSeconds > 0 else { return nil }

        return String(format: "%.1f", Double(generatedTokenCount) / elapsedSeconds)
    }

    var phaseHeading: String {
        switch finalPhase {
        case .completed, .cancelled, .failed:
            return "Final phase"
        default:
            return "Current phase"
        }
    }
}

extension InferencePhase {
    var displayName: String {
        switch self {
        case .idle:
            return "Idle"
        case .resolving, .initializing:
            return "Initializing"
        case .checkingRuntimeState:
            return "Checking runtime state"
        case .checkingLocalTime:
            return "Checking local time"
        case .checkingWeather:
            return "Checking weather"
        case .usingCachedWeather:
            return "Using cached weather"
        case .downloadingModel:
            return "Initializing"
        case .loadingModel:
            return "Initializing"
        case .formattingPrompt:
            return "Thinking"
        case .tokenizing:
            return "Processing"
        case .prefilling:
            return "Reasoning"
        case .decoding:
            return "Responding"
        case .flushingOutput:
            return "Responding"
        case .completed:
            return "Completed"
        case .cancelled:
            return "Cancelled"
        case .failed:
            return "Failed"
        }
    }
}

extension WarmupStatus {
    var displayName: String {
        switch self {
        case .initializingRuntime:
            return "Pre-heating · starting engine"
        case .allocatingContext:
            return "Pre-heating · allocating memory"
        case .mappingWeights:
            return "Pre-heating · loading weights"
        case .compilingMetal:
            return "Pre-heating · compiling shaders"
        case .warmingTokenizer:
            return "Pre-heating · warming tokenizer"
        case .ready:
            return "Model ready"
        }
    }
}
