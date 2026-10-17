import Foundation

/// The last `limit` lines of a log chunk, without the partial first line of a chunk read from mid-file.
func lastLines(of chunk: Data, readFromOffset offset: UInt64, limit: Int) -> String {
    var lines = String(decoding: chunk, as: UTF8.self).split(separator: "\n")
    if offset > 0, !lines.isEmpty { lines.removeFirst() }
    return lines.suffix(limit).joined(separator: "\n")
}
