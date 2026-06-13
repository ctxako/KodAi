import Foundation

public enum TokenEstimator {
    public static func estimate(_ text: String) -> Int {
        max(1, text.utf8.count / 4)
    }

    /// Estimate from a pre-computed character count. Unlike `estimate(_:)`,
    /// this has no floor of 1 so an empty buffer reports 0 tokens.
    public static func estimate(characterCount: Int) -> Int {
        max(0, characterCount / 4)
    }
}
