import XCTest
import CatGameCore
@testable import CatLife

@MainActor
final class ArrangementDesign68Tests: XCTestCase {
    func testDragHistoryRecordsOneStepPerGestureCapsTwentyAndNeverWritesUncommittedDraft() async throws {
        let (store, repository) = try await makeStore()
        let saved = try XCTUnwrap(store.snapshot)
        let id = try XCTUnwrap(saved.inventory.furniture.first { $0.kind == .plant }?.id)
        let writes = await repository.writes
        store.beginDecorating()
        store.beginArrangementGesture68(); store.endArrangementGesture68()
        XCTAssertFalse(store.arrangement68.canUndo)
        for gesture in 0..<25 {
            store.beginArrangementGesture68()
            for sample in 0..<8 {
                store.moveFurniture(id: id, to: .init(x: 0.4 + Double(gesture) * 0.002 + Double(sample) * 0.0001, y: 0.7))
            }
            store.endArrangementGesture68()
            XCTAssertEqual(store.arrangement68.history.count, min(20, gesture + 1))
        }
        let beforeUndo = try XCTUnwrap(store.draftFurniture?.first { $0.itemID == id }?.position)
        store.undoArrangement68()
        let afterUndo = try XCTUnwrap(store.draftFurniture?.first { $0.itemID == id }?.position)
        XCTAssertLessThan(afterUndo.x, beforeUndo.x)
        XCTAssertEqual(store.arrangement68.history.count, 19)
        XCTAssertEqual(store.snapshot?.home, saved.home)
        XCTAssertEqual(store.snapshot?.inventory, saved.inventory)
        let finalWrites = await repository.writes
        XCTAssertEqual(finalWrites, writes)
        store.cancelDecorating()
        XCTAssertFalse(store.isDecorating)
        XCTAssertNil(store.draftFurniture)
        XCTAssertFalse(store.arrangement68.canUndo)
        XCTAssertEqual(store.snapshot?.home, saved.home)
        store.setForeground(false)
    }

    func testRotationAndNudgeRequestsPreserveScreenDirectionAndWaitForTheMatchingSceneAcknowledgement() async throws {
        let (store, _) = try await makeStore()
        let saved = try XCTUnwrap(store.snapshot)
        let item = try XCTUnwrap(saved.inventory.furniture.first { $0.kind == .catBed })
        store.beginDecorating(); store.selectFurniture(id: item.id)
        store.rotateSelectedFurniture68(clockwise: true)
        let rotation = try XCTUnwrap(store.arrangement68.pendingRequest)
        XCTAssertEqual(rotation.command, .rotate(id: item.id, orientation: item.orientation.turnedRight))
        XCTAssertEqual(store.selectedFurniture?.orientation, item.orientation)
        store.applyArrangementOrientation68(id: item.id, orientation: item.orientation.turnedRight)
        store.completeArrangementCommand68(UUID())
        XCTAssertEqual(store.arrangement68.pendingRequest?.id, rotation.id)
        store.completeArrangementCommand68(rotation.id)
        XCTAssertNil(store.arrangement68.pendingRequest)
        XCTAssertEqual(store.arrangement68.history.count, 1)
        store.nudgeSelectedFurniture68(dx: 1, dy: 0)
        let nudge = try XCTUnwrap(store.arrangement68.pendingRequest)
        XCTAssertEqual(nudge.command, .nudge(id: item.id, dx: 1, dy: 0, step: 0.5))
        let point = try XCTUnwrap(store.draftFurniture?.first { $0.itemID == item.id }?.position)
        store.moveFurniture(id: item.id, to: .init(x: point.x + 0.01, y: point.y))
        store.completeArrangementCommand68(nudge.id)
        XCTAssertEqual(store.arrangement68.history.count, 2)
        store.arrangement68.snapEnabled = false
        store.selectBowl68()
        store.nudgeSelectedFurniture68(dx: 0, dy: -1)
        let bowlNudge = try XCTUnwrap(store.arrangement68.pendingRequest)
        XCTAssertEqual(bowlNudge.command, .nudge(id: nil, dx: 0, dy: -1, step: 0.1))
        store.completeArrangementCommand68(bowlNudge.id)
        XCTAssertEqual(store.snapshot?.home, saved.home)
        XCTAssertEqual(store.snapshot?.inventory, saved.inventory)
        store.cancelDecorating(); store.setForeground(false)
    }

