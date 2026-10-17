import Foundation
import Network
import Observation

/// The paired LG television: its live state, the remote commands, and the GeForce NOW automation.
@Observable @MainActor
final class TelevisionControl {
    struct Input: Identifiable, Hashable {
        let id: String
        let label: String

        /// "HDMI 2" for "HDMI_2".
        var port: String { id.replacingOccurrences(of: "_", with: " ") }
    }

    enum Power { case unknown, off, on }

    var discoveredNames: [String] = []
    var journal: [String] = []
    var power = Power.unknown
    var inputs = (1...4).map { Input(id: "HDMI_\($0)", label: "HDMI \($0)") }
    var currentInput: String?
    var volume = 0
    var isMuted = false
    var isPlaying = true

    var serviceName: String? { didSet { UserDefaults.standard.set(serviceName, forKey: "televisionName") } }
    var launchInput: String { didSet { UserDefaults.standard.set(launchInput, forKey: "televisionInput") } }
    var switchesInputOnLaunch: Bool { didSet { UserDefaults.standard.set(switchesInputOnLaunch, forKey: "televisionSwitchesInputOnLaunch") } }
    var turnsOffOnQuit: Bool { didSet { UserDefaults.standard.set(turnsOffOnQuit, forKey: "televisionTurnsOffOnQuit") } }
    // shortcut: the client key sits in UserDefaults, not the Keychain; it only controls the TV and pairing again replaces it.
    private(set) var clientKey: String? { didSet { UserDefaults.standard.set(clientKey, forKey: "televisionClientKey") } }
    private(set) var macAddresses: [String] { didSet { UserDefaults.standard.set(macAddresses, forKey: "televisionMACAddresses") } }

    private var link: TelevisionLink?
    private var gameSwitch: Task<Void, Never>?
    private var lastRefreshError: String?
    private let buttonPresses: AsyncStream<RemoteButton>.Continuation
    private let browser = NWBrowser(for: .bonjour(type: LGTelevision.serviceType, domain: nil), using: .tcp)

