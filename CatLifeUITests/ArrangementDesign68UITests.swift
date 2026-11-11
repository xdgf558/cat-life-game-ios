import XCTest

extension RoomHomeUITests {
    @MainActor
    func testArrangement68RealBagDragDeliversOwnedItemAndCancelRestoresTheSavedRoom() throws {
        continueAfterFailure = false
        let app = launchFurnitureHome()
        let startingGold = try XCTUnwrap(observedHomeValue("goldCount", in: app))
        let original = furnitureState(in: app)
        tapAnimationControl("homeDecorateButton", in: app)
        tapAnimationControl("layoutTrayToggle", in: app)
        waitForObservedValue("layoutTrayToggle", "collapsed", in: app)
        _ = try selectFurniture("catBed", in: app)
        tapAnimationControl("quickStoreFurnitureButton", in: app)
        _ = waitForFurniture(in: app, description: "the owned bed is stored only in the current draft") {
            !$0.pending && !$0.items.contains { $0.id == "catBed" }
        }
        tapAnimationControl("layoutTrayToggle", in: app)
        waitForObservedValue("layoutTrayToggle", "expanded", in: app)
        tapAnimationControl("arrangementFilter68_bag", in: app)
        scrollPage("arrangementPanelScroll68", to: "layoutStored_catBed", allowDisabled: false, maximumDrags: 12, in: app)
        let card = element("layoutStored_catBed", in: app)
        XCTAssertTrue(card.isHittable)
        XCTAssertTrue(unobscuredScrollViewport(element("arrangementPanelScroll68", in: app), in: app).contains(card.frame),
                      "The OS drag must begin on the complete visible bag card.")
        let destination = element("roomScene", in: app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        attachScreenshot(app, named: "Arrangement 68 — real owned bag card before the OS drag")
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.8, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 0.15)
        let dropped = waitForFurniture(in: app, timeout: 30, description: "the OS text item provider delivers the owned bed into the room draft") {
            $0.phase == "editing" && !$0.pending && $0.selected == "catBed" && $0.items.contains { $0.id == "catBed" }
        }
        XCTAssertEqual(dropped.items.filter { $0.id == "catBed" }.count, 1)
        XCTAssertEqual(Set(dropped.items.map(\.id)), Set(original.items.map(\.id)))
        XCTAssertTrue(element("layoutUnsavedChanges", in: app).exists)
        attachScreenshot(app, named: "Arrangement 68 — OS-delivered bed is selected in an unsaved draft")
        tapAnimationControl("layoutCancelButton", in: app)
        _ = waitForFurniture(in: app, description: "cancel discards the OS drop without changing the saved room") { $0.phase == "idle" && !$0.pending }
        let reopened = relaunchRestHome(app)
        XCTAssertEqual(Set(reopened.items.map(\.id)), Set(original.items.map(\.id)))
        for item in original.items {
            let same = try XCTUnwrap(reopened.items.first { $0.id == item.id })
            XCTAssertEqual(same.orientation, item.orientation)
            XCTAssertEqual(try XCTUnwrap(same.worldX), try XCTUnwrap(item.worldX), accuracy: 0.003)
            XCTAssertEqual(try XCTUnwrap(same.worldY), try XCTUnwrap(item.worldY), accuracy: 0.003)
        }
        waitForObservedValue("goldCount", startingGold, in: app)
        waitForObservedValue("foodCount", "3", in: app)
    }

    @MainActor
    func testArrangement68SimplifiedAtLargestTypeUsesTrayAndStickyConfirmation() throws {
        try assertArrangement68AtLargestType(language: "zh-Hans", locale: "zh_CN")
    }

    @MainActor
    func testArrangement68TraditionalAtLargestTypeUsesTrayAndStickyConfirmation() throws {
        try assertArrangement68AtLargestType(language: "zh-Hant", locale: "zh_TW")
    }

    @MainActor
    func testArrangement68EnglishAtLargestTypeUsesTrayAndStickyConfirmation() throws {
        try assertArrangement68AtLargestType(language: "en", locale: "en_US")
    }

