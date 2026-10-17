import Foundation

/// Wakes a television from standby; it must have "Turn on via Wi-Fi" enabled.
enum WakeOnLAN {
    /// Six 0xFF bytes followed by the hardware address sixteen times; nil for a malformed address.
    static func magicPacket(macAddress: String) -> [UInt8]? {
        let fields = macAddress.split(separator: ":")
        let bytes = fields.compactMap { UInt8($0, radix: 16) }
        guard fields.count == 6, bytes.count == 6 else { return nil }
        return [UInt8](repeating: 0xFF, count: 6) + (0..<16).flatMap { _ in bytes }
    }

    /// Broadcasts the magic packet on UDP port 9. Returns whether the whole packet left.
    static func send(to macAddress: String) -> Bool {
        guard let packet = magicPacket(macAddress: macAddress) else { return false }
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var broadcast: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            return false
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(9).bigEndian
        address.sin_addr.s_addr = UInt32.max
        let sent = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(descriptor, packet, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return sent == packet.count
    }
}
