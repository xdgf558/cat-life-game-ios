import XCTest

extension RoomHomeUITests {
    @MainActor
    func testLegacyMirroredRoomCanSaveOnlyTheBowlAndCancelOneExplicitTurnWithoutChangingOtherFurniture() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = arguments(reset: true) + ["--legacy-mirrors-fixture", "--furniture-test", "--animation-test", "--reduce-motion-test"]
        launchAndEnterHome(app)
        let original = waitForFurniture(in: app, description: "the real schema 14 mirrored room migrates and opens normally") {
            $0.phase == "idle" && !$0.pending && $0.items.count == 9
        }
        let budget = try ["goldCount", "foodCount", "litterCount", "toyCount"].map { id in
            (id, try XCTUnwrap(observedHomeValue(id, in: app)))
        }
        for item in original.items {
            XCTAssertEqual(item.orientation, item.isWall ? "front" : "left")
            XCTAssertEqual(item.usesLegacyFootprint, !item.isWall)
            XCTAssertNotNil(item.footprintWidth); XCTAssertNotNil(item.footprintHeight)
        }
        let originalBowl = try XCTUnwrap(original.savedBowl)
        tapAnimationControl("homeDecorateButton", in: app)
        _ = waitForFurniture(in: app, description: "all untouched mirrored furniture remains legal on entering the editor") {
            $0.phase == "editing" && !$0.pending
        }
        XCTAssertTrue(element("layoutDoneButton", in: app).isEnabled)
        XCTAssertFalse(element("arrangementInvalidReason68", in: app).exists)
        tapAnimationControl("layoutTrayToggle", in: app)
        waitForObservedValue("layoutTrayToggle", "collapsed", in: app)
        let collapsed = furnitureState(in: app)
        element("roomScene", in: app).coordinate(withNormalizedOffset: collapsed.bowl.position).tap()
        tapAnimationControl("layoutTrayToggle", in: app)
        waitForObservedValue("layoutTrayToggle", "expanded", in: app)
        scrollPage("arrangementPanelScroll68", to: "nudgeFurniture68_right", allowDisabled: false, maximumDrags: 12, in: app)
        tapAnimationControl("nudgeFurniture68_right", in: app)
        let nudged = waitForFurniture(in: app, timeout: 30, description: "the visible bowl nudge completes without releasing any old furniture footprint") {
            guard !$0.pending, let bowl = $0.savedBowl else { return false }
            return hypot(bowl.x - originalBowl.x, bowl.y - originalBowl.y) > 0.0005
        }
        try assertLegacyFurnitureUnchanged(nudged, from: original)
        XCTAssertTrue(element("layoutDoneButton", in: app).isEnabled)
        attachScreenshot(app, named: "Legacy mirror migration — bowl-only draft has no invalid furniture")
        tapAnimationControl("layoutDoneButton", in: app)
        _ = waitForFurniture(in: app, description: "the bowl-only layout is durably saved") { $0.phase == "idle" && !$0.pending }
        let reopened = relaunchRestHome(app)
        try assertLegacyFurnitureUnchanged(reopened, from: original)
        XCTAssertEqual(try XCTUnwrap(reopened.savedBowl).x, try XCTUnwrap(nudged.savedBowl).x, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(reopened.savedBowl).y, try XCTUnwrap(nudged.savedBowl).y, accuracy: 0.000_001)
        for (id, amount) in budget { waitForObservedValue(id, amount, in: app) }
        tapAnimationControl("homeDecorateButton", in: app)
        tapAnimationControl("layoutTrayToggle", in: app)
        waitForObservedValue("layoutTrayToggle", "collapsed", in: app)
        _ = try selectFurniture("cabinet", in: app)
        tapAnimationControl("flipFurnitureButton", in: app)
        let turned = waitForFurniture(in: app, timeout: 30, description: "one real cabinet turn alone opts into the four-way footprint") {
            !$0.pending && $0.items.first { $0.id == "cabinet" }?.orientation == "front"
                && $0.items.first { $0.id == "cabinet" }?.usesLegacyFootprint == false
        }
        for item in turned.items where item.id != "cabinet" {
            XCTAssertEqual(item.usesLegacyFootprint, original.items.first { $0.id == item.id }?.usesLegacyFootprint)
            XCTAssertEqual(item.orientation, original.items.first { $0.id == item.id }?.orientation)
        }
        attachScreenshot(app, named: "Legacy mirror migration — only the deliberately turned cabinet releases its old footprint")
        tapAnimationControl("layoutCancelButton", in: app)
        let canceled = waitForFurniture(in: app, description: "Cancel restores the saved legacy marker and orientation") { $0.phase == "idle" && !$0.pending }
        try assertLegacyFurnitureUnchanged(canceled, from: reopened)
        let cold = relaunchRestHome(app)
        try assertLegacyFurnitureUnchanged(cold, from: reopened)
        for (id, amount) in budget { waitForObservedValue(id, amount, in: app) }
    }

    @MainActor
    private func assertLegacyFurnitureUnchanged(_ current: FurnitureState, from baseline: FurnitureState,
                                               file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(Set(current.items.map(\.id)), Set(baseline.items.map(\.id)), file: file, line: line)
        for before in baseline.items {
            let after = try XCTUnwrap(current.items.first { $0.id == before.id }, file: file, line: line)
            XCTAssertEqual(after.orientation, before.orientation, before.id, file: file, line: line)
            XCTAssertEqual(after.usesLegacyFootprint, before.usesLegacyFootprint, before.id, file: file, line: line)
            XCTAssertEqual(try XCTUnwrap(after.worldX), try XCTUnwrap(before.worldX), accuracy: 0.000_001, before.id, file: file, line: line)
            XCTAssertEqual(try XCTUnwrap(after.worldY), try XCTUnwrap(before.worldY), accuracy: 0.000_001, before.id, file: file, line: line)
            XCTAssertEqual(try XCTUnwrap(after.footprintWidth), try XCTUnwrap(before.footprintWidth), accuracy: 0.000_001, before.id, file: file, line: line)
            XCTAssertEqual(try XCTUnwrap(after.footprintHeight), try XCTUnwrap(before.footprintHeight), accuracy: 0.000_001, before.id, file: file, line: line)
        }
    }
}
