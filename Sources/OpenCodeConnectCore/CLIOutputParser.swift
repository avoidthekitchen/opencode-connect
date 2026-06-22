import Foundation

public enum TailscaleConnectionState: Equatable, Sendable {
    case connected
    case signedOut
    case disconnected
    case unknown
}

public enum CLIOutputParser {
    public static func managedRouteInspection(_ output: String, httpsPort: Int, backendPort: Int) -> ManagedRouteInspection {
        let routes = serveRoutes(output)
        guard let route = routes.first(where: { $0.port == httpsPort }) else { return .available }
        return route.proxy == "http://127.0.0.1:\(backendPort)" ? .matching : .occupied
    }

    public static func serveEndpoint(_ output: String) -> URL? {
        guard let route = serveRoutes(output).first else { return nil }
        return URL(string: route.port == 443 ? "https://\(route.host)" : "https://\(route.host):\(route.port)")
    }

    public static func openCodeVersion(_ output: String) -> String? {
        semanticVersion(atStartOf: output)
    }

    public static func tailscaleVersion(_ output: String) -> String? {
        semanticVersion(atStartOf: output)
    }

    public static func tailscaleConnection(_ output: String) -> TailscaleConnectionState {
        struct Status: Decodable {
            let backendState: String

            enum CodingKeys: String, CodingKey {
                case backendState = "BackendState"
            }
        }

        guard let data = output.data(using: .utf8),
              let status = try? JSONDecoder().decode(Status.self, from: data)
        else {
            return .unknown
        }

        switch status.backendState {
        case "Running": return .connected
        case "NeedsLogin", "NoState": return .signedOut
        case "Stopped", "Starting": return .disconnected
        default: return .unknown
        }
    }

    public static func tailscaleApprovalURL(_ output: String) -> URL? {
        guard let range = output.range(
            of: #"https://login\.tailscale\.com/[^\s<>\"]+"#,
            options: .regularExpression
        ) else {
            return nil
        }
        return URL(string: String(output[range]))
    }

    private static func semanticVersion(atStartOf output: String) -> String? {
        output
            .split(whereSeparator: \Character.isWhitespace)
            .first
            .map(String.init)
            .flatMap { token in
                token.range(of: #"^v?\d+\.\d+\.\d+([+-][0-9A-Za-z.-]+)?$"#, options: .regularExpression) == nil
                    ? nil
                    : String(token.trimmingPrefix("v"))
            }
    }

    private static func serveRoutes(_ output: String) -> [(host: String, port: Int, proxy: String?)] {
        guard let data = output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let web = root["Web"] as? [String: Any]
        else { return [] }
        return web.compactMap { key, value in
            let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let port = Int(parts[1]) else { return nil }
            let config = value as? [String: Any]
            let handlers = config?["Handlers"] as? [String: Any]
            let rootHandler = handlers?["/"] as? [String: Any]
            return (parts[0], port, rootHandler?["Proxy"] as? String)
        }
    }
}
