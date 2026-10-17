import Foundation

/// Files shared by the app and the root daemon. The log path is repeated in the launchd plist.
enum ServicePaths {
    /// Exists while a session is open; holds what the daemon must restore.
    static let sessionState = URL(filePath: "/var/db/cue-network-service.state")
    /// Created by the app to pause the service. Anyone can write it, but it can only disable.
    static let pauseFlag = URL(filePath: "/Users/Shared/cue-network-service.disabled")
    static let log = URL(filePath: "/var/log/cue-network-service.log")
}
