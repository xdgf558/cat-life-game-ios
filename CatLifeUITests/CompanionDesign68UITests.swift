import XCTest

extension RoomHomeUITests {
    @MainActor
    func testCompanionDesign68RealPlayChoicesRhythmsAndFirstReceiptDoNotSpend() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = arguments(reset: true) + ["--habit-play-need-fixture", "--furniture-test"]
        launchAndEnterHome(app)
        let startingGold = try XCTUnwrap(observedHomeValue("goldCount", in: app))
        waitForObservedValue("toyCount", "3", in: app)
        // Real controls: playButton → playTogetherChoice; the sheet only selects a route.
        tapAnimationControl("playButton", in: app)
        waitForElement("playChoicesSheet68", in: app)
        waitForElement("playChoiceFirstFree", in: app)
        XCTAssertTrue(element("quickPlayChoice", in: app).isEnabled)
        XCTAssertTrue(element("playTogetherChoice", in: app).isEnabled)
        attachScreenshot(app, named: "Companion design 68 — P2 first-free play choice cards")
        scrollPage("playChoicesSheet68", to: "playTogetherChoice", allowDisabled: false, maximumDrags: 12, in: app)
        tapAnimationControl("playTogetherChoice", in: app)
        waitForElement("playTogetherStage", in: app)
        waitForElement("playTogetherTime", in: app)
        let seconds = try XCTUnwrap(Int(element("playTogetherTime", in: app).label.filter(\.isNumber)))
        XCTAssertTrue((1...20).contains(seconds), "The live timer must retain Core's real 20-second session.")
        let speed = element("playTogetherSpeed", in: app)
        XCTAssertTrue(speed.exists)
        XCTAssertEqual(speed.value as? String, "停")
        XCTAssertEqual(speed.label, "玩具的速度")
        XCTAssertGreaterThan(speed.frame.width, 100)
        attachScreenshot(app, named: "Companion design 68 — P3 real cat toy stage and speed ruler")
        XCTAssertTrue(element("playTogetherStep_slowMove", in: app).exists)
        XCTAssertTrue(element("playTogetherStep_moveAndPause", in: app).exists)
        scrollPage("playTogetherScroll", to: "playTogether_slowMove", allowDisabled: false, maximumDrags: 12, in: app)
        tapAnimationControl("playTogether_slowMove", in: app)
        waitForObservedValue("playTogetherTutorialHint", "1", in: app, timeout: 7)
        XCTAssertTrue((element("playTogetherStage", in: app).value as? String)?.contains("|0|0|1") == true,
                      "A saved comparison must not pounce or spend a toy.")
        scrollPage("playTogetherScroll", to: "playTogether_moveAndPause", allowDisabled: false, maximumDrags: 12, in: app)
        tapAnimationControl("playTogether_moveAndPause", in: app)
        waitForElement("playTogetherResult", in: app, timeout: 14)
        waitForObservedValue("playTogetherResult", "cat_001|2|0", in: app)
        waitForObservedValue("habitPlayProgress", "1/2", in: app)
        waitForElement("catMemory_firstResponse", in: app)
        XCTAssertFalse(element("catHabitsSection", in: app).exists)
        XCTAssertFalse(element("catMemory_favoritePlay", in: app).exists,
                       "The free introduction saves one clue, not a confirmed preference.")
        scrollPage("playTogetherScroll", to: "playTogetherResponses", allowDisabled: true, maximumDrags: 12, requiresHitPoint: false, in: app)
        attachScreenshot(app, named: "Companion design 68 — P6 accepted responses and first memory")
        scrollPage("playTogetherScroll", to: "playTogetherToyCost", allowDisabled: true, maximumDrags: 12, requiresHitPoint: false, in: app)
        waitForObservedValue("playTogetherToyCost", "0", in: app)
        waitForObservedValue("playTogetherCatMood", "0", in: app)
        waitForObservedValue("playTogetherPlayerMood", "0", in: app)
        XCTAssertTrue(app.frame.contains(element("playTogetherFinishButton", in: app).frame))
        attachScreenshot(app, named: "Companion design 68 — P6 three actual zero-cost tutorial receipt tiles")
        tapAnimationControl("playTogetherFinishButton", in: app)
        waitForObservedValue("goldCount", startingGold, in: app)
        waitForObservedValue("toyCount", "3", in: app)
        waitForObservedValue("foodCount", "3", in: app)
        tapAnimationControl("tabInventory", in: app)
        waitForObservedValue("inventoryToyUses", "3", in: app)
        waitForObservedValue("inventoryLitterCount", "2", in: app)
        tapAnimationControl("tabHome", in: app)
        _ = waitForFurniture(in: app, description: "home resumes after the free result", matching: { $0.phase == "idle" && !$0.pending })
        tapAnimationControl("playButton", in: app)
        waitForElement("playChoicesSheet68", in: app)
        XCTAssertFalse(element("playChoiceFirstFree", in: app).exists,
                       "The actual completed tutorial must remove the first-free offer.")
        XCTAssertTrue(element("playTogetherChoice", in: app).label.contains("用 1 次玩具"))
        attachScreenshot(app, named: "Companion design 68 — P1 ordinary choice after the one free tutorial")
    }

    @MainActor
    func testCompanionDesign68GuideSaveFailureHasOneVisibleOwnerAndRetryKeepsTheChoice() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = arguments(reset: true) + ["--uitesting-siamese-owned", "--habit-pin-save-failure-once", "--reduce-motion-test"]
        launchAndEnterHome(app)
        let gold = try XCTUnwrap(observedHomeValue("goldCount", in: app))
        tapAnimationControl("tabTown", in: app)
        tapAnimationControl("townCollectionButton", in: app)
        scrollCareerPage("catCollectionScroll", to: "catFilter_owned", in: app)
        tapAnimationControl("catFilter_owned", in: app)
        scrollCareerPage("catCollectionScroll", to: "catProfile_cat_004", in: app)
        tapAnimationControl("catProfile_cat_004", in: app)
        scrollCareerPage("catProfileScroll", to: "habitGuideMenu", in: app)
        tapAnimationControl("habitGuideMenu", in: app)
        scrollPage("habitGuidePicker", to: "habitPin_settledAfterMove", allowDisabled: false, maximumDrags: 12, in: app)
        tapAnimationControl("habitPin_settledAfterMove", in: app)
        tapAnimationControl("habitPinConfirm", in: app)
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 6))
        XCTAssertEqual(app.alerts.count, 1)
        attachScreenshot(app, named: "Companion design 68 - guide save failure on the visible child sheet")
        let retry = alert.buttons.matching(NSPredicate(format: "label == %@", "重试保存")).firstMatch
        XCTAssertTrue(retry.isHittable)
        retry.tap()
        waitForElement("habitGuidePicker", in: app)
        scrollPage("habitGuidePicker", to: "habitPinConfirm", allowDisabled: false, maximumDrags: 12, in: app)
        tapAnimationControl("habitPinConfirm", in: app)
        waitForObservedValue("habitPinnedGuide", "settledAfterMove|expanded", in: app)
        tapAnimationControl("closeSheetButton", in: app)
        tapAnimationControl("tabHome", in: app)
        waitForObservedValue("goldCount", gold, in: app)
    }

    @MainActor
    func testCompanionDesign68MemoryGridHidesUnknownTitlesAndGuideWaitsForConfirmation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = arguments(reset: true) + ["--uitesting-siamese-owned", "--furniture-test", "--reduce-motion-test"]
        launchAndEnterHome(app)
        let startingGold = try XCTUnwrap(observedHomeValue("goldCount", in: app))
        // The collection route directly opens the real cat profile, without a growth-page detour.
        tapAnimationControl("tabTown", in: app)
        tapAnimationControl("townCollectionButton", in: app)
        scrollCareerPage("catCollectionScroll", to: "catFilter_owned", in: app)
        tapAnimationControl("catFilter_owned", in: app)
        scrollCareerPage("catCollectionScroll", to: "catProfile_cat_004", in: app)
        tapAnimationControl("catProfile_cat_004", in: app)
        waitForObservedValue("catProfileScroll", "cat_004", in: app)
        scrollPage("catProfileScroll", to: "habitPlayProgress", allowDisabled: true, maximumDrags: 16, requiresHitPoint: false, in: app)
        waitForObservedValue("habitRestProgress", "0/2", in: app)
        waitForObservedValue("habitPlayProgress", "0/2", in: app)
        attachScreenshot(app, named: "Companion design 68 — M1 genuine unknown habits and two clue dots")
        for kind in ["firstResponse", "favoriteRest", "favoritePlay", "littleCorner", "settledAfterMove", "understandEachOther"] {
            let identifier = "habitMemoryEmpty_" + kind
            scrollPage("catProfileScroll", to: identifier, allowDisabled: true, maximumDrags: 16, requiresHitPoint: false, in: app)
            XCTAssertEqual(element(identifier, in: app).label, "还没有留下",
                           "An unearned memory must expose neither its title nor its unlock condition.")
            XCTAssertFalse(element("catMemory_" + kind, in: app).exists)
        }
        attachScreenshot(app, named: "Companion design 68 — M1 six anonymous unearned memory slots")
        scrollPage("catProfileScroll", to: "habitGuideMenu", allowDisabled: false, maximumDrags: 16, in: app)
        tapAnimationControl("habitGuideMenu", in: app)
        waitForElement("habitGuidePicker", in: app)
        XCTAssertFalse(element("habitPinConfirm", in: app).isEnabled)
        tapAnimationControl("habitPin_favoritePlay", in: app)
        XCTAssertTrue(element("habitPin_favoritePlay", in: app).isSelected)
        XCTAssertFalse(element("habitPinnedGuide", in: app).exists, "Selecting alone must not publish a pinned guide.")
        scrollPage("habitGuidePicker", to: "habitPin_littleCorner", allowDisabled: false, maximumDrags: 16, in: app)
        tapAnimationControl("habitPin_littleCorner", in: app)
        XCTAssertTrue(element("habitPin_littleCorner", in: app).isSelected)
        XCTAssertFalse(element("habitPin_favoritePlay", in: app).isSelected,
                       "The picker must keep only one pending selection.")
        attachScreenshot(app, named: "Companion design 68 — M3 one selected guide before durable confirmation")
        tapAnimationControl("habitPinConfirm", in: app)
        waitForObservedValue("habitPinnedGuide", "littleCorner|expanded", in: app)
        XCTAssertFalse(element("catMemory_littleCorner", in: app).exists)
        tapAnimationControl("habitGuideMenu", in: app)
        tapAnimationControl("habitUnpin", in: app)
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element("habitPinnedGuide", in: app))
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 8), .completed)
        tapAnimationControl("closeSheetButton", in: app)
        tapAnimationControl("tabHome", in: app)
        waitForObservedValue("goldCount", startingGold, in: app)
        waitForObservedValue("foodCount", "3", in: app)
        tapAnimationControl("tabInventory", in: app)
        waitForObservedValue("inventoryFoodCount", "3", in: app)
        waitForObservedValue("inventoryLitterCount", "2", in: app)
        waitForObservedValue("inventoryToyUses", "6", in: app)
    }

    @MainActor
    func testCompanionDesign68ShopInspirationAndLearningNeighborDialogue() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = arguments(reset: true) + ["--community-fixture", "--reduce-motion-test"]
        launchAndEnterHome(app)
        tapAnimationControl("tabShop", in: app)
        tapAnimationControl("shopCategory_furniture", in: app)
        scrollPage("destinationScroll", to: "shopItem_cozy_cushion", allowDisabled: false, maximumDrags: 12, in: app)
        tapAnimationControl("shopItem_cozy_cushion", in: app)
        waitForElement("shopDetailName", in: app)
        scrollPage("shopDetailScroll", to: "shopHabitGoal", allowDisabled: true, maximumDrags: 12,
                   requiresHitPoint: false, in: app)
        waitForLabel("shopHabitGoal", "陪伴的小灵感", in: app, contains: true)
        let inspiration = element("shopHabitGoal", in: app)
        XCTAssertTrue(inspiration.label.contains("不用为了回忆额外购买"))
        XCTAssertTrue(inspiration.label.contains("已有的猫窝或地垫"))
        XCTAssertTrue(app.frame.contains(inspiration.frame), "The real product's inspiration must be readable in the captured viewport.")
        attachScreenshot(app, named: "Companion design 68 — M4 real resting furniture inspiration without extra purchase")

        tapAnimationControl("shopDetailBackButton", in: app)
        tapAnimationControl("tabTown", in: app)
        scrollCareerPage("townMapScroll", to: "townPlot_street", in: app)
        tapAnimationControl("townPlot_street", in: app)
        scrollCareerPage("townMapScroll", to: "townEnter_street", in: app)
        tapAnimationControl("townEnter_street", in: app)
        waitForElement("communityDirectory", in: app)
        scrollCareerPage("communityDirectory", to: "neighborCard_neighbor_mira", in: app)
        tapAnimationControl("neighborCard_neighbor_mira", in: app)
        scrollPage("neighborDetail_neighbor_mira", to: "neighborDialogue", allowDisabled: true, maximumDrags: 12,
                   requiresHitPoint: false, in: app)
        waitForLabel("neighborDialogue", "慢慢了解", in: app, contains: true)
        let dialogue = element("neighborDialogue", in: app)
        XCTAssertTrue(dialogue.label.contains("不急着猜答案"))
        for hiddenPreference in ["喜欢圆圆的猫窝", "喜欢柔软的地垫", "喜欢玩具慢慢移动", "喜欢玩具移动后停一停"] {
            XCTAssertFalse(dialogue.label.contains(hiddenPreference), "A neighbor must not reveal an unconfirmed habit.")
        }
        XCTAssertTrue(app.frame.contains(dialogue.frame), "The actual learning dialogue must be readable in the captured viewport.")
        attachScreenshot(app, named: "Companion design 68 — M5 real neighbor dialogue keeps unknown preferences private")
    }
}
