import Foundation
import Observation
import CatGameCore

enum AppScreen: Equatable {
    case home
    case workshop
}

enum CatHomePose: String, Equatable {
    case idle
    case happy
    case hungry
    case sleep
    case pet
    case play
    case eat

    func assetName(stage: CatGrowthStage = .kitten) -> String {
        switch stage {
        case .kitten: "cat_\(rawValue)"
        case .junior: "cat_junior_\(rawValue)"
        case .adult: "cat_adult_\(rawValue)"
        }
    }
}

struct LevelUpModalItem: Identifiable, Equatable {
    let id = UUID()
    let level: Int
    let unlocks: [UnlockRule]
}

enum ActiveSheet: Identifiable, Equatable {
    case shop
    case diary
    case settings
    case orderDetail(CustomerOrder)

    var id: String {
        switch self {
        case .shop: "shop"
        case .diary: "diary"
        case .settings: "settings"
        case .orderDetail(let order): "order-\(order.id)"
        }
    }
}

enum OrderCardStatus: Equatable {
    case saving
    case retrySave
    case deliverable
    case incomplete
}

struct PendingOrderDelivery: Equatable {
    let orderID: String
    var reservedCells: [Int]
}

private struct PendingAdCompletion: Equatable {
    let claimID: String
    let offer: AdOffer
    let result: AdPlayResult
}

@MainActor
@Observable
final class DiaryAppStore {
    private(set) var state: DiaryGameState
    private(set) var isLoaded = false
    private(set) var isSaving = false
    private(set) var loadError: String?
    private(set) var saveError: String?

    var activeScreen: AppScreen = .home
    var activeRoom: RoomID = .livingroom
    var activeSheet: ActiveSheet?

    // Modals & transient UI feedback
    private(set) var photoQueue: [String] = []
    private(set) var levelUpQueue: [LevelUpModalItem] = []
    private(set) var activeAdOffer: AdOffer?
    private(set) var playingMockAdSlot: AdSlot?
    private(set) var offlineNoteID: String?
    private(set) var showingOfflineNote = false
    private(set) var catBubbleKey: String?
    private(set) var transientCatPose: CatHomePose?
    private(set) var luckyCells: Set<Int> = []
    private(set) var recentMergedCell: Int?
    private(set) var pendingOrderDeliveries: [PendingOrderDelivery] = []

    // Debug / M1 testing toggles (exposed in Settings)
    var mockAdsEnabled: Bool = true {
        didSet {
            engine.adConfig.adEnabled = mockAdsEnabled
            if !mockAdsEnabled {
                activeAdOffer = nil
            }
        }
    }

    let audio = GameAudioController()
    let notices = GameNoticeCenter()
    let mockAdService: MockRewardedAdService

    @ObservationIgnored private let adService: any RewardedAdService
    @ObservationIgnored private let repository: any GameSaveRepository
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let saveRetryDelays: [Duration]
    @ObservationIgnored private var engine: DiaryGameEngine
    @ObservationIgnored private var saveRetry = SaveRetryState()
    @ObservationIgnored private var saveNeedsWrite = false
    @ObservationIgnored private var pendingAdCompletions: [PendingAdCompletion] = []
    @ObservationIgnored private var expiredWishGuardGoal: WishGoal?
    @ObservationIgnored private var stateGeneration = 0
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var poseTask: Task<Void, Never>?
    @ObservationIgnored private var bubbleTask: Task<Void, Never>?
    @ObservationIgnored private var comboCount = 0
    @ObservationIgnored private var lastMergeAt: TimeInterval = -100
    @ObservationIgnored private var lastBubbleKey: String?
    @ObservationIgnored private var isForeground = true
    @ObservationIgnored private var homeTrack: GameMusicTrack
    @ObservationIgnored private var workshopTrack: GameMusicTrack

    var currentPhotoModalID: String? { photoQueue.first }
    var currentLevelUpModal: LevelUpModalItem? { photoQueue.isEmpty ? levelUpQueue.first : nil }
    var reservedBoardCells: Set<Int> { Set(pendingOrderDeliveries.flatMap(\.reservedCells)) }

    func isOrderDeliveryPending(_ orderID: String) -> Bool {
        pendingOrderDeliveries.contains { $0.orderID == orderID }
    }

    func isCellReserved(_ index: Int) -> Bool {
        reservedBoardCells.contains(index)
    }

