import Foundation
import Network
import Synchronization

/// Network side of the LG webOS client: discovery, address resolution and registration. Messages live in `SSAP`.
enum LGTelevision {
    // shortcut: LG televisions are found through their AirPlay advertisement, so pre-2018 models are not listed.
    static let serviceType = "_airplay._tcp"

    /// Resolves an advertised television to its IPv4 address; nil while it is off or unreachable.
    static func resolveAddress(serviceName: String) async -> String? {
        let parameters = NWParameters.tcp
        (parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        let connection = NWConnection(
            to: .service(name: serviceName, type: serviceType, domain: "local.", interface: nil),
            using: parameters
        )
        defer { connection.cancel() }
        return await withCheckedContinuation { continuation in
            let resume = ResumeOnce(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case .hostPort(.ipv4(let address), _) = connection.currentPath?.remoteEndpoint {
                        // Built from the raw bytes: the description carries the interface scope ("%en0").
                        resume(address.rawValue.map(String.init).joined(separator: "."))
                    } else {
                        resume(nil)
                    }
                case .waiting, .failed, .cancelled:
                    resume(nil)
                default:
                    break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { resume(nil) }
        }
    }

    /// Without a client key the television asks on screen to accept the connection. Returns the new key.
    static func pair(host: String) async throws -> String {
        let registration = try await register(host: host, clientKey: nil)
        registration.session.invalidateAndCancel()
        return registration.clientKey
    }

    /// Opens a websocket and registers with the manifest; a first pairing waits for someone at the television.
    fileprivate static func register(host: String, clientKey: String?) async throws
        -> (session: URLSession, socket: URLSessionWebSocketTask, clientKey: String) {
        guard let url = URL(string: "wss://\(host):3001") else { throw TelevisionError.invalidAddress(host) }
        guard let manifest = Bundle.main.url(forResource: "lg_registration", withExtension: "json") else {
            throw TelevisionError.pairingManifestMissing
        }
        let message = try SSAP.registrationMessage(manifest: try Data(contentsOf: manifest), clientKey: clientKey)
        let session = URLSession(configuration: .ephemeral, delegate: SelfSignedTrust(), delegateQueue: nil)
        let socket = session.webSocketTask(with: url)
        socket.resume()
        do {
            let key = try await withTimeout(seconds: clientKey == nil ? 60 : 6, onTimeout: { socket.cancel() }) {
                try await socket.send(.string(message))
                while true {
                    if let key = try SSAP.clientKey(fromRegistrationMessage: try await socket.receiveJSON()) { return key }
                }
            }
            return (session, socket, key)
        } catch {
            session.invalidateAndCancel()
            throw error
        }
    }
}

/// One registered connection to a television, kept open so remote buttons answer without a handshake each time.
actor TelevisionLink {
    private struct PendingRequest {
        let continuation: CheckedContinuation<Data, Error>
        let timeout: Task<Void, Never>
    }

    private let host: String
    private let clientKey: String
    private var session: URLSession?
    private var requestSocket: URLSessionWebSocketTask?
    private var pointerSocket: URLSessionWebSocketTask?
    private var connectionTask: Task<URLSessionWebSocketTask, Error>?
    private var pointerTask: Task<URLSessionWebSocketTask, Error>?
    private var pending: [String: PendingRequest] = [:]
    private var nextID = 0

    init(host: String, clientKey: String) {
        self.host = host
        self.clientKey = clientKey
    }

    /// Sends an SSAP request and returns its response payload as JSON.
    func request(_ uri: String, payload: [String: any Sendable] = [:]) async throws -> Data {
        let socket = try await connectedRequestSocket()
        nextID += 1
        let id = "request_\(nextID)"
        let message = try SSAP.requestMessage(id: id, uri: uri, payload: payload)
        return try await withCheckedThrowingContinuation { continuation in
            let timeout = Task {
                guard (try? await Task.sleep(for: .seconds(5))) != nil else { return }
                complete(id, with: .failure(TelevisionError.notResponding))
            }
            pending[id] = PendingRequest(continuation: continuation, timeout: timeout)
            Task {
                do {
                    try await socket.send(.string(message))
                } catch {
                    complete(id, with: .failure(error))
                }
            }
        }
    }

    func press(_ button: RemoteButton) async throws {
        let socket = try await connectedPointerSocket()
        do {
            try await socket.send(.string(SSAP.buttonMessage(button)))
        } catch {
            pointerTask = nil
            pointerSocket = nil
            throw error
        }
    }

    func close() {
        disconnect(TelevisionError.connectionClosed)
    }

    /// Concurrent callers share one opening attempt, so the television never sees two registrations at once.
    private func connectedRequestSocket() async throws -> URLSessionWebSocketTask {
        let task = connectionTask ?? Task { try await openRequestSocket() }
        connectionTask = task
        do {
            return try await task.value
        } catch {
            connectionTask = nil
            throw error
        }
    }

    private func connectedPointerSocket() async throws -> URLSessionWebSocketTask {
        let task = pointerTask ?? Task { try await openPointerSocket() }
        pointerTask = task
        do {
            return try await task.value
        } catch {
            pointerTask = nil
            throw error
        }
    }

    private func openRequestSocket() async throws -> URLSessionWebSocketTask {
        let registration = try await LGTelevision.register(host: host, clientKey: clientKey)
        session = registration.session
        requestSocket = registration.socket
        Task { await receive(from: registration.socket) }
        return registration.socket
    }

    private func openPointerSocket() async throws -> URLSessionWebSocketTask {
        let response = try await request("ssap://com.webos.service.networkinput/getPointerInputSocket")
        guard let path = (try JSONSerialization.jsonObject(with: response) as? [String: Any])?["socketPath"] as? String,
              let url = URL(string: path), let session
        else { throw TelevisionError.navigationUnavailable }
        let socket = session.webSocketTask(with: url)
        socket.resume()
        pointerSocket = socket
        return socket
    }

    private func receive(from socket: URLSessionWebSocketTask) async {
        do {
            while true {
                guard let response = SSAP.response(from: try await socket.receiveJSON()) else { continue }
                complete(response.id, with: response.result)
            }
        } catch {
            if socket === requestSocket { disconnect(error) }
        }
    }

    private func complete(_ id: String, with result: Result<Data, Error>) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeout.cancel()
        request.continuation.resume(with: result)
    }

    private func disconnect(_ error: Error) {
        pending.keys.forEach { complete($0, with: .failure(error)) }
        pointerSocket?.cancel()
        requestSocket?.cancel()
        session?.invalidateAndCancel()
        pointerSocket = nil
        requestSocket = nil
        session = nil
        connectionTask = nil
        pointerTask = nil
    }
}

/// The television serves its API with a self-signed certificate on the local network.
private final class SelfSignedTrust: NSObject, URLSessionDelegate, Sendable {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard let trust = challenge.protectionSpace.serverTrust else { return (.performDefaultHandling, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }
}

private final class ResumeOnce: Sendable {
    private let continuation: Mutex<CheckedContinuation<String?, Never>?>

    init(_ continuation: CheckedContinuation<String?, Never>) { self.continuation = Mutex(continuation) }

    func callAsFunction(_ value: String?) {
        continuation.withLock { $0.take() }?.resume(returning: value)
    }
}

private extension URLSessionWebSocketTask {
    func receiveJSON() async throws -> [String: Any] {
        let data: Data
        switch try await receive() {
        case .string(let text): data = Data(text.utf8)
        case .data(let bytes): data = bytes
        @unknown default: return [:]
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
