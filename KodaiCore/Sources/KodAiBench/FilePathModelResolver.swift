import Foundation
import KodaiKernel
import KodaiRuntime

struct FilePathModelResolver: ModelFileResolver {
    let path: String

    func resolve(configuration: LocalModelConfiguration) throws -> URL {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LocalModelRuntimeError.modelFileMissing(expectedFileName: url.lastPathComponent)
        }
        return url
    }
}
