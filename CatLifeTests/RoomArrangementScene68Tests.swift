import SpriteKit
import XCTest
import CatGameCore
@testable import CatLife

@MainActor
final class RoomArrangementScene68Tests: XCTestCase {
    func testLateYieldCompletionChecksRevisionFloorAndActiveStateBeforeFinishingTheTransaction() async throws {
        let scene = RoomScene(size: CGSize(width: 375, height: 569))
        defer { scene.setPresentationActive(false) }
        scene.apply(snapshot: GameSnapshot.fresh(), editing: true, selectedFurnitureID: "cabinet")
        try await wait { scene.bowlPlanningRequest == nil && !scene.isPlacementPending }
        let request = ArrangementRequest68(command: .rotate(id: "cabinet", orientation: .back))
        var completed: [UUID] = [], ended = 0
        scene.onArrangementCommandCompleted = { completed.append($0) }
        scene.onArrangementGestureEnded = { ended += 1 }
        scene.arrangement68.pendingRequest = request
        scene.beginArrangementGesture68()
        scene.arrangement68.yielding = true
        scene.setPlacementPending(true)
        let ticket = scene.placementRevision
        scene.finishArrangementYield68(ticket: ticket - 1, requestedFloor: .ground)
        XCTAssertTrue(scene.isPlacementPending)
        scene.homeFloor = .upper
        scene.finishArrangementYield68(ticket: ticket, requestedFloor: .ground)
        XCTAssertTrue(scene.isPlacementPending)
        scene.homeFloor = .ground
        scene.setPresentationActive(false)
        scene.finishArrangementYield68(ticket: ticket, requestedFloor: .ground)
        XCTAssertTrue(scene.isPlacementPending)
        XCTAssertNotNil(scene.arrangement68.yieldContinuation)
        XCTAssertTrue(completed.isEmpty); XCTAssertEqual(ended, 0)
        scene.setPresentationActive(true)
        XCTAssertFalse(scene.isPlacementPending)
        XCTAssertFalse(scene.arrangementYielding68)
        XCTAssertEqual(completed, [request.id]); XCTAssertEqual(ended, 1)
        scene.finishArrangementYield68(ticket: ticket, requestedFloor: .ground)
        XCTAssertEqual(completed, [request.id]); XCTAssertEqual(ended, 1)
    }

    func testASecondTransformCannotReplaceThePendingCommandWhileCatsAreYielding() async throws {
        let scene = RoomScene(size: CGSize(width: 375, height: 569))
        defer { scene.setPresentationActive(false) }
        scene.apply(snapshot: GameSnapshot.fresh(), editing: true, selectedFurnitureID: "cabinet")
        try await wait { scene.bowlPlanningRequest == nil && !scene.isPlacementPending }
        let first = ArrangementRequest68(command: .rotate(id: "cabinet", orientation: .back))
        scene.arrangement68.pendingRequest = first
        scene.arrangement68.yielding = true
        scene.setPlacementPending(true)
        let position = scene.selectedNode.position
        scene.applyArrangementCommand68(.init(command: .nudge(id: "cabinet", dx: 1, dy: 0, step: 0.5)), snapEnabled: true)
        XCTAssertEqual(scene.arrangement68.pendingRequest?.id, first.id)
        XCTAssertEqual(scene.selectedNode.position, position)
        XCTAssertTrue(scene.isPlacementPending)
        XCTAssertFalse(scene.canChangeRoomView)
        scene.invalidateArrangement68()
        XCTAssertFalse(scene.arrangementYielding68)
        XCTAssertFalse(scene.isPlacementPending)
    }

