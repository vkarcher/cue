import Foundation
import SystemConfiguration

func logEvent(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    print("\(formatter.string(from: .now)) \(message)")
    fflush(stdout)
}

@discardableResult
func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(filePath: path)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
    } catch {
        return (-1, error.localizedDescription)
    }
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}

/// Runs a command in the user's own launchd session, so preferences go through that user's cfprefsd.
func runAsUser(_ user: String, uid: uid_t, _ arguments: [String]) -> (status: Int32, output: String) {
    run("/bin/launchctl", ["asuser", String(uid), "/usr/bin/sudo", "-u", user] + arguments)
}

func isRunning(_ process: String) -> Bool {
    run("/usr/bin/pgrep", ["-qx", process]).status == 0
}

/// The logged-in user, or nil at the login window, where the console belongs to root or a setup account.
func consoleUser() -> (name: String, uid: uid_t)? {
    var uid: uid_t = 0
    guard let name = SCDynamicStoreCopyConsoleUser(nil, &uid, nil) as String?, uid >= 501 else { return nil }
    return (name, uid)
}

enum AirDrop {
    static func mode(of user: String, uid: uid_t) -> String?? {
        let result = runAsUser(user, uid: uid, ["defaults", "read", "com.apple.sharingd", "DiscoverableMode"])
        return AirDropSetting.mode(fromReadStatus: result.status, output: result.output)
    }

    static func set(_ mode: String?, for user: String, uid: uid_t) {
        let arguments = mode.map { ["defaults", "write", "com.apple.sharingd", "DiscoverableMode", "-string", $0] }
            ?? ["defaults", "delete", "com.apple.sharingd", "DiscoverableMode"]
        guard runAsUser(user, uid: uid, arguments).status == 0 || mode == nil else {
            return logEvent("AirDrop unchanged for \(user): the setting could not be written")
        }
        run("/usr/bin/pkill", ["-x", "-u", user, "sharingd"]) // relaunched on demand with the new value
        logEvent("AirDrop set to \(mode ?? "its default") for \(user)")
    }
}

/// The root daemon registered by Cue: AWDL down and AirDrop on "No One" while GeForce NOW runs.
/// Runs on the main queue only, so the evaluation timer and the stop signal never interleave.
@MainActor
final class NetworkService {
    private var activeSession: SessionState? = (try? Data(contentsOf: ServicePaths.sessionState))
        .flatMap { try? JSONDecoder().decode(SessionState.self, from: $0) }

    func evaluateSession() {
        let wantsSession = !FileManager.default.fileExists(atPath: ServicePaths.pauseFlag.path) && isRunning("GeForceNOW")
        if wantsSession {
            if activeSession == nil { startSession() }
            // macOS brings awdl0 back up on its own, so it is forced down on every pass.
            run("/sbin/ifconfig", ["awdl0", "down"])
        } else if let activeSession {
            endSession(activeSession)
        }
    }

    func stop() {
        if let activeSession { endSession(activeSession) }
    }

    private func startSession() {
        let user = consoleUser()
        let mode = user.flatMap { AirDrop.mode(of: $0.name, uid: $0.uid) }
        let session = SessionState(user: user?.name ?? "", airDropMode: mode ?? nil, changedAirDrop: mode != nil)
        activeSession = session
        do {
            try JSONEncoder().encode(session).write(to: ServicePaths.sessionState, options: .atomic)
        } catch {
            logEvent("Session state not saved, a restart during this session would not restore it: \(error.localizedDescription)")
        }
        logEvent("GeForce NOW started: AWDL off")
        if let user, session.changedAirDrop {
            AirDrop.set("Off", for: user.name, uid: user.uid)
        }
    }

    private func endSession(_ session: SessionState) {
        // Closing the window quits GeForceNOW but leaves its container running. The container is kept while
        // GeForceNOW still runs, which happens when the service is paused during a game.
        if !isRunning("GeForceNOW") { run("/usr/bin/pkill", ["-x", "GeForceNOWContainer"]) }
        run("/sbin/ifconfig", ["awdl0", "up"])
        if session.changedAirDrop, let account = getpwnam(session.user) {
            AirDrop.set(session.airDropMode, for: session.user, uid: account.pointee.pw_uid)
        }
        activeSession = nil
        try? FileManager.default.removeItem(at: ServicePaths.sessionState)
        logEvent("Session ended: AWDL restored")
    }
}

let service = NetworkService()

signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler {
    MainActor.assumeIsolated { service.stop() }
    exit(0)
}
termination.resume()

let timer = DispatchSource.makeTimerSource(queue: .main)
// 5 seconds: restarting sharingd for AirDrop brings awdl0 back up once, shortly after the session starts.
timer.schedule(deadline: .now(), repeating: .seconds(5))
timer.setEventHandler { MainActor.assumeIsolated { service.evaluateSession() } }
timer.resume()

dispatchMain()
