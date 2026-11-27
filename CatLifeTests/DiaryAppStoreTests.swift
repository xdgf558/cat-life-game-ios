import XCTest
import CatGameCore
@testable import CatLife

@MainActor
final class DiaryAppStoreTests: XCTestCase {
    private func makeTempStore(adOutcome: AdPlayResult = .ended) -> (DiaryAppStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repo = DiarySaveRepository(directory: dir)
        let ad = MockRewardedAdService(immediateOutcome: adOutcome)
        let store = DiaryAppStore(repository: repo, adService: ad)
        return (store, dir)
    }

    func testBootstrapAndCompleteTutorialUpdatesStoreAndDiary() async {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        await store.bootstrap()
        XCTAssertTrue(store.isLoaded)
        XCTAssertEqual(store.state.tutorialStep, .meet)

        store.petCat()
        XCTAssertEqual(store.state.tutorialStep, .gather)

        store.switchScreen(to: .workshop)
        for _ in 0..<4 { store.tapGenerator(.cloth) }
        XCTAssertEqual(store.state.tutorialStep, .merge)

        XCTAssertEqual(store.moveItem(from: 0, to: 1), .merged(MergeItem(chain: .cloth, level: 2)))
        XCTAssertEqual(store.moveItem(from: 2, to: 3), .merged(MergeItem(chain: .cloth, level: 2)))
        XCTAssertEqual(store.moveItem(from: 1, to: 3), .merged(MergeItem(chain: .cloth, level: 3)))
        XCTAssertEqual(store.state.tutorialStep, .bringHome)

        store.bringHome(cellIndex: 3)
        XCTAssertEqual(store.activeScreen, .home)
        XCTAssertEqual(store.state.tutorialStep, .play)

        store.playWithToy(at: 0)
        XCTAssertEqual(store.currentPhotoModalID, DiaryCatalog.tutorialPhotoID)

        store.dismissCurrentPhotoModal()
        XCTAssertEqual(store.state.tutorialStep, .done)
        XCTAssertNotNil(store.state.home.wish)
    }

    func testTrilingualStringsCoverAllKeysAnd36Photos() {
        let zhKeys = Set(GameStrings.chinese.keys)
        let zhtKeys = Set(GameStrings.traditionalChinese.keys)
        let enKeys = Set(GameStrings.english.keys)
        XCTAssertEqual(zhKeys, zhtKeys, "Traditional Chinese keys must match Simplified Chinese")
        XCTAssertEqual(zhKeys, enKeys, "English keys must match Simplified Chinese")

        for photo in DiaryCatalog.photos {
            XCTAssertNotNil(GameStrings.chinese["photo.\(photo.id).title"], photo.id)
            XCTAssertNotNil(GameStrings.chinese["photo.\(photo.id).caption"], photo.id)
        }
    }

    func testAppReleaseIncludesBuild70AndPreservesHistoricalBuild69() {
        XCTAssertEqual(AppVersion.current.version, "2.0.0")
        XCTAssertEqual(AppVersion.current.buildNumber, 70)
        let builds = AppRelease.recent.map(\.build)
        XCTAssertTrue(builds.contains(70))
        XCTAssertTrue(builds.contains(69))
    }

    func testRelaunchAtTutorialFinishRequeuesTutorialPhotoModal() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = DiarySaveRepository(directory: dir)
        let now = Date(timeIntervalSince1970: 1_760_000_000)

        var saved = DiaryGameState.fresh(now: DayClock.epochMs(now))
        saved.addPhoto(DiaryCatalog.tutorialPhotoID, now: DayClock.epochMs(now))
        XCTAssertEqual(saved.tutorialStep, .finish)
        try await repo.save(saved, now: now)

        let store = DiaryAppStore(repository: repo, adService: MockRewardedAdService(), clock: { now })
        await store.bootstrap()

        XCTAssertEqual(store.state.tutorialStep, .finish)
        XCTAssertEqual(store.currentPhotoModalID, DiaryCatalog.tutorialPhotoID)

