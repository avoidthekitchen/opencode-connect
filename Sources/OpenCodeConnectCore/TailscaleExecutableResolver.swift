public enum TailscaleExecutableResolver {
    public static let knownPaths = [
        "/opt/homebrew/bin/tailscale",
        "/usr/local/bin/tailscale",
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
    ]

    public static func resolve(
        customPath: String?,
        checking files: any ExecutableFileChecking
    ) -> String? {
        if let customPath {
            return files.executableStatus(atPath: customPath) == .executable ? customPath : nil
        }
        return knownPaths.first { files.executableStatus(atPath: $0) == .executable }
    }

    public static func environment(for path: String) -> [String: String] {
        path.contains(".app/Contents/MacOS/") ? ["TS_MAC_CLIENT_USE_CLI": "1"] : [:]
    }
}
