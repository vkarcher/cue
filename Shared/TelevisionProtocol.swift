import Foundation

enum TelevisionError: LocalizedError, Equatable {
    case notPaired
    case notFound(String)
    case notResponding
    case refused(String?)
    case pairingRefused(String?)
    case pairingManifestMissing
    case invalidAddress(String)
    case navigationUnavailable
    case connectionClosed

    var errorDescription: String? {
        switch self {
        case .notPaired: String(localized: "Television not paired")
        case .notFound(let name): String(localized: "\(name) not found on the network")
        case .notResponding: String(localized: "The television is not responding")
        case .refused(let reason): reason ?? String(localized: "Command refused")
        case .pairingRefused(let reason): reason ?? String(localized: "Pairing refused")
        case .pairingManifestMissing: String(localized: "Pairing manifest missing")
        case .invalidAddress(let host): String(localized: "Invalid address: \(host)")
        case .navigationUnavailable: String(localized: "Navigation socket unavailable")
        case .connectionClosed: String(localized: "Connection closed")
        }
    }

    /// The television answered and declined: the connection that carried the command is still healthy.
    var keepsConnection: Bool {
        if case .refused = self { true } else { false }
    }
}

enum RemoteButton: String, CaseIterable {
    case up = "UP", down = "DOWN", left = "LEFT", right = "RIGHT", enter = "ENTER", back = "BACK", home = "HOME"
    case play = "PLAY", pause = "PAUSE"
}

/// Messages of the SSAP websocket protocol, kept apart from the sockets so they can be tested.
enum SSAP {
    static func registrationMessage(manifest: Data, clientKey: String?) throws -> String {
        guard var payload = try JSONSerialization.jsonObject(with: manifest) as? [String: Any] else {
            throw TelevisionError.pairingManifestMissing
        }
        payload["client-key"] = clientKey
        return try json(["type": "register", "id": "register_0", "payload": payload])
    }

    static func requestMessage(id: String, uri: String, payload: [String: any Sendable]) throws -> String {
        try json(["type": "request", "id": id, "uri": uri, "payload": payload])
    }

    /// Sent on the pointer socket, which speaks a line protocol rather than JSON.
    static func buttonMessage(_ button: RemoteButton) -> String {
        "type:button\nname:\(button.rawValue)\n\n"
    }

    /// The client key once the television accepted the registration; nil for messages that only acknowledge it.
    static func clientKey(fromRegistrationMessage message: [String: Any]) throws -> String? {
        switch message["type"] as? String {
        case "error":
            throw TelevisionError.pairingRefused(message["error"] as? String)
        case "registered":
            guard let key = (message["payload"] as? [String: Any])?["client-key"] as? String, !key.isEmpty else {
                throw TelevisionError.pairingRefused(nil)
            }
            return key
        default:
            return nil
        }
    }

    /// The request a message answers, with its payload as JSON or the refusal; nil for a message that answers none.
    static func response(from message: [String: Any]) -> (id: String, result: Result<Data, Error>)? {
        guard let id = message["id"] as? String else { return nil }
        let payload = message["payload"] as? [String: Any] ?? [:]
        if message["type"] as? String == "error" || payload["returnValue"] as? Bool == false {
            let reason = message["error"] as? String ?? payload["errorText"] as? String
            return (id, .failure(TelevisionError.refused(reason)))
        }
        return (id, Result { try JSONSerialization.data(withJSONObject: payload) })
    }

    /// "HDMI_2" for "com.webos.app.hdmi2", the app that shows that input; nil for any other app.
    static func inputID(foregroundAppID appID: String) -> String? {
        let prefix = "com.webos.app.hdmi"
        guard appID.hasPrefix(prefix), let number = Int(appID.dropFirst(prefix.count)) else { return nil }
        return "HDMI_\(number)"
    }

    private static func json(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
}
