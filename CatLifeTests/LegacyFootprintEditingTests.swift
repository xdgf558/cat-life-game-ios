import SpriteKit
import XCTest
import CatGameCore
@testable import CatLife

@MainActor
final class LegacyFootprintEditingTests: XCTestCase {
    func testBowlOnlySaveAndOtherFloorProjectionKeepEveryLegacyFootprint() async throws {
        let (store, repository) = try await makeStore()
        defer { store.setForeground(false) }
        let before = try XCTUnwrap(store.snapshot)
        store.beginDecorating()
        let bowl = try XCTUnwrap(store.draftBowlPosition)
        store.moveBowl(to: .init(x: bowl.x - 0.01, y: bowl.y))
        XCTAssertEqual(store.sceneSnapshot?.inventory.furniture, before.inventory.furniture)
        XCTAssertFalse(try XCTUnwrap(store.sceneSnapshot).home.furniture.contains { $0.floor == .upper })
        store.finishDecorating()
        try await settle { !store.isBusy && !store.isDecorating }
        XCTAssertEqual(store.snapshot?.inventory.furniture, before.inventory.furniture)
        XCTAssertEqual(store.snapshot?.home.furniture.sorted { $0.itemID < $1.itemID },
                       before.home.furniture.sorted { $0.itemID < $1.itemID })
        let persisted = await repository.saved
        XCTAssertEqual(persisted.inventory.furniture, before.inventory.furniture)
        await store.changeHomeFloor(to: .upper)
        XCTAssertEqual(store.visibleHomeFloor, .upper)
        store.beginDecorating()
        XCTAssertEqual(store.sceneSnapshot?.inventory.furniture, before.inventory.furniture,
                       "One-floor scene projection must not treat the omitted floor as storage.")
        store.cancelDecorating()
    }

    func testMoveRotateAndStorageReleaseOnlyTheEditedItemAndUndoCancelRestoreItsBaseline() async throws {
        let (store, _) = try await makeStore()
        defer { store.setForeground(false) }
        let before = try XCTUnwrap(store.snapshot)
        let point = try XCTUnwrap(before.home.furniture.first { $0.itemID == "cabinet" }?.position)
        store.beginDecorating(); store.selectFurniture(id: "cabinet")
        store.beginArrangementGesture68()
        store.moveFurniture(id: "cabinet", to: .init(x: point.x + 0.000_000_1, y: point.y))
        XCTAssertTrue(try item("cabinet", in: store.sceneSnapshot).usesLegacyFootprint,
                      "A SpriteKit float round trip is not a player move.")
        store.moveFurniture(id: "cabinet", to: .init(x: point.x + 0.03, y: point.y))
        store.endArrangementGesture68()
        XCTAssertFalse(try item("cabinet", in: store.sceneSnapshot).usesLegacyFootprint)
        XCTAssertTrue(try item("upstairs-bookcase", in: store.sceneSnapshot).usesLegacyFootprint)
        store.undoArrangement68()
        XCTAssertTrue(try item("cabinet", in: store.sceneSnapshot).usesLegacyFootprint)
        XCTAssertEqual(store.draftFurniture, before.home.placements(on: .ground))
        store.beginArrangementGesture68()
        store.applyArrangementOrientation68(id: "cabinet", orientation: .left)
        store.endArrangementGesture68()
        XCTAssertFalse(try item("cabinet", in: store.sceneSnapshot).usesLegacyFootprint,
                       "An explicit facing selection adopts the new model even when the facing is unchanged.")
        XCTAssertTrue(store.hasUnsavedLayoutChanges, "Releasing the old footprint is an unsaved geometry change even with the same facing.")
        store.undoArrangement68()
        XCTAssertTrue(try item("cabinet", in: store.sceneSnapshot).usesLegacyFootprint)
        XCTAssertFalse(store.hasUnsavedLayoutChanges)
        store.selectFurniture(id: "cabinet"); store.storeSelectedFurniture()
        XCTAssertFalse(try item("cabinet", in: store.sceneSnapshot).usesLegacyFootprint)
        store.undoArrangement68()
        XCTAssertTrue(try item("cabinet", in: store.sceneSnapshot).usesLegacyFootprint)
        store.moveFurniture(id: "cabinet", to: .init(x: point.x + 0.03, y: point.y))
        store.cancelDecorating()
        XCTAssertEqual(store.sceneSnapshot?.inventory.furniture, before.inventory.furniture)
        XCTAssertEqual(store.snapshot?.home.furniture, before.home.furniture)
    }

