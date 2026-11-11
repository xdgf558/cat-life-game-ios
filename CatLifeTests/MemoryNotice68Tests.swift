import XCTest
import CatGameCore
@testable import CatLife

@MainActor
final class MemoryNotice68Tests: XCTestCase {
    func testExistingHistoryDoesNotReplayAndNewReceiptsRetainTheirCatAndGeneration() throws {
        var previous = GameSnapshot.fresh()
        previous.cats[0].habits.memories = [try memory(.firstResponse)]
        let center = CompanionMemoryNotices68()
        let generation = UUID()
        center.record(from: previous, to: previous, generation: generation)
        XCTAssertFalse(center.hasPending)
        var current = previous
        current.cats[0].habits.memories.append(try memory(.favoritePlay))
        center.record(from: previous, to: current, generation: generation)
        center.record(from: previous, to: current, generation: generation)
        XCTAssertEqual(center.pending.count, 1)
        XCTAssertEqual(center.current?.catID, current.cats[0].id)
        XCTAssertEqual(center.current?.memory.kind, .favoritePlay)
        XCTAssertEqual(center.current?.generation, generation)
        center.clear()
        XCTAssertFalse(center.hasPending, "Replacing a save must discard the old timeline's display receipts.")
    }

    func testResultAcknowledgesOnlyItsDisplayedMemoryFromTheSameCatAndGeneration() throws {
        let previous = GameSnapshot.fresh()
        var current = previous
        current.cats[0].habits.memories = [try memory(.favoritePlay), try memory(.understandEachOther)]
        let center = CompanionMemoryNotices68()
        let generation = UUID()
        let catID = current.cats[0].id
        center.record(from: previous, to: current, generation: generation)
        let notices = center.pending
        XCTAssertEqual(notices.map(\.memory.kind), [.favoritePlay, .understandEachOther])

        center.acknowledge(catID: catID, kind: .understandEachOther, generation: UUID())
        XCTAssertEqual(center.pending, notices, "A callback from another save generation must not consume these memories.")
        center.acknowledge(catID: "another-cat", kind: .understandEachOther, generation: generation)
        XCTAssertEqual(center.pending, notices, "Showing another cat must not consume this cat's memories.")

        center.acknowledge(catID: catID, kind: .understandEachOther, generation: generation)
        XCTAssertEqual(center.pending, [notices[0]], "Only the result card that actually appeared is acknowledged; the earlier memory stays queued for Home.")
        center.acknowledge(catID: catID, kind: .understandEachOther, generation: generation)
        XCTAssertEqual(center.pending, [notices[0]], "Repeated appearances must preserve the remaining queue and its order.")
    }

    func testFailedCornerSaveDoesNotPublishAMemoryAndRetryPublishesItOnce() async throws {
        let now = Date()
        var seed = GameSnapshot.fresh(now: now.addingTimeInterval(-60))
        seed.settings.audio = AudioSettings(musicEnabled: false, effectsEnabled: false, catEnabled: false, haptics: false)
        let catID = seed.activeCatID
        let item = try XCTUnwrap(seed.home.furniture.first { $0.itemID == "floorCushion" })
        XCTAssertTrue(GameEngine.startCatRest(&seed, catID: catID, furnitureID: item.itemID,
            observation: .init(floor: item.floor, position: item.position), now: now.addingTimeInterval(-30)).succeeded)
        XCTAssertTrue(GameEngine.synchronize(&seed, now: now).succeeded)
        let receipt = try XCTUnwrap(seed.cats[0].habits.lastRestObservation)
        let repository = MemoryNoticeRepository68(seed)
        let store = GameStore(repository: repository)
        await store.load(); store.enterHome(); store.setForeground(true)
        try await wait { !store.isBusy }
        XCTAssertFalse(store.companionMemories.hasPending, "Loading history never produces a new-memory banner.")
        await repository.setFailing(true)
        let failed = await store.chooseHabitCorner(catID: catID, observationID: receipt.id)
        XCTAssertFalse(failed)
        XCTAssertFalse(store.companionMemories.hasPending)
        XCTAssertNil(store.cat?.habits.cornerFurnitureID)
        await repository.setFailing(false)
        let saved = await store.chooseHabitCorner(catID: catID, observationID: receipt.id)
        XCTAssertTrue(saved)
        XCTAssertEqual(store.companionMemories.pending.map(\.memory.kind), [.littleCorner])
        XCTAssertEqual(store.companionMemories.current?.catID, catID)
        store.setForeground(false)
    }

    func testRootDesignCopyIsRegisteredInEveryLanguage() {
        let dictionaries = [GameStrings.design68Chinese, GameStrings.design68Traditional, GameStrings.design68English]
        let registered = [GameStrings.chinese, GameStrings.traditionalChinese, GameStrings.english]
        for (index, dictionary) in dictionaries.enumerated() {
            XCTAssertEqual(Set(dictionary.keys), Set(dictionaries[0].keys))
            for (key, value) in dictionary {
                XCTAssertEqual(registered[index][key], value)
                XCTAssertEqual(value.components(separatedBy: "%@").count, dictionaries[0][key]!.components(separatedBy: "%@").count)
            }
        }
    }

    private func memory(_ kind: CatMemoryKind) throws -> CatMemory {
        try JSONDecoder().decode(CatMemory.self, from: Data("{\"kind\":\"\(kind.rawValue)\",\"createdAt\":0}".utf8))
    }
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(4)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(15)) }
        XCTAssertTrue(condition())
    }
}

private actor MemoryNoticeRepository68: GameSaveRepository {
    let lastLoadDisposition = SaveLoadDisposition.loaded
    var saved: GameSnapshot
    var failing = false
    init(_ value: GameSnapshot) { saved = value }
    func setFailing(_ value: Bool) { failing = value }
    func loadOrCreate(now: Date) -> GameSnapshot { saved }
    func checkWritable() throws { if failing { throw CocoaError(.fileWriteUnknown) } }
    func save(_ value: GameSnapshot) throws { try checkWritable(); saved = value }
}
