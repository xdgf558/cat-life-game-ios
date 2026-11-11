import XCTest
import CatGameCore
@testable import CatLife

@MainActor
final class HabitDesign68Tests: XCTestCase {
    func testUnrecordedMemorySlotsDoNotExposeTitlesOrRecordedIdentifiers() throws {
        let oldLanguage = GameLocalization.shared.language
        defer { GameLocalization.shared.language = oldLanguage }
        var cat = GameSnapshot.fresh().cats[0]
        cat.habits.memories = [try JSONDecoder().decode(CatMemory.self,
            from: Data(#"{"kind":"firstResponse","createdAt":0}"#.utf8))]
        for language in GameLanguage.allCases {
            GameLocalization.shared.language = language
            for kind in CatMemoryKind.allCases {
                let slot = HabitMemorySlot68(kind: kind, cat: cat)
                if kind == .firstResponse {
                    XCTAssertNotNil(slot.memory)
                    XCTAssertEqual(slot.title, GameStrings.text(kind.titleKey))
                    XCTAssertEqual(slot.accessibilityIdentifier, "catMemory_firstResponse")
                } else {
                    XCTAssertNil(slot.memory)
                    XCTAssertEqual(slot.title, GameStrings.text("habit68.memory.empty"))
                    XCTAssertFalse(slot.accessibilityIdentifier.hasPrefix("catMemory_"))
                    XCTAssertNotEqual(slot.title, GameStrings.text(kind.titleKey))
                }
            }
        }
    }

    func testHabitDesignCopyIsRegisteredWithMatchingFormatsInAllLanguages() {
        let dictionaries = [GameStrings.habitDesign68Chinese, GameStrings.habitDesign68Traditional, GameStrings.habitDesign68English]
        let registered = [GameStrings.chinese, GameStrings.traditionalChinese, GameStrings.english]
        let keys = Set(dictionaries[0].keys)
        let regex = try! NSRegularExpression(pattern: "%[@df]")
        for (index, dictionary) in dictionaries.enumerated() {
            XCTAssertEqual(Set(dictionary.keys), keys)
            for key in keys {
                let value = dictionary[key]!
                XCTAssertFalse(value.isEmpty)
                XCTAssertEqual(registered[index][key], value)
                let formats: (String) -> [String] = { text in
                    regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                        .map { String(text[Range($0.range, in: text)!]) }
                }
                XCTAssertEqual(formats(value), formats(dictionaries[0][key]!))
            }
        }
    }
}