    func testInvalidPlacementBlocksFinishAndSaveFailureKeepsTheEntireDraftForRetry() async throws {
        let (store, repository) = try await makeStore()
        let before = try XCTUnwrap(store.snapshot)
        let item = try XCTUnwrap(before.inventory.furniture.first { $0.kind == .plant })
        store.beginDecorating(); store.selectFurniture(id: item.id)
        store.setArrangementIssue68(id: item.id, issue: .overlap("catBed"))
        store.confirmArrangementSelection68()
        XCTAssertNil(store.arrangement68.pendingRequest)
        store.finishDecorating()
        XCTAssertTrue(store.isDecorating)
        XCTAssertEqual(store.snapshot, before)
        store.setArrangementIssue68(id: item.id, issue: nil)
        store.beginArrangementGesture68()
        store.applyArrangementOrientation68(id: item.id, orientation: .right)
        store.endArrangementGesture68()
        var checked = before
        let validationTime = checked.meta.lastSyncAt
        XCTAssertTrue(GameEngine.setRoomLayout(&checked, bowlPosition: try XCTUnwrap(store.draftBowlPosition),
            furniture: try XCTUnwrap(store.draftFurniture), orientations: try XCTUnwrap(store.draftFurnitureOrientations),
            floor: store.visibleHomeFloor, now: validationTime).succeeded)
        let draft = store.draftFurniture
        let orientations = store.draftFurnitureOrientations
        await repository.setFailing(true)
        store.finishDecorating()
        try await eventually { !store.isBusy && store.hasSaveFailure }
        XCTAssertTrue(store.isDecorating)
        XCTAssertEqual(store.draftFurniture, draft)
        XCTAssertEqual(store.draftFurnitureOrientations, orientations)
        XCTAssertEqual(store.snapshot, before)
        XCTAssertTrue(store.arrangement68.canUndo)
        await repository.setFailing(false)
        store.finishDecorating()
        try await eventually { !store.isBusy && !store.isDecorating }
        XCTAssertEqual(store.snapshot?.inventory.furniture.first { $0.id == item.id }?.orientation, .right)
        XCTAssertEqual(store.snapshot?.home.furniture, before.home.furniture)
        XCTAssertFalse(store.arrangement68.canUndo)
        store.setForeground(false)
    }

    func testAcceptedNewFurnitureRemainsLockedUntilCatYieldEndsAsOneUndoStep() async throws {
        let (store, repository) = try await makeStore()
        let saved = try XCTUnwrap(store.snapshot)
        let id = try XCTUnwrap(saved.inventory.furniture.first { $0.kind == .plant }?.id)
        let position = try XCTUnwrap(saved.home.furniture.first { $0.itemID == id }?.position)
        store.beginDecorating(); store.selectFurniture(id: id); store.storeSelectedFurniture()
        let previousSteps = store.arrangement68.history.count
        let writes = await repository.writes
        store.placeFurniture(id: id)
        store.moveFurniture(id: id, to: position)
        store.finishFurniturePlacement(id: id, succeeded: true, keepingResolutionPending: true)
        XCTAssertNil(store.placingFurnitureID)
        XCTAssertTrue(store.isResolvingLayout)
        XCTAssertFalse(store.canEditArrangement68)
        XCTAssertEqual(store.arrangement68.history.count, previousSteps)
        store.finishDecorating(); store.undoArrangement68()
        XCTAssertTrue(store.isDecorating)
        XCTAssertEqual(store.snapshot, saved)
        XCTAssertEqual(store.arrangement68.history.count, previousSteps)
        let currentWrites = await repository.writes
        XCTAssertEqual(currentWrites, writes)
        store.setLayoutResolving(false); store.endArrangementGesture68()
        XCTAssertEqual(store.arrangement68.history.count, previousSteps + 1)
        store.undoArrangement68()
        XCTAssertFalse(store.draftFurniture?.contains { $0.itemID == id } ?? true)
        store.cancelDecorating(); store.setForeground(false)
    }

    func testUndoKeepsTheEarlierBlockedValidationResultInsteadOfMakingItSavable() async throws {
        let (store, repository) = try await makeStore()
        let saved = try XCTUnwrap(store.snapshot)
        let id = try XCTUnwrap(saved.home.furniture.first?.itemID)
        let writes = await repository.writes
        store.beginDecorating(); store.selectFurniture(id: id)
        store.beginArrangementGesture68()
        store.moveFurniture(id: id, to: .init(x: 0.55, y: 0.72))
        store.setArrangementIssue68(id: id, issue: .blocked)
        store.endArrangementGesture68()
        store.beginArrangementGesture68()
        store.moveFurniture(id: id, to: .init(x: 0.58, y: 0.74))
        store.setArrangementIssue68(id: id, issue: .overlap("catBed"))
        store.endArrangementGesture68()
        store.undoArrangement68()
        XCTAssertEqual(store.draftFurniture?.first { $0.itemID == id }?.position, .init(x: 0.55, y: 0.72))
        XCTAssertEqual(store.selectedArrangementIssue68, .blocked)
        store.finishDecorating()
        XCTAssertTrue(store.isDecorating)
        XCTAssertFalse(store.isBusy)
        XCTAssertEqual(store.snapshot, saved)
        let after = await repository.writes
        XCTAssertEqual(after, writes)
        store.undoArrangement68()
        XCTAssertFalse(store.arrangement68.hasInvalidPlacement)
        XCTAssertEqual(store.draftFurniture, saved.home.placements(on: store.visibleHomeFloor))
        store.cancelDecorating(); store.setForeground(false)
    }

