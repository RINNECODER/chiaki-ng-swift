#if os(macOS)
    import Foundation

    /// The local preference shared by Network settings and the macOS stream player.
    public enum SteadyWiFiPreference {
        public static let key = "steadyWiFiEnabled"
        public static let helperPath = "/Library/PrivilegedHelperTools/io.github.chiaki-ng.steady-wifi"

        public static var isHelperInstalled: Bool {
            FileManager.default.isExecutableFile(atPath: helperPath)
        }
    }
#endif
