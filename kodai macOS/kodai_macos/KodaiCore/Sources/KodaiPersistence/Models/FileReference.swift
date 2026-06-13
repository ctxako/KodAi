import Foundation
import KodaiKernel
import SwiftData

@Model
public final class FileReference {
    public var id: UUID
    public var path: String
    public var filename: String
    public var size: Int
    public var mimeType: String
    public var createdAt: Date

    public var session: KodaiChatSession?
    public var project: KodaiProject?

    public init(
        id: UUID = UUID(),
        path: String,
        filename: String,
        size: Int = 0,
        mimeType: String = "application/octet-stream",
        createdAt: Date = .now,
        session: KodaiChatSession? = nil,
        project: KodaiProject? = nil
    ) {
        self.id = id
        self.path = path
        self.filename = filename
        self.size = size
        self.mimeType = mimeType
        self.createdAt = createdAt
        self.session = session
        self.project = project
    }
}
