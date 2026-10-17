import Foundation
import Testing

@Suite("French translation")
struct LocalizationTests {
    private struct Catalog: Decodable {
        struct Entry: Decodable { let localizations: [String: Localization]? }
        struct Localization: Decodable { let stringUnit: StringUnit? }
        struct StringUnit: Decodable { let state: String; let value: String }

        let strings: [String: Entry]
    }

    private static let catalogFile = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Cue/Resources/Localizable.xcstrings")

    private static func catalog() throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: catalogFile))
    }

    private static func placeholders(in text: String) -> [String] {
        text.matches(of: /%(?:\d+\$)?(@|lld)/).map { String($0.output.1) }.sorted()
    }

    @Test func everyStringIsTranslated() throws {
        for (key, entry) in try Self.catalog().strings {
            let french = entry.localizations?["fr"]?.stringUnit
            #expect(french?.state == "translated", "no French translation for \(key)")
        }
    }

    @Test func everyTranslationKeepsThePlaceholdersOfItsKey() throws {
        for (key, entry) in try Self.catalog().strings {
            guard let french = entry.localizations?["fr"]?.stringUnit?.value else { continue }
            #expect(Self.placeholders(in: key) == Self.placeholders(in: french), "\(key)")
        }
    }

    @Test func translationsContainNoEmDash() throws {
        for (key, entry) in try Self.catalog().strings {
            let french = entry.localizations?["fr"]?.stringUnit?.value ?? ""
            #expect(!key.contains("\u{2014}") && !french.contains("\u{2014}"), "\(key)")
        }
    }
}
