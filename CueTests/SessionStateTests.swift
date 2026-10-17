import Foundation
import Testing

@Suite("Session state and AirDrop setting")
struct SessionStateTests {
    @Test func readSettingIsReturned() {
        #expect(AirDropSetting.mode(fromReadStatus: 0, output: "Contacts Only") == .some("Contacts Only"))
    }

    @Test(arguments: [
        "Error: Could not find key 'DiscoverableMode' in domain 'com.apple.sharingd'.",
        "The domain/default pair of (com.apple.sharingd, DiscoverableMode) does not exist",
    ])
    func keyNeverSetIsKnownAsUnset(output: String) {
        #expect(AirDropSetting.mode(fromReadStatus: 1, output: output) == .some(nil))
    }

    @Test func otherFailureLeavesTheSettingUnknown() {
        #expect(AirDropSetting.mode(fromReadStatus: 1, output: "Could not find service in domain for user gui: 501") == nil)
    }

    @Test(arguments: [
        SessionState(user: "player", airDropMode: "Contacts Only", changedAirDrop: true),
        SessionState(user: "player", airDropMode: nil, changedAirDrop: true),
        SessionState(user: "", airDropMode: nil, changedAirDrop: false),
    ])
    func stateSurvivesADaemonRestart(state: SessionState) throws {
        let saved = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(SessionState.self, from: saved) == state)
    }
}