    func testFailedMovedLayoutKeepsSavedLegacyGeometryUntilRetryCommits() async throws {
        let (store, repository) = try await makeStore()
        defer { store.setForeground(false) }
        let before = try XCTUnwrap(store.snapshot)
        let point = try XCTUnwrap(before.home.furniture.first { $0.itemID == "cabinet" }?.position)
        store.beginDecorating(); store.beginArrangementGesture68()
        store.moveFurniture(id: "cabinet", to: .init(x: point.x + 0.03, y: point.y))
        store.endArrangementGesture68()
        await repository.setFailing(true)
        store.finishDecorating()
        try await settle { !store.isBusy && store.hasSaveFailure }
        XCTAssertTrue(try item("cabinet", in: store.snapshot).usesLegacyFootprint)
        XCTAssertFalse(try item("cabinet", in: store.sceneSnapshot).usesLegacyFootprint)
        XCTAssertTrue(store.isDecorating)
        let failedSave = await repository.saved
        XCTAssertEqual(failedSave.inventory.furniture, before.inventory.furniture)
        await repository.setFailing(false)
        store.finishDecorating()
        try await settle { !store.isBusy && !store.isDecorating }
        XCTAssertFalse(try item("cabinet", in: store.snapshot).usesLegacyFootprint)
        XCTAssertTrue(try item("upstairs-bookcase", in: store.snapshot).usesLegacyFootprint)
        let persisted = await repository.saved
        XCTAssertEqual(persisted.inventory, try XCTUnwrap(store.snapshot).inventory)
    }

    func testDraggedOutlineAndPlanningUseTheReleasedFootprintWhileUnmovedTapKeepsOldDimensions() throws {
        let snapshot = try legacySnapshot()
        let item = try item("cabinet", in: snapshot)
        let transform = RoomArtworkTransform(sceneSize: .init(width: 402, height: 600),
                                              artworkSize: .init(width: 1024, height: 1536))
        let world = RoomFurnitureWorld(transform: transform, catWidth: 40, bowlSize: .init(width: 30, height: 25),
            bowlPosition: .zero, items: [item], placements: [.init(itemID: item.id, position: .init(x: 0.5, y: 0.7))])
        let original = try XCTUnwrap(world.center(item.id))
        let preview = CGPoint(x: original.x + 30, y: original.y - 20)
        let projection = RoomViewProjection(worldSize: transform.sceneSize, angle: .right)
        let artwork = RoomArrangementRendering68()
        for point in [original, preview] {
            let proposed = world.replacing(item.id, with: point)
            let expectedItem = try XCTUnwrap(proposed.item(item.id))
            XCTAssertEqual(expectedItem.usesLegacyFootprint, point == original)
            artwork.update(world: world, projection: projection, editing: true, selectedID: item.id,
                bowlSelected: false, issues: [:], previewCenter: point)
            let rectangle = proposed.rectangle(expectedItem, at: point)
            let projected = [CGPoint(x: rectangle.minX, y: rectangle.minY), CGPoint(x: rectangle.maxX, y: rectangle.minY),
                             CGPoint(x: rectangle.maxX, y: rectangle.maxY), CGPoint(x: rectangle.minX, y: rectangle.maxY)].map(projection.project)
            let expectedPath = CGMutablePath(); expectedPath.addLines(between: projected); expectedPath.closeSubpath()
            let shape = try XCTUnwrap(artwork.childNode(withName: "arrangement-footprint68") as? SKShapeNode)
            XCTAssertEqual(try XCTUnwrap(shape.path).boundingBoxOfPath, expectedPath.boundingBoxOfPath)
        }
        XCTAssertNotEqual(world.footprint(item), world.replacing(item.id, with: preview).footprint(try XCTUnwrap(world.replacing(item.id, with: preview).item(item.id))))
        XCTAssertTrue(try XCTUnwrap(world.item(item.id)).usesLegacyFootprint)
    }