    init() {
        let defaults = UserDefaults.standard
        serviceName = defaults.string(forKey: "televisionName")
        launchInput = defaults.string(forKey: "televisionInput") ?? "HDMI_2"
        switchesInputOnLaunch = defaults.object(forKey: "televisionSwitchesInputOnLaunch") as? Bool ?? true
        turnsOffOnQuit = defaults.object(forKey: "televisionTurnsOffOnQuit") as? Bool ?? true
        clientKey = defaults.string(forKey: "televisionClientKey")
        macAddresses = defaults.stringArray(forKey: "televisionMACAddresses") ?? []
        let (presses, continuation) = AsyncStream.makeStream(of: RemoteButton.self)
        buttonPresses = continuation

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let names = results.compactMap { result -> String? in
                guard case .service(let name, _, _, _) = result.endpoint, name.hasPrefix("[LG]") else { return nil }
                return name
            }
            MainActor.assumeIsolated { self?.discoveredNames = names.sorted() }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                MainActor.assumeIsolated { self?.record(String(localized: "Bonjour browsing failed: \(error.localizedDescription)")) }
            }
        }
        browser.start(queue: .main)

        // One consumer keeps key presses in order, even while the first one waits for the connection.
        Task { [weak self] in
            for await button in presses { await self?.send(button) }
        }
    }

    var isPaired: Bool { serviceName != nil && clientKey != nil }
    var choices: [String] { Array(Set(discoveredNames + [serviceName].compactMap { $0 })).sorted() }
    /// "OLED55C44LA" out of "[LG] webOS TV OLED55C44LA".
    var model: String { serviceName?.split(separator: " ").last.map(String.init) ?? String(localized: "Television") }

    func record(_ text: String) {
        journal.append("\(Date.now.formatted(date: .omitted, time: .standard))  \(text)")
        if journal.count > 300 { journal.removeFirst() }
    }

    func label(of input: String) -> String {
        inputs.first { $0.id == input }?.label ?? Input(id: input, label: input).port
    }

    // MARK: Pairing

    func select(_ newName: String?) {
        guard newName != serviceName else { return }
        if let old = link {
            link = nil
            Task { await old.close() }
        }
        serviceName = newName
        clientKey = nil
        macAddresses = []
        power = .unknown
        record(newName.map { String(localized: "Television selected: \($0)") } ?? String(localized: "Television removed"))
    }

    func pair() async {
        guard let serviceName else { return }
        guard let host = await LGTelevision.resolveAddress(serviceName: serviceName) else {
            return record(String(localized: "\(serviceName) not found on the network: is it on?"))
        }
        record(String(localized: "Pairing request sent: accept it on the television"))
        do {
            clientKey = try await LGTelevision.pair(host: host)
            record(String(localized: "Paired"))
            // The kept connection registered with the previous key.
            if let link { await disconnect(link) }
            let info = try await request("ssap://com.webos.service.connectionmanager/getinfo")
            macAddresses = ["wiredInfo", "wifiInfo"].compactMap { (info[$0] as? [String: Any])?["macAddress"] as? String }
            record(macAddresses.isEmpty
                ? String(localized: "No MAC address found")
                : String(localized: "MAC addresses: \(macAddresses.joined(separator: ", "))"))
            await refresh()
        } catch {
            record(String(localized: "Pairing failed: \(error.localizedDescription)"))
        }
    }

    // MARK: Live state

    /// Reads power, inputs, the input on screen and the volume. Polled every few seconds, so a failure is logged once.
    func refresh() async {
        guard isPaired else { return }
        do {
            let list = try await request("ssap://tv/getExternalInputList")
            if let devices = list["devices"] as? [[String: Any]] {
                inputs = devices.compactMap { device in
                    guard let id = device["id"] as? String else { return nil }
                    return Input(id: id, label: device["label"] as? String ?? id)
                }
            }
            let foreground = try await request("ssap://com.webos.applicationManager/getForegroundAppInfo")
            currentInput = SSAP.inputID(foregroundAppID: foreground["appId"] as? String ?? "")
            let audio = try await request("ssap://audio/getVolume")
            let status = audio["volumeStatus"] as? [String: Any] ?? audio
            volume = status["volume"] as? Int ?? volume
            isMuted = status["muteStatus"] as? Bool ?? (status["muteStatus"] as? Int).map { $0 != 0 } ?? isMuted
            power = .on
            lastRefreshError = nil
        } catch {
            if error.localizedDescription != lastRefreshError {
                record(String(localized: "Television unreachable: \(error.localizedDescription)"))
            }
            lastRefreshError = error.localizedDescription
            if (error as? TelevisionError)?.keepsConnection != true { power = .off }
        }
    }

    // MARK: Remote

    func press(_ button: RemoteButton) {
        buttonPresses.yield(button)
    }

    func playPause() {
        press(isPlaying ? .pause : .play)
        isPlaying.toggle()
    }

    func setVolume(_ level: Int) {
        volume = level
        command("ssap://audio/setVolume", payload: ["volume": level])
    }

    func toggleMute() {
        isMuted.toggle()
        command("ssap://audio/setMute", payload: ["mute": isMuted])
    }

    func switchInput(to input: String) {
        currentInput = input
        command("ssap://tv/switchInput", payload: ["inputId": input])
    }

    func togglePower() async {
        if power == .on {
            await turnOff()
        } else {
            wake()
            for _ in 0..<10 where power != .on {
                try? await Task.sleep(for: .seconds(2))
                await refresh()
            }
        }
    }

    private func send(_ button: RemoteButton) async {
        do {
            let current = try await connectedLink()
            do {
                try await current.press(button)
            } catch {
                await disconnect(current)
                throw error
            }
        } catch {
            record(String(localized: "Key \(button.rawValue): \(error.localizedDescription)"))
        }
    }

    private func command(_ uri: String, payload: [String: any Sendable]) {
        Task {
            do {
                _ = try await request(uri, payload: payload)
            } catch {
                record(String(localized: "Command \(uri) failed: \(error.localizedDescription)"))
                await refresh()
            }
        }
    }

    // MARK: GeForce NOW automation

    func gameStarted() {
        guard switchesInputOnLaunch else { return }
        gameSwitch?.cancel()
        gameSwitch = Task { await switchToLaunchInput() }
    }

    /// Cancels a switch still waiting for the television, so it cannot land after the power off.
    func gameEnded() async {
        gameSwitch?.cancel()
        gameSwitch = nil
        if turnsOffOnQuit { await turnOff() }
    }

    func switchToLaunchInput() async {
        guard isPaired else { return record(String(localized: "Input switch skipped: television not paired")) }
        wake()
        // A television woken from standby needs several seconds before its API answers.
        for attempt in 1...15 {
            guard !Task.isCancelled else { return }
            do {
                _ = try await request("ssap://tv/switchInput", payload: ["inputId": launchInput])
                guard !Task.isCancelled else { return }
                currentInput = launchInput
                power = .on
                return record(String(localized: "Switched to \(label(of: launchInput))"))
            } catch {
                record(String(localized: "Attempt \(attempt): \(error.localizedDescription)"))
            }
            try? await Task.sleep(for: .seconds(2))
        }
        record(String(localized: "Gave up switching to \(label(of: launchInput))"))
    }

    func turnOff() async {
        guard isPaired else { return record(String(localized: "Power off skipped: television not paired")) }
        do {
            _ = try await request("ssap://system/turnOff")
            power = .off
            record(String(localized: "Television turned off"))
        } catch {
            record(String(localized: "Power off failed: \(error.localizedDescription)"))
        }
        if let link { await disconnect(link) }
    }

    private func wake() {
        guard !macAddresses.isEmpty else { return record(String(localized: "No MAC address: cannot power on remotely")) }
        let sent = macAddresses.filter(WakeOnLAN.send(to:))
        record(sent.isEmpty ? String(localized: "Wake-on-LAN failed") : String(localized: "Wake-on-LAN sent"))
    }

    // MARK: Connection

    private func connectedLink() async throws -> TelevisionLink {
        if let link { return link }
        guard let serviceName, let clientKey else { throw TelevisionError.notPaired }
        guard let host = await LGTelevision.resolveAddress(serviceName: serviceName) else {
            throw TelevisionError.notFound(serviceName)
        }
        // Another caller may have connected, or the television may have changed, during the lookup.
        if let link { return link }
        guard serviceName == self.serviceName, clientKey == self.clientKey else { throw TelevisionError.notPaired }
        let newLink = TelevisionLink(host: host, clientKey: clientKey)
        link = newLink
        return newLink
    }

    private func request(_ uri: String, payload: [String: any Sendable] = [:]) async throws -> [String: Any] {
        let current = try await connectedLink()
        let data: Data
        do {
            data = try await current.request(uri, payload: payload)
        } catch let error as TelevisionError {
            // Only a refusal leaves the connection usable; a timeout drops it but is not retried at once.
            if !error.keepsConnection { await disconnect(current) }
            throw error
        } catch {
            // A closed socket: the television slept or the network changed. Reconnect and retry once.
            await disconnect(current)
            data = try await connectedLink().request(uri, payload: payload)
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    /// The link stays the kept one only if no newer connection replaced it meanwhile.
    private func disconnect(_ stale: TelevisionLink) async {
        if link === stale { link = nil }
        await stale.close()
    }
}