        store.dismissCurrentPhotoModal()
        XCTAssertEqual(store.state.tutorialStep, .done)
        XCTAssertFalse(store.state.tutorialActive)
        XCTAssertNotNil(store.state.home.wish)
    }

    func testSaveFailureSurfacesErrorAndAutomaticRetryPersistsLatestState() async throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        var initial = DiaryGameState.fresh(now: DayClock.epochMs(now))
        initial.tutorialActive = false
        initial.board.cells[0] = MergeItem(chain: .cloth, level: 3)
        initial.board.cells[1] = MergeItem(chain: .cloth, level: 3)

        let repo = FlakySaveRepository(initialState: initial)
        let store = DiaryAppStore(
            repository: repo,
            adService: MockRewardedAdService(),
            clock: { now },
            saveRetryDelays: [.milliseconds(25), .milliseconds(40), .milliseconds(60)]
        )
        await store.bootstrap()
        try await waitUntil { !store.isSaving }

        // Fail the next write; sell item 0 -> saveError must become visible.
        await repo.setFailuresRemaining(1)
        store.sellItem(at: 0)
        let coinsAfterFirstSale = store.state.coins
        try await waitUntil { store.saveError != nil && !store.isSaving }
        XCTAssertNotNil(store.saveError)

        // Mutate again before automatic retry fires -> retry must write the LATEST coins!
        store.sellItem(at: 1)
        let expectedLatestCoins = store.state.coins
        XCTAssertGreaterThan(expectedLatestCoins, coinsAfterFirstSale)

        try await waitUntil { store.saveError == nil && !store.isSaving }
        let lastSaved = await repo.lastSavedState
        XCTAssertEqual(lastSaved?.coins, expectedLatestCoins)

        // Exhaust all automatic retries -> manual retrySaveNow() recovers and clears saveError.
        await repo.setFailuresRemaining(10)
        store.toggleWishlist(.windowCushion)
        try await waitUntil(timeoutMs: 1200) {
            let attempts = await repo.failedAttemptsSinceReset
            return attempts >= SaveRetryState.maximumAutomaticAttempts + 1 && !store.isSaving
        }
        XCTAssertNotNil(store.saveError)

        await repo.setFailuresRemaining(0)
        store.retrySaveNow()
        try await waitUntil { store.saveError == nil && !store.isSaving }
        let manualSaved = await repo.lastSavedState
        XCTAssertEqual(manualSaved?.home.wishlist, .windowCushion)
    }

    func testMidnightRolloverOnHomeRefreshesWishWithoutConsumingToy() async throws {
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        var comps = DateComponents()
        comps.calendar = utcCal
        comps.timeZone = utcCal.timeZone
        comps.year = 2026
        comps.month = 11
        comps.day = 26
        comps.hour = 23
        comps.minute = 59
        comps.second = 50
        let beforeMidnight = try XCTUnwrap(comps.date)
        let afterMidnight = beforeMidnight.addingTimeInterval(20) // 2026-11-27 00:00:10 UTC

        let clock = MutableTestClock(beforeMidnight)
        let ball = MergeItem(chain: .cloth, level: 3)
        var initial = DiaryGameState.fresh(now: DayClock.epochMs(beforeMidnight), calendar: utcCal)
        initial.tutorialActive = false
        initial.primaryCat.satiety = 80
        initial.home.toys = [OwnedToy(item: ball, usesLeft: 3)]
        initial.home.wish = DailyWish(dayKey: 20261126, goal: .play(ball), completed: false)

        let repo = FlakySaveRepository(initialState: initial)
        let store = DiaryAppStore(
            repository: repo,
            adService: MockRewardedAdService(),
            clock: { clock.now },
            calendar: utcCal
        )
        await store.bootstrap()
        XCTAssertEqual(store.state.dayKey, 20261126)
        XCTAssertEqual(store.state.home.wish?.goal, .play(ball))

        // Stay on Home past midnight; tap toy targeting yesterday's wish before periodic poll.
        clock.now = afterMidnight
        store.playWithToy(at: 0)

        XCTAssertEqual(store.state.dayKey, 20261127)
        XCTAssertEqual(store.state.home.wish?.dayKey, 20261127)
        XCTAssertNotEqual(store.state.home.wish?.goal, .play(ball))
        XCTAssertEqual(store.state.home.toys.first?.usesLeft, 3, "Toy durability must not be consumed on midnight wish rollover")
        XCTAssertEqual(store.notices.toast, GameStrings.text("wish.refreshedAtMidnight"))

        // Tapping again after seeing the refreshed wish plays normally.
        store.playWithToy(at: 0)
        XCTAssertEqual(store.state.home.toys.first?.usesLeft, 2)
    }

    func testMidnightPetOnCooldownSyncsDayAndGuardsYesterdayWishToy() async throws {
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        var comps = DateComponents()
        comps.calendar = utcCal
        comps.timeZone = utcCal.timeZone
        comps.year = 2026
        comps.month = 11
        comps.day = 26
        comps.hour = 23
        comps.minute = 59
        comps.second = 10
        let beforeMidnight = try XCTUnwrap(comps.date)
        let afterMidnight = beforeMidnight.addingTimeInterval(60) // 2026-11-27 00:00:10 UTC (within 5m pet cooldown)

        let clock = MutableTestClock(beforeMidnight)
        let ball = MergeItem(chain: .cloth, level: 3)
        var initial = DiaryGameState.fresh(now: DayClock.epochMs(beforeMidnight), calendar: utcCal)
        initial.tutorialActive = false
        initial.primaryCat.satiety = 80
        initial.home.toys = [OwnedToy(item: ball, usesLeft: 3)]
        initial.home.wish = DailyWish(dayKey: 20261126, goal: .play(ball), completed: false)

        let repo = FlakySaveRepository(initialState: initial)
        let store = DiaryAppStore(
            repository: repo,
            adService: MockRewardedAdService(),
            clock: { clock.now },
            calendar: utcCal
        )
        await store.bootstrap()

        // 23:59:10 -> pet cat (starts 5-minute cooldown)
        store.petCat()
        XCTAssertNotNil(store.state.primaryCat.lastPetAt)

        // 00:00:10 -> pet cat again while still on cooldown: day rollover MUST sync to Home immediately!
        clock.now = afterMidnight
        store.petCat()
        XCTAssertEqual(store.state.dayKey, 20261127)
        XCTAssertEqual(store.state.home.wish?.dayKey, 20261127)
        XCTAssertNotEqual(store.state.home.wish?.goal, .play(ball))

        // Tapping yesterday's wish toy right after must still protect durability instead of wasting a charge.
        store.playWithToy(at: 0)
        XCTAssertEqual(store.state.home.toys.first?.usesLeft, 3)
        XCTAssertEqual(store.notices.toast, GameStrings.text("wish.refreshedAtMidnight"))

        // Second tap plays normally.
        store.playWithToy(at: 0)
        XCTAssertEqual(store.state.home.toys.first?.usesLeft, 2)
        try await waitUntil { !store.isSaving }
    }

    func testOrderDeliveryWaitsForSuccessfulSaveBeforeCreditingCoinsOrShowingBonus() async throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let wand = MergeItem(chain: .cloth, level: 4)
        let order = CustomerOrder(id: "o1", customer: .ajian, items: [wand], wage: 20)

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(now))
        initial.tutorialActive = false
        initial.coins = 110 // 10 short of window_cushion (120)
        initial.orders.completedTotal = 2 // eligible for wage ad bonus
        initial.orders.active = [order]
        initial.orders.nextID = 2
        initial.board.cells[0] = wand

        let repo = FlakySaveRepository(initialState: initial)
        let store = DiaryAppStore(
            repository: repo,
            adService: MockRewardedAdService(),
            clock: { now },
            saveRetryDelays: [.milliseconds(250), .milliseconds(300), .milliseconds(400)]
        )
        await store.bootstrap()
        try await waitUntil { !store.isSaving }
        store.notices.dismiss()

        // Force disk save failures when delivering order "o1".
        await repo.setFailuresRemaining(10)
        store.deliverOrder("o1")
        try await waitUntil { store.saveError != nil && !store.isSaving }

        // While write has failed: coins, toast, and double-wage ad MUST NOT be credited/shown,
        // and the player must NOT be able to spend the unpersisted 20 coins in the shop!
        XCTAssertEqual(store.state.coins, 110)
        XCTAssertNil(store.notices.toast)
        XCTAssertNil(store.activeAdOffer)
        XCTAssertEqual(store.state.orders.active.first?.id, "o1")
        XCTAssertEqual(store.state.board.cells[0], wand)

        store.buyFurniture(.windowCushion)
        XCTAssertFalse(store.state.home.furnitureOwned.contains(.windowCushion))
        XCTAssertEqual(store.state.coins, 110)
        store.notices.dismiss()

        // Once disk recovers and retry runs, order commits, coins credit, toast & double-wage ad appear!
        await repo.setFailuresRemaining(0)
        store.retrySaveNow()
        try await waitUntil { store.saveError == nil && !store.isSaving && store.state.coins == 130 }

        XCTAssertEqual(store.state.coins, 130)
        XCTAssertEqual(store.notices.toast, GameStrings.format("order.deliveredCoins", 20))
        if case .wage(let bonus) = store.activeAdOffer {
            XCTAssertEqual(bonus.amount, 20)
            XCTAssertEqual(bonus.orderID, "o1")
        } else {
            XCTFail("Expected double-wage ad offer after order delivery is persisted")
        }
        let persisted = await repo.lastSavedState
        XCTAssertEqual(persisted?.coins, 130)
        XCTAssertNil(persisted?.board.cells[0])

        // Now the persisted coins can be spent cleanly.
        store.buyFurniture(.windowCushion)
        XCTAssertTrue(store.state.home.furnitureOwned.contains(.windowCushion))
        XCTAssertEqual(store.state.coins, 10)
        try await waitUntil { !store.isSaving }
    }

    func testReservedOrderItemCannotBeBroughtHomeSoldOrMergedDuringSave() async throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let ball = MergeItem(chain: .cloth, level: 3)
        let order = CustomerOrder(id: "o1", customer: .ajian, items: [ball], wage: 10)

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(now))
        initial.tutorialActive = false
        initial.orders.active = [order]
        initial.orders.nextID = 2
        initial.board.cells[0] = ball

        let repo = FlakySaveRepository(initialState: initial)
        let store = DiaryAppStore(
            repository: repo,
            adService: MockRewardedAdService(),
            clock: { now }
        )
        await store.bootstrap()
        try await waitUntil { !store.isSaving }
        store.notices.dismiss()

        // Pause disk writes mid-flight so we can tap Bring Home / Sell / Merge during order delivery.
        await repo.setSavePaused(true)
        store.deliverOrder("o1")
        try await waitUntil { await repo.inFlightSaves == 1 }

        XCTAssertTrue(store.isOrderDeliveryPending("o1"))
        XCTAssertTrue(store.isCellReserved(0))

        // Attempting to bring home, sell, or move cell 0 while reserved must be rejected cleanly.
        store.bringHome(cellIndex: 0)
        store.sellItem(at: 0)
        XCTAssertEqual(store.moveItem(from: 0, to: 1), .invalid)
        XCTAssertTrue(store.state.home.toys.isEmpty)
        XCTAssertNil(store.notices.toast)

        // Release disk write -> order settles once with +10 coins and cell 0 consumed cleanly.
        await repo.setSavePaused(false)
        try await waitUntil { !store.isSaving && store.pendingOrderDeliveries.isEmpty }

        XCTAssertEqual(store.state.coins, 10)
        XCTAssertNil(store.state.board.cells[0])
        XCTAssertTrue(store.state.home.toys.isEmpty)
        let persisted = await repo.lastSavedState
        XCTAssertEqual(persisted?.coins, 10)
        XCTAssertNil(persisted?.board.cells[0])
        XCTAssertEqual(persisted?.home.toys.isEmpty, true)
    }

    func testBackToBackOrderDeliveriesQueueWithoutDroppingSecondClick() async throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let ball = MergeItem(chain: .cloth, level: 3)
        let wand = MergeItem(chain: .cloth, level: 4)
        let order1 = CustomerOrder(id: "o1", customer: .ajian, items: [ball], wage: 10)
        let order2 = CustomerOrder(id: "o2", customer: .grandma, items: [wand], wage: 20)
        // Order 3 competes for the same single `ball` on cell 0 -> must not steal order 1's item!
        let order3 = CustomerOrder(id: "o3", customer: .petshop, items: [ball], wage: 10)

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(now))
        initial.tutorialActive = false
        initial.orders.active = [order1, order2, order3]
        initial.orders.nextID = 4
        initial.board.cells[0] = ball
        initial.board.cells[1] = wand

        let repo = FlakySaveRepository(initialState: initial)
        let store = DiaryAppStore(
            repository: repo,
            adService: MockRewardedAdService(),
            clock: { now }
        )
        await store.bootstrap()
        try await waitUntil { !store.isSaving }

        await repo.setSavePaused(true)
        store.deliverOrder("o1")
        try await waitUntil { await repo.inFlightSaves == 1 }

        // Click second non-overlapping order while first order is saving -> must queue!
        store.deliverOrder("o2")
        // Click third order that requires the same single `ball` -> must be rejected!
        store.deliverOrder("o3")

        XCTAssertTrue(store.isOrderDeliveryPending("o1"))
        XCTAssertTrue(store.isOrderDeliveryPending("o2"))
        XCTAssertFalse(store.isOrderDeliveryPending("o3"))

        await repo.setSavePaused(false)
        try await waitUntil { !store.isSaving && store.pendingOrderDeliveries.isEmpty }

        XCTAssertEqual(store.state.coins, 30)
        XCTAssertNil(store.state.board.cells[0])
        XCTAssertNil(store.state.board.cells[1])
        XCTAssertTrue(store.state.orders.active.contains(where: { $0.id == "o3" }))
        let persisted = await repo.lastSavedState
        XCTAssertEqual(persisted?.coins, 30)
    }

    func testDoubleWageBonusWaitsForSuccessfulSaveBeforeUpdatingBalanceOrToast() async throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let wand = MergeItem(chain: .cloth, level: 4)
        let order = CustomerOrder(id: "o1", customer: .ajian, items: [wand], wage: 20)

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(now))
        initial.tutorialActive = false
        initial.coins = 110
        initial.orders.completedTotal = 2
        initial.orders.active = [order]
        initial.orders.nextID = 2
        initial.board.cells[0] = wand

        let repo = FlakySaveRepository(initialState: initial)
        let adService = MockRewardedAdService()
        let store = DiaryAppStore(
            repository: repo,
            adService: adService,
            clock: { now },
            saveRetryDelays: [.milliseconds(250), .milliseconds(300), .milliseconds(400)]
        )
        await store.bootstrap()
        try await waitUntil { !store.isSaving }

        // Deliver base order -> balance becomes 130 and double-wage ad offer appears.
        store.deliverOrder("o1")
        try await waitUntil { !store.isSaving && store.state.coins == 130 }
        XCTAssertNotNil(store.activeAdOffer)

        // Start watching the ad and wait for pending ledger entry to save cleanly.
        store.watchActiveAd()
        try await waitUntil { store.playingMockAdSlot == .wage && !store.isSaving }
        store.notices.dismiss()

        // Fail disk writes when the ad finishes -> bonus coins & toast MUST NOT appear prematurely!
        await repo.setFailuresRemaining(10)
        store.finishMockAdPlayback(with: .ended)
        try await waitUntil { store.saveError != nil && !store.isSaving }

        XCTAssertEqual(store.state.coins, 130)
        XCTAssertNil(store.notices.toast)
        XCTAssertEqual(store.state.ads.ledger.last?.status, .pending)

        // Restore disk and retry -> coins + granted ledger record persist together, then balance & toast update!
        await repo.setFailuresRemaining(0)
        store.retrySaveNow()
        try await waitUntil { store.saveError == nil && !store.isSaving && store.state.coins == 150 }

        XCTAssertEqual(store.state.coins, 150)
        XCTAssertEqual(store.notices.toast, GameStrings.format("ad.rewardCoins", 20))
        XCTAssertEqual(store.state.ads.ledger.last?.status, .granted)
        let persisted = await repo.lastSavedState
        XCTAssertEqual(persisted?.coins, 150)
        XCTAssertEqual(persisted?.ads.ledger.last?.status, .granted)
    }

    func testMaterialAdExcludesBoardCellsReservedByPendingOrderDelivery() async throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let ball = MergeItem(chain: .cloth, level: 3) // 4 units
        let wand = MergeItem(chain: .cloth, level: 4) // 8 units
        let order1 = CustomerOrder(id: "o1", customer: .ajian, items: [ball], wage: 10)
        let order2 = CustomerOrder(id: "o2", customer: .grandma, items: [wand], wage: 20)
        // Populate all 3 active order slots so `bootstrap()` never rolls a random order with smaller gap.
        let order3 = CustomerOrder(id: "o3", customer: .ajian, items: [wand, wand], wage: 40)

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(now))
        initial.tutorialActive = false
        initial.orders.completedTotal = 2
        initial.energy.current = 0
        initial.energy.updatedAt = DayClock.epochMs(now)
        initial.orders.active = [order1, order2, order3]
        initial.orders.nextID = 4
        initial.board.cells[0] = ball

        let repo = FlakySaveRepository(initialState: initial)
        let store = DiaryAppStore(
            repository: repo,
            adService: MockRewardedAdService(),
            clock: { now }
        )
        await store.bootstrap()
        try await waitUntil { !store.isSaving }

        // Reserve cell 0 (`ball`) for o1 while o1's save is in flight.
        await repo.setSavePaused(true)
        store.deliverOrder("o1")
        try await waitUntil { await repo.inFlightSaves == 1 }
        XCTAssertTrue(store.isCellReserved(0))

        // Tapping cloth generator with 0 energy must offer all 8 cloth_1 units for o2 (`wand`),
        // NOT 4 units by mistakenly counting o1's reserved `ball`!
        store.tapGenerator(.cloth)
        if case .material(let offer) = store.activeAdOffer {
            XCTAssertEqual(offer.orderID, "o2")
            XCTAssertEqual(offer.target, wand)
            XCTAssertEqual(offer.count, 8)
        } else {
            XCTFail("Expected material ad offer for o2 with full 8-unit gap")
        }

        await repo.setSavePaused(false)
        try await waitUntil { !store.isSaving && store.pendingOrderDeliveries.isEmpty }
    }

    func testOrderDeliveryWithConcurrentMutationKeepsIdenticalReplacementOrder() async throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let ball = MergeItem(chain: .cloth, level: 3)

        for iteration in 0..<5 {
            let order = CustomerOrder(id: "o1", customer: .ajian, items: [ball], wage: 10)
            var initial = DiaryGameState.fresh(now: DayClock.epochMs(now))
            initial.tutorialActive = false
            initial.primaryCat.level = 4 // unlock all chains & customers for wide RNG space
            initial.orders.active = [order]
            initial.orders.nextID = 2
            initial.board.cells[0] = ball

            let repo = FlakySaveRepository(initialState: initial)
            let store = DiaryAppStore(
                repository: repo,
                adService: MockRewardedAdService(),
                clock: { now }
            )
            await store.bootstrap()
            try await waitUntil { !store.isSaving }
            await repo.clearSavedHistory()

            // Start delivering o1 and mutate unrelated state (`wishlist`) while o1's write is in flight.
            await repo.setSavePaused(true)
            store.deliverOrder("o1")
            try await waitUntil { await repo.inFlightSaves == 1 }

            store.toggleWishlist(.windowCushion)
            await repo.setSavePaused(false)
            try await waitUntil { !store.isSaving && store.pendingOrderDeliveries.isEmpty }

            let history = await repo.savedHistory
            XCTAssertGreaterThanOrEqual(history.count, 2, "Iteration \(iteration) expected initial delivery save + follow-up state save")
            let firstSavedOrders = history[0].orders.active
            let finalSavedOrders = history[history.count - 1].orders.active
            XCTAssertEqual(
                firstSavedOrders,
                finalSavedOrders,
                "Single order delivery must not generate two different replacement orders across concurrent saves"
            )
            XCTAssertEqual(store.state.orders.active, finalSavedOrders)
            XCTAssertEqual(store.state.home.wishlist, .windowCushion)
        }
    }

    func testDisablingMockAdsDuringPendingSaveIsNotOverwrittenOnCommit() async throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let wand = MergeItem(chain: .cloth, level: 4)
        let order = CustomerOrder(id: "o1", customer: .ajian, items: [wand], wage: 20)
        let order2 = CustomerOrder(id: "o2", customer: .grandma, items: [wand], wage: 20)

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(now))
        initial.tutorialActive = false
        initial.orders.completedTotal = 2
        initial.energy.current = 0
        initial.energy.updatedAt = DayClock.epochMs(now)
        initial.orders.active = [order, order2]
        initial.orders.nextID = 3
        initial.board.cells[0] = wand

        let repo = FlakySaveRepository(initialState: initial)
        let store = DiaryAppStore(
            repository: repo,
            adService: MockRewardedAdService(),
            clock: { now }
        )
        await store.bootstrap()
        try await waitUntil { !store.isSaving }

        await repo.setSavePaused(true)
        store.deliverOrder("o1")
        try await waitUntil { await repo.inFlightSaves == 1 }

        // User turns off mock ads in Settings while o1's save is in flight.
        store.mockAdsEnabled = false

        await repo.setSavePaused(false)
        try await waitUntil { !store.isSaving && store.pendingOrderDeliveries.isEmpty }

        XCTAssertFalse(store.mockAdsEnabled)
        XCTAssertNil(store.activeAdOffer, "Wage ad offer must not appear after user disabled mock ads")

        // Subsequent zero-energy generator tap must ALSO respect mockAdsEnabled == false!
        store.tapGenerator(.cloth)
        XCTAssertNil(store.activeAdOffer, "Engine adConfig.adEnabled must remain false after commit")
    }

    func testOrderCardStatusShowsRetryInsteadOfSavingAfterRetriesExhaust() async throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let ball = MergeItem(chain: .cloth, level: 3)
        let order = CustomerOrder(id: "o1", customer: .ajian, items: [ball], wage: 10)

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(now))
        initial.tutorialActive = false
        initial.orders.active = [order]
        initial.orders.nextID = 2
        initial.board.cells[0] = ball

        let repo = FlakySaveRepository(initialState: initial)
        let store = DiaryAppStore(
            repository: repo,
            adService: MockRewardedAdService(),
            clock: { now },
            saveRetryDelays: [.milliseconds(20), .milliseconds(30), .milliseconds(40)]
        )
        await store.bootstrap()
        try await waitUntil { !store.isSaving }

        await repo.setFailuresRemaining(10)
        await repo.setSavePaused(true)
        store.deliverOrder("o1")
        try await waitUntil { await repo.inFlightSaves == 1 }

        // While actively writing, status is `.saving`.
        XCTAssertEqual(store.orderCardStatus(for: order), .saving)

        // Unpause and let all automatic retries exhaust -> status must switch to `.retrySave`
        // and banner copy must prompt manual retry instead of promising further automatic retries!
        await repo.setSavePaused(false)
        try await waitUntil(timeoutMs: 1200) {
            let attempts = await repo.failedAttemptsSinceReset
            return attempts >= SaveRetryState.maximumAutomaticAttempts + 1 && !store.isSaving
        }
        XCTAssertEqual(store.orderCardStatus(for: order), .retrySave)
        XCTAssertEqual(store.saveError, GameStrings.text("save.writeFailedManual"))

        // Manual retry succeeds and completes delivery.
        await repo.setFailuresRemaining(0)
        store.retrySaveNow()
        try await waitUntil { store.saveError == nil && !store.isSaving && store.pendingOrderDeliveries.isEmpty }
        XCTAssertEqual(store.state.coins, 10)
    }

    func testConcurrentActionDuringOrderDeliveryDoesNotRollBackSettlementTimestamps() async throws {
        let t0 = Date(timeIntervalSince1970: 1_760_000_000)
        let t1 = t0.addingTimeInterval(60) // +60s when player taps generator mid-save
        let t2 = t0.addingTimeInterval(90) // +90s when order save finishes
        let clock = MutableTestClock(t0)

        let wand = MergeItem(chain: .cloth, level: 4)
        let order = CustomerOrder(id: "o1", customer: .ajian, items: [wand], wage: 20)

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(t0))
        initial.tutorialActive = false
        initial.orders.completedTotal = 2
        initial.orders.active = [order]
        initial.orders.nextID = 2
        initial.board.cells[0] = wand

        let repo = FlakySaveRepository(initialState: initial)
        let store = DiaryAppStore(
            repository: repo,
            adService: MockRewardedAdService(),
            clock: { clock.now }
        )
        await store.bootstrap()
        try await waitUntil { !store.isSaving }

        // Start delivering o1 at t0 (`saveNowMs == t0`).
        await repo.setSavePaused(true)
        store.deliverOrder("o1")
        try await waitUntil { await repo.inFlightSaves == 1 }

        // At t1 (+60s), player taps generator while o1's save is still in flight:
        // energy spends 30 -> 29 and `energy.updatedAt` advances to `t1`.
        clock.now = t1
        store.tapGenerator(.cloth)
        XCTAssertEqual(store.state.energy.current, 29)
        XCTAssertEqual(store.state.energy.updatedAt, DayClock.epochMs(t1))

        // At t2 (+90s), o1's save finishes and commits onto the live engine:
        // settlement timestamps MUST NOT roll backward to `t0`!
        clock.now = t2
        await repo.setSavePaused(false)
        try await waitUntil { !store.isSaving && store.pendingOrderDeliveries.isEmpty }

        XCTAssertEqual(store.state.energy.current, 29)
        XCTAssertEqual(store.state.energy.updatedAt, DayClock.epochMs(t1))
        XCTAssertEqual(store.state.updatedAt, DayClock.epochMs(t2))
        XCTAssertEqual(store.state.primaryCat.updatedAt, DayClock.epochMs(t2))
        XCTAssertEqual(store.state.ads.lastOfferAt, DayClock.epochMs(t2))
    }

    func testWageAdCooldownIsMeasuredFromActualDisplayAndDismissalTime() async throws {
        let t0 = Date(timeIntervalSince1970: 1_760_000_000)
        let t1 = t0.addingTimeInterval(89) // o1 slow save finishes at +89s -> Wage Ad #1 appears at +89s
        let t2 = t0.addingTimeInterval(90) // o2 delivered 1s later at +90s -> must NOT pop Wage Ad #2!
        let clock = MutableTestClock(t0)

        let wand = MergeItem(chain: .cloth, level: 4)
        let order1 = CustomerOrder(id: "o1", customer: .ajian, items: [wand], wage: 20)
        let order2 = CustomerOrder(id: "o2", customer: .grandma, items: [wand], wage: 20)
        let order3 = CustomerOrder(id: "o3", customer: .ajian, items: [wand, wand], wage: 40)

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(t0))
        initial.tutorialActive = false
        initial.orders.completedTotal = 2
        initial.orders.active = [order1, order2, order3]
        initial.orders.nextID = 4
        initial.board.cells[0] = wand
        initial.board.cells[1] = wand

        let repo = FlakySaveRepository(initialState: initial)
        let store = DiaryAppStore(
            repository: repo,
            adService: MockRewardedAdService(),
            clock: { clock.now }
        )
        await store.bootstrap()
        try await waitUntil { !store.isSaving }

        // Start delivering o1 at t0; save completes 89s later at t1 with NO concurrent board mutation.
        await repo.setSavePaused(true)
        store.deliverOrder("o1")
        try await waitUntil { await repo.inFlightSaves == 1 }

        clock.now = t1
        await repo.setSavePaused(false)
        try await waitUntil { !store.isSaving && store.pendingOrderDeliveries.isEmpty }

        XCTAssertNotNil(store.activeAdOffer, "Wage Ad #1 appears at t1 (+89s)")
        XCTAssertEqual(store.state.ads.lastOfferAt, DayClock.epochMs(t1))

        // Dismiss Wage Ad #1 at t1 and deliver o2 just 1 second later at t2 (+90s):
        // Wage Ad #2 must be suppressed by the 90s cooldown!
        store.refuseActiveAd()
        try await waitUntil { !store.isSaving }

        clock.now = t2
        store.deliverOrder("o2")
        try await waitUntil { !store.isSaving && store.pendingOrderDeliveries.isEmpty }

        XCTAssertEqual(store.state.coins, 40)
        XCTAssertNil(store.activeAdOffer, "Second wage ad must not pop up 1 second after the first")
    }

    func testAdCompletedBeforeMidnightCommittedAfterMidnightKeepsNextDayQuota() async throws {
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        var comps = DateComponents()
        comps.calendar = utcCal
        comps.timeZone = utcCal.timeZone
        comps.year = 2026
        comps.month = 11
        comps.day = 26
        comps.hour = 23
        comps.minute = 59
        comps.second = 45
        let tStart = try XCTUnwrap(comps.date)
        let tEndBeforeMidnight = tStart.addingTimeInterval(10) // 23:59:55 UTC (Day 1)
        let tAfterMidnight = tStart.addingTimeInterval(20)     // 00:00:05 UTC (Day 2)
        let clock = MutableTestClock(tStart)

        let wand = MergeItem(chain: .cloth, level: 4)
        let order1 = CustomerOrder(id: "o1", customer: .ajian, items: [wand], wage: 20)
        let order2 = CustomerOrder(id: "o2", customer: .grandma, items: [wand], wage: 20)
        let order3 = CustomerOrder(id: "o3", customer: .ajian, items: [wand, wand], wage: 40)

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(tStart), calendar: utcCal)
        initial.tutorialActive = false
        initial.coins = 110
        initial.orders.completedTotal = 2
        initial.orders.active = [order1, order2, order3]
        initial.orders.nextID = 4
        initial.board.cells[0] = wand

        let repo = FlakySaveRepository(initialState: initial)
        let store = DiaryAppStore(
            repository: repo,
            adService: MockRewardedAdService(),
            clock: { clock.now },
            calendar: utcCal
        )
        await store.bootstrap()
        try await waitUntil { !store.isSaving }

        store.deliverOrder("o1")
        try await waitUntil { !store.isSaving && store.state.coins == 130 }
        store.watchActiveAd()
        try await waitUntil { store.playingMockAdSlot == .wage && !store.isSaving }

        // Finish watching the ad BEFORE midnight (23:59:55), pause its save, then cross midnight
        // with a concurrent action so `commitSavedAdCompletion` commits on Day 2 (00:00:05).
        clock.now = tEndBeforeMidnight
        await repo.setSavePaused(true)
        store.finishMockAdPlayback(with: .ended)
        try await waitUntil { await repo.inFlightSaves == 1 }

        clock.now = tAfterMidnight
        store.toggleWishlist(.windowCushion)
        await repo.setSavePaused(false)
        try await waitUntil { !store.isSaving }

        XCTAssertEqual(store.state.coins, 150)
        XCTAssertEqual(store.state.dayKey, 20_261_127)
        XCTAssertEqual(store.state.ads.used[.wage], 0, "Yesterday's ad must not deduct today's quota")
        XCTAssertEqual(DiaryAds.remainingForSlot(store.state, slot: .wage, config: .default), 2)
    }

    func testRelaunchImmediatelyAfterSeeingWageOfferEnforcesCooldown() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }

        let t0 = Date(timeIntervalSince1970: 1_760_000_000)
        let tReopen = t0.addingTimeInterval(5) // force-quit & reopen 5 seconds later

        let wand = MergeItem(chain: .cloth, level: 4)
        let order1 = CustomerOrder(id: "o1", customer: .ajian, items: [wand], wage: 20)
        let order2 = CustomerOrder(id: "o2", customer: .grandma, items: [wand], wage: 20)
        let order3 = CustomerOrder(id: "o3", customer: .ajian, items: [wand, wand], wage: 40)

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(t0))
        initial.tutorialActive = false
        initial.orders.completedTotal = 2
        initial.orders.active = [order1, order2, order3]
        initial.orders.nextID = 4
        initial.board.cells[0] = wand
        initial.board.cells[1] = wand

        let repo1 = DiarySaveRepository(directory: dir)
        try await repo1.save(initial, now: t0)

        let store1 = DiaryAppStore(
            repository: repo1,
            adService: MockRewardedAdService(),
            clock: { t0 }
        )
        await store1.bootstrap()
        try await waitUntil { !store1.isSaving }

        // Deliver o1 and wait ONLY until the wage offer appears (simulate immediate kill before any follow-up save).
        store1.deliverOrder("o1")
        try await waitUntil { store1.activeAdOffer != nil }

        // Relaunch 5 seconds later from disk and deliver o2 -> must NOT pop a second wage offer!
        let repo2 = DiarySaveRepository(directory: dir)
        let store2 = DiaryAppStore(
            repository: repo2,
            adService: MockRewardedAdService(),
            clock: { tReopen }
        )
        await store2.bootstrap()
        try await waitUntil { !store2.isSaving }

        XCTAssertEqual(store2.state.ads.lastOfferAt, DayClock.epochMs(t0))

        store2.deliverOrder("o2")
        try await waitUntil { !store2.isSaving && store2.pendingOrderDeliveries.isEmpty }

        XCTAssertEqual(store2.state.coins, 40)
        XCTAssertNil(store2.activeAdOffer, "Relaunching 5s after seeing wage offer must still honor cooldown")
    }

    func testCrossMidnightOrderWithoutConcurrentActionGetsNextDayWageOffer() async throws {
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        var comps = DateComponents()
        comps.calendar = utcCal
        comps.timeZone = utcCal.timeZone
        comps.year = 2026
        comps.month = 11
        comps.day = 26
        comps.hour = 23
        comps.minute = 59
        comps.second = 55
        let beforeMidnight = try XCTUnwrap(comps.date)
        let afterMidnight = beforeMidnight.addingTimeInterval(7) // 2026-11-27 00:00:02 UTC
        let clock = MutableTestClock(beforeMidnight)

        let wand = MergeItem(chain: .cloth, level: 4)
        let order1 = CustomerOrder(id: "o1", customer: .ajian, items: [wand], wage: 20)
        let order2 = CustomerOrder(id: "o2", customer: .grandma, items: [wand], wage: 20)
        let order3 = CustomerOrder(id: "o3", customer: .ajian, items: [wand, wand], wage: 40)

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(beforeMidnight), calendar: utcCal)
        initial.tutorialActive = false
        initial.orders.completedTotal = 2
        // Day 1 wage quota is completely exhausted & disabled by refusals!
        initial.ads.used[.wage] = 2
        initial.ads.disabledToday = [.wage]
        initial.orders.active = [order1, order2, order3]
        initial.orders.nextID = 4
        initial.board.cells[0] = wand

        let repo = FlakySaveRepository(initialState: initial)
        let store = DiaryAppStore(
            repository: repo,
            adService: MockRewardedAdService(),
            clock: { clock.now },
            calendar: utcCal
        )
        await store.bootstrap()
        try await waitUntil { !store.isSaving }

        // Start delivering o1 at 23:59:55 (Day 1), cross midnight to 00:00:02 (Day 2) with NO concurrent action.
        await repo.setSavePaused(true)
        store.deliverOrder("o1")
        try await waitUntil { await repo.inFlightSaves == 1 }

        clock.now = afterMidnight
        await repo.setSavePaused(false)
        try await waitUntil { !store.isSaving && store.pendingOrderDeliveries.isEmpty }

        XCTAssertEqual(store.state.dayKey, 20_261_127)
        XCTAssertEqual(store.state.coins, 20)
        if case .wage(let bonus) = store.activeAdOffer {
            XCTAssertEqual(bonus.orderID, "o1")
            XCTAssertEqual(bonus.amount, 20)
        } else {
            XCTFail("Cross-midnight order must roll to Day 2 quota and present wage bonus offer")
        }
    }

    func testBackgroundOrderSaveDoesNotMarkWageOfferSeenOnDiskOrShowModal() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }

        let t0 = Date(timeIntervalSince1970: 1_760_000_000)
        let wand = MergeItem(chain: .cloth, level: 4)
        let order1 = CustomerOrder(id: "o1", customer: .ajian, items: [wand], wage: 20)
        let order2 = CustomerOrder(id: "o2", customer: .grandma, items: [wand], wage: 20)
        let order3 = CustomerOrder(id: "o3", customer: .ajian, items: [wand, wand], wage: 40)

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(t0))
        initial.tutorialActive = false
        initial.orders.completedTotal = 2
        initial.orders.active = [order1, order2, order3]
        initial.orders.nextID = 4
        initial.board.cells[0] = wand
        initial.board.cells[1] = wand

        let diskRepo = DiarySaveRepository(directory: dir)
        try await diskRepo.save(initial, now: t0)
        let gateRepo = GatedDiskSaveRepository(backing: diskRepo)

        let store = DiaryAppStore(
            repository: gateRepo,
            adService: MockRewardedAdService(),
            clock: { t0 }
        )
        await store.bootstrap()
        try await waitUntil { !store.isSaving }
        store.switchScreen(to: .workshop)
        try await waitUntil { !store.isSaving }

        // Sub-case A: App goes to background BEFORE wage offer save runs.
        await gateRepo.setPaused(true)
        store.deliverOrder("o1")
        try await waitUntil { await gateRepo.inFlightSaves == 1 }
        store.setForeground(false)
        await gateRepo.setPaused(false)
        try await waitUntil { !store.isSaving && store.pendingOrderDeliveries.isEmpty }

        XCTAssertEqual(store.state.coins, 20)
        XCTAssertNil(store.activeAdOffer, "Background order completion must not show wage ad")
        XCTAssertNil(store.state.ads.lastOfferAt)
        let diskAfterA = try await DiarySaveRepository(directory: dir).loadOrCreate(now: t0)
        XCTAssertNil(diskAfterA.ads.lastOfferAt, "Disk must not record lastOfferAt when app was backgrounded")

        // Sub-case B: App goes to background DURING the wage offer save itself -> rollback disk cooldown!
        store.setForeground(true)
        await gateRepo.pauseOnSaveNumber(2) // let o2 delivery (save #1) pass, pause offerShown (save #2)
        store.deliverOrder("o2")
        try await waitUntil { await gateRepo.inFlightSaves == 1 }
        store.setForeground(false)
        await gateRepo.setPaused(false)
        try await waitUntil { !store.isSaving && store.pendingOrderDeliveries.isEmpty }

        XCTAssertEqual(store.state.coins, 40)
        XCTAssertNil(store.activeAdOffer)
        XCTAssertNil(store.state.ads.lastOfferAt)
        let diskAfterB = try await DiarySaveRepository(directory: dir).loadOrCreate(now: t0)
        XCTAssertNil(diskAfterB.ads.lastOfferAt, "Disk must roll back unshown wage offer cooldown when backgrounded mid-save")
    }

    func testRefusingMaterialAdDuringWageOfferSaveBlocksWagePopupAt250ms() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }

        let t0 = Date(timeIntervalSince1970: 1_760_000_000)
        let clock = MutableTestClock(t0)

        let ball = MergeItem(chain: .cloth, level: 3)
        let wand = MergeItem(chain: .cloth, level: 4)
        let order1 = CustomerOrder(id: "o1", customer: .ajian, items: [wand], wage: 20)
        let order2 = CustomerOrder(id: "o2", customer: .grandma, items: [ball], wage: 10)
        let order3 = CustomerOrder(id: "o3", customer: .ajian, items: [wand, wand], wage: 40)

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(t0))
        initial.tutorialActive = false
        initial.orders.completedTotal = 2
        initial.energy.current = 0
        initial.energy.updatedAt = DayClock.epochMs(t0)
        initial.orders.active = [order1, order2, order3]
        initial.orders.nextID = 4
        initial.board.cells[0] = wand

        let diskRepo = DiarySaveRepository(directory: dir)
        try await diskRepo.save(initial, now: t0)
        let gateRepo = GatedDiskSaveRepository(backing: diskRepo)

        let store = DiaryAppStore(
            repository: gateRepo,
            adService: MockRewardedAdService(),
            clock: { clock.now }
        )
        await store.bootstrap()
        try await waitUntil { !store.isSaving }

        // Let o1 delivery save (#1) complete, pause wage offer cooldown save (#2) at t0.
        await gateRepo.pauseOnSaveNumber(2)
        store.deliverOrder("o1")
        try await waitUntil { await gateRepo.inFlightSaves == 1 && store.state.coins == 20 }

        // At +100ms player triggers Material Ad; at +200ms player refuses Material Ad (`activeAdOffer` becomes nil!).
        clock.now = t0.addingTimeInterval(0.10)
        store.tapGenerator(.cloth)
        if case .material = store.activeAdOffer {
            // expected
        } else {
            XCTFail("Expected material ad to appear while wage offer save is in flight")
        }

        clock.now = t0.addingTimeInterval(0.20)
        store.refuseActiveAd()
        XCTAssertNil(store.activeAdOffer)

        // At +250ms wage offer save returns -> MUST re-check live cooldown and NOT pop Wage Ad!
        clock.now = t0.addingTimeInterval(0.25)
        await gateRepo.setPaused(false)
        try await waitUntil { !store.isSaving && store.pendingOrderDeliveries.isEmpty }

        XCTAssertNil(store.activeAdOffer, "Wage ad must not pop 250ms after refusing material ad")
        XCTAssertEqual(store.state.ads.lastOfferAt, DayClock.epochMs(t0.addingTimeInterval(0.20)))
        let disk = try await DiarySaveRepository(directory: dir).loadOrCreate(now: clock.now)
        XCTAssertEqual(disk.ads.refusals[.material], 1)
        XCTAssertEqual(disk.ads.lastOfferAt, DayClock.epochMs(t0.addingTimeInterval(0.20)))
    }

    func testTwoConsecutiveSlowWageOfferSavesDoNotLeaveStaleCooldownOnDisk() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }

        let t0 = Date(timeIntervalSince1970: 1_760_000_000)
        let clock = MutableTestClock(t0)

        let wand = MergeItem(chain: .cloth, level: 4)
        let order1 = CustomerOrder(id: "o1", customer: .ajian, items: [wand], wage: 20)
        let order2 = CustomerOrder(id: "o2", customer: .grandma, items: [wand], wage: 20)
        let order3 = CustomerOrder(id: "o3", customer: .ajian, items: [wand, wand], wage: 40)

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(t0))
        initial.tutorialActive = false
        initial.orders.completedTotal = 2
        initial.orders.active = [order1, order2, order3]
        initial.orders.nextID = 4
        initial.board.cells[0] = wand

        let diskRepo = DiarySaveRepository(directory: dir)
        try await diskRepo.save(initial, now: t0)
        let slowRepo = GatedDiskSaveRepository(backing: diskRepo)

        let store = DiaryAppStore(
            repository: slowRepo,
            adService: MockRewardedAdService(),
            clock: { clock.now }
        )
        await store.bootstrap()
        try await waitUntil { !store.isSaving }

        // Make BOTH wage-offer persistence saves (#2 and #3) advance the clock by 1.5s (>= 1s threshold).
        await slowRepo.setClockAdvanceOnSaves([2: 1.5, 3: 1.5], clock: clock)
        store.deliverOrder("o1")
        try await waitUntil { !store.isSaving && store.pendingOrderDeliveries.isEmpty }

        XCTAssertEqual(store.state.coins, 20)
        XCTAssertNil(store.activeAdOffer, "Two consecutive >=1s slow offer saves should abort showing modal")
        XCTAssertNil(store.state.ads.lastOfferAt)

        // Reloading from disk must NOT contain a phantom cooldown from the aborted offer saves!
        let disk = try await DiarySaveRepository(directory: dir).loadOrCreate(now: clock.now)
        XCTAssertNil(disk.ads.lastOfferAt, "Aborted slow wage offer saves must roll back disk cooldown")
    }

    private func waitUntil(timeoutMs: Int = 1000, condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .milliseconds(timeoutMs)
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for async condition")
    }
}

