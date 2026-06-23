import Foundation
import KodaiKernel

public protocol ModelFileResolver: Sendable {
    func resolve(configuration: LocalModelConfiguration) throws -> URL
}
