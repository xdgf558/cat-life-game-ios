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
    private var failuresRemaining = 0
    private(set) var failedAttemptsSinceReset = 0
    private var savePaused = false
    private(set) var inFlightSaves = 0
    private var resumeContinuations: [CheckedContinuation<Void, Never>] = []

    init(initialState: DiaryGameState) {
        self.state = initialState
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