    func canDeliverOrder(_ order: CustomerOrder) -> Bool {
        guard !isOrderDeliveryPending(order.id),
              state.orders.active.contains(where: { $0.id == order.id }) else {
            return false
        }
        return selectUnreservedCells(for: order.items, excluding: reservedBoardCells) != nil
    }

    func orderCardStatus(for order: CustomerOrder) -> OrderCardStatus {
        if isOrderDeliveryPending(order.id) {
            return isSaving ? .saving : .retrySave
        }
        return canDeliverOrder(order) ? .deliverable : .incomplete
    }

    func unreservedOrderItemMatches(for order: CustomerOrder) -> [Bool] {
        if isOrderDeliveryPending(order.id) {
            return Array(repeating: true, count: order.items.count)
        }
        let reserved = reservedBoardCells
        var available: [MergeItem: Int] = [:]
        for (idx, cell) in state.board.cells.enumerated() where !reserved.contains(idx) {
            if let item = cell {
                available[item, default: 0] += 1
            }
        }
        return order.items.map { item in
            let count = available[item] ?? 0
            guard count > 0 else { return false }
            available[item] = count - 1
            return true
        }
    }

    var nowMs: Int64 { DayClock.epochMs(clock()) }
    var sceneLight: SceneLight { engine.sceneLight(now: nowMs) }
    var energyStatus: (current: Int, msToNext: Int64) { DiaryEnergy.view(state, now: nowMs, balance: engine.balance) }
    var daysTogether: Int { DayClock.daysTogether(createdAt: state.createdAt, now: nowMs, calendar: calendar) }
    var photoProgress: (got: Int, total: Int) { DiaryHome.photoProgress(state) }
    var currentMusicTrack: GameMusicTrack { activeScreen == .home ? homeTrack : workshopTrack }

    var displayedCatPose: CatHomePose {
        if let transient = transientCatPose { return transient }
        if DiaryHome.isHungry(state.primaryCat) && !state.tutorialActive { return .hungry }
        if sceneLight == .night && !state.tutorialActive { return .sleep }
        return .idle
    }

