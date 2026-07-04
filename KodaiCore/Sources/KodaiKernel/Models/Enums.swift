import Foundation

public enum ChatRole: String, Codable, CaseIterable, Sendable {
    case user = "user"
    case assistant = "assistant"
    case system = "system"
}

public enum ProjectStatus: String, Codable, CaseIterable, Sendable {
    case active = "active"
    case paused = "paused"
    case archived = "archived"
}

public enum PersonaMode: String, Codable, CaseIterable, Sendable {
    case default_ = "default"
    case consultant = "consultant"
    case teacher = "teacher"
    case explorer = "explorer"
    case critic = "critic"
}

public enum OutputFormat: String, Codable, CaseIterable, Sendable {
    case chat = "chat"
    case organize = "organize"
    case summarize = "summarize"
    case checklist = "checklist"
    case debug = "debug"
}

public enum TaskPriority: String, Codable, CaseIterable, Sendable {
    case low = "low"
    case medium = "medium"
    case high = "high"

    public var sortOrder: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}

public enum ActivityKind: String, Codable, CaseIterable, Sendable {
    case turn = "turn"
    case toolCall = "toolCall"
    case memoryWrite = "memoryWrite"
    case summaryWrite = "summaryWrite"
    case taskChange = "taskChange"
    case reminderScheduled = "reminderScheduled"
    case fetch = "fetch"
    case error = "error"
    case toolProposal = "toolProposal"
    case briefingDelivered = "briefingDelivered"
    case nudgeSent = "nudgeSent"
    case commitmentChange = "commitmentChange"
}

public enum CommitmentStatus: String, Codable, CaseIterable, Sendable {
    case open = "open"
    case kept = "kept"
    case slipped = "slipped"
    case dropped = "dropped"
}

public enum CommitmentSource: String, Codable, CaseIterable, Sendable {
    case chat = "chat"
    case journal = "journal"
    case manual = "manual"
}

public enum BriefingKind: String, Codable, CaseIterable, Sendable {
    case morning = "morning"
    case evening = "evening"
}

public enum ToolOutcome: String, Codable, CaseIterable, Sendable {
    case success = "success"
    case failed = "failed"
    case denied = "denied"
    case cancelled = "cancelled"
}

public enum ToolInvoker: String, Codable, CaseIterable, Sendable {
    case model = "model"
    case rule = "rule"
    case user = "user"
}

public enum MemoryType: String, Codable, CaseIterable, Sendable {
    case decision = "decision"
    case preference = "preference"
    case fact = "fact"
    case fileSummary = "fileSummary"
    case note = "note"
}

public enum MemoryStatus: String, Codable, CaseIterable, Sendable {
    case proposed = "proposed"
    case active = "active"
    case superseded = "superseded"
    case archived = "archived"
}

public enum SummaryKind: String, Codable, CaseIterable, Sendable {
    case session = "session"
    case project = "project"
    case file = "file"
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
}
