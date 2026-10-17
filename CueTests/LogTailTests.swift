import Foundation
import Testing

@Suite("Log tail")
struct LogTailTests {
    private let chunk = Data("one\ntwo\nthree\nfour\n".utf8)

    @Test func chunkReadFromTheStartKeepsItsFirstLine() {
        #expect(lastLines(of: chunk, readFromOffset: 0, limit: 10) == "one\ntwo\nthree\nfour")
    }

    @Test func chunkReadFromMidFileDropsItsPartialFirstLine() {
        #expect(lastLines(of: chunk, readFromOffset: 512, limit: 10) == "two\nthree\nfour")
    }

    @Test func onlyTheLastLinesAreKept() {
        #expect(lastLines(of: chunk, readFromOffset: 0, limit: 2) == "three\nfour")
    }

    @Test func emptyLogGivesNothing() {
        #expect(lastLines(of: Data(), readFromOffset: 0, limit: 80).isEmpty)
        #expect(lastLines(of: Data(), readFromOffset: 512, limit: 80).isEmpty)
    }
}