    init(
        repository: (any GameSaveRepository)? = nil,
        adService: (any RewardedAdService)? = nil,
        clock: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = .current,
        saveRetryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(60)]
    ) {
        self.clock = clock
        self.calendar = calendar
        self.saveRetryDelays = saveRetryDelays.isEmpty ? [.seconds(2)] : saveRetryDelays
        let resolvedRepo: any GameSaveRepository
        if let repository {
            resolvedRepo = repository
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            resolvedRepo = DiarySaveRepository(directory: base.appendingPathComponent("CatLife", isDirectory: true))
        }
        self.repository = resolvedRepo

        let mock = (adService as? MockRewardedAdService) ?? MockRewardedAdService()
        self.mockAdService = mock
        self.adService = adService ?? mock

        let initial = DiaryGameState.fresh(now: DayClock.epochMs(clock()), calendar: calendar)
        self.state = initial
        self.engine = DiaryGameEngine(state: initial, adConfig: AdRemoteConfig(adEnabled: true), calendar: calendar)
        self.homeTrack = GameMusicTrack.homeTracks.randomElement() ?? .home
        self.workshopTrack = GameMusicTrack.workshopTracks.randomElement() ?? .work

        self.mockAdService.onRequestPlayback = { [weak self] slot in
            self?.playingMockAdSlot = slot
        }
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        guard !isLoaded else { return }
        do {
            let loaded = try await repository.loadOrCreate(now: clock())
            engine = DiaryGameEngine(state: loaded, adConfig: AdRemoteConfig(adEnabled: mockAdsEnabled), calendar: calendar)
            let startOut = engine.start(now: nowMs)
            syncStateAndApply(events: startOut.events, save: false)
            applyLanguagePreference()
            isLoaded = true
            loadError = nil

            let visit = engine.visitHome(now: nowMs)
            syncStateAndApply(events: visit.events, save: true)
            if state.tutorialStep == .finish && !photoQueue.contains(DiaryCatalog.tutorialPhotoID) {
                photoQueue.insert(DiaryCatalog.tutorialPhotoID, at: 0)
            }
            if let note = visit.value.offlineNoteID {
                offlineNoteID = note
                showingOfflineNote = true
            }
            reconcileAudio()
        } catch {
            loadError = GameStrings.text("save.loadFailed")
        }
    }

    @discardableResult
    func refreshDayIfNeeded() -> Bool {
        guard isLoaded else { return false }
        let previousDayKey = state.dayKey
        let out = engine.refreshDay(now: nowMs)
        guard out.didMutate || engine.state != state else { return false }
        syncStateAndApply(events: out.events, save: true)
        return state.dayKey != previousDayKey
    }

    func retrySaveNow() {
        scheduleSave(force: true, resetBackoff: true)
    }

    func setForeground(_ foreground: Bool) {
        let wasForeground = isForeground
        isForeground = foreground
        if !foreground, isLoaded {
            if activeScreen == .home {
                let out = engine.leaveHome(now: nowMs)
                syncStateAndApply(events: out.events, save: true)
            }
        } else if !wasForeground, foreground, isLoaded {
            let dayOut = engine.refreshDay(now: nowMs)
            if dayOut.didMutate || engine.state != state {
                syncStateAndApply(events: dayOut.events, save: true)
            }
            if activeScreen == .home {
                let visit = engine.visitHome(now: nowMs)
                syncStateAndApply(events: visit.events, save: true)
                if let note = visit.value.offlineNoteID {
                    offlineNoteID = note
                    showingOfflineNote = true
                }
            }
        }
        reconcileAudio()
    }

    func switchScreen(to screen: AppScreen) {
        guard activeScreen != screen else { return }
        expiredWishGuardGoal = nil
        if activeScreen == .home {
            let out = engine.leaveHome(now: nowMs)
            syncStateAndApply(events: out.events, save: true)
        }
        activeScreen = screen
        audio.play(.tap, userInitiated: true)
        if screen == .home {
            let visit = engine.visitHome(now: nowMs)
            syncStateAndApply(events: visit.events, save: true)
            if let note = visit.value.offlineNoteID {
                offlineNoteID = note
                showingOfflineNote = true
            }
        }
        reconcileAudio()
    }

    func selectRoom(_ room: RoomID) {
        guard DiaryProgression.roomUnlocked(state, room: room) else {
            let lv = DiaryProgression.unlockLevel(for: .room(room))
            notices.show(GameStrings.format("room.lockedNotice", lv))
            return
        }
        activeRoom = room
        audio.play(.tap, userInitiated: true)
    }

    // MARK: - Workshop Actions

    func tapGenerator(_ chain: MergeChain) {
        let out = engine.tapGenerator(chain: chain, now: nowMs)
        switch out.value {
        case .generated(let item, let cell):
            syncStateAndApply(events: out.events, save: true)
            audio.play(item.level >= 2 ? .coins : .place, userInitiated: true)
            if item.level >= 2 && cell >= 0 {
                luckyCells.insert(cell)
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(900))
                    self?.luckyCells.remove(cell)
                }
            } else if cell < 0 {
                notices.show(GameStrings.text("workshop.sentToPending"))
            }
        case .locked:
            syncStateAndApply(events: out.events, save: false)
            let lv = DiaryProgression.unlockLevel(for: .chain(chain))
            notices.show(GameStrings.format("workshop.chainLocked", lv))
        case .noEnergy:
            syncStateAndApply(events: out.events, save: false)
            tryPresentMaterialAd(for: chain)
        }
    }

    func moveItem(from: Int, to: Int) -> MoveItemResult {
        guard !isCellReserved(from), !isCellReserved(to) else { return .invalid }
        let out = engine.moveItem(from: from, to: to, now: nowMs)
        syncStateAndApply(events: out.events, save: out.value != .invalid)
        switch out.value {
        case .merged:
            let uptime = ProcessInfo.processInfo.systemUptime
            comboCount = (uptime - lastMergeAt <= 5.0) ? min(3, comboCount + 1) : 0
            lastMergeAt = uptime
            let pitch = Float(1.0 + 0.06 * Double(comboCount))
            audio.play(.merge, rate: pitch, userInitiated: true)
            recentMergedCell = to
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(420))
                if self?.recentMergedCell == to { self?.recentMergedCell = nil }
            }
        case .moved, .swapped:
            audio.play(.place, userInitiated: true)
        case .invalid:
            break
        }
        return out.value
    }

    func claimPending() {
        let out = engine.claimPending(now: nowMs)
        guard out.value != nil else {
            syncStateAndApply(events: out.events, save: false)
            notices.show(GameStrings.text("workshop.boardFull"))
            return
        }
        syncStateAndApply(events: out.events, save: true)
        audio.play(.place, userInitiated: true)
    }

    func sellItem(at index: Int) {
        guard !isCellReserved(index) else { return }
        let out = engine.sellItem(at: index, now: nowMs)
        guard out.value > 0 else {
            syncStateAndApply(events: out.events, save: false)
            return
        }
        syncStateAndApply(events: out.events, save: true)
        audio.play(.coins, userInitiated: true)
        notices.show(GameStrings.format("workshop.soldCoins", out.value))
    }

    func bringHome(cellIndex: Int) {
        guard !isCellReserved(cellIndex) else { return }
        let out = engine.bringHome(cellIndex: cellIndex, now: nowMs)
        switch out.value {
        case .brought(let item):
            syncStateAndApply(events: out.events, save: true)
            audio.play(.purchase, userInitiated: true)
            notices.show(GameStrings.format("workshop.broughtHomeNotice", GameStrings.itemName(item)))
            if state.tutorialStep == .play {
                switchScreen(to: .home)
            }
        case .levelTooLow:
            syncStateAndApply(events: out.events, save: false)
            notices.show(GameStrings.text("workshop.bringHomeLevelTooLow"))
        case .empty:
            syncStateAndApply(events: out.events, save: false)
        }
    }

    func setTarget(item: MergeItem, orderID: String? = nil) {
        let out = engine.setTarget(item: item, orderID: orderID, now: nowMs)
        syncStateAndApply(events: out.events, save: true)
        audio.play(.tap, userInitiated: true)
    }

    func clearTarget() {
        let out = engine.clearTarget(now: nowMs)
        syncStateAndApply(events: out.events, save: true)
    }

    func deliverOrder(_ orderID: String) {
        if isOrderDeliveryPending(orderID) {
            if !isSaving {
                scheduleSave(force: true, resetBackoff: true)
            }
            return
        }
        guard let order = state.orders.active.first(where: { $0.id == orderID }),
              let cells = selectUnreservedCells(for: order.items, excluding: reservedBoardCells) else {
            return
        }
        pendingOrderDeliveries.append(PendingOrderDelivery(orderID: orderID, reservedCells: cells))
        scheduleSave(force: true, resetBackoff: true)
    }

    func rerollOrder(_ orderID: String) {
        guard !(isSaving && !pendingOrderDeliveries.isEmpty) else { return }
        if isOrderDeliveryPending(orderID) {
            pendingOrderDeliveries.removeAll { $0.orderID == orderID }
        }
        let out = engine.rerollOrder(orderID: orderID, now: nowMs)
        guard out.value != nil else {
            syncStateAndApply(events: out.events, save: false)
            notices.show(GameStrings.text("order.rerollUsed"))
            return
        }
        syncStateAndApply(events: out.events, save: true)
        audio.play(.tap, userInitiated: true)
        activeSheet = nil
    }

    // MARK: - Home & Shop Actions

    func petCat() {
        let out = engine.pet(now: nowMs)
        switch out.value {
        case .petted:
            syncStateAndApply(events: out.events, save: true)
            audio.play(.pet, userInitiated: true)
            audio.playPetPurrHaptics()
            showTransientPose(.pet, durationMs: 1300)
        case .failed(.cooldown):
            syncStateAndApply(events: out.events, save: false)
            let mood: CatBubbleMood = if DiaryHome.isHungry(state.primaryCat) && !state.tutorialActive {
                .hungry
            } else if sceneLight == .night && !state.tutorialActive {
                .sleep
            } else {
                .normal
            }
            let key = DiaryCatalog.pickBubbleKey(mood: mood, excluding: lastBubbleKey, randomUnit: Double.random(in: 0..<1))
            lastBubbleKey = key
            showBubble(key: key)
            audio.play(.tap, userInitiated: true)
        case .failed:
            syncStateAndApply(events: out.events, save: false)
        }
    }

    func playWithToy(at index: Int) {
        guard state.home.toys.indices.contains(index) else { return }
        let item = state.home.toys[index].item
        if shouldAbortItemUseAfterMidnightWishChange(for: .play(item)) { return }
        let out = engine.playWithToy(index: index, now: nowMs)
        switch out.value {
        case .played(_, _, let wornOut):
            syncStateAndApply(events: out.events, save: true)
            audio.play(.catHappy, userInitiated: true)
            showTransientPose(.play, durationMs: 1400)
            if wornOut { notices.show(GameStrings.text("home.toyWornOut")) }
        case .failed(.hungry):
            syncStateAndApply(events: out.events, save: false)
            showBubble(key: "bubble.hungry.01")
            notices.show(GameStrings.text("home.hungryRefusePlay"))
        case .failed:
            syncStateAndApply(events: out.events, save: false)
        }
    }

    func feedCat(at index: Int) {
        guard state.home.food.indices.contains(index) else { return }
        let item = state.home.food[index]
        if shouldAbortItemUseAfterMidnightWishChange(for: .feed(item)) { return }
        let out = engine.feed(index: index, now: nowMs)
        switch out.value {
        case .fed:
            syncStateAndApply(events: out.events, save: true)
            audio.play(.feed, userInitiated: true)
            showTransientPose(.eat, durationMs: 1600)
        case .failed:
            syncStateAndApply(events: out.events, save: false)
        }
    }

    func buyFurniture(_ id: FurnitureID) {
        let out = engine.buyFurniture(id: id, now: nowMs)
        switch out.value {
        case .bought(let furniture, _):
            syncStateAndApply(events: out.events, save: true)
            audio.play(.purchase, userInitiated: true)
            notices.show(GameStrings.format("shop.boughtNotice", GameStrings.furnitureName(furniture)))
            // Xiaoju immediately tries newly bought furniture in the current room!
            let settle = engine.settleNewFurniture(now: nowMs)
            syncStateAndApply(events: settle.events, save: true)
            if let def = DiaryCatalog.furnitureDef(furniture) {
                activeRoom = def.room
            }
            activeSheet = nil
        case .notEnoughCoins:
            let wishOut = engine.setWishlist(id, now: nowMs)
            syncStateAndApply(events: wishOut.events, save: true)
            notices.show(GameStrings.format("shop.wishlistPinned", GameStrings.furnitureName(id)))
        case .roomLocked(let room):
            syncStateAndApply(events: out.events, save: false)
            let lv = DiaryProgression.unlockLevel(for: .room(room))
            notices.show(GameStrings.format("room.lockedNotice", lv))
        case .owned, .notForSale:
            syncStateAndApply(events: out.events, save: false)
        }
    }

    func toggleWishlist(_ id: FurnitureID) {
        let next: FurnitureID? = state.home.wishlist == id ? nil : id
        let out = engine.setWishlist(next, now: nowMs)
        syncStateAndApply(events: out.events, save: true)
    }

    // MARK: - Modals & Tutorial

    func dismissCurrentPhotoModal() {
        guard !photoQueue.isEmpty else { return }
        let dismissed = photoQueue.removeFirst()
        if dismissed == DiaryCatalog.tutorialPhotoID && state.tutorialStep == .finish {
            let out = engine.finishTutorial(now: nowMs)
            syncStateAndApply(events: out.events, save: true)
            notices.show(GameStrings.text("tutorial.completedNotice"))
        }
    }

    func dismissCurrentLevelUpModal() {
        guard !levelUpQueue.isEmpty else { return }
        levelUpQueue.removeFirst()
    }

    func toggleOfflineNote() {
        showingOfflineNote.toggle()
    }

    // MARK: - Ads

    private func tryPresentMaterialAd(for chain: MergeChain) {
        guard activeAdOffer == nil, pendingAdCompletions.isEmpty else { return }
        let pendingOrderIDs = Set(pendingOrderDeliveries.map(\.orderID))
        let out = engine.materialOfferFor(
            chain: chain,
            now: nowMs,
            reservedCells: reservedBoardCells,
            excludedOrderIDs: pendingOrderIDs
        ) { [weak self] _ in
            self?.adService.isReady(slot: .material) == true
        }
        guard let offer = out.value else {
            syncStateAndApply(events: out.events, save: false)
            notices.show(GameStrings.text("workshop.noEnergyNotice"))
            return
        }
        syncStateAndApply(events: out.events, save: true)
        presentAdOffer(.material(offer))
    }

    private func presentAdOffer(_ offer: AdOffer) {
        let out = engine.offerShown(offer, now: nowMs)
        syncStateAndApply(events: out.events, save: true)
        activeAdOffer = offer
    }

    func refuseActiveAd() {
        guard let offer = activeAdOffer else { return }
        activeAdOffer = nil
        let out = engine.refuseAd(slot: offer.slot, now: nowMs)
        syncStateAndApply(events: out.events, save: true)
    }

    func watchActiveAd() {
        guard let offer = activeAdOffer, pendingAdCompletions.isEmpty else { return }
        activeAdOffer = nil
        let startOut = engine.startAd(offer: offer, now: nowMs)
        guard let claimID = startOut.value else {
            syncStateAndApply(events: startOut.events, save: false)
            notices.show(GameStrings.text("ad.unavailable"))
            return
        }
        syncStateAndApply(events: startOut.events, save: true)
        audio.setAdPaused(true)
        let generation = stateGeneration
        Task { [weak self] in
            guard let self else { return }
            let result = await self.adService.play(slot: offer.slot)
            guard self.stateGeneration == generation else { return }
            self.playingMockAdSlot = nil
            self.audio.setAdPaused(false)
            if result == .ended {
                self.pendingAdCompletions.append(
                    PendingAdCompletion(claimID: claimID, offer: offer, result: .ended)
                )
                self.scheduleSave(force: true, resetBackoff: true)
            } else {
                let finishOut = self.engine.finishAd(claimID: claimID, result: result, now: self.nowMs)
                self.syncStateAndApply(events: finishOut.events, save: true)
                if result == .failed {
                    self.notices.show(GameStrings.text("ad.playFailed"))
                } else {
                    self.notices.show(GameStrings.text("ad.closedEarly"))
                }
            }
        }
    }

    func finishMockAdPlayback(with result: AdPlayResult) {
        mockAdService.complete(with: result)
    }

    // MARK: - Settings & Debug Helpers

    func updateAudioSettings(_ newAudio: AudioSettings, commit: Bool) {
        var settings = state.settings
        settings.audio = newAudio
        let out = engine.updateSettings(settings, now: nowMs)
        syncStateAndApply(events: out.events, save: commit)
        reconcileAudio()
    }

    func updateLanguage(_ language: GameLanguage?) {
        var settings = state.settings
        settings.language = language
        let out = engine.updateSettings(settings, now: nowMs)
        syncStateAndApply(events: out.events, save: true)
        applyLanguagePreference()
    }

    func resetProgress() {
        stateGeneration &+= 1
        pendingOrderDeliveries.removeAll()
        pendingAdCompletions.removeAll()
        expiredWishGuardGoal = nil
        let out = engine.resetProgress(now: nowMs)
        photoQueue.removeAll()
        levelUpQueue.removeAll()
        activeAdOffer = nil
        offlineNoteID = nil
        showingOfflineNote = false
        activeScreen = .home
        activeRoom = .livingroom
        activeSheet = nil
        syncStateAndApply(events: out.events, save: true)
        notices.show(GameStrings.text("settings.resetDone"))
    }

    // MARK: - Internals

    private func syncStateAndApply(events: [DiaryGameEvent], save: Bool) {
        let previousDayKey = state.dayKey
        let previousWish = state.home.wish
        let nextState = engine.state
        let dayRolled = nextState.dayKey != previousDayKey
            || events.contains(where: { if case .dayStarted = $0 { return true } else { return false } })
        if dayRolled,
           let previousWish,
           !previousWish.completed,
           nextState.home.wish?.goal != previousWish.goal {
            switch previousWish.goal {
            case .play, .feed:
                expiredWishGuardGoal = previousWish.goal
            case .pet:
                expiredWishGuardGoal = nil
            }
        }
        state = nextState
        for event in events {
            switch event {
            case .photoTaken(_, let photoID):
                if !photoQueue.contains(photoID) { photoQueue.append(photoID) }
                audio.play(.photo)
            case .levelUp(_, let level, let unlocks):
                levelUpQueue.append(LevelUpModalItem(level: level, unlocks: unlocks))
                audio.play(.levelUp)
            case .wishCompleted(_, _, let bonusXP):
                notices.show(GameStrings.format("wish.completedNotice", bonusXP))
            default:
                break
            }
        }
        if save || dayRolled { scheduleSave() }
    }

    private func shouldAbortItemUseAfterMidnightWishChange(for goal: WishGoal) -> Bool {
        _ = refreshDayIfNeeded()
        guard let guardedGoal = expiredWishGuardGoal else { return false }
        expiredWishGuardGoal = nil
        guard guardedGoal == goal, state.home.wish?.goal != goal else {
            return false
        }
        notices.show(GameStrings.text("wish.refreshedAtMidnight"))
        audio.play(.tap, userInitiated: true)
        return true
    }

    private func scheduleSave(force: Bool = false, resetBackoff: Bool = false) {
        if resetBackoff {
            saveRetry.succeeded()
        }
        if !force, saveRetry.failures > 0, !saveRetry.permitsAutomaticAttempt(at: clock()) {
            if retryTask == nil, saveRetry.failures < SaveRetryState.maximumAutomaticAttempts {
                scheduleAutomaticSaveRetry()
            }
            return
        }
        retryTask?.cancel()
        retryTask = nil
        saveNeedsWrite = true
        guard saveTask == nil else { return }
        startSaveLoop()
    }

    private func selectUnreservedCells(for items: [MergeItem], excluding alreadyReserved: Set<Int>) -> [Int]? {
        var used = alreadyReserved
        var chosen: [Int] = []
        for needed in items {
            guard let idx = state.board.cells.indices.first(where: { cellIdx in
                !used.contains(cellIdx) && state.board.cells[cellIdx] == needed
            }) else {
                return nil
            }
            used.insert(idx)
            chosen.append(idx)
        }
        return chosen
    }

    private func startSaveLoop() {
        isSaving = true
        saveTask = Task { [weak self] in
            guard let self else { return }
            while !self.pendingAdCompletions.isEmpty || !self.pendingOrderDeliveries.isEmpty || self.saveNeedsWrite {
                let generation = self.stateGeneration
                let now = self.clock()
                let saveNowMs = DayClock.epochMs(now)
                do {
                    if let completion = self.pendingAdCompletions.first {
                        self.saveNeedsWrite = false
                        let baseState = self.state
                        let candidateEngine = self.engine.cloned()
                        let finishOut = candidateEngine.finishAd(
                            claimID: completion.claimID,
                            result: completion.result,
                            now: saveNowMs
                        )
                        if finishOut.value {
                            try await self.repository.save(candidateEngine.state, now: now)
                            guard self.stateGeneration == generation else { continue }
                            if self.pendingAdCompletions.first == completion {
                                self.pendingAdCompletions.removeFirst()
                            }
                            self.commitSavedAdCompletion(
                                completion: completion,
                                baseState: baseState,
                                candidateEngine: candidateEngine,
                                commitEvents: finishOut.events
                            )
                        } else {
                            if self.pendingAdCompletions.first == completion {
                                self.pendingAdCompletions.removeFirst()
                            }
                            try await self.repository.save(self.state, now: now)
                        }
                    } else if let delivery = self.pendingOrderDeliveries.first {
                        self.saveNeedsWrite = false
                        let baseState = self.state
                        let candidateEngine = self.engine.cloned()
                        let out = candidateEngine.deliverOrder(
                            orderID: delivery.orderID,
                            preferredCells: delivery.reservedCells,
                            now: saveNowMs
                        )
                        if case .delivered(_, let wage, let gift, let replacement) = out.value.result {
                            let eligibleBonus: WageOffer? = if let bonus = out.value.bonusOffer,
                                self.adService.isReady(slot: .wage),
                                candidateEngine.offerStillAllowed(.wage(bonus), now: saveNowMs),
                                self.activeAdOffer == nil,
                                self.pendingAdCompletions.isEmpty {
                                bonus
                            } else {
                                nil
                            }
                            var commitEvents = out.events
                            if let eligibleBonus {
                                let shownOut = candidateEngine.offerShown(.wage(eligibleBonus), now: saveNowMs)
                                commitEvents.append(contentsOf: shownOut.events)
                            }
                            try await self.repository.save(candidateEngine.state, now: now)
                            guard self.stateGeneration == generation else { continue }
                            self.pendingOrderDeliveries.removeAll { $0.orderID == delivery.orderID }
                            self.commitSavedOrderDelivery(
                                delivery: delivery,
                                baseState: baseState,
                                candidateEngine: candidateEngine,
                                commitEvents: commitEvents,
                                wage: wage,
                                gift: gift,
                                replacement: replacement,
                                saveNowMs: saveNowMs,
                                bonus: eligibleBonus
                            )
                        } else {
                            self.pendingOrderDeliveries.removeAll { $0.orderID == delivery.orderID }
                            try await self.repository.save(self.state, now: now)
                        }
                    } else {
                        self.saveNeedsWrite = false
                        let snapshot = self.state
                        try await self.repository.save(snapshot, now: now)
                    }
                    self.saveRetry.succeeded()
                    self.saveError = nil
                } catch {
                    self.saveNeedsWrite = false
                    let hadAutomaticAttemptLeft = self.saveRetry.failures < SaveRetryState.maximumAutomaticAttempts
                    _ = self.saveRetry.failed(at: now)
                    self.saveError = GameStrings.text("save.writeFailed")
                    if hadAutomaticAttemptLeft {
                        self.scheduleAutomaticSaveRetry()
                    }
                    break
                }
            }
            self.saveTask = nil
            self.isSaving = false
        }
    }

    private func commitSavedAdCompletion(
        completion: PendingAdCompletion,
        baseState: DiaryGameState,
        candidateEngine: DiaryGameEngine,
        commitEvents: [DiaryGameEvent]
    ) {
        var granted = true
        if self.state == baseState {
            let currentAdConfig = self.engine.adConfig
            self.engine = candidateEngine
            self.engine.adConfig = currentAdConfig
            self.syncStateAndApply(events: commitEvents, save: false)
        } else {
            let liveOut = self.engine.finishAd(
                claimID: completion.claimID,
                result: completion.result,
                now: self.nowMs
            )
            granted = liveOut.value
            self.syncStateAndApply(events: liveOut.events, save: false)
            if granted {
                self.saveNeedsWrite = true
            }
        }
        guard granted else { return }
        self.audio.play(.coins)
        switch completion.offer {
        case .material(let m):
            self.notices.show(GameStrings.format("ad.rewardMaterials", m.count, GameStrings.itemName(m.item)))
        case .wage(let w):
            self.notices.show(GameStrings.format("ad.rewardCoins", w.amount))
        }
    }

    private func commitSavedOrderDelivery(
        delivery: PendingOrderDelivery,
        baseState: DiaryGameState,
        candidateEngine: DiaryGameEngine,
        commitEvents: [DiaryGameEvent],
        wage: Int,
        gift: FurnitureID?,
        replacement: CustomerOrder,
        saveNowMs: Int64,
        bonus: WageOffer?
    ) {
        var finalWage = wage
        var finalGift = gift
        var finalBonus = self.mockAdsEnabled ? bonus : nil

        if self.state == baseState {
            let currentAdConfig = self.engine.adConfig
            self.engine = candidateEngine
            self.engine.adConfig = currentAdConfig
            self.syncStateAndApply(events: commitEvents, save: false)
        } else {
            let liveOut = self.engine.deliverOrder(
                orderID: delivery.orderID,
                preferredCells: delivery.reservedCells,
                fixedReplacement: replacement,
                now: saveNowMs
            )
            guard case .delivered(_, let liveWage, let liveGift, _) = liveOut.value.result else { return }
            finalWage = liveWage
            finalGift = liveGift
            var liveEvents = liveOut.events
            if self.mockAdsEnabled,
               let candidateBonus = liveOut.value.bonusOffer,
               self.adService.isReady(slot: .wage),
               self.engine.offerStillAllowed(.wage(candidateBonus), now: saveNowMs),
               self.activeAdOffer == nil,
               self.pendingAdCompletions.isEmpty {
                let shownOut = self.engine.offerShown(.wage(candidateBonus), now: saveNowMs)
                liveEvents.append(contentsOf: shownOut.events)
                finalBonus = candidateBonus
            } else {
                finalBonus = nil
            }
            self.syncStateAndApply(events: liveEvents, save: false)
            self.saveNeedsWrite = true
        }

        if case .orderDetail(let sheetOrder) = self.activeSheet, sheetOrder.id == delivery.orderID {
            self.activeSheet = nil
        }
        self.audio.play(.coins, userInitiated: true)
        self.notices.show(GameStrings.format("order.deliveredCoins", finalWage))
        if let finalGift {
            self.notices.show(GameStrings.format("order.customerGift", GameStrings.furnitureName(finalGift)))
        }
        if let finalBonus, self.mockAdsEnabled, self.activeAdOffer == nil {
            self.activeAdOffer = .wage(finalBonus)
        }
    }

    private func scheduleAutomaticSaveRetry() {
        retryTask?.cancel()
        let delayIndex = min(saveRetryDelays.count - 1, max(0, saveRetry.failures - 1))
        let delay = saveRetryDelays[delayIndex]
        retryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.retryTask = nil
            self.saveNeedsWrite = true
            if self.saveTask == nil {
                self.startSaveLoop()
            }
        }
    }

    private func applyLanguagePreference() {
        GameLocalization.shared.language = state.settings.language
            ?? GameLanguage.preferred(in: Locale.preferredLanguages)
    }

    private func reconcileAudio() {
        audio.configure(
            settings: state.settings.audio,
            track: currentMusicTrack,
            foreground: isForeground,
            ready: isLoaded,
            now: clock()
        )
    }

    private func showTransientPose(_ pose: CatHomePose, durationMs: Int) {
        poseTask?.cancel()
        transientCatPose = pose
        poseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(durationMs))
            guard let self, !Task.isCancelled else { return }
            self.transientCatPose = nil
        }
    }

    private func showBubble(key: String) {
        bubbleTask?.cancel()
        catBubbleKey = key
        bubbleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2200))
            guard let self, !Task.isCancelled else { return }
            self.catBubbleKey = nil
        }
    }
}
