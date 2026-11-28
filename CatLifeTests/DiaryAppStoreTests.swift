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

    func testTrilingualStringsCoverAllKeysAndM2Catalog() {
        let zhKeys = Set(GameStrings.chinese.keys)
        let zhtKeys = Set(GameStrings.traditionalChinese.keys)
        let enKeys = Set(GameStrings.english.keys)
        XCTAssertEqual(zhKeys, zhtKeys, "Traditional Chinese keys must match Simplified Chinese")
        XCTAssertEqual(zhKeys, enKeys, "English keys must match Simplified Chinese")

        XCTAssertEqual(DiaryCatalog.allPhotoIDs.count, 90)
        for photoID in DiaryCatalog.allPhotoIDs {
            XCTAssertNotNil(GameStrings.chinese["photo.\(photoID).title"], photoID)
            XCTAssertNotNil(GameStrings.chinese["photo.\(photoID).caption"], photoID)
        }
        for album in DiaryCatalog.albumPhotos {
            XCTAssertNotNil(GameStrings.chinese["album.hint.\(album.id)"], album.id)
        }
        for furniture in DiaryCatalog.furniture {
            XCTAssertNotNil(GameStrings.chinese["furn.\(furniture.id.rawValue)"], furniture.id.rawValue)
        }
        for skin in DiaryCatalog.roomSkins {
            XCTAssertNotNil(GameStrings.chinese["skin.\(skin.id.rawValue)"], skin.id.rawValue)
        }
        for treasure in DiaryCatalog.treasures {
            XCTAssertNotNil(GameStrings.chinese["treasure.\(treasure.id.rawValue).name"], treasure.id.rawValue)
            XCTAssertNotNil(GameStrings.chinese["treasure.\(treasure.id.rawValue).first"], treasure.id.rawValue)
            XCTAssertNotNil(GameStrings.chinese["treasure.\(treasure.id.rawValue).repeat"], treasure.id.rawValue)
        }
        for spot in OutingSpot.allCases {
            XCTAssertNotNil(GameStrings.chinese["outing.spot.\(spot.rawValue)"], spot.rawValue)
        }
        for customer in CustomerID.allCases {
            XCTAssertNotNil(GameStrings.chinese["weekend.line.\(customer.rawValue)"], customer.rawValue)
            for idx in 1...4 {
                let storyKey = String(format: "story.%@.%02d", customer.rawValue, idx)
                XCTAssertNotNil(GameStrings.chinese[storyKey], storyKey)
            }
            for idx in 1...3 {
                let noteKey = String(format: "neighborNote.%@.%02d", customer.rawValue, idx)
                XCTAssertNotNil(GameStrings.chinese[noteKey], noteKey)
            }
        }
        for milestone in MilestoneID.allCases {
            XCTAssertNotNil(GameStrings.chinese["milestone.\(milestone.rawValue).title"], milestone.rawValue)
            XCTAssertNotNil(GameStrings.chinese["milestone.\(milestone.rawValue).body"], milestone.rawValue)
        }
    }

    func testAppReleaseIncludesBuild71AndPreservesHistoricalBuilds() {
        XCTAssertEqual(AppVersion.current.version, "2.1.0")
        XCTAssertEqual(AppVersion.current.buildNumber, 71)
        let builds = AppRelease.recent.map(\.build)
        XCTAssertTrue(builds.contains(71))
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
        try await bootstrapReady(store)
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
        try await bootstrapReady(store)

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
        try await bootstrapReady(store)

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
        try await bootstrapReady(store)

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
        try await bootstrapReady(store)

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
        try await bootstrapReady(store)

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
        try await bootstrapReady(store)

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
        try await bootstrapReady(store1)

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
        try await bootstrapReady(store2)

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
        try await bootstrapReady(store)

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
        try await bootstrapReady(store)
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
        try await bootstrapReady(store)

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
        try await bootstrapReady(store)

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

    func testAutoRetryWhileDiarySheetCoversScreenSkipsHiddenWageOffer() async throws {
        // Repro case 1: Order o1 fails initial save, player opens Diary, automatic retry succeeds at +2s.
        // Player quits without closing Diary and relaunches at +10s -> o2 must still get its wage offer.
        // Repro case 2: Player closes Diary at +95s (must NOT reveal a stale +2s offer), relaunches,
        // delivers o2 at +100s (freshly stamped at +100s), relaunches and delivers o3 at +105s -> blocked.
        let t0 = Date(timeIntervalSince1970: 1_760_000_000)
        let wand = MergeItem(chain: .cloth, level: 4)
        let order1 = CustomerOrder(id: "o1", customer: .ajian, items: [wand], wage: 20)
        let order2 = CustomerOrder(id: "o2", customer: .grandma, items: [wand], wage: 20)
        let order3 = CustomerOrder(id: "o3", customer: .ajian, items: [wand], wage: 20)

        func makeInitialState() -> DiaryGameState {
            var initial = DiaryGameState.fresh(now: DayClock.epochMs(t0))
            initial.tutorialActive = false
            initial.orders.completedTotal = 2
            initial.orders.active = [order1, order2, order3]
            initial.orders.nextID = 4
            initial.board.cells[0] = wand
            initial.board.cells[1] = wand
            initial.board.cells[2] = wand
            return initial
        }

        // Case 1: Quit while Diary is still open, relaunch at +10s.
        do {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: dir) }

            let clock = MutableTestClock(t0)
            let diskRepo = DiarySaveRepository(directory: dir)
            try await diskRepo.save(makeInitialState(), now: t0)
            let gateRepo = GatedDiskSaveRepository(backing: diskRepo)

            let store1 = DiaryAppStore(
                repository: gateRepo,
                adService: MockRewardedAdService(),
                clock: { clock.now },
                saveRetryDelays: [.milliseconds(40)]
            )
            try await bootstrapReady(store1)

            await gateRepo.setFailuresRemaining(1)
            store1.deliverOrder("o1")
            try await waitUntil { store1.saveError != nil && !store1.isSaving }
            XCTAssertEqual(store1.state.coins, 0)

            // Player opens Diary before automatic retry succeeds at +2s.
            store1.activeSheet = .diary
            clock.now = t0.addingTimeInterval(2)
            try await waitUntil { store1.pendingOrderDeliveries.isEmpty && !store1.isSaving }

            XCTAssertEqual(store1.state.coins, 20)
            XCTAssertNil(store1.activeAdOffer, "Auto-retry while Diary sheet covers screen must not queue hidden offer")
            XCTAssertNil(store1.state.ads.lastOfferAt)
            let diskAt2 = try await DiarySaveRepository(directory: dir).loadOrCreate(now: clock.now)
            XCTAssertNil(diskAt2.ads.lastOfferAt, "Disk must not record lastOfferAt for an offer covered by Diary")

            // Quit without closing Diary; relaunch at +10s and deliver o2 -> must receive wage offer!
            clock.now = t0.addingTimeInterval(10)
            let store2 = DiaryAppStore(
                repository: DiarySaveRepository(directory: dir),
                adService: MockRewardedAdService(),
                clock: { clock.now }
            )
            try await bootstrapReady(store2)
            store2.deliverOrder("o2")
            try await waitUntil { !store2.isSaving && store2.pendingOrderDeliveries.isEmpty }

            XCTAssertEqual(store2.state.coins, 40)
            if case .wage(let bonus) = store2.activeAdOffer {
                XCTAssertEqual(bonus.orderID, "o2")
            } else {
                XCTFail("Second order at +10s must receive wage offer because first offer was never shown")
            }
        }

        // Case 2: Close Diary at +95s (no stale offer), relaunch, deliver o2 at +100s, relaunch & deliver o3 at +105s (blocked).
        do {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: dir) }

            let clock = MutableTestClock(t0)
            let diskRepo = DiarySaveRepository(directory: dir)
            try await diskRepo.save(makeInitialState(), now: t0)
            let gateRepo = GatedDiskSaveRepository(backing: diskRepo)

            let store1 = DiaryAppStore(
                repository: gateRepo,
                adService: MockRewardedAdService(),
                clock: { clock.now },
                saveRetryDelays: [.milliseconds(40)]
            )
            try await bootstrapReady(store1)

            await gateRepo.setFailuresRemaining(1)
            store1.deliverOrder("o1")
            try await waitUntil { store1.saveError != nil && !store1.isSaving }

            store1.activeSheet = .diary
            clock.now = t0.addingTimeInterval(2)
            try await waitUntil { store1.pendingOrderDeliveries.isEmpty && !store1.isSaving }
            XCTAssertEqual(store1.state.coins, 20)
            XCTAssertNil(store1.activeAdOffer)

            // Closing Diary at +95s must NOT uncover a stale +2s invitation.
            clock.now = t0.addingTimeInterval(95)
            store1.activeSheet = nil
            XCTAssertNil(store1.activeAdOffer)

            // Relaunch and deliver o2 at +100s -> first actual display, stamped at +100s.
            clock.now = t0.addingTimeInterval(100)
            let store2 = DiaryAppStore(
                repository: DiarySaveRepository(directory: dir),
                adService: MockRewardedAdService(),
                clock: { clock.now }
            )
            try await bootstrapReady(store2)
            store2.deliverOrder("o2")
            try await waitUntil { !store2.isSaving && store2.pendingOrderDeliveries.isEmpty }
            XCTAssertEqual(store2.state.coins, 40)
            XCTAssertNotNil(store2.activeAdOffer)
            XCTAssertEqual(store2.state.ads.lastOfferAt, DayClock.epochMs(t0.addingTimeInterval(100)))

            // Relaunch immediately and deliver o3 at +105s -> only 5s after real display, must be blocked!
            clock.now = t0.addingTimeInterval(105)
            let store3 = DiaryAppStore(
                repository: DiarySaveRepository(directory: dir),
                adService: MockRewardedAdService(),
                clock: { clock.now }
            )
            try await bootstrapReady(store3)
            store3.deliverOrder("o3")
            try await waitUntil { !store3.isSaving && store3.pendingOrderDeliveries.isEmpty }
            XCTAssertEqual(store3.state.coins, 60)
            XCTAssertNil(store3.activeAdOffer, "o3 at +105s must honor 90s cooldown from o2 displayed at +100s")
        }
    }

    func testOpeningDiaryMidOfferSaveRollsBackDiskCooldownAndPhotoModalBlocksOffer() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }

        let t0 = Date(timeIntervalSince1970: 1_760_000_000)
        let ball = MergeItem(chain: .cloth, level: 3)
        let wand = MergeItem(chain: .cloth, level: 4)
        let order1 = CustomerOrder(id: "o1", customer: .ajian, items: [wand], wage: 20)
        let order2 = CustomerOrder(id: "o2", customer: .grandma, items: [wand], wage: 20)
        let order3 = CustomerOrder(id: "o3", customer: .ajian, items: [wand, wand], wage: 40)

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(t0))
        initial.tutorialActive = false
        initial.primaryCat.satiety = 80
        initial.home.toys = [OwnedToy(item: ball, usesLeft: 3)]
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
        try await bootstrapReady(store)

        // Sub-case A: Player opens Diary WHILE wage offer cooldown save (#2) is in flight -> rollback disk cooldown!
        await gateRepo.pauseOnSaveNumber(2)
        store.deliverOrder("o1")
        try await waitUntil { await gateRepo.inFlightSaves == 1 && store.state.coins == 20 }

        store.activeSheet = .diary
        await gateRepo.setPaused(false)
        try await waitUntil { !store.isSaving && store.pendingOrderDeliveries.isEmpty }

        XCTAssertNil(store.activeAdOffer)
        XCTAssertNil(store.state.ads.lastOfferAt)
        let diskAfterA = try await DiarySaveRepository(directory: dir).loadOrCreate(now: t0)
        XCTAssertNil(diskAfterA.ads.lastOfferAt, "Disk must roll back wage cooldown when Diary opens mid-save")

        // Sub-case B: Closing Diary and delivering o2 while a photo reveal modal is on screen skips wage offer too.
        store.activeSheet = nil
        store.playWithToy(at: 0) // first cloth_3 toy play deterministically enqueues photo_toy_01
        try await waitUntil { !store.isSaving }
        XCTAssertEqual(store.currentPhotoModalID, DiaryCatalog.tutorialPhotoID, "Expected photo modal to obstruct ad overlay")

        store.deliverOrder("o2")
        try await waitUntil { !store.isSaving && store.pendingOrderDeliveries.isEmpty }

        XCTAssertEqual(store.state.coins, 40)
        XCTAssertNil(store.activeAdOffer, "Photo modal preempts AdOfferOverlayView so wage offer must be skipped")
        XCTAssertNil(store.state.ads.lastOfferAt)
        let diskAfterB = try await DiarySaveRepository(directory: dir).loadOrCreate(now: t0)
        XCTAssertNil(diskAfterB.ads.lastOfferAt)
    }

    // MARK: - M2 Regression Tests

    func testDeliverWeekendOrderTransactionalAndSurvivesMondayRolloverDuringConcurrentMutation() async throws {
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        // 2026-11-29 is Sunday; 23:59:59 UTC -> +2s crosses into Monday 2026-11-30 00:00:01 UTC.
        var sundayComps = DateComponents()
        sundayComps.calendar = utcCal
        sundayComps.timeZone = utcCal.timeZone
        sundayComps.year = 2026
        sundayComps.month = 11
        sundayComps.day = 29
        sundayComps.hour = 23
        sundayComps.minute = 59
        sundayComps.second = 59
        let sundayNight = try XCTUnwrap(sundayComps.date)
        let mondayMorning = sundayNight.addingTimeInterval(2)
        let clock = MutableTestClock(sundayNight)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let diskRepo = DiarySaveRepository(directory: dir)

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(sundayNight), calendar: utcCal)
        initial.tutorialActive = false
        initial.primaryCat.level = 7
        initial.coins = 50
        DiaryOrders.syncWeekendOrder(&initial)
        let weekend = try XCTUnwrap(initial.orders.weekendOrder)
        for (idx, item) in weekend.items.enumerated() {
            initial.board.cells[idx] = item
        }
        try await diskRepo.save(initial, now: sundayNight)

        let gateRepo = GatedDiskSaveRepository(backing: diskRepo)
        let store = DiaryAppStore(
            repository: gateRepo,
            adService: MockRewardedAdService(),
            clock: { clock.now },
            calendar: utcCal
        )
        try await bootstrapReady(store)
        XCTAssertEqual(store.state.orders.weekendOrder?.id, weekend.id)

        // Pause disk save #1 (the weekend order delivery write).
        await gateRepo.pauseOnSaveNumber(1)
        store.deliverOrder(weekend.id)
        try await waitUntil { await gateRepo.inFlightSaves == 1 }

        // While save is in flight: coins must NOT be credited yet, and all items' cells are reserved.
        XCTAssertEqual(store.state.coins, 50)
        XCTAssertEqual(store.orderCardStatus(for: weekend), .saving)
        for idx in weekend.items.indices {
            XCTAssertTrue(store.isCellReserved(idx))
        }

        // Cross into Monday and trigger an unrelated mutation so `self.state != baseState` AND `weekendOrder` clears in-memory!
        clock.now = mondayMorning
        store.toggleWishlist(.windowCushion)
        XCTAssertNil(store.state.orders.weekendOrder, "Monday rollover clears live weekendOrder")

        // Unpause disk save -> reconciled commit must preserve the Sunday delivery, wage, and Monday timestamp!
        await gateRepo.setPaused(false)
        try await waitUntil { !store.isSaving && store.pendingOrderDeliveries.isEmpty }

        XCTAssertEqual(store.state.coins, 50 + weekend.wage)
        XCTAssertEqual(store.state.orders.weekendDoneWeek, DayClock.weekKey(for: 20261129))
        XCTAssertNil(store.activeAdOffer, "Weekend orders must not spawn double-wage ad offers")
        for idx in weekend.items.indices {
            XCTAssertNil(store.state.board.cells[idx])
        }
        XCTAssertGreaterThanOrEqual(store.state.updatedAt, DayClock.epochMs(mondayMorning))

        let reloaded = try await diskRepo.loadOrCreate(now: mondayMorning)
        XCTAssertEqual(reloaded.coins, 50 + weekend.wage)
        XCTAssertEqual(reloaded.home.wishlist, .windowCushion)
        XCTAssertEqual(reloaded.orders.weekendDoneWeek, DayClock.weekKey(for: 20261129))
    }

    func testRegularOrderStoryUnlockBlocksWageOfferWithoutRecordingHiddenCooldown() async throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let wand = MergeItem(chain: .cloth, level: 4)
        let order = CustomerOrder(id: "o1", customer: .ajian, items: [wand], wage: 20)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let diskRepo = DiarySaveRepository(directory: dir)

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(now))
        initial.tutorialActive = false
        initial.coins = 100
        initial.orders.completedTotal = 34
        initial.orders.customerProgress[.ajian] = 34 // 35th Ajian order unlocks Story #3 (+150 bonus)
        initial.orders.storiesSeen = ["ajian:10", "ajian:20"]
        initial.orders.active = [order]
        initial.orders.nextID = 2
        initial.board.cells[0] = wand
        try await diskRepo.save(initial, now: now)

        let store = DiaryAppStore(
            repository: diskRepo,
            adService: MockRewardedAdService(),
            clock: { now }
        )
        try await bootstrapReady(store)

        store.deliverOrder("o1")
        try await waitUntil { !store.isSaving && store.pendingOrderDeliveries.isEmpty }

        XCTAssertEqual(store.currentStoryModal?.id, "ajian:35")
        XCTAssertEqual(store.currentStoryModal?.bonusCoins, 150)
        XCTAssertEqual(store.state.coins, 100 + 20 + 150)
        XCTAssertFalse(store.canPresentAdOfferOverlay)
        XCTAssertNil(store.activeAdOffer, "Story modal must suppress double-wage ad overlay")
        XCTAssertNil(store.state.ads.lastOfferAt, "Suppressed ad offer must not record cooldown")

        let reloaded = try await diskRepo.loadOrCreate(now: now)
        XCTAssertNil(reloaded.ads.lastOfferAt)
        XCTAssertEqual(reloaded.orders.storiesSeen, ["ajian:10", "ajian:20", "ajian:35"])
    }

    func testNightSaleQuotedPriceAndExpiredWageOfferGuardAcrossMidnight() async throws {
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        // Find a day in Nov 2026 whose deterministic 22:00-24:00 night sale includes a non-Xueqiu-gated theme furniture item.
        var foundSale: (date: Date, furniture: FurnitureID)?
        for day in 1...30 {
            var nightComps = DateComponents()
            nightComps.calendar = utcCal
            nightComps.timeZone = utcCal.timeZone
            nightComps.year = 2026
            nightComps.month = 11
            nightComps.day = day
            nightComps.hour = 23
            nightComps.minute = 59
            nightComps.second = 50
            guard let candidateDate = nightComps.date else { continue }
            let sale = DiaryThemes.nightSale(now: DayClock.epochMs(candidateDate), calendar: utcCal)
            if let furn = sale.compactMap({ good -> FurnitureID? in
                guard case .furniture(let id) = good,
                      DiaryCatalog.furnitureDef(id)?.xueqiuLevel == nil else { return nil }
                return id
            }).first {
                foundSale = (candidateDate, furn)
                break
            }
        }
        let picked = try XCTUnwrap(foundSale)
        let nightSaleTime = picked.date
        let saleFurniture = picked.furniture
        let afterMidnight = nightSaleTime.addingTimeInterval(20)
        let clock = MutableTestClock(nightSaleTime)

        let ball = MergeItem(chain: .cloth, level: 3) // small order (wage 10), eligible ONLY via wishlist shortfall!
        let order = CustomerOrder(id: "o1", customer: .ajian, items: [ball], wage: 10)
        let fullPrice = try XCTUnwrap(DiaryCatalog.furnitureDef(saleFurniture)?.price)
        let salePrice = DiaryThemes.priceNow(furniture: saleFurniture, now: DayClock.epochMs(nightSaleTime), calendar: utcCal)
        XCTAssertLessThan(salePrice, fullPrice)

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(nightSaleTime), calendar: utcCal)
        initial.tutorialActive = false
        initial.primaryCat.level = 8 // unlocks winter/spring themes & all rooms
        initial.orders.completedTotal = 5
        initial.orders.active = [order]
        initial.orders.nextID = 2
        initial.board.cells[0] = ball
        initial.home.wishlist = saleFurniture
        // Before delivery: salePrice - 15 -> after +10 wage = salePrice - 5 (short by 5 <= 10 during sale, short by >10 at full price).
        initial.coins = salePrice - 15

        let repo = FlakySaveRepository(initialState: initial)
        let store = DiaryAppStore(
            repository: repo,
            adService: MockRewardedAdService(),
            clock: { clock.now },
            calendar: utcCal
        )
        try await bootstrapReady(store)
        XCTAssertTrue(store.isNightSaleActive)

        let saleQuote = store.currentFurniturePrice(saleFurniture)
        XCTAssertEqual(saleQuote, salePrice)

        // Deliver order during night sale -> small-order wage ad offer appears because (salePrice - 5) + 10 >= salePrice!
        store.deliverOrder("o1")
        try await waitUntil { !store.isSaving && store.pendingOrderDeliveries.isEmpty }
        XCTAssertNotNil(store.activeAdOffer)

        // Cross midnight: night sale ends, price returns to fullPrice!
        clock.now = afterMidnight
        XCTAssertFalse(store.isNightSaleActive)
        XCTAssertEqual(store.currentFurniturePrice(saleFurniture), fullPrice)

        // 1. Stale quoted buy must fail with `.priceChanged` and NOT charge coins.
        store.notices.dismiss()
        store.buyFurniture(saleFurniture, quoted: saleQuote)
        XCTAssertFalse(store.state.home.furnitureOwned.contains(saleFurniture))
        XCTAssertEqual(store.state.coins, salePrice - 5)
        XCTAssertEqual(store.notices.toast, GameStrings.format("shop.priceChanged", fullPrice))

        // 2. Accepting the now-expired small-order wage offer must abort cleanly without starting playback!
        store.notices.dismiss()
        store.watchActiveAd()
        XCTAssertNil(store.activeAdOffer)
        XCTAssertNil(store.playingMockAdSlot)
        XCTAssertEqual(store.notices.toast, GameStrings.text("ad.wagePriceUp"))
    }

    func testDecorateModeRollsBackMidSaveWageOfferCooldown() async throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let wand = MergeItem(chain: .cloth, level: 4)
        let order = CustomerOrder(id: "o1", customer: .ajian, items: [wand], wage: 20)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let diskRepo = DiarySaveRepository(directory: dir)

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(now))
        initial.tutorialActive = false
        initial.orders.completedTotal = 2
        initial.orders.active = [order]
        initial.orders.nextID = 2
        initial.board.cells[0] = wand
        initial.home.furnitureOwned = [.windowCushion]
        try await diskRepo.save(initial, now: now)

        let gateRepo = GatedDiskSaveRepository(backing: diskRepo)
        let store = DiaryAppStore(
            repository: gateRepo,
            adService: MockRewardedAdService(),
            clock: { now }
        )
        try await bootstrapReady(store)

        // Pause save #2 (the wage offer cooldown write).
        await gateRepo.pauseOnSaveNumber(2)
        store.deliverOrder("o1")
        try await waitUntil { await gateRepo.inFlightSaves == 1 && store.state.coins == 20 }

        // Enter decorate mode mid-save -> ad overlay cannot show -> disk cooldown must roll back!
        store.enterDecorateMode()
        XCTAssertTrue(store.isDecorating)
        XCTAssertFalse(store.canPresentAdOfferOverlay)

        await gateRepo.setPaused(false)
        try await waitUntil { !store.isSaving && store.pendingOrderDeliveries.isEmpty }

        XCTAssertNil(store.activeAdOffer)
        XCTAssertNil(store.state.ads.lastOfferAt)
        let reloaded = try await diskRepo.loadOrCreate(now: now)
        XCTAssertNil(reloaded.ads.lastOfferAt)
    }

    func testEntranceBasketStrayAdoptionMultiCatAndDecoratePersistAcrossRelaunch() async throws {
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let baseDate = Date(timeIntervalSince1970: 1_760_000_000)
        let clock = MutableTestClock(baseDate)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let diskRepo = DiarySaveRepository(directory: dir)
        let suiteName = "CatLifeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(baseDate), calendar: utcCal)
        initial.tutorialActive = false
        initial.primaryCat.level = 7 // unlocks entrance, outing, and stray Xueqiu adoption
        initial.home.furnitureOwned = [.windowCushion]
        initial.home.food = [
            MergeItem(chain: .food, level: 3),
            MergeItem(chain: .food, level: 4),
            MergeItem(chain: .food, level: 4),
            MergeItem(chain: .food, level: 4),
            MergeItem(chain: .food, level: 4)
        ]
        try await diskRepo.save(initial, now: baseDate)

        let store = DiaryAppStore(
            repository: diskRepo,
            adService: MockRewardedAdService(),
            clock: { clock.now },
            calendar: utcCal,
            userDefaults: defaults
        )
        try await bootstrapReady(store)

        // 1. Select Entrance room -> stray peeks (trust 0 -> present).
        store.selectRoom(.entrance)
        XCTAssertEqual(store.activeRoom, .entrance)
        XCTAssertTrue(store.isStrayPresentAtEntrance)

        // 2. Pack food into entrance basket & adopt stray over 5 visits.
        store.packBasket(source: .food, index: 0)
        XCTAssertEqual(store.state.home.basket?.item, MergeItem(chain: .food, level: 3))

        for step in 1...5 {
            if !store.isStrayPresentAtEntrance {
                clock.now = clock.now.addingTimeInterval(3600 * 6)
                if store.state.home.basket == nil && !store.state.home.food.isEmpty {
                    store.packBasket(source: .food, index: 0)
                }
                store.selectRoom(.livingroom)
                store.selectRoom(.entrance)
            }
            if store.isStrayPresentAtEntrance {
                store.meetStray()
            }
            if store.hasXueqiu {
                XCTAssertEqual(step, 5)
                break
            }
        }
        XCTAssertTrue(store.hasXueqiu)
        XCTAssertTrue(store.showingAdoptionModal)
        XCTAssertFalse(store.canPresentAdOfferOverlay)
        store.dismissAdoptionModal()

        // 3. Interact with Xueqiu in living room.
        store.selectRoom(.livingroom)
        store.petCat(.xueqiu)
        XCTAssertEqual(store.effectiveSelectedCatID, .xueqiu)
        XCTAssertGreaterThan(store.state.cats[.xueqiu]?.petCount ?? 0, 0)

        // 4. Decorate mode: place + flip `.windowCushion` in `.livingroom`.
        store.enterDecorateMode()
        XCTAssertTrue(store.placeFurniture(.windowCushion, room: .livingroom, x: 0.35, bottom: 0.72, flip: false))
        store.toggleFurnitureFlip(.windowCushion)
        store.exitDecorateMode()
        try await waitUntil { !store.isSaving }

        // 5. Relaunch from disk and verify everything persisted cleanly!
        let relaunched = DiaryAppStore(
            repository: diskRepo,
            adService: MockRewardedAdService(),
            clock: { clock.now },
            calendar: utcCal,
            userDefaults: defaults
        )
        try await bootstrapReady(relaunched)
        XCTAssertTrue(relaunched.hasXueqiu)
        let placed = DiaryLayout.placement(of: .windowCushion, in: relaunched.state)
        XCTAssertEqual(placed?.room, .livingroom)
        XCTAssertEqual(placed?.flip, true)
    }

    func testM1SaveUpgradeBackpaysRetroactiveStoriesOnceOnBootstrap() async throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let diskRepo = DiarySaveRepository(directory: dir)

        // Encode an M1-era save (`schemaVersion: 1`) and strip M2 fields so `init(from:)` runs the M1 -> M2 migration path.
        var base = DiaryGameState.fresh(now: DayClock.epochMs(now))
        base.tutorialActive = false
        base.coins = 100
        base.orders.customerProgress[.ajian] = 50 // qualifies for Ajian 10/20/35 (+150)/50 (+300) => 450 backpay!
        let encoded = try JSONEncoder().encode(base)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json["schemaVersion"] = 1
        var orders = try XCTUnwrap(json["orders"] as? [String: Any])
        orders.removeValue(forKey: "storiesSeen")
        orders.removeValue(forKey: "storyBackpay")
        orders.removeValue(forKey: "weekendOrder")
        orders.removeValue(forKey: "weekendDoneWeek")
        json["orders"] = orders
        let m1Data = try JSONSerialization.data(withJSONObject: json)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try m1Data.write(to: dir.appendingPathComponent("cat-diary-save-v1.json"))

        let store = DiaryAppStore(repository: diskRepo, adService: MockRewardedAdService(), clock: { now })
        try await bootstrapReady(store)

        XCTAssertEqual(store.state.schemaVersion, 2)
        XCTAssertEqual(store.state.coins, 550, "100 base + 450 retroactive story backpay")
        XCTAssertEqual(store.state.orders.storyBackpay, 0)
        XCTAssertEqual(store.state.orders.storiesSeen, ["ajian:10", "ajian:20", "ajian:35", "ajian:50"])
        XCTAssertEqual(store.notices.toast, GameStrings.format("story.backpayNotice", 450))

        // Second relaunch must NOT pay backpay a second time, and disk schemaVersion must be 2!
        let rawOnDisk = try Data(contentsOf: dir.appendingPathComponent("cat-diary-save-v1.json"))
        let onDiskJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: rawOnDisk) as? [String: Any])
        XCTAssertEqual(onDiskJSON["schemaVersion"] as? Int, 2)

        let relaunched = DiaryAppStore(repository: diskRepo, adService: MockRewardedAdService(), clock: { now })
        try await bootstrapReady(relaunched)
        XCTAssertEqual(relaunched.state.coins, 550)
    }

    func testQueuedSundayWeekendOrderSucceedsWhenEarlierSaveFinishesOnMonday() async throws {
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        // 2026-11-29 23:59:59 UTC (Sunday) -> +2s = 2026-11-30 00:00:01 UTC (Monday)
        var sundayComps = DateComponents()
        sundayComps.calendar = utcCal
        sundayComps.timeZone = utcCal.timeZone
        sundayComps.year = 2026
        sundayComps.month = 11
        sundayComps.day = 29
        sundayComps.hour = 23
        sundayComps.minute = 59
        sundayComps.second = 59
        let sundayNight = try XCTUnwrap(sundayComps.date)
        let mondayMorning = sundayNight.addingTimeInterval(2)
        let clock = MutableTestClock(sundayNight)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let diskRepo = DiarySaveRepository(directory: dir)

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(sundayNight), calendar: utcCal)
        initial.tutorialActive = false
        initial.primaryCat.level = 7
        initial.coins = 100
        DiaryOrders.syncWeekendOrder(&initial)
        let weekend = try XCTUnwrap(initial.orders.weekendOrder)
        for (idx, item) in weekend.items.enumerated() {
            initial.board.cells[idx] = item
        }
        try await diskRepo.save(initial, now: sundayNight)

        let gateRepo = GatedDiskSaveRepository(backing: diskRepo)
        let store = DiaryAppStore(
            repository: gateRepo,
            adService: MockRewardedAdService(),
            clock: { clock.now },
            calendar: utcCal
        )
        try await bootstrapReady(store)

        // Start an unrelated save #1 (wishlist toggle) on Sunday 23:59:59 and pause it mid-flight.
        await gateRepo.pauseOnSaveNumber(1)
        store.toggleWishlist(.windowCushion)
        try await waitUntil { await gateRepo.inFlightSaves == 1 }

        // Still Sunday 23:59:59: player taps Deliver on the weekend order -> queues behind save #1!
        store.deliverOrder(weekend.id)
        XCTAssertTrue(store.isOrderDeliveryPending(weekend.id))
        for idx in weekend.items.indices {
            XCTAssertTrue(store.isCellReserved(idx))
        }
        XCTAssertEqual(store.state.coins, 100)

        // Clock crosses Monday 00:00:01 BEFORE save #1 completes, so save #2 (the weekend delivery) starts on Monday!
        clock.now = mondayMorning
        await gateRepo.setPaused(false)
        try await waitUntil { !store.isSaving && store.pendingOrderDeliveries.isEmpty }

        // Timely Sunday submission must complete and credit the weekend wage!
        XCTAssertEqual(store.state.coins, 100 + weekend.wage)
        XCTAssertEqual(store.state.orders.weekendDoneWeek, DayClock.weekKey(for: 20261129))
        for idx in weekend.items.indices {
            XCTAssertNil(store.state.board.cells[idx])
        }
        let reloaded = try await diskRepo.loadOrCreate(now: mondayMorning, calendar: utcCal)
        XCTAssertEqual(reloaded.coins, 100 + weekend.wage)
        XCTAssertEqual(reloaded.orders.weekendDoneWeek, DayClock.weekKey(for: 20261129))
        XCTAssertEqual(reloaded.home.wishlist, .windowCushion)
    }

    func testRoomSkinPurchaseWaitsForSuccessfulSaveBeforeDeductingCoinsOrApplyingSkin() async throws {
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        // Pick noon UTC so night sale is inactive and `.honey` costs its full 800 coins.
        var noonComps = DateComponents()
        noonComps.calendar = utcCal
        noonComps.timeZone = utcCal.timeZone
        noonComps.year = 2026
        noonComps.month = 11
        noonComps.day = 28
        noonComps.hour = 12
        let noon = try XCTUnwrap(noonComps.date)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let diskRepo = DiarySaveRepository(directory: dir)

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(noon), calendar: utcCal)
        initial.tutorialActive = false
        initial.primaryCat.level = 8 // unlocks room skins
        initial.coins = 1_000
        try await diskRepo.save(initial, now: noon)

        let gateRepo = GatedDiskSaveRepository(backing: diskRepo)
        let store = DiaryAppStore(
            repository: gateRepo,
            adService: MockRewardedAdService(),
            clock: { noon },
            calendar: utcCal,
            saveRetryDelays: [.milliseconds(20), .milliseconds(30), .milliseconds(40)]
        )
        try await bootstrapReady(store)
        store.notices.dismiss()

        // Force disk write failures when buying `.honey` (800 coins).
        await gateRepo.setFailuresRemaining(10)
        store.buyRoomSkin(.honey, quoted: 800)
        try await waitUntil(timeoutMs: 1200) { store.saveError == GameStrings.text("save.writeFailedManual") && !store.isSaving }

        // While write failed: coins must stay 1,000, activeSkin must stay `.defaultSkin`, and NO success toast!
        XCTAssertEqual(store.state.coins, 1_000)
        XCTAssertEqual(store.state.home.activeSkin, .defaultSkin)
        XCTAssertEqual(store.state.home.skinsOwned, [.defaultSkin])
        XCTAssertNil(store.notices.toast)
        XCTAssertEqual(store.skinPurchaseStatus(for: .honey), .retrySave)
        XCTAssertEqual(store.availableCoinsForPurchase, 200)

        // Cannot double-spend the reserved 800 coins on another 800-coin skin while `.honey` is pending!
        store.buyRoomSkin(.mint, quoted: 800)
        XCTAssertFalse(store.isSkinPurchasePending(.mint))
        XCTAssertEqual(store.notices.toast, GameStrings.format("shop.shortCoins", 600))
        store.notices.dismiss()

        let diskWhileFailed = try await diskRepo.loadOrCreate(now: noon, calendar: utcCal)
        XCTAssertEqual(diskWhileFailed.coins, 1_000)
        XCTAssertEqual(diskWhileFailed.home.activeSkin, .defaultSkin)

        // Restore disk and retry -> purchase commits, coins drop to 200, `.honey` equips, toast appears, disk matches!
        await gateRepo.setFailuresRemaining(0)
        store.retrySaveNow()
        try await waitUntil { store.saveError == nil && !store.isSaving && store.pendingSkinPurchases.isEmpty }

        XCTAssertEqual(store.state.coins, 200)
        XCTAssertEqual(store.state.home.activeSkin, .honey)
        XCTAssertTrue(store.state.home.skinsOwned.contains(.honey))
        XCTAssertEqual(store.notices.toast, GameStrings.format("shop.skinAppliedNotice", GameStrings.roomSkinName(.honey)))

        let diskAfterRetry = try await diskRepo.loadOrCreate(now: noon, calendar: utcCal)
        XCTAssertEqual(diskAfterRetry.coins, 200)
        XCTAssertEqual(diskAfterRetry.home.activeSkin, .honey)
        XCTAssertEqual(diskAfterRetry.schemaVersion, 2)
    }

    func testExpiredWeekendTargetDoesNotTriggerMaterialAdOnMonday() async throws {
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        var sunComps = DateComponents()
        sunComps.calendar = utcCal
        sunComps.timeZone = utcCal.timeZone
        sunComps.year = 2026
        sunComps.month = 11
        sunComps.day = 29
        sunComps.hour = 23
        sunComps.minute = 59
        sunComps.second = 30
        let sundayNight = try XCTUnwrap(sunComps.date)
        let mondayMorning = sundayNight.addingTimeInterval(60) // Monday 00:00:30 UTC (< 1 energy regen tick)
        let clock = MutableTestClock(sundayNight)

        var initial = DiaryGameState.fresh(now: DayClock.epochMs(sundayNight), calendar: utcCal)
        initial.tutorialActive = false
        initial.primaryCat.level = 7
        initial.orders.completedTotal = 5
        initial.energy.current = 0
        initial.energy.updatedAt = DayClock.epochMs(sundayNight)
        DiaryOrders.syncWeekendOrder(&initial)
        let weekend = try XCTUnwrap(initial.orders.weekendOrder)
        let targetItem = try XCTUnwrap(weekend.items.first)
        let otherChain: MergeChain = targetItem.chain == .cloth ? .wood : .cloth
        initial.orders.active = [
            CustomerOrder(id: "o1", customer: .ajian, items: [MergeItem(chain: otherChain, level: 4)], wage: 20),
            CustomerOrder(id: "o2", customer: .grandma, items: [MergeItem(chain: otherChain, level: 4)], wage: 20),
            CustomerOrder(id: "o3", customer: .petshop, items: [MergeItem(chain: otherChain, level: 4)], wage: 20)
        ]
        // Place items worth `targetItem.energyValue - 1` so gap == 1 unit.
        var remaining = targetItem.energyValue - 1
        var cellIdx = 0
        for lvl in stride(from: targetItem.level - 1, through: 1, by: -1) {
            let val = MergeItem(chain: targetItem.chain, level: lvl).energyValue
            while remaining >= val {
                initial.board.cells[cellIdx] = MergeItem(chain: targetItem.chain, level: lvl)
                cellIdx += 1
                remaining -= val
            }
        }

        let repo = FlakySaveRepository(initialState: initial)
        let store = DiaryAppStore(
            repository: repo,
            adService: MockRewardedAdService(),
            clock: { clock.now },
            calendar: utcCal
        )
        try await bootstrapReady(store)
        store.switchScreen(to: .workshop)
        store.setTarget(item: targetItem, orderID: weekend.id)
        XCTAssertEqual(store.state.target?.orderID, weekend.id)

        // Advance to Monday while staying on Workshop, zero energy -> tapping generator must clear stale weekend target and NOT offer a material ad for the expired weekend order!
        clock.now = mondayMorning
        store.tapGenerator(targetItem.chain)
        XCTAssertNil(store.state.orders.weekendOrder)
        XCTAssertNil(store.state.target)
        XCTAssertNil(store.activeAdOffer)
    }

    private func bootstrapReady(_ store: DiaryAppStore) async throws {
        await store.bootstrap()
        while store.currentPhotoModalID != nil {
            store.dismissCurrentPhotoModal()
        }
        while store.currentLevelUpModal != nil {
            store.dismissCurrentLevelUpModal()
        }
        while store.currentStoryModal != nil {
            store.dismissCurrentStoryModal()
        }
        store.dismissMilestoneModal()
        try await waitUntil { !store.isSaving }
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
    private var failuresRemaining = 0
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

    func setFailuresRemaining(_ count: Int) {
        failuresRemaining = count
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
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw MockSaveFailure.diskFull
        }
        try await backing.save(state, now: now)
        if let delta = advanceBySaveIndex[currentIndex], let clock {
            clock.now = clock.now.addingTimeInterval(delta)
        }
    }
}