    func testUnmovedTapAndRestoredUndoLayoutKeepTheirFullBlockedValidation() async throws {
        let scene = RoomScene(size: CGSize(width: 375, height: 569))
        defer { scene.setPresentationActive(false) }
        var earlier = GameSnapshot.fresh()
        earlier.home.roomLevel = 2
        scene.apply(snapshot: earlier, editing: true, selectedFurnitureID: "cabinet")
        try await wait { scene.bowlPlanningRequest == nil && !scene.isPlacementPending }
        scene.setArrangementIssue68(id: "cabinet", issue: .blocked)
        scene.beginArrangementGesture68()
        // Touch previews know static bounds; a tap must retain the completed
        // worker's stricter feeding/rest-route verdict at the unchanged location.
        _ = scene.previewArrangementPoint68(scene.selectedNode.position)
        scene.preserveUnmovedArrangementIssue68(scene.arrangement68.gestureIssues["cabinet"])
        scene.endArrangementGesture68()
        XCTAssertEqual(scene.arrangementPlacementIssues68["cabinet"], .blocked)
        var later = earlier
        later.home.furniture[0].position.x += 0.001
        scene.configureArrangement68(snapEnabled: true, placementIssues: ["cabinet": .blocked])
        scene.apply(snapshot: later, editing: true, selectedFurnitureID: "cabinet")
        scene.configureArrangement68(snapEnabled: true, placementIssues: ["cabinet": .blocked])
        scene.apply(snapshot: earlier, editing: true, selectedFurnitureID: "cabinet")
        XCTAssertEqual(scene.arrangementPlacementIssues68["cabinet"], .blocked,
                       "Undo must restore the original worker verdict instead of making a blocked layout savable.")
    }

    func testInvalidNudgeRetainsTheRedDraftAndCompletesItsUUIDOnlyOnce() async throws {
        let scene = RoomScene(size: CGSize(width: 375, height: 569))
        defer { scene.setPresentationActive(false) }
        var snapshot = GameSnapshot.fresh()
        snapshot.home.roomLevel = 2
        scene.apply(snapshot: snapshot, editing: true, selectedFurnitureID: "cabinet")
        try await wait { scene.bowlPlanningRequest == nil && !scene.isPlacementPending }
        var completed: [UUID] = [], starts = 0, ends = 0
        var moved: NormalizedPoint?
        scene.onArrangementCommandCompleted = { completed.append($0) }
        scene.onArrangementGestureBegan = { starts += 1 }
        scene.onArrangementGestureEnded = { ends += 1 }
        scene.onFurnitureMoved = { id, point in if id == "cabinet" { moved = point } }
        scene.configureArrangement68(snapEnabled: false)
        let request = ArrangementRequest68(command: .nudge(id: "cabinet", dx: -1, dy: 0, step: 100))
        scene.applyArrangementCommand68(request, snapEnabled: false)
        try await wait { completed == [request.id] }
        XCTAssertEqual(scene.arrangementPlacementIssues68["cabinet"], .outside)
        XCTAssertLessThan(try XCTUnwrap(moved).x, 0)
        XCTAssertEqual(starts, 1); XCTAssertEqual(ends, 1)
        scene.applyArrangementCommand68(request, snapEnabled: false)
        XCTAssertEqual(completed, [request.id])
        XCTAssertEqual(starts, 1); XCTAssertEqual(ends, 1)
    }

    func testOwnedBagDropSupersedesAutoPlacementAndKeepsAnInvalidDropForAdjustment() async throws {
        let scene = RoomScene(size: CGSize(width: 375, height: 569))
        defer { scene.setPresentationActive(false) }
        var snapshot = GameSnapshot.fresh()
        snapshot.home.roomLevel = 2
        snapshot.inventory.furniture.append(.init(id: "bag-plant", kind: .plant))
        scene.apply(snapshot: snapshot, editing: true)
        try await wait { scene.bowlPlanningRequest == nil && !scene.isPlacementPending }
        var starts = 0, ends = 0, finished = 0
        var moved: NormalizedPoint?
        scene.onArrangementGestureBegan = { starts += 1 }
        scene.onArrangementGestureEnded = { ends += 1 }
        scene.onFurnitureMoved = { id, point in if id == "bag-plant" { moved = point } }
        scene.onFurniturePlacementFinished = { id, accepted in
            XCTAssertEqual(id, "bag-plant"); XCTAssertTrue(accepted); finished += 1
        }
        scene.apply(snapshot: snapshot, editing: true, selectedFurnitureID: "bag-plant", placingFurnitureID: "bag-plant")
        scene.dropStoredFurniture68("bag-plant", atViewPoint: CGPoint(x: -500, y: -500))
        try await wait { finished == 1 && !scene.isPlacementPending }
        XCTAssertNotNil(moved)
        XCTAssertNotNil(scene.arrangementPlacementIssues68["bag-plant"])
        XCTAssertEqual(starts, 1); XCTAssertEqual(ends, 1)
        XCTAssertNil(scene.newPlacementID)
    }

    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(predicate(), "The real Scene planning callback did not finish.")
    }
}
