import Foundation
import Testing

@Suite("SSAP messages")
struct TelevisionProtocolTests {
    private func object(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    @Test func registrationCarriesTheManifestAndTheClientKey() throws {
        let manifest = Data(#"{"pairingType":"PROMPT"}"#.utf8)
        let message = try object(SSAP.registrationMessage(manifest: manifest, clientKey: "key-123"))
        let payload = try #require(message["payload"] as? [String: Any])
        #expect(message["type"] as? String == "register")
        #expect(payload["pairingType"] as? String == "PROMPT")
        let clientKey = payload["client-key"] as? String
        #expect(clientKey == "key-123")
    }

    @Test func firstRegistrationHasNoClientKey() throws {
        let message = try object(SSAP.registrationMessage(manifest: Data("{}".utf8), clientKey: nil))
        let payload = try #require(message["payload"] as? [String: Any])
        #expect(payload["client-key"] == nil)
    }

    @Test func manifestThatIsNotAnObjectIsRejected() {
        #expect(throws: TelevisionError.pairingManifestMissing) {
            try SSAP.registrationMessage(manifest: Data("[]".utf8), clientKey: nil)
        }
    }

    @Test func requestCarriesItsIdentifierURIAndPayload() throws {
        let message = try object(SSAP.requestMessage(id: "request_7", uri: "ssap:audio/setVolume", payload: ["volume": 12]))
        let header = [message["type"], message["id"], message["uri"]].map { $0 as? String }
        #expect(header == ["request", "request_7", "ssap:audio/setVolume"])
        #expect((message["payload"] as? [String: Any])?["volume"] as? Int == 12)
    }

    @Test(arguments: RemoteButton.allCases)
    func buttonMessageFollowsThePointerLineProtocol(button: RemoteButton) {
        #expect(SSAP.buttonMessage(button) == "type:button\nname:\(button.rawValue)\n\n")
    }

    @Test func registeredMessageGivesTheClientKey() throws {
        let key = try SSAP.clientKey(fromRegistrationMessage: ["type": "registered", "payload": ["client-key": "abc"]])
        #expect(key == "abc")
    }

    @Test func acknowledgementIsNotARegistration() throws {
        #expect(try SSAP.clientKey(fromRegistrationMessage: ["type": "response", "payload": ["pairingType": "PROMPT"]]) == nil)
    }

    @Test func registrationWithoutAKeyIsRefused() {
        #expect(throws: TelevisionError.pairingRefused(nil)) {
            try SSAP.clientKey(fromRegistrationMessage: ["type": "registered", "payload": ["client-key": ""]])
        }
    }

    @Test func registrationErrorKeepsTheTelevisionsReason() {
        #expect(throws: TelevisionError.pairingRefused("403 User denied access")) {
            try SSAP.clientKey(fromRegistrationMessage: ["type": "error", "error": "403 User denied access"])
        }
    }

    @Test func successfulResponseReturnsItsPayload() throws {
        let response = try #require(SSAP.response(from: ["id": "request_1", "type": "response", "payload": ["returnValue": true, "volume": 5]]))
        let payload = try object(String(decoding: try response.result.get(), as: UTF8.self))
        #expect(response.id == "request_1")
        #expect(payload["volume"] as? Int == 5)
    }

    @Test func responseWithReturnValueFalseIsARefusal() throws {
        let response = try #require(SSAP.response(from: ["id": "request_2", "payload": ["returnValue": false, "errorText": "Unknown input"]]))
        #expect(throws: TelevisionError.refused("Unknown input")) { try response.result.get() }
    }

    @Test func errorMessageIsARefusal() throws {
        let response = try #require(SSAP.response(from: ["id": "request_3", "type": "error", "error": "401 insufficient permissions"]))
        #expect(throws: TelevisionError.refused("401 insufficient permissions")) { try response.result.get() }
    }

    @Test func messageWithoutIdentifierAnswersNoRequest() {
        #expect(SSAP.response(from: ["type": "response", "payload": [:]]) == nil)
    }

    @Test(arguments: [("com.webos.app.hdmi1", "HDMI_1"), ("com.webos.app.hdmi4", "HDMI_4")])
    func hdmiAppMapsToItsInput(appID: String, input: String) {
        #expect(SSAP.inputID(foregroundAppID: appID) == input)
    }

    @Test(arguments: ["com.webos.app.livetv", "netflix", "com.webos.app.hdmi", "com.webos.app.hdmiX", ""])
    func otherAppsShowNoInput(appID: String) {
        #expect(SSAP.inputID(foregroundAppID: appID) == nil)
    }

    @Test(arguments: [
        (TelevisionError.refused(nil), true),
        (.notResponding, false),
        (.connectionClosed, false),
        (.notFound("TV"), false),
    ])
    func onlyARefusalKeepsTheConnection(error: TelevisionError, keepsConnection: Bool) {
        #expect(error.keepsConnection == keepsConnection)
    }

    @Test(arguments: [
        TelevisionError.notPaired, .notFound("TV"), .notResponding, .refused(nil), .pairingRefused(nil),
        .pairingManifestMissing, .invalidAddress("host"), .navigationUnavailable, .connectionClosed,
    ])
    func everyErrorHasADescription(error: TelevisionError) {
        #expect(error.errorDescription?.isEmpty == false)
    }
}