    @MainActor
    private func assertArrangement68AtLargestType(language: String, locale: String) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--skip-onboarding", "--reset-ui-test-save", "--furniture-test",
            "--animation-test", "--reduce-motion-test", "-AppleLanguages", "(\(language))", "-AppleLocale", locale,
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launchAndEnterHome(app)
        let startingGold = try XCTUnwrap(observedHomeValue("goldCount", in: app))
        let original = waitForFurniture(in: app, description: "the largest-type room is ready before editing") { $0.phase == "idle" && !$0.pending }
        let originalCabinet = try XCTUnwrap(original.items.first { $0.id == "cabinet" })
        tapAnimationControl("homeDecorateButton", in: app)
        waitForElement("arrangementHeader68", in: app)
        assertArrangement68AccessibleHeader(in: app)
        XCTAssertFalse(element("quickConfirmFurniture68", in: app).exists)
        scrollPage("arrangementPanelScroll68", to: "layoutPlaced_cabinet", allowDisabled: false, maximumDrags: 16, in: app)
        let trayButton = element("layoutPlaced_cabinet", in: app)
        XCTAssertTrue(trayButton.isHittable)
        XCTAssertGreaterThanOrEqual(trayButton.frame.width, 44)
        XCTAssertGreaterThanOrEqual(trayButton.frame.height, 44)
        attachScreenshot(app, named: "Arrangement 68 — \(language) maximum text real cabinet tray button")
        tapAnimationControl("layoutPlaced_cabinet", in: app)
        _ = waitForFurniture(in: app, description: "the real tray selects the cabinet without a scene-coordinate tap") {
            $0.phase == "editing" && !$0.pending && $0.selected == "cabinet"
        }
        scrollPage("arrangementPanelScroll68", to: "rotateFurnitureRight68", allowDisabled: false, maximumDrags: 16, in: app)
        assertArrangement68AccessibleControl("rotateFurnitureRight68", in: app)
        assertArrangement68AccessibleHeader(in: app)
        tapAnimationControl("rotateFurnitureRight68", in: app)
        let turned = waitForFurniture(in: app, timeout: 30, description: "one real clockwise turn completes at maximum text") {
            !$0.pending && $0.items.first { $0.id == "cabinet" }?.orientation == "right"
        }
        let beforeNudge = try XCTUnwrap(turned.items.first { $0.id == "cabinet" })
        let beforeX = try XCTUnwrap(beforeNudge.worldX), beforeY = try XCTUnwrap(beforeNudge.worldY)
        attachScreenshot(app, named: "Arrangement 68 — \(language) maximum text actual right-facing cabinet")
        scrollPage("arrangementPanelScroll68", to: "nudgeFurniture68_down", allowDisabled: false, maximumDrags: 16, in: app)
        assertArrangement68AccessibleControl("nudgeFurniture68_down", in: app)
        assertArrangement68AccessibleHeader(in: app)
        tapAnimationControl("nudgeFurniture68_down", in: app)
        _ = waitForFurniture(in: app, timeout: 30, description: "the visible down-nudge changes the real draft position") {
            guard !$0.pending, let item = $0.items.first(where: { $0.id == "cabinet" }),
                  let x = item.worldX, let y = item.worldY else { return false }
            return hypot(x - beforeX, y - beforeY) > 0.0005
        }
        let confirm = element("layoutConfirmPlacement68", in: app)
        XCTAssertTrue(confirm.exists && confirm.isEnabled && confirm.isHittable)
        XCTAssertGreaterThanOrEqual(confirm.frame.width, 44)
        XCTAssertGreaterThanOrEqual(confirm.frame.height, 44)
        XCTAssertTrue(app.frame.contains(confirm.frame), "The complete confirmation remains fixed inside the screen while its settings scroll.")
        XCTAssertFalse(element("arrangementPanelScroll68", in: app).frame.intersects(confirm.frame))
        assertArrangement68AccessibleHeader(in: app)
        attachScreenshot(app, named: "Arrangement 68 — \(language) maximum text reachable nudge and fixed confirmation")
        tapAnimationControl("layoutConfirmPlacement68", in: app)
        _ = waitForFurniture(in: app, description: "confirm ends the selection while retaining an unsaved draft") { !$0.pending }
        let ended = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element("layoutConfirmPlacement68", in: app))
        XCTAssertEqual(XCTWaiter.wait(for: [ended], timeout: 12), .completed)
        assertArrangement68AccessibleControl("layoutCancelButton", in: app)
        tapAnimationControl("layoutCancelButton", in: app)
        let canceled = waitForFurniture(in: app, description: "cancel restores the original largest-type room") { $0.phase == "idle" && !$0.pending }
        let restored = try XCTUnwrap(canceled.items.first { $0.id == "cabinet" })
        XCTAssertEqual(restored.orientation, originalCabinet.orientation)
        XCTAssertEqual(try XCTUnwrap(restored.worldX), try XCTUnwrap(originalCabinet.worldX), accuracy: 0.003)
        XCTAssertEqual(try XCTUnwrap(restored.worldY), try XCTUnwrap(originalCabinet.worldY), accuracy: 0.003)
        waitForObservedValue("goldCount", startingGold, in: app)
    }

    @MainActor
    private func assertArrangement68AccessibleControl(_ identifier: String, in app: XCUIApplication) {
        let control = element(identifier, in: app)
        XCTAssertTrue(control.exists && control.isHittable, "The real \(identifier) button must be reachable at maximum text.")
        XCTAssertGreaterThanOrEqual(control.frame.width, 44)
        XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        XCTAssertTrue(app.frame.contains(control.frame))
    }

    @MainActor
    private func assertArrangement68AccessibleHeader(in app: XCUIApplication) {
        let header = element("arrangementHeader68", in: app), done = element("layoutDoneButton", in: app)
        XCTAssertGreaterThanOrEqual(header.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(header.frame.maxX, app.frame.maxX)
        assertArrangement68AccessibleControl("layoutDoneButton", in: app)
        let issue = element("arrangementInvalidReason68", in: app)
        if issue.exists { XCTAssertFalse(issue.frame.intersects(done.frame), "A footprint error must not cover the fixed Done control.") }
    }

    @MainActor
    func testArrangement68InvalidDragBlocksConfirmationUntilUndoAndKeepsSavedLayout() throws {
        continueAfterFailure = false
        let app = launchFurnitureHome()
        let startingGold = try XCTUnwrap(observedHomeValue("goldCount", in: app))
        let original = furnitureState(in: app)
        tapAnimationControl("homeDecorateButton", in: app)
        tapAnimationControl("layoutTrayToggle", in: app)
        waitForObservedValue("layoutTrayToggle", "collapsed", in: app)
        let selected = try selectFurniture("catBed", in: app)
        let bed = try XCTUnwrap(selected.items.first { $0.id == "catBed" })
        let canvas = element("roomScene", in: app)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: bed.x, dy: bed.y - 0.02))
            .press(forDuration: 0.15, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.53)),
                   withVelocity: .slow, thenHoldForDuration: 0)
        _ = waitForFurniture(in: app, description: "the real invalid drag finishes without silently restoring the previous point") {
            $0.phase == "editing" && !$0.pending && $0.selected == "catBed"
        }
        let done = element("layoutDoneButton", in: app)
        let invalid = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in done.exists && !done.isEnabled }, object: done)
        XCTAssertEqual(XCTWaiter.wait(for: [invalid], timeout: 25), .completed,
                       "Releasing outside the floor must leave a red invalid draft, rather than silently moving it back.")
        tapAnimationControl("layoutTrayToggle", in: app)
        waitForObservedValue("layoutTrayToggle", "expanded", in: app)
        waitForElement("layoutConfirmPlacement68", in: app)
        XCTAssertFalse(element("layoutConfirmPlacement68", in: app).isEnabled)
        scrollPage("arrangementPanelScroll68", to: "arrangementInvalidReason68", allowDisabled: true, maximumDrags: 12, in: app)
        attachScreenshot(app, named: "Arrangement 68 — invalid red draft blocks both confirmation controls")
        XCTAssertTrue(element("arrangementUndo68", in: app).isEnabled)
        tapAnimationControl("arrangementUndo68", in: app)
        let restored = waitForFurniture(in: app, description: "undo restores the last safe draft without spending") {
            !$0.pending && $0.items.first { $0.id == "catBed" }?.orientation == "front"
        }
        XCTAssertTrue(element("layoutDoneButton", in: app).isEnabled)
        XCTAssertEqual(restored.items.first { $0.id == "catBed" }?.orientation, bed.orientation)
        tapAnimationControl("layoutCancelButton", in: app)
        _ = waitForFurniture(in: app, description: "cancel discards the invalid placement and its undo history") { $0.phase == "idle" && !$0.pending }
        let reopened = relaunchRestHome(app)
        XCTAssertEqual(Set(reopened.items.map(\.id)), Set(original.items.map(\.id)))
        XCTAssertEqual(reopened.items.first { $0.id == "catBed" }?.orientation, original.items.first { $0.id == "catBed" }?.orientation)
        for item in original.items {
            let same = try XCTUnwrap(reopened.items.first { $0.id == item.id })
            XCTAssertEqual(try XCTUnwrap(same.worldX), try XCTUnwrap(item.worldX), accuracy: 0.003)
            XCTAssertEqual(try XCTUnwrap(same.worldY), try XCTUnwrap(item.worldY), accuracy: 0.003)
        }
        waitForObservedValue("goldCount", startingGold, in: app)
    }

    @MainActor
    func testArrangement68FourWayDraftNudgeUndoAndCancelUseRealControlsWithoutSpending() throws {
        continueAfterFailure = false
        let app = launchFurnitureHome()
        let startingGold = try XCTUnwrap(observedHomeValue("goldCount", in: app))
        let original = furnitureState(in: app)
        tapAnimationControl("homeDecorateButton", in: app)
        waitForElement("arrangementHeader68", in: app)
        waitForElement("arrangementCapacity68", in: app)
        XCTAssertFalse(element("homeNavigationBar", in: app).exists)
        XCTAssertFalse(element("homeCareBar63", in: app).exists)
        XCTAssertFalse(element("arrangementUndo68", in: app).isEnabled)
        XCTAssertTrue(element("arrangementFilter68_floor", in: app).exists)
        XCTAssertFalse(element("quickConfirmFurniture68", in: app).exists, "The unselected tray must not display bowl tools.")
        for id in ["roomViewLeftButton", "roomViewRightButton"] {
            XCTAssertTrue(element(id, in: app).isHittable)
            XCTAssertGreaterThanOrEqual(element(id, in: app).frame.height, 44)
        }
        tapAnimationControl("roomViewLeftButton", in: app)
        _ = waitForFurniture(in: app, description: "arrangement keeps the real left view available above the tray") { !$0.pending && $0.viewAngle == -1 }
        attachScreenshot(app, named: "Arrangement 68 — B1 left view and bag-first tray")
        tapAnimationControl("roomViewRightButton", in: app)
        _ = waitForFurniture(in: app, description: "the arrangement returns to front without changing its draft") { !$0.pending && $0.viewAngle == 0 }
        attachScreenshot(app, named: "Arrangement 68 — B1 real capacity grid and bag-first tray")
        tapAnimationControl("layoutTrayToggle", in: app)
        waitForObservedValue("layoutTrayToggle", "collapsed", in: app)
        _ = try selectFurniture("catBed", in: app)
        tapAnimationControl("flipFurnitureButton", in: app)
        let turned = waitForFurniture(in: app, description: "the bed previews the next physical direction") {
            !$0.pending && $0.selected == "catBed" && $0.items.first { $0.id == "catBed" }?.orientation == "right"
        }
        XCTAssertTrue(element("arrangementUndo68", in: app).isEnabled)
        tapAnimationControl("layoutTrayToggle", in: app)
        waitForObservedValue("layoutTrayToggle", "expanded", in: app)
        scrollPage("arrangementPanelScroll68", to: "nudgeFurniture68_right", allowDisabled: false, maximumDrags: 12, in: app)
        XCTAssertTrue(element("roomViewRightButton", in: app).isHittable)
        tapAnimationControl("roomViewRightButton", in: app)
        _ = waitForFurniture(in: app, description: "selected furniture keeps a reachable right-view capsule") { !$0.pending && $0.viewAngle == 1 }
        attachScreenshot(app, named: "Arrangement 68 — B3 selected furniture from the right")
        tapAnimationControl("roomViewLeftButton", in: app)
        _ = waitForFurniture(in: app, description: "the selected draft returns to front before a screen-right nudge") { !$0.pending && $0.viewAngle == 0 }
        attachScreenshot(app, named: "Arrangement 68 — B3 four-direction editor and true oriented artwork")
        let beforeNudge = try XCTUnwrap(turned.items.first { $0.id == "catBed" })
        let beforeWorldX = try XCTUnwrap(beforeNudge.worldX)
        let beforeWorldY = try XCTUnwrap(beforeNudge.worldY)
        tapAnimationControl("nudgeFurniture68_right", in: app)
        _ = waitForFurniture(in: app, description: "the half-tile screen-right nudge updates the draft") {
            !$0.pending && ($0.items.first { $0.id == "catBed" }?.worldX ?? 0) > beforeWorldX + 0.001
        }
        tapAnimationControl("arrangementUndo68", in: app)
        _ = waitForFurniture(in: app, description: "undo restores the position while preserving the preceding turn") {
            guard let item = $0.items.first(where: { $0.id == "catBed" }) else { return false }
            return !$0.pending && item.orientation == "right" && abs((item.worldX ?? .nan) - beforeWorldX) < 0.003 && abs((item.worldY ?? .nan) - beforeWorldY) < 0.003
        }
        tapAnimationControl("arrangementUndo68", in: app)
        _ = waitForFurniture(in: app, description: "a second undo restores the earlier direction") {
            !$0.pending && $0.items.first { $0.id == "catBed" }?.orientation == "front"
        }
        tapAnimationControl("layoutCancelButton", in: app)
        let canceled = waitForFurniture(in: app, description: "cancel returns to the unchanged saved room") { $0.phase == "idle" && !$0.pending }
        XCTAssertEqual(Set(canceled.items.map(\.id)), Set(original.items.map(\.id)))
        XCTAssertEqual(canceled.items.first { $0.id == "catBed" }?.orientation, "front")
        waitForObservedValue("goldCount", startingGold, in: app)
        XCTAssertTrue(element("homeNavigationBar", in: app).exists)
        XCTAssertTrue(element("homeCareBar63", in: app).exists)
        attachScreenshot(app, named: "Arrangement 68 — canceled preview preserves the saved room")
    }
}