private enum MockSaveFailure: Error {
    case diskFull
}

private actor FlakySaveRepository: GameSaveRepository {
    var lastLoadDisposition: SaveLoadDisposition = .loaded
    private var state: DiaryGameState
    private(set) var lastSavedState: DiaryGameState?
    private(set) var savedHistory: [DiaryGameState] = []
    private var failuresRemaining = 0
    private(set) var failedAttemptsSinceReset = 0
    private var savePaused = false
    private(set) var inFlightSaves = 0
    private var resumeContinuations: [CheckedContinuation<Void, Never>] = []

    init(initialState: DiaryGameState) {
        self.state = initialState
    }

    func clearSavedHistory() {
        savedHistory.removeAll()
    }

    func setFailuresRemaining(_ count: Int) {
        failuresRemaining = count
        failedAttemptsSinceReset = 0
    }

    func setSavePaused(_ paused: Bool) {
        savePaused = paused
        if !paused {
            let waiting = resumeContinuations
            resumeContinuations.removeAll()
            for continuation in waiting {
                continuation.resume()
            }
        }
    }

    func loadOrCreate(now: Date) async throws -> DiaryGameState {
        state
    }

    func save(_ state: DiaryGameState, now: Date) async throws {
        inFlightSaves += 1
        defer { inFlightSaves -= 1 }
        if savePaused {
            await withCheckedContinuation { continuation in
                resumeContinuations.append(continuation)
            }
        }
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            failedAttemptsSinceReset += 1
            throw MockSaveFailure.diskFull
        }
        self.state = state
        self.lastSavedState = state
        self.savedHistory.append(state)
    }
}

