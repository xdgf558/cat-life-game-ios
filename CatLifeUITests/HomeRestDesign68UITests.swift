import XCTest

extension RoomHomeUITests {
    @MainActor
    func testHomeRestDesign68LargestTypeFurnitureConfirmationScrollsAndWakeInterruptsWithoutSpending() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = arguments(reset: true) + [
            "--rest-test", "--animation-test", "--reduce-motion-test",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        launchAndEnterHome(app)
        let before = waitForFurniture(in: app, description: "the maximum-type room is ready for a real furniture tap",
                                     matching: { $0.phase == "idle" && !$0.pending && $0.restPhase == "none" })
        let bed = try XCTUnwrap(before.items.first { $0.id == "catBed" })
        try restFurnitureCoordinate(bed, in: app).tap()
        waitForElement("homeRestAsk", in: app)
        XCTAssertNil(furnitureState(in: app).restFurniture, "Opening the invitation must not start a rest.")
        let invitationScroll = app.scrollViews.containing(.any, identifier: "homeRestAsk").firstMatch
        XCTAssertTrue(invitationScroll.exists, "Long confirmation copy must remain inside a real scroll view.")
        let confirm = element("homeRestAskConfirm", in: app)
        revealRestDesign68Control(confirm, in: invitationScroll, app: app)
        attachScreenshot(app, named: "Companion design 68 — C3 SE largest text real furniture confirmation scrolled to action")
        confirm.tap()

        // Use the production 12-second bed rest. Do not spend that interval on
        // additional profile navigation before delivering the real wake input.
        let resting = waitForFurniture(in: app, timeout: 60, description: "the cat settles and the actual rest is saved",
                                      matching: { $0.phase == "resting" && $0.restFurniture == "catBed"
                                          && $0.restPhase == "resting" && $0.savedRestSession?.isEmpty == false })
        waitForElement("homeRestStatus", in: app, timeout: 3)
        let wake = element("homeRestWake", in: app)
        XCTAssertTrue(wake.waitForExistence(timeout: 3), "An overflowing largest-type card must retain an explicit wake button.")
        XCTAssertTrue(wake.isEnabled && wake.isHittable)
        let statusScroll = app.scrollViews.containing(.any, identifier: "homeRestStatus").firstMatch
        let statusExists = statusScroll.exists
        let statusViewport = statusScroll.frame
        let wakeFrame = wake.frame
        let stage = element("roomStage63", in: app).frame
        let controls = element("roomViewControls", in: app).frame
        attachScreenshot(app, named: "Companion design 68 — C4 SE largest text bounded rest card and reachable wake")
        wake.tap()

        XCTAssertTrue(statusExists)
        XCTAssertGreaterThan(statusViewport.height, 0)
        XCTAssertTrue(stage.contains(statusViewport))
        XCTAssertTrue(stage.contains(wakeFrame))
        let occupied = statusViewport.union(wakeFrame)
        XCTAssertLessThan(occupied.height, stage.height * 0.6,
                          "The readable rest card must leave a substantial real canvas touch region.")
        XCTAssertGreaterThan(occupied.minY - stage.minY, stage.height * 0.3,
                             "A tiny stage must still retain uncovered space above the bottom card.")
        XCTAssertFalse(occupied.intersects(controls), "Rest copy and the wake action must not swallow camera controls.")
        let awake = waitForFurniture(in: app, timeout: 30, description: "the explicit wake safely exits and saves the interruption",
                                    matching: { $0.phase == "idle" && $0.restFurniture == nil && $0.restPhase == "none"
                                        && $0.savedRestSession == nil
                                        && $0.restExits == (resting.restExits ?? -1) + 1 })
        XCTAssertEqual(resting.completedRests, (before.completedRests ?? -1) + 1, "The furniture invitation must settle the cat exactly once.")
        XCTAssertEqual(awake.completedRests, resting.completedRests, "Waking must not start another visual rest.")
        XCTAssertEqual(awake.lastRestEndReason, "interaction")
        XCTAssertFalse(element("habitCornerOffer", in: app).exists, "Interrupted observation must not offer a corner.")
        assertRestSuppliesUnchanged(in: app)
        // Inspect the same committed cat through the collection, without an
        // unrelated growth-page round trip on the largest text setting.
        tapAnimationControl("tabTown", in: app)
        tapAnimationControl("townCollectionButton", in: app)
        scrollCareerPage("catCollectionScroll", to: "catFilter_owned", in: app)
        tapAnimationControl("catFilter_owned", in: app)
        scrollCareerPage("catCollectionScroll", to: "catProfile_cat_001", in: app)
        tapAnimationControl("catProfile_cat_001", in: app)
        scrollCareerPage("catProfileScroll", to: "habitRestProgress", in: app)
        waitForObservedValue("habitRestProgress", "0/2", in: app)
        scrollCareerPage("catProfileScroll", to: "habitCornerEmpty", in: app)
        XCTAssertTrue(element("habitCornerEmpty", in: app).exists)
        XCTAssertFalse(element("catMemory_littleCorner", in: app).exists)
        attachScreenshot(app, named: "Companion design 68 — C4 largest text interruption leaves no rest clue or corner memory")
    }

    @MainActor
    private func revealRestDesign68Control(_ control: XCUIElement, in scroll: XCUIElement, app: XCUIApplication,
                                          file: StaticString = #filePath, line: UInt = #line) {
        for attempt in 0...8 {
            let viewport = scroll.frame.intersection(app.frame)
            if control.exists, control.isEnabled, control.isHittable, viewport.contains(control.frame) { return }
            guard attempt < 8, viewport.width > 40, viewport.height > 40 else { break }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.minY + viewport.height * 0.8))
            let end = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.minY + viewport.height * 0.25))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        let evidence = XCTAttachment(string: app.debugDescription)
        evidence.name = "Largest-type real rest confirmation could not reveal its action"
        evidence.lifetime = .keepAlways
        add(evidence)
        XCTFail("The real furniture invitation must expose its confirmation by scrolling.", file: file, line: line)
    }
}
