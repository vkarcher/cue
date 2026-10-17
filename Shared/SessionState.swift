import Foundation

/// What a game session changed, saved to disk so a daemon restarted in the middle of a session can still restore it.
struct SessionState: Codable, Equatable {
    let user: String
    /// nil when the setting was never set; the key is then deleted on restore.
    let airDropMode: String?
    /// false when the setting could not be read: AirDrop is left alone rather than restored to a guess.
    let changedAirDrop: Bool
}

enum AirDropSetting {
    /// Interprets `defaults read com.apple.sharingd DiscoverableMode`: the mode, .some(nil) when the key was
    /// never set, nil when the setting could not be read.
    static func mode(fromReadStatus status: Int32, output: String) -> String?? {
        if status == 0 { return .some(output) }
        // A key never set reads "does not exist" up to macOS 26 and "Could not find key" since macOS 27.
        if output.contains("does not exist") || output.contains("Could not find key") { return .some(nil) }
        return nil
    }
}