private final class MutableTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ initial: Date) {
        self.value = initial
    }

    var now: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }
}

private actor GatedDiskSaveRepository: GameSaveRepository {
    private let backing: DiarySaveRepository
    private var paused = false
    private var pauseOnSaveIndex: Int?
    private var saveCount = 0
    private(set) var inFlightSaves = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var advanceBySaveIndex: [Int: TimeInterval] = [:]
    private var clock: MutableTestClock?

    init(backing: DiarySaveRepository) {
        self.backing = backing
    }

    var lastLoadDisposition: SaveLoadDisposition {
        get async { await backing.lastLoadDisposition }
    }

    func setPaused(_ value: Bool) {
        paused = value
        pauseOnSaveIndex = nil
        if !value {
            let waiting = continuations
            continuations.removeAll()
            for c in waiting { c.resume() }
        }
    }

    func pauseOnSaveNumber(_ index: Int) {
        saveCount = 0
        paused = false
        pauseOnSaveIndex = index
    }

    func setClockAdvanceOnSaves(_ map: [Int: TimeInterval], clock: MutableTestClock) {
        saveCount = 0
        advanceBySaveIndex = map
        self.clock = clock
    }

    func loadOrCreate(now: Date) async throws -> DiaryGameState {
        try await backing.loadOrCreate(now: now)
    }

    func save(_ state: DiaryGameState, now: Date) async throws {
        saveCount += 1
        let currentIndex = saveCount
        inFlightSaves += 1
        defer { inFlightSaves -= 1 }

        if paused || pauseOnSaveIndex == currentIndex {
            pauseOnSaveIndex = nil
            await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }
        try await backing.save(state, now: now)
        if let delta = advanceBySaveIndex[currentIndex], let clock {
            clock.now = clock.now.addingTimeInterval(delta)
        }
    }
}
