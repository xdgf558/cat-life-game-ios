#if os(macOS)
import XCTest
@testable import CatLifeMac

@MainActor
final class MacRoomInputTests: XCTestCase {
    func testNativeViewCoordinatesMatchSceneTopLeftConvention() {
        let point = CGPoint(x: 240, y: 160)
        XCTAssertEqual(MacRoomPointer.screenPoint(point, height: 720, isFlipped: false), CGPoint(x: 240, y: 560))
        XCTAssertEqual(MacRoomPointer.screenPoint(point, height: 720, isFlipped: true), point)
        let converted = MacRoomPointer.screenPoint(point, height: 720, isFlipped: false)
        XCTAssertEqual(MacRoomPointer.screenPoint(converted, height: 720, isFlipped: false), point)
    }

    func testWheelReversalAndLargeDeltasStayBounded() {
        XCTAssertEqual(MacRoomPointer.zoomFactor(delta: 0, reversed: false), 1)
        for delta: CGFloat in [-100_000, -2, 2, 100_000] {
            let normal = MacRoomPointer.zoomFactor(delta: delta, reversed: false)
            let reversed = MacRoomPointer.zoomFactor(delta: delta, reversed: true)
            XCTAssertEqual(normal * reversed, 1, accuracy: 0.000_001)
            XCTAssertLessThanOrEqual(normal, exp(0.35))
            XCTAssertGreaterThanOrEqual(normal, exp(-0.35))
        }
    }

    func testFrameLimitHonorsSettingAndDisplayRefreshRate() {
        XCTAssertEqual(MacRoomPointer.frameLimit(requested: 120, screenMaximum: 120), 120)
        XCTAssertEqual(MacRoomPointer.frameLimit(requested: 120, screenMaximum: 60), 60)
        XCTAssertEqual(MacRoomPointer.frameLimit(requested: 30, screenMaximum: 120), 30)
        XCTAssertEqual(MacRoomPointer.frameLimit(requested: 999, screenMaximum: 120), 60)
    }

    func testWholeRoomZoomKeepsCenterWhenTheViewportIsWiderThanTheRoom() {
        let camera = RoomViewCamera()
        camera.configure(bounds: CGRect(x: 0, y: 0, width: 1000, height: 1000),
            viewport: CGSize(width: 800, height: 600), usableRect: CGRect(x: 0, y: 0, width: 800, height: 600),
            worldScale: 2, reset: true)
        // Fit includes horizontal letterboxing; keeping the room in bounds takes priority over the cursor anchor.
        camera.beginPinch(at: CGPoint(x: 430, y: 280))
        camera.changePinch(factor: MacRoomPointer.zoomFactor(delta: 8, reversed: false), at: CGPoint(x: 430, y: 280))
        camera.endPinch()
        XCTAssertGreaterThan(camera.visibleRect.width, 1000)
        XCTAssertEqual(camera.center.x, 500, accuracy: 0.000_001)
    }

    func testReadOnlyPreviewFinishesLayoutWithoutActivatingGameplay() async throws {
        let scene = RoomScene(size: CGSize(width: 800, height: 600))
        scene.setPresentationActive(false)
        scene.apply(snapshot: .fresh(now: Date()), editing: false)
        scene.prepareDesktopView()
        scene.setReadOnlyPreviewEnabled(true)
        defer { scene.setReadOnlyPreviewEnabled(false); scene.setPresentationActive(false) }
        for _ in 0..<200 where scene.bowlPlanningRequest != nil {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertNil(scene.bowlPlanningRequest)
        XCTAssertFalse(scene.cat.isHidden)
        XCTAssertFalse(scene.bowl.isHidden)
        XCTAssertFalse(scene.presentationActive)
        XCTAssertEqual(scene.roomViewAngle, .right)
        XCTAssertTrue(scene.isWholeRoomView)
        scene.takeQuietStroll(now: Date().addingTimeInterval(120), restRoll: 0)
        XCTAssertNil(scene.activeRest)
    }

    func testPreviewAndRetainedRoomRepublishReadinessAndCatsToANewHost() async throws {
        let scene = RoomScene(size: CGSize(width: 800, height: 600))
        scene.setPresentationActive(false)
        scene.apply(snapshot: .fresh(now: Date()), editing: false)
        scene.setReadOnlyPreviewEnabled(true)
        defer { scene.setReadOnlyPreviewEnabled(false); scene.setPresentationActive(false) }
        for _ in 0..<200 where scene.bowlPlanningRequest != nil {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertNil(scene.bowlPlanningRequest)
        // The title preview consumes scene samples without forwarding them to Store.
        scene.onFloorTravelAvailabilityChanged = { _ in }
        scene.onVisibleResidentsChanged = { _ in }
        scene.update(1)
        var readiness: [Bool] = []
        var visible: [Set<String>] = []
        scene.onFloorTravelAvailabilityChanged = { readiness.append($0) }
        scene.onVisibleResidentsChanged = { visible.append($0) }
        scene.setReadOnlyPreviewEnabled(false)
        scene.setPresentationActive(true)
        scene.update(2)
        XCTAssertEqual(readiness, [true], "Title → home must publish the already-idle state.")
        XCTAssertTrue(visible.last?.contains(try XCTUnwrap(scene.displayedCatID)) == true)

        scene.setPresentationActive(false) // A shop/work page retains the scene without rendering it.
        readiness = []; visible = []
        scene.onFloorTravelAvailabilityChanged = { readiness.append($0) }
        scene.onVisibleResidentsChanged = { visible.append($0) }
        scene.setPresentationActive(true)
        scene.update(3)
        XCTAssertEqual(readiness, [true], "Home → shop → home must not retain a stale Store travel lock.")
        XCTAssertTrue(visible.last?.contains(try XCTUnwrap(scene.displayedCatID)) == true)
    }

    func testCursorAnchoredZoomKeepsTheSameRoomPoint() {
        let camera = RoomViewCamera()
        camera.configure(bounds: CGRect(x: 0, y: 0, width: 1000, height: 1000),
            viewport: CGSize(width: 800, height: 600), usableRect: CGRect(x: 0, y: 0, width: 800, height: 600),
            worldScale: 2, reset: true)
        camera.zoom(by: 2)
        let cursor = CGPoint(x: 430, y: 280)
        let world = camera.worldPoint(viewPoint: cursor)
        camera.beginPinch(at: cursor)
        camera.changePinch(factor: MacRoomPointer.zoomFactor(delta: 8, reversed: false), at: cursor)
        camera.endPinch()
        let result = camera.viewPoint(projectedWorld: world)
        XCTAssertEqual(result.x, cursor.x, accuracy: 0.000_001)
        XCTAssertEqual(result.y, cursor.y, accuracy: 0.000_001)
        XCTAssertFalse(camera.isPinching)
    }
}
#endif
