import CryptoKit
import Foundation
import Observation
import ServiceManagement

/// The root daemon that tunes the network during a GeForce NOW session, as the app sees it.
@Observable @MainActor
final class NetworkServiceStatus {
    enum Installation { case notInstalled, awaitingApproval, installed }

    var installation = Installation.notInstalled
    var isEnabled = true
    var isSessionActive = false
    var opensAtLogin = SMAppService.mainApp.status == .enabled
    var daemonLog = ""
    var lastError: String?

    /// The daemon ships inside the app; macOS asks once to allow it in System Settings.
    private let daemon = SMAppService.daemon(plistName: "com.vkarcher.cue.network-service.plist")
    private static let registeredDigestKey = "serviceBinaryDigest"

    init() {
        refresh()
        Task { await reloadIfUpdated() }
    }

    var isInstalled: Bool { installation == .installed }

    var summary: String {
        switch installation {
        case .notInstalled: String(localized: "Service not installed")
        case .awaitingApproval: String(localized: "Waiting for approval")
        case .installed where isSessionActive: isEnabled ? String(localized: "In game") : String(localized: "Restoring…")
        case .installed: isEnabled ? String(localized: "Waiting for GeForce NOW") : String(localized: "Paused")
        }
    }

    /// Cheap enough for the menu bar to poll. Values are assigned only when they change,
    /// since every assignment redraws the observers, the menu bar image included.
    func refresh() {
        let files = FileManager.default
        update(\.isEnabled, !files.fileExists(atPath: ServicePaths.pauseFlag.path))
        update(\.isSessionActive, files.fileExists(atPath: ServicePaths.sessionState.path))
        switch daemon.status {
        case .enabled: update(\.installation, .installed)
        case .requiresApproval: update(\.installation, .awaitingApproval)
        default: update(\.installation, .notInstalled)
        }
    }

    func install() {
        do {
            try registerDaemon()
        } catch {
            // The first registration fails until the user allows Cue in System Settings.
            if daemon.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            } else {
                lastError = error.localizedDescription
            }
        }
        refresh()
    }

    /// launchd stops the daemon, which restores AWDL and AirDrop first if a session is open.
    func uninstall() async {
        do {
            try await daemon.unregister()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try FileManager.default.removeItem(at: ServicePaths.pauseFlag)
            } else {
                try Data().write(to: ServicePaths.pauseFlag)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            lastError = error.localizedDescription
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Reads only the end of the log, which the daemon appends to forever.
    func readLog() {
        guard let handle = try? FileHandle(forReadingFrom: ServicePaths.log) else { return update(\.daemonLog, "") }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > 16_384 ? size - 16_384 : 0
        try? handle.seek(toOffset: offset)
        update(\.daemonLog, lastLines(of: handle.readDataToEndOfFile(), readFromOffset: offset, limit: 80))
    }

    private func update<Value: Equatable>(_ property: ReferenceWritableKeyPath<NetworkServiceStatus, Value>, _ value: Value) {
        if self[keyPath: property] != value { self[keyPath: property] = value }
    }

    private func registerDaemon() throws {
        try daemon.register()
        UserDefaults.standard.set(Self.daemonDigest(), forKey: Self.registeredDigestKey)
        lastError = nil
    }

    /// launchd keeps running the previous daemon binary after Cue is updated, so the service is reloaded once.
    private func reloadIfUpdated() async {
        guard daemon.status == .enabled, let digest = Self.daemonDigest(),
              UserDefaults.standard.string(forKey: Self.registeredDigestKey) != digest else { return }
        do {
            try await daemon.unregister()
        } catch {
            lastError = error.localizedDescription
            return refresh()
        }
        // macOS refuses a registration right after an unregistration ("Operation not permitted") for a moment.
        for attempt in 1...10 {
            do {
                try registerDaemon()
                break
            } catch {
                if attempt == 10 { lastError = error.localizedDescription }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        refresh()
    }

    private static func daemonDigest() -> String? {
        guard let url = Bundle.main.url(forAuxiliaryExecutable: "CueNetworkService"),
              let binary = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: binary).map { String(format: "%02x", $0) }.joined()
    }
}
