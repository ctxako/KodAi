import Foundation

/// Identifies the machine a benchmark ran on, for the `device` column.
public enum DeviceInfo {
    /// A human-meaningful device string.
    /// - iOS device: hardware model id (e.g. "iPhone16,1").
    /// - iOS simulator: "Simulator" (Metal numbers there are not comparable).
    /// - macOS: the CPU brand string (e.g. "Apple M4").
    public static var current: String {
        #if targetEnvironment(simulator)
        return "Simulator"
        #elseif os(iOS) || os(tvOS) || os(watchOS)
        return sysctlString("hw.machine") ?? "iOS device"
        #else
        return sysctlString("machdep.cpu.brand_string") ?? "Mac"
        #endif
    }

    /// True on the iOS Simulator, where on-device timings are meaningless.
    public static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