    func testLateConfirmValidationFailureClearsPendingButKeepsTheInvalidSelection() async throws {
        let (store, _) = try await makeStore()
        let id = try XCTUnwrap(store.snapshot?.home.furniture.first?.itemID)
        store.beginDecorating(); store.selectFurniture(id: id)
        store.confirmArrangementSelection68()
        let request = try XCTUnwrap(store.arrangement68.pendingRequest)
        store.setArrangementIssue68(id: id, issue: .blocked)
        store.completeArrangementCommand68(request.id)
        XCTAssertNil(store.arrangement68.pendingRequest)
        XCTAssertEqual(store.selectedFurnitureID, id)
        XCTAssertEqual(store.selectedArrangementIssue68, .blocked)
        store.setArrangementIssue68(id: id, issue: nil)
        store.confirmArrangementSelection68()
        store.completeArrangementCommand68(try XCTUnwrap(store.arrangement68.pendingRequest).id)
        XCTAssertNil(store.selectedFurnitureID)
        store.cancelDecorating(); store.setForeground(false)
    }

    func testDroppedItemMustStillBeOwnedStoredEditableAndFromTheSameSaveAndFloor() async throws {
        let (store, _) = try await makeStore()
        let saved = try XCTUnwrap(store.snapshot)
        let id = try XCTUnwrap(saved.inventory.furniture.first { $0.kind == .plant }?.id)
        let generation = store.saveSceneGeneration
        let floor = store.visibleHomeFloor
        XCTAssertFalse(store.canDropArrangementFurniture68(id: id, generation: generation, floor: floor))
        store.beginDecorating()
        XCTAssertFalse(store.canDropArrangementFurniture68(id: id, generation: generation, floor: floor), "Placed furniture cannot be introduced as a bag item.")
        store.selectFurniture(id: id); store.storeSelectedFurniture()
        XCTAssertTrue(store.canDropArrangementFurniture68(id: id, generation: generation, floor: floor))
        XCTAssertFalse(store.canDropArrangementFurniture68(id: "unowned-item", generation: generation, floor: floor))
        XCTAssertFalse(store.canDropArrangementFurniture68(id: id, generation: UUID(), floor: floor))
        XCTAssertFalse(store.canDropArrangementFurniture68(id: id, generation: generation, floor: .upper))
        store.placeFurniture(id: id)
        XCTAssertFalse(store.canDropArrangementFurniture68(id: id, generation: generation, floor: floor), "A second asynchronous drop cannot enter an unfinished placement.")
        store.cancelDecorating()
        XCTAssertFalse(store.canDropArrangementFurniture68(id: id, generation: generation, floor: floor))
        XCTAssertEqual(store.snapshot?.home, saved.home)
        XCTAssertEqual(store.snapshot?.inventory, saved.inventory)
        store.setForeground(false)
    }

    func testBuildCopyHasMatchingKeysAndFormatsAndUsesRealFourWayMetadata() {
        let tables = [GameStrings.buildDesign68Chinese, GameStrings.buildDesign68Traditional, GameStrings.buildDesign68English]
        let registered = [GameStrings.chinese, GameStrings.traditionalChinese, GameStrings.english]
        for (index, table) in tables.enumerated() {
            XCTAssertEqual(Set(table.keys), Set(tables[0].keys))
            for key in table.keys {
                XCTAssertEqual(registered[index][key], table[key])
                XCTAssertFalse(table[key]!.isEmpty)
                XCTAssertEqual(formats(table[key]!), formats(tables[0][key]!))
            }
            for orientation in FurnitureOrientation.allCases { XCTAssertNotNil(table["build68.facing.\(orientation.rawValue)"]) }
        }
        XCTAssertEqual(FurnitureOrientation.allCases, [.front, .left, .back, .right])
    }

    private func formats(_ text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "%[0-9.]*[@df]")
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { String(text[Range($0.range, in: text)!]) }
    }
    private func makeStore() async throws -> (GameStore, ArrangementDesign68Repository) {
        var seed = GameSnapshot.fresh()
        seed.settings.audio = AudioSettings(musicEnabled: false, effectsEnabled: false, catEnabled: false, haptics: false)
        let suite = "CatLife-Arrangement68-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let repository = ArrangementDesign68Repository(seed)
        let store = GameStore(repository: repository, reminderDefaults: defaults)
        await store.load(); store.enterHome(); store.setForeground(true)
        try await eventually { !store.isBusy }
        return (store, repository)
    }
    private func eventually(_ condition: @MainActor () -> Bool) async throws {
        let until = Date().addingTimeInterval(5)
        while Date() < until {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("The arrangement save did not settle.")
        throw CocoaError(.coderInvalidValue)
    }
}

private actor ArrangementDesign68Repository: GameSaveRepository {
    let lastLoadDisposition = SaveLoadDisposition.loaded
    private(set) var writes = 0
    private var saved: GameSnapshot
    private var failing = false
    init(_ value: GameSnapshot) { saved = value }
    func setFailing(_ value: Bool) { failing = value }
    func loadOrCreate(now: Date) -> GameSnapshot { saved }
    func checkWritable() throws { if failing { throw CocoaError(.fileWriteUnknown) } }
    func save(_ value: GameSnapshot) throws { try checkWritable(); writes += 1; saved = value }
}
