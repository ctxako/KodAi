import Foundation

public struct TokenBudget: Sendable {
    public static let defaultTotal = 3200

    public var total: Int
    public var perBlockCaps: [String: Int]

    public init(total: Int = defaultTotal, perBlockCaps: [String: Int] = [:]) {
        self.total = total
        self.perBlockCaps = perBlockCaps
    }

    public func cap(for kind: String) -> Int? {
        perBlockCaps[kind]
    }
}
