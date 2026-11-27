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

    init(initialState: DiaryGameState) {
        self.state = initialState
    }

    func setFailuresRemaining(_ count: Int) {
        failuresRemaining = count
        failedAttemptsSinceReset = 0
    }

    func loadOrCreate(now: Date) async throws -> DiaryGameState {
        state
    }

    func save(_ state: DiaryGameState, now: Date) async throws {
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
