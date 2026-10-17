import Testing

@Suite("Wake-on-LAN")
struct WakeOnLANTests {
    @Test func magicPacketIsSyncStreamThenSixteenAddresses() throws {
        let packet = try #require(WakeOnLAN.magicPacket(macAddress: "0A:1B:2C:0D:4E:5F"))
        let address: [UInt8] = [0x0A, 0x1B, 0x2C, 0x0D, 0x4E, 0x5F]
        #expect(packet.count == 102)
        #expect(packet.prefix(6).allSatisfy { $0 == 0xFF })
        for repetition in 0..<16 {
            let start = 6 + repetition * 6
            #expect(Array(packet[start..<start + 6]) == address)
        }
    }

    @Test func addressWithoutLeadingZerosIsAccepted() {
        // arp prints "0a:1b:2c:d:4e:5f", dropping leading zeros.
        #expect(WakeOnLAN.magicPacket(macAddress: "0a:1b:2c:d:4e:5f") == WakeOnLAN.magicPacket(macAddress: "0A:1B:2C:0D:4E:5F"))
    }

    @Test(arguments: ["", "0a:1b:2c:0d:4e", "0a:1b:2c:0d:4e:5f:00", "0a:1b:2c:0d:4e:zz", "0a-1b-2c-0d-4e-5f"])
    func malformedAddressGivesNoPacket(address: String) {
        #expect(WakeOnLAN.magicPacket(macAddress: address) == nil)
    }
}