    func testSceneDropPublishesReleasedGeometryBeforeTheStoreCallback() async throws {
        var snapshot = try legacySnapshot()
        snapshot.home = HomeState(roomLevel: 2)
        snapshot.inventory.furniture.removeAll { $0.id == "upstairs-bookcase" }
        XCTAssertNoThrow(try NativeSaveTransfer.encode(snapshot: snapshot))
        let scene = RoomScene(size: .init(width: 375, height: 569))
        defer { scene.setPresentationActive(false) }
        scene.apply(snapshot: snapshot, editing: true, selectedFurnitureID: "cabinet")
        try await settle(seconds: 15) { scene.bowlPlanningRequest == nil && !scene.isPlacementPending }
        XCTAssertTrue(try XCTUnwrap(scene.furnitureWorld.item("cabinet")).usesLegacyFootprint)
        var callbackMarker: Bool?
        scene.onFurnitureMoved = { id, _ in
            if id == "cabinet" { callbackMarker = scene.furnitureWorld.item(id)?.usesLegacyFootprint }
        }
        // An outside drop is deliberately kept as a red draft; its pending geometry
        // still has to match the outline and the Store's eventual draft projection.
        scene.selectedNode.position.x += 1_000
        scene.resolveArrangementPlacement68(findNearest: false, snapPoint: false)
        try await settle(seconds: 15) { callbackMarker != nil && !scene.isPlacementPending }
        XCTAssertEqual(callbackMarker, false)
        XCTAssertFalse(try XCTUnwrap(scene.furnitureWorld.item("cabinet")).usesLegacyFootprint)
        XCTAssertEqual(scene.arrangementPlacementIssues68["cabinet"], .outside)
    }

    private func item(_ id: String, in snapshot: GameSnapshot?) throws -> FurnitureItem {
        try XCTUnwrap(snapshot?.inventory.furniture.first { $0.id == id })
    }
    private func legacySnapshot() throws -> GameSnapshot {
        var value = GameSnapshot.fresh()
        value.home = HomeState(roomLevel: 6)
        value.inventory.furniture.append(.init(id: "upstairs-bookcase", kind: .bookcase))
        value.home.furniture.append(.init(itemID: "upstairs-bookcase", position: .init(x: 0.6, y: 0.65), floor: .upper))
        value.settings.audio = AudioSettings(musicEnabled: false, effectsEnabled: false, catEnabled: false, haptics: false)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any])
        json["schemaVersion"] = 14
        var inventory = try XCTUnwrap(json["inventory"] as? [String: Any])
        var furniture = try XCTUnwrap(inventory["furniture"] as? [[String: Any]])
        for index in furniture.indices {
            furniture[index].removeValue(forKey: "usesLegacyFootprint")
            furniture[index]["orientation"] = ["cabinet", "upstairs-bookcase"].contains(furniture[index]["id"] as? String ?? "") ? "mirrored" : "normal"
        }
        inventory["furniture"] = furniture; json["inventory"] = inventory
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GameSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    }
    private func makeStore() async throws -> (GameStore, LegacyFootprintRepository) {
        let repository = LegacyFootprintRepository(try legacySnapshot())
        let suite = "CatLife-LegacyFootprint-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = GameStore(repository: repository, reminderDefaults: defaults)
        await store.load(); store.enterHome(); store.setForeground(true)
        try await settle { !store.isBusy }
        return (store, repository)
    }
    private func settle(seconds: Double = 5, _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(predicate(), "The legacy-footprint edit did not settle.")
    }
}

private actor LegacyFootprintRepository: GameSaveRepository {
    let lastLoadDisposition = SaveLoadDisposition.loaded
    private(set) var saved: GameSnapshot
    private var failing = false
    init(_ value: GameSnapshot) { saved = value }
    func setFailing(_ value: Bool) { failing = value }
    func loadOrCreate(now: Date) -> GameSnapshot { saved }
    func checkWritable() throws { if failing { throw CocoaError(.fileWriteUnknown) } }
    func save(_ value: GameSnapshot) throws { try checkWritable(); saved = value }
}
