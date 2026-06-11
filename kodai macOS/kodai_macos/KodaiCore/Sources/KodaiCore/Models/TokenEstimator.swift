import Foundation

public enum TokenEstimator {
    public static func estimate(_ text: String) -> Int {
        max(1, text.utf8.count / 4)
    }
}
