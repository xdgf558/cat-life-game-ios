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

    func assetName(stage: CatGrowthStage = .kitten, cat: CatID = .primary) -> String {
        if cat == .xueqiu {
            return "cat_xueqiu_\(rawValue)"
        }
        switch stage {
        case .kitten: return "cat_\(rawValue)"
        case .junior: return "cat_junior_\(rawValue)"
        case .adult: return "cat_adult_\(rawValue)"
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
    case basket

    var id: String {
        switch self {
        case .shop: "shop"
        case .diary: "diary"
        case .settings: "settings"
        case .orderDetail(let order): "order-\(order.id)"
        case .basket: "basket"
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
    let isWeekend: Bool
    let weekendOrder: CustomerOrder?

    init(orderID: String, reservedCells: [Int], weekendOrder: CustomerOrder? = nil) {
        self.orderID = orderID
        self.reservedCells = reservedCells
        self.isWeekend = weekendOrder != nil
        self.weekendOrder = weekendOrder
    }
}

struct PendingSkinPurchase: Equatable {
    let skinID: RoomSkinID
    let quotedPrice: Int
    let selectionRevision: Int
}

struct PendingFurniturePurchase: Equatable {
    let furnitureID: FurnitureID
    let quotedPrice: Int
}

enum PurchaseButtonStatus: Equatable {
    case saving
    case retrySave
    case available
}

enum SaveHealth: Equatable {
    case saved
    case saving
    case failed(String)
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
    private(set) var hasEntered = false
    private(set) var overlaysReady = false
    private(set) var isSaving = false
    private(set) var lastPersistedAt: Date?
    private(set) var loadError: String?
    private(set) var saveError: String?

    var activeScreen: AppScreen = .home
    var activeRoom: RoomID = .livingroom
    var activeSheet: ActiveSheet? {
        didSet {
            if activeSheet != nil, let pending = pendingSeenDayMilestones, milestoneModal == pending.milestone {
                milestoneModal = nil
                pendingSeenDayMilestones = nil
            } else if activeSheet == nil {
                checkDayMilestoneIfNeeded()
            }
        }
    }
    var selectedCatID: CatID = .primary
    var isDecorating = false

    // Modals & transient UI feedback
    private(set) var photoQueue: [String] = []
    private(set) var levelUpQueue: [LevelUpModalItem] = []
    private(set) var storyQueue: [StoryUnlock] = []
    private(set) var arrivalModal: OutingArrival?
    private(set) var showingAdoptionModal = false
    private(set) var milestoneModal: MilestoneID?
    private(set) var activeAdOffer: AdOffer?
    private(set) var playingMockAdSlot: AdSlot?
    private(set) var offlineNoteID: String?
    private(set) var showingOfflineNote = false
    private(set) var catBubbleKey: String?
    private(set) var xueqiuBubbleKey: String?
    private(set) var strayBubbleKey: String?
    private(set) var transientCatPose: CatHomePose?
    private(set) var xueqiuTransientPose: CatHomePose?
    private(set) var xueqiuHangout: XueqiuHangout = .follow
    private(set) var luckyCells: Set<Int> = []
    private(set) var recentMergedCell: Int?
    private(set) var pendingOrderDeliveries: [PendingOrderDelivery] = []
    private(set) var pendingSkinPurchases: [PendingSkinPurchase] = []
    private(set) var pendingFurniturePurchases: [PendingFurniturePurchase] = []

    // Debug / testing toggles (exposed in Settings)
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
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let saveRetryDelays: [Duration]
    @ObservationIgnored private var engine: DiaryGameEngine
    @ObservationIgnored private var saveRetry = SaveRetryState()
    private var saveNeedsWrite = false
    @ObservationIgnored private var pendingAdCompletions: [PendingAdCompletion] = []
    @ObservationIgnored private var pendingSeenDayMilestones: (milestone: MilestoneID, seen: [MilestoneID])?
    @ObservationIgnored private var expiredWishGuardGoal: WishGoal?
    @ObservationIgnored private var stateGeneration = 0
    @ObservationIgnored private var skinSelectionRevision = 0
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var poseTask: Task<Void, Never>?
    @ObservationIgnored private var xueqiuPoseTask: Task<Void, Never>?
    @ObservationIgnored private var bubbleTask: Task<Void, Never>?
    @ObservationIgnored private var xueqiuBubbleTask: Task<Void, Never>?
    @ObservationIgnored private var strayBubbleTask: Task<Void, Never>?
    @ObservationIgnored private var lastPresencePingMs: Int64 = 0
    @ObservationIgnored private var comboCount = 0
    @ObservationIgnored private var lastMergeAt: TimeInterval = -100
    @ObservationIgnored private var lastBubbleKey: String?
    @ObservationIgnored private var lastXueqiuBubbleKey: String?
    @ObservationIgnored private var isForeground = true
    @ObservationIgnored private var homeTrack: GameMusicTrack
    @ObservationIgnored private var workshopTrack: GameMusicTrack

    var currentPhotoModalID: String? { photoQueue.first }
    var currentLevelUpModal: LevelUpModalItem? { photoQueue.isEmpty ? levelUpQueue.first : nil }
    var currentStoryModal: StoryUnlock? { storyQueue.first }

    var saveHealth: SaveHealth {
        if isSaving {
            return .saving
        }
        if let saveError {
            return .failed(saveError)
        }
        if saveNeedsWrite
            || !pendingAdCompletions.isEmpty
            || !pendingOrderDeliveries.isEmpty
            || !pendingSkinPurchases.isEmpty
            || !pendingFurniturePurchases.isEmpty {
            return .saving
        }
        return .saved
    }

    var canPresentDayMilestone: Bool {
        isLoaded
            && hasEntered
            && overlaysReady
            && isForeground
            && activeScreen == .home
            && !isDecorating
            && activeSheet == nil
            && !showingAdoptionModal
            && arrivalModal == nil
            && currentStoryModal == nil
            && playingMockAdSlot == nil
    }

    // AdOfferOverlayView is hidden behind cover, overlay reveal delay, sheets, decorate mode, or higher-priority modals in DiaryRootView.
    var canPresentAdOfferOverlay: Bool {
        isLoaded
            && hasEntered
            && overlaysReady
            && isForeground
            && !isDecorating
            && activeSheet == nil
            && currentPhotoModalID == nil
            && currentLevelUpModal == nil
            && currentStoryModal == nil
            && arrivalModal == nil
            && !showingAdoptionModal
            && milestoneModal == nil
            && playingMockAdSlot == nil
    }

    var reservedBoardCells: Set<Int> { Set(pendingOrderDeliveries.flatMap(\.reservedCells)) }

    var isXiaojuOut: Bool { DiaryOuting.isCatOut(state, now: nowMs) }
    var hasXueqiu: Bool { state.cats[.xueqiu] != nil }
    var isStrayPresentAtEntrance: Bool { state.home.stray?.present == true && !hasXueqiu }
    var isXueqiuInActiveRoom: Bool {
        guard hasXueqiu, activeRoom != .entrance else { return false }
        switch xueqiuHangout {
        case .follow: return true
        case .room(let room): return room == activeRoom
        }
    }
    var unlockedRooms: [RoomID] {
        RoomID.allCases.filter { DiaryProgression.roomUnlocked(state, room: $0, balance: engine.balance) }
    }
    var storedFurnitureIDs: [FurnitureID] { DiaryLayout.storedFurniture(in: state) }
    var extraPhotoProgress: (got: Int, total: Int) { DiaryHome.extraPhotoProgress(state) }
    var albumProgress: (got: Int, total: Int) { DiaryAlbum.progress(state) }
    var isAlbumOpen: Bool { DiaryAlbum.isOpen(state) }
    var treasureCount: Int { DiaryOuting.treasureCount(state) }
    var reachedMilestones: [MilestoneID] {
        DiaryMilestones.reached(state, now: nowMs, calendar: calendar, balance: engine.balance)
    }
    var isNightSaleActive: Bool {
        DiaryThemes.isNightSaleTime(now: nowMs, calendar: calendar, balance: engine.balance)
    }
    var effectiveSelectedCatID: CatID {
        (selectedCatID == .xueqiu && hasXueqiu) ? .xueqiu : .primary
    }

    func currentFurniturePrice(_ id: FurnitureID) -> Int {
        DiaryThemes.priceNow(furniture: id, now: nowMs, calendar: calendar, balance: engine.balance)
    }

    func currentSkinPrice(_ id: RoomSkinID) -> Int {
        DiaryThemes.priceNow(skin: id, now: nowMs, calendar: calendar, balance: engine.balance)
    }

    func isFurnitureOnSale(_ id: FurnitureID) -> Bool {
        DiaryThemes.isOnNightSale(furniture: id, now: nowMs, calendar: calendar, balance: engine.balance)
    }

    func isSkinOnSale(_ id: RoomSkinID) -> Bool {
        DiaryThemes.isOnNightSale(skin: id, now: nowMs, calendar: calendar, balance: engine.balance)
    }

    func isOrderDeliveryPending(_ orderID: String) -> Bool {
        pendingOrderDeliveries.contains { $0.orderID == orderID }
    }

    var displayedWeekendOrder: CustomerOrder? {
        pendingOrderDeliveries.first(where: { $0.isWeekend })?.weekendOrder ?? state.orders.weekendOrder
    }

    var reservedPurchaseCoins: Int {
        pendingSkinPurchases.reduce(0) { $0 + $1.quotedPrice }
            + pendingFurniturePurchases.reduce(0) { $0 + $1.quotedPrice }
    }

    var availableCoinsForPurchase: Int {
        max(0, state.coins - reservedPurchaseCoins)
    }

    func isSkinPurchasePending(_ id: RoomSkinID) -> Bool {
        pendingSkinPurchases.contains { $0.skinID == id }
    }

    func skinPurchaseStatus(for id: RoomSkinID) -> PurchaseButtonStatus {
        if isSkinPurchasePending(id) {
            return isSaving ? .saving : .retrySave
        }
        return .available
    }

    func isFurniturePurchasePending(_ id: FurnitureID) -> Bool {
        pendingFurniturePurchases.contains { $0.furnitureID == id }
    }

    func furniturePurchaseStatus(for id: FurnitureID) -> PurchaseButtonStatus {
        if isFurniturePurchasePending(id) {
            return isSaving ? .saving : .retrySave
        }
        return .available
    }

    func isCellReserved(_ index: Int) -> Bool {
        reservedBoardCells.contains(index)
    }

    func canDeliverOrder(_ order: CustomerOrder) -> Bool {
        let isActive = state.orders.active.contains(where: { $0.id == order.id })
            || displayedWeekendOrder?.id == order.id
        guard !isOrderDeliveryPending(order.id), isActive else {
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

    var displayedCatPose: CatHomePose { displayedPose(for: .primary) }

    func displayedPose(for catID: CatID) -> CatHomePose {
        if catID == .xueqiu {
            if let transient = xueqiuTransientPose { return transient }
            if let xq = state.cats[.xueqiu], DiaryHome.isHungry(xq) { return .hungry }
            if sceneLight == .night { return .sleep }
            return .idle
        }
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
        userDefaults: UserDefaults = .standard,
        saveRetryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(60)]
    ) {
        self.clock = clock
        self.calendar = calendar
        self.userDefaults = userDefaults
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

    func bootstrap(enterImmediately: Bool = true) async {
        guard !isLoaded else { return }
        loadError = nil
        do {
            let loadNow = clock()
            let loaded = try await repository.loadOrCreate(now: loadNow)
            let persistedAt = await repository.lastSavedAt ?? DayClock.date(fromEpochMs: loaded.updatedAt)
            engine = DiaryGameEngine(state: loaded, adConfig: AdRemoteConfig(adEnabled: mockAdsEnabled), calendar: calendar)
            state = loaded
            lastPersistedAt = persistedAt
            applyLanguagePreference()
            isLoaded = true
            loadError = nil
            if enterImmediately {
                enterDiary(revealOverlaysImmediately: true)
            } else {
                // Keep audio settings synced (so cover haptics honor the player's toggle) without starting BGM yet.
                reconcileAudio()
            }
        } catch {
            loadError = GameStrings.text("save.loadFailed")
        }
    }

    func enterDiary(revealOverlaysImmediately: Bool = false) {
        guard isLoaded, !hasEntered else { return }
        hasEntered = true
        let startOut = engine.start(now: nowMs)
        syncStateAndApply(events: startOut.events, save: false)
        if state.orders.storyBackpay > 0 {
            let backpayOut = engine.takeStoryBackpay(now: nowMs)
            syncStateAndApply(events: backpayOut.events, save: false)
            if backpayOut.value > 0 {
                notices.show(GameStrings.format("story.backpayNotice", backpayOut.value))
            }
        }

        let visit = engine.visitHome(now: nowMs)
        lastPresencePingMs = nowMs
        xueqiuHangout = DiaryAdoption.xueqiuHangout(engine.state, visitAt: nowMs, balance: engine.balance)
        syncStateAndApply(events: visit.events, save: true)
        if state.tutorialStep == .finish && !photoQueue.contains(DiaryCatalog.tutorialPhotoID) {
            photoQueue.insert(DiaryCatalog.tutorialPhotoID, at: 0)
        }
        if let note = visit.value.offlineNoteID {
            offlineNoteID = note
            showingOfflineNote = true
        }
        reconcileAudio()
        if revealOverlaysImmediately {
            completeOverlayReveal()
        }
    }

    func completeOverlayReveal() {
        guard isLoaded, hasEntered, !overlaysReady, isForeground else { return }
        overlaysReady = true
        if activeScreen == .home {
            checkDayMilestoneIfNeeded()
        }
    }

    @discardableResult
    func refreshDayIfNeeded() -> Bool {
        guard isLoaded, hasEntered else { return false }
        let previousDayKey = state.dayKey
        let out = engine.refreshDay(now: nowMs)
        guard out.didMutate || engine.state != state else { return false }
        syncStateAndApply(events: out.events, save: true)
        return state.dayKey != previousDayKey
    }

    func tickHomePresence() {
        guard isLoaded, hasEntered, isForeground, activeScreen == .home else { return }
        _ = refreshDayIfNeeded()
        if let outing = state.home.outing, nowMs >= outing.returnAt {
            let out = engine.checkOuting(now: nowMs)
            syncStateAndApply(events: out.events, save: true)
        } else if DayClock.elapsedMs(from: lastPresencePingMs, to: nowMs) >= DayClock.minuteMs {
            lastPresencePingMs = nowMs
            let out = engine.stayHome(now: nowMs)
            syncStateAndApply(events: out.events, save: true)
        }
    }

    func retrySaveNow() {
        scheduleSave(force: true, resetBackoff: true)
    }

    func setForeground(_ foreground: Bool) {
        let wasForeground = isForeground
        isForeground = foreground
        if !foreground, isLoaded, hasEntered {
            if let pending = pendingSeenDayMilestones, milestoneModal == pending.milestone {
                milestoneModal = nil
                pendingSeenDayMilestones = nil
            }
            if activeScreen == .home {
                let out = engine.leaveHome(now: nowMs)
                syncStateAndApply(events: out.events, save: true)
            }
        } else if !wasForeground, foreground, isLoaded, hasEntered {
            overlaysReady = true
            let dayOut = engine.refreshDay(now: nowMs)
            if dayOut.didMutate || engine.state != state {
                syncStateAndApply(events: dayOut.events, save: true)
            }
            if activeScreen == .home {
                let visit = engine.visitHome(now: nowMs)
                lastPresencePingMs = nowMs
                xueqiuHangout = DiaryAdoption.xueqiuHangout(engine.state, visitAt: nowMs, balance: engine.balance)
                syncStateAndApply(events: visit.events, save: true)
                if let note = visit.value.offlineNoteID {
                    offlineNoteID = note
                    showingOfflineNote = true
                }
                checkDayMilestoneIfNeeded()
            }
        }
        reconcileAudio()
    }

    func switchScreen(to screen: AppScreen) {
        guard activeScreen != screen else { return }
        isDecorating = false
        expiredWishGuardGoal = nil
        if activeScreen == .home {
            let out = engine.leaveHome(now: nowMs)
            syncStateAndApply(events: out.events, save: true)
        }
        activeScreen = screen
        audio.play(.tap, userInitiated: true)
        if screen == .home {
            let visit = engine.visitHome(now: nowMs)
            lastPresencePingMs = nowMs
            xueqiuHangout = DiaryAdoption.xueqiuHangout(engine.state, visitAt: nowMs, balance: engine.balance)
            syncStateAndApply(events: visit.events, save: true)
            if let note = visit.value.offlineNoteID {
                offlineNoteID = note
                showingOfflineNote = true
            }
            checkDayMilestoneIfNeeded()
        }
        reconcileAudio()
    }

    func selectRoom(_ room: RoomID) {
        guard DiaryProgression.roomUnlocked(state, room: room, balance: engine.balance) else {
            let lv = DiaryProgression.unlockLevel(for: .room(room), balance: engine.balance)
            notices.show(GameStrings.format("room.lockedNotice", lv))
            return
        }
        activeRoom = room
        audio.play(.tap, userInitiated: true)
        if room == .entrance && !isDecorating {
            let strayOut = engine.checkStray(now: nowMs)
            if strayOut.value != nil {
                syncStateAndApply(events: strayOut.events, save: true)
            }
        }
    }

    func selectCat(_ catID: CatID) {
        guard state.cats[catID] != nil else { return }
        selectedCatID = catID
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
        _ = refreshDayIfNeeded()
        if let orderID {
            let exists = state.orders.active.contains(where: { $0.id == orderID })
                || state.orders.weekendOrder?.id == orderID
            guard exists else {
                if case .orderDetail(let sheetOrder) = activeSheet, sheetOrder.id == orderID {
                    activeSheet = nil
                }
                return
            }
        }
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
        if let weekend = displayedWeekendOrder, weekend.id == orderID {
            deliverWeekendOrder()
            return
        }
        guard let order = state.orders.active.first(where: { $0.id == orderID }),
              let cells = selectUnreservedCells(for: order.items, excluding: reservedBoardCells) else {
            return
        }
        pendingOrderDeliveries.append(PendingOrderDelivery(orderID: orderID, reservedCells: cells, weekendOrder: nil))
        scheduleSave(force: true, resetBackoff: true)
    }

    func deliverWeekendOrder() {
        if pendingOrderDeliveries.contains(where: { $0.isWeekend }) {
            if !isSaving {
                scheduleSave(force: true, resetBackoff: true)
            }
            return
        }
        // Evaluate weekend eligibility at tap time so late Monday taps expire cleanly,
        // while timely Sunday taps snapshot `order` and survive queued/retried writes across Monday 00:00.
        _ = refreshDayIfNeeded()
        guard let order = state.orders.weekendOrder else { return }
        guard let cells = selectUnreservedCells(for: order.items, excluding: reservedBoardCells) else {
            return
        }
        pendingOrderDeliveries.append(PendingOrderDelivery(orderID: order.id, reservedCells: cells, weekendOrder: order))
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

    // MARK: - Home, Multi-Cat, Outing, Stray & Decorate Actions

    func petCat(_ catID: CatID? = nil) {
        let target = catID ?? effectiveSelectedCatID
        selectedCatID = target
        let out = engine.pet(now: nowMs, catID: target)
        switch out.value {
        case .petted:
            syncStateAndApply(events: out.events, save: true)
            audio.play(.pet, userInitiated: true)
            audio.playPetPurrHaptics()
            showTransientPose(.pet, for: target, durationMs: 1300)
        case .failed(.outing):
            syncStateAndApply(events: out.events, save: false)
            notices.show(GameStrings.text("home.catOutNotice"))
        case .failed(.cooldown):
            syncStateAndApply(events: out.events, save: false)
            let catState = state.cats[target] ?? state.primaryCat
            let mood: CatBubbleMood = if DiaryHome.isHungry(catState) && !state.tutorialActive {
                .hungry
            } else if sceneLight == .night && !state.tutorialActive {
                .sleep
            } else {
                .normal
            }
            let lastKey = target == .xueqiu ? lastXueqiuBubbleKey : lastBubbleKey
            let key = DiaryCatalog.pickBubbleKey(mood: mood, cat: target, excluding: lastKey, randomUnit: Double.random(in: 0..<1))
            if target == .xueqiu {
                lastXueqiuBubbleKey = key
            } else {
                lastBubbleKey = key
            }
            showBubble(key: key, for: target)
            audio.play(.tap, userInitiated: true)
        case .failed:
            syncStateAndApply(events: out.events, save: false)
        }
    }

    func playWithToy(at index: Int, catID: CatID? = nil) {
        let target = catID ?? effectiveSelectedCatID
        if target == .xueqiu && !isXueqiuInActiveRoom {
            notices.show(GameStrings.text("home.xueqiuNotHere"))
            return
        }
        guard state.home.toys.indices.contains(index) else { return }
        let item = state.home.toys[index].item
        if shouldAbortItemUseAfterMidnightWishChange(for: .play(item)) { return }
        let out = engine.playWithToy(index: index, now: nowMs, catID: target)
        switch out.value {
        case .played(_, _, let wornOut):
            syncStateAndApply(events: out.events, save: true)
            audio.play(.catHappy, userInitiated: true)
            showTransientPose(.play, for: target, durationMs: 1400)
            if wornOut { notices.show(GameStrings.text("home.toyWornOut")) }
        case .failed(.outing):
            syncStateAndApply(events: out.events, save: false)
            notices.show(GameStrings.text("home.catOutNotice"))
        case .failed(.hungry):
            syncStateAndApply(events: out.events, save: false)
            showBubble(key: target == .xueqiu ? "bubble.xueqiu.hungry.01" : "bubble.hungry.01", for: target)
            notices.show(GameStrings.format("home.hungryRefusePlayCat", GameStrings.catName(target)))
        case .failed:
            syncStateAndApply(events: out.events, save: false)
        }
    }

    func feedCat(at index: Int, catID: CatID? = nil) {
        let target = catID ?? effectiveSelectedCatID
        if target == .xueqiu && !isXueqiuInActiveRoom {
            notices.show(GameStrings.text("home.xueqiuNotHere"))
            return
        }
        guard state.home.food.indices.contains(index) else { return }
        let item = state.home.food[index]
        if shouldAbortItemUseAfterMidnightWishChange(for: .feed(item)) { return }
        let out = engine.feed(index: index, now: nowMs, catID: target)
        switch out.value {
        case .fed:
            syncStateAndApply(events: out.events, save: true)
            audio.play(.feed, userInitiated: true)
            showTransientPose(.eat, for: target, durationMs: 1600)
        case .failed(.outing):
            syncStateAndApply(events: out.events, save: false)
            notices.show(GameStrings.text("home.catOutNotice"))
        case .failed:
            syncStateAndApply(events: out.events, save: false)
        }
    }

    func openPendingArrival() {
        let out = engine.claimArrival(now: nowMs)
        guard let arrival = out.value else { return }
        arrivalModal = arrival
        audio.play(.photo, userInitiated: true)
        syncStateAndApply(events: out.events, save: true)
    }

    func dismissArrivalModal() {
        arrivalModal = nil
        checkDayMilestoneIfNeeded()
    }

    func packBasket(source: BasketSource, index: Int) {
        let out = engine.packBasket(source: source, index: index, now: nowMs)
        if case .updated(let item) = out.value {
            syncStateAndApply(events: out.events, save: true)
            audio.play(.place, userInitiated: true)
            notices.show(GameStrings.format("outing.basketPacked", GameStrings.itemName(item)))
            if activeRoom == .entrance && item.isFood {
                let strayOut = engine.checkStray(now: nowMs)
                if strayOut.value != nil {
                    syncStateAndApply(events: strayOut.events, save: true)
                }
            }
        }
    }

    func unpackBasket() {
        let out = engine.unpackBasket(now: nowMs)
        if case .updated(let item) = out.value {
            syncStateAndApply(events: out.events, save: true)
            audio.play(.tap, userInitiated: true)
            notices.show(GameStrings.format("outing.basketUnpacked", GameStrings.itemName(item)))
        }
    }

    func recallXiaoju() {
        let out = engine.recallCat(now: nowMs)
        switch out.value {
        case .recalled:
            syncStateAndApply(events: out.events, save: true)
            audio.play(.catHappy, userInitiated: true)
            notices.show(GameStrings.text("outing.recalledNotice"))
        case .failed(.usedToday):
            notices.show(GameStrings.text("outing.recallUsed"))
        case .failed(.notOut):
            break
        }
    }

    func meetStray() {
        let out = engine.meetStray(now: nowMs)
        guard case .met(let trust, let ate, let adopted, _, _) = out.value else { return }
        syncStateAndApply(events: out.events, save: true)
        audio.play(adopted ? .levelUp : .pet, userInitiated: true)
        if adopted {
            showingAdoptionModal = true
            xueqiuHangout = .follow
        } else if trust <= 1 {
            showStrayBubble(key: "stray.bubble.peek")
            notices.show(GameStrings.text("stray.met.1"))
        } else if trust == 2 {
            if let ate {
                notices.show(GameStrings.format("stray.met.2", GameStrings.itemName(ate)))
            } else {
                notices.show(GameStrings.text("stray.met.2.fallback"))
            }
        } else if trust == 3 {
            notices.show(GameStrings.text("stray.met.3"))
        } else {
            notices.show(GameStrings.text("stray.met.4"))
        }
    }

    func dismissAdoptionModal() {
        showingAdoptionModal = false
        checkDayMilestoneIfNeeded()
    }

    func enterDecorateMode() {
        guard !state.home.furnitureOwned.isEmpty else {
            notices.show(GameStrings.text("decorate.noFurniture"))
            return
        }
        isDecorating = true
        audio.play(.tap, userInitiated: true)
    }

    func exitDecorateMode() {
        isDecorating = false
        audio.play(.tap, userInitiated: true)
        checkDayMilestoneIfNeeded()
    }

    @discardableResult
    func placeFurniture(_ id: FurnitureID, room: RoomID, x: Double, bottom: Double, flip: Bool? = nil) -> Bool {
        let out = engine.placeFurniture(id: id, room: room, x: x, bottom: bottom, flip: flip, now: nowMs)
        guard case .placed = out.value else { return false }
        syncStateAndApply(events: out.events, save: true)
        audio.play(.place, userInitiated: true)
        return true
    }

    func toggleFurnitureFlip(_ id: FurnitureID) {
        let out = engine.toggleFurnitureFlip(id: id, now: nowMs)
        guard case .flipped = out.value else { return }
        syncStateAndApply(events: out.events, save: true)
        audio.play(.tap, userInitiated: true)
    }

    func storeFurniture(_ id: FurnitureID) {
        let out = engine.storeFurniture(id: id, now: nowMs)
        guard case .stored = out.value else { return }
        syncStateAndApply(events: out.events, save: true)
        audio.play(.tap, userInitiated: true)
    }

    func resetRoomLayout(_ room: RoomID) {
        let out = engine.resetRoomLayout(room: room, now: nowMs)
        syncStateAndApply(events: out.events, save: true)
        audio.play(.tap, userInitiated: true)
        notices.show(GameStrings.text("decorate.resetDone"))
    }

    func buyFurniture(_ id: FurnitureID, quoted: Int? = nil) {
        if isFurniturePurchasePending(id) {
            if !isSaving {
                scheduleSave(force: true, resetBackoff: true)
            }
            return
        }
        _ = refreshDayIfNeeded()
        guard let def = DiaryCatalog.furnitureDef(id), (def.price ?? 0) > 0 else { return }
        if state.home.furnitureOwned.contains(id) { return }
        if let lock = DiaryThemes.furnitureLock(state, id: id, balance: engine.balance) {
            switch lock {
            case .room(let room):
                let lv = DiaryProgression.unlockLevel(for: .room(room), balance: engine.balance)
                notices.show(GameStrings.format("room.lockedNotice", lv))
            case .theme(let lv):
                notices.show(GameStrings.format("shop.themeLocked", lv))
            case .xueqiu(let lv):
                notices.show(GameStrings.format("shop.xueqiuLocked", lv))
            }
            return
        }
        let price = currentFurniturePrice(id)
        if let quoted, quoted != price {
            notices.show(GameStrings.format("shop.priceChanged", price))
            return
        }
        guard availableCoinsForPurchase >= price else {
            let wishOut = engine.setWishlist(id, now: nowMs)
            syncStateAndApply(events: wishOut.events, save: true)
            notices.show(GameStrings.format("shop.wishlistPinned", GameStrings.furnitureName(id)))
            return
        }
        // Persist furniture purchase before mutating coins/ownership/layout or showing success notice.
        pendingFurniturePurchases.append(PendingFurniturePurchase(furnitureID: id, quotedPrice: price))
        scheduleSave(force: true, resetBackoff: true)
    }

    func buyRoomSkin(_ id: RoomSkinID, quoted: Int? = nil) {
        if isSkinPurchasePending(id) {
            if !isSaving {
                scheduleSave(force: true, resetBackoff: true)
            }
            return
        }
        if state.home.skinsOwned.contains(id) {
            equipRoomSkin(id)
            return
        }
        _ = refreshDayIfNeeded()
        if !DiaryThemes.themesUnlocked(state, balance: engine.balance) {
            notices.show(GameStrings.format("shop.themeLocked", DiaryThemes.themeUnlockLevel(balance: engine.balance)))
            return
        }
        let price = currentSkinPrice(id)
        if let quoted, quoted != price {
            notices.show(GameStrings.format("shop.priceChanged", price))
            return
        }
        guard availableCoinsForPurchase >= price else {
            notices.show(GameStrings.format("shop.shortCoins", max(0, price - availableCoinsForPurchase)))
            return
        }
        // Persist skin purchase before mutating coins/activeSkin or showing success notice.
        skinSelectionRevision &+= 1
        pendingSkinPurchases.append(
            PendingSkinPurchase(skinID: id, quotedPrice: price, selectionRevision: skinSelectionRevision)
        )
        scheduleSave(force: true, resetBackoff: true)
    }

    func equipRoomSkin(_ id: RoomSkinID) {
        let out = engine.equipRoomSkin(id: id, now: nowMs)
        if case .applied(let skin, _) = out.value {
            skinSelectionRevision &+= 1
            syncStateAndApply(events: out.events, save: true)
            audio.play(.tap, userInitiated: true)
            notices.show(GameStrings.format("shop.skinAppliedNotice", GameStrings.roomSkinName(skin)))
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

    func dismissCurrentStoryModal() {
        guard !storyQueue.isEmpty else { return }
        storyQueue.removeFirst()
        checkDayMilestoneIfNeeded()
    }

    func showMilestone(_ id: MilestoneID) {
        if hasEntered { overlaysReady = true }
        pendingSeenDayMilestones = nil
        milestoneModal = id
    }

    func markMilestonePresented(_ id: MilestoneID) {
        guard canPresentDayMilestone,
              milestoneModal == id,
              let pending = pendingSeenDayMilestones,
              pending.milestone == id else { return }
        pendingSeenDayMilestones = nil
        let key = seenDayMilestonesStorageKey(for: state.createdAt)
        userDefaults.set(pending.seen.map(\.rawValue), forKey: key)
    }

    func dismissMilestoneModal() {
        if let current = milestoneModal {
            markMilestonePresented(current)
        }
        milestoneModal = nil
    }

    func toggleOfflineNote() {
        showingOfflineNote.toggle()
    }

    // MARK: - Ads

    private func tryPresentMaterialAd(for chain: MergeChain) {
        guard canPresentAdOfferOverlay, activeAdOffer == nil, pendingAdCompletions.isEmpty else { return }
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
        if let invalidReason = engine.wageOfferInvalidReason(offer, now: nowMs) {
            activeAdOffer = nil
            notices.show(GameStrings.text(invalidReason == .affordable ? "ad.wageAffordable" : "ad.wagePriceUp"))
            return
        }
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
            self.checkDayMilestoneIfNeeded()
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
        let previousCreatedAt = state.createdAt
        userDefaults.removeObject(forKey: seenDayMilestonesStorageKey(for: previousCreatedAt))
        stateGeneration &+= 1
        skinSelectionRevision &+= 1
        pendingOrderDeliveries.removeAll()
        pendingSkinPurchases.removeAll()
        pendingFurniturePurchases.removeAll()
        pendingAdCompletions.removeAll()
        expiredWishGuardGoal = nil
        let out = engine.resetProgress(now: nowMs)
        photoQueue.removeAll()
        levelUpQueue.removeAll()
        storyQueue.removeAll()
        arrivalModal = nil
        showingAdoptionModal = false
        pendingSeenDayMilestones = nil
        milestoneModal = nil
        activeAdOffer = nil
        offlineNoteID = nil
        showingOfflineNote = false
        isDecorating = false
        selectedCatID = .primary
        activeScreen = .home
        activeRoom = .livingroom
        activeSheet = nil
        syncStateAndApply(events: out.events, save: true)
        notices.show(GameStrings.text("settings.resetDone"))
    }

    // MARK: - Internals

    private func seenDayMilestonesStorageKey(for createdAt: Int64) -> String {
        "CatLife.seenDayMilestones.\(createdAt)"
    }

    private func checkDayMilestoneIfNeeded() {
        guard canPresentDayMilestone, !state.tutorialActive, milestoneModal == nil else { return }
        let key = seenDayMilestonesStorageKey(for: state.createdAt)
        let savedRaw = userDefaults.stringArray(forKey: key) ?? []
        let saved = savedRaw.compactMap(MilestoneID.init(rawValue:))
        let res = DiaryMilestones.nextDayMilestone(
            state,
            now: nowMs,
            seen: saved,
            calendar: calendar,
            balance: engine.balance
        )
        guard let show = res.show else { return }
        pendingSeenDayMilestones = (show, res.seen)
        milestoneModal = show
    }

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
        if selectedCatID == .xueqiu && state.cats[.xueqiu] == nil {
            selectedCatID = .primary
        }
        if case .orderDetail(let sheetOrder) = activeSheet {
            let orderStillLive = state.orders.active.contains(where: { $0.id == sheetOrder.id })
                || displayedWeekendOrder?.id == sheetOrder.id
            if !orderStillLive {
                activeSheet = nil
            }
        }
        if case .material(let material) = activeAdOffer, let orderID = material.orderID {
            let orderStillLive = state.orders.active.contains(where: { $0.id == orderID })
                || state.orders.weekendOrder?.id == orderID
            if !orderStillLive {
                activeAdOffer = nil
            }
        }
        for event in events {
            switch event {
            case .photoTaken(_, let photoID):
                if !photoQueue.contains(photoID) { photoQueue.append(photoID) }
                audio.play(.photo)
            case .levelUp(let cat, let level, let unlocks):
                if cat == .primary {
                    levelUpQueue.append(LevelUpModalItem(level: level, unlocks: unlocks))
                }
                audio.play(.levelUp)
            case .storyUnlocked(let story):
                if !storyQueue.contains(where: { $0.id == story.id }) {
                    storyQueue.append(story)
                }
            case .strayArrived(let trust, let ate):
                if trust == 0 {
                    notices.show(GameStrings.text("stray.arrival.peek"))
                } else if let ate {
                    notices.show(GameStrings.format("stray.arrival.ate", GameStrings.itemName(ate)))
                } else {
                    notices.show(GameStrings.text("stray.arrival.rain"))
                }
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

    private func persist(_ snapshot: DiaryGameState, now: Date, generation: Int) async throws {
        try await repository.save(snapshot, now: now)
        let savedAt = await repository.lastSavedAt ?? now
        if stateGeneration == generation {
            lastPersistedAt = savedAt
        }
    }

    private func startSaveLoop() {
        isSaving = true
        saveTask = Task { [weak self] in
            guard let self else { return }
            while !self.pendingAdCompletions.isEmpty
                || !self.pendingOrderDeliveries.isEmpty
                || !self.pendingSkinPurchases.isEmpty
                || !self.pendingFurniturePurchases.isEmpty
                || self.saveNeedsWrite {
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
                            try await self.persist(candidateEngine.state, now: now, generation: generation)
                            guard self.stateGeneration == generation else { continue }
                            if self.pendingAdCompletions.first == completion {
                                self.pendingAdCompletions.removeFirst()
                            }
                            self.commitSavedAdCompletion(
                                completion: completion,
                                baseState: baseState,
                                candidateEngine: candidateEngine,
                                saveNowMs: saveNowMs,
                                commitEvents: finishOut.events
                            )
                        } else {
                            if self.pendingAdCompletions.first == completion {
                                self.pendingAdCompletions.removeFirst()
                            }
                            try await self.persist(self.state, now: now, generation: generation)
                        }
                    } else if let delivery = self.pendingOrderDeliveries.first {
                        self.saveNeedsWrite = false
                        let baseState = self.state
                        let candidateEngine = self.engine.cloned()
                        if delivery.isWeekend {
                            let out = candidateEngine.deliverWeekendOrder(
                                expectedID: delivery.orderID,
                                fallbackOrder: delivery.weekendOrder,
                                preferredCells: delivery.reservedCells,
                                now: saveNowMs
                            )
                            if case .delivered(let deliveredWeekend, let wage, let gift, _) = out.value {
                                try await self.persist(candidateEngine.state, now: now, generation: generation)
                                guard self.stateGeneration == generation else { continue }
                                self.pendingOrderDeliveries.removeAll { $0.orderID == delivery.orderID }
                                self.commitSavedWeekendDelivery(
                                    delivery: delivery,
                                    deliveredOrder: deliveredWeekend,
                                    baseState: baseState,
                                    candidateEngine: candidateEngine,
                                    commitEvents: out.events,
                                    wage: wage,
                                    gift: gift,
                                    saveNowMs: saveNowMs
                                )
                            } else {
                                self.pendingOrderDeliveries.removeAll { $0.orderID == delivery.orderID }
                                try await self.persist(self.state, now: now, generation: generation)
                            }
                        } else {
                            let out = candidateEngine.deliverOrder(
                                orderID: delivery.orderID,
                                preferredCells: delivery.reservedCells,
                                now: saveNowMs
                            )
                            if case .delivered(let deliveredOrder, let wage, let gift, _, let replacement) = out.value.result {
                                try await self.persist(candidateEngine.state, now: now, generation: generation)
                                guard self.stateGeneration == generation else { continue }
                                self.pendingOrderDeliveries.removeAll { $0.orderID == delivery.orderID }
                                self.commitSavedOrderDelivery(
                                    delivery: delivery,
                                    baseState: baseState,
                                    candidateEngine: candidateEngine,
                                    commitEvents: out.events,
                                    wage: wage,
                                    gift: gift,
                                    replacement: replacement,
                                    saveNowMs: saveNowMs
                                )
                                await self.presentPersistedWageOfferIfEligible(
                                    for: deliveredOrder,
                                    generation: generation,
                                    floorNowMs: saveNowMs
                                )
                            } else {
                                self.pendingOrderDeliveries.removeAll { $0.orderID == delivery.orderID }
                                try await self.persist(self.state, now: now, generation: generation)
                            }
                        }
                    } else if let skinPurchase = self.pendingSkinPurchases.first {
                        let hadPendingWrite = self.saveNeedsWrite
                        self.saveNeedsWrite = false
                        let baseState = self.state
                        let shouldEquipAtSave = skinPurchase.selectionRevision == self.skinSelectionRevision
                        let candidateEngine = self.engine.cloned()
                        let out = candidateEngine.buyRoomSkin(
                            id: skinPurchase.skinID,
                            quoted: skinPurchase.quotedPrice,
                            equip: shouldEquipAtSave,
                            now: saveNowMs
                        )
                        switch out.value {
                        case .applied(let skin, let price):
                            try await self.persist(candidateEngine.state, now: now, generation: generation)
                            guard self.stateGeneration == generation else { continue }
                            self.pendingSkinPurchases.removeAll { $0.skinID == skinPurchase.skinID }
                            self.commitSavedSkinPurchase(
                                purchase: skinPurchase,
                                skin: skin,
                                price: price,
                                equippedAtSave: shouldEquipAtSave,
                                baseState: baseState,
                                candidateEngine: candidateEngine,
                                commitEvents: out.events,
                                saveNowMs: saveNowMs
                            )
                        case .priceChanged(let currentPrice):
                            self.pendingSkinPurchases.removeAll { $0.skinID == skinPurchase.skinID }
                            self.notices.show(GameStrings.format("shop.priceChanged", currentPrice))
                            if hadPendingWrite {
                                try await self.persist(self.state, now: now, generation: generation)
                            }
                        case .notEnoughCoins:
                            self.pendingSkinPurchases.removeAll { $0.skinID == skinPurchase.skinID }
                            let currentPrice = self.currentSkinPrice(skinPurchase.skinID)
                            self.notices.show(GameStrings.format("shop.shortCoins", max(0, currentPrice - self.availableCoinsForPurchase)))
                            if hadPendingWrite {
                                try await self.persist(self.state, now: now, generation: generation)
                            }
                        case .themeLocked(let lv):
                            self.pendingSkinPurchases.removeAll { $0.skinID == skinPurchase.skinID }
                            self.notices.show(GameStrings.format("shop.themeLocked", lv))
                            if hadPendingWrite {
                                try await self.persist(self.state, now: now, generation: generation)
                            }
                        case .owned, .notOwned:
                            self.pendingSkinPurchases.removeAll { $0.skinID == skinPurchase.skinID }
                            if hadPendingWrite {
                                try await self.persist(self.state, now: now, generation: generation)
                            }
                        }
                    } else if let furniturePurchase = self.pendingFurniturePurchases.first {
                        let hadPendingWrite = self.saveNeedsWrite
                        self.saveNeedsWrite = false
                        let baseState = self.state
                        let candidateEngine = self.engine.cloned()
                        let buyOut = candidateEngine.buyFurniture(
                            id: furniturePurchase.furnitureID,
                            quoted: furniturePurchase.quotedPrice,
                            now: saveNowMs
                        )
                        switch buyOut.value {
                        case .bought(let furniture, let price):
                            let settleOut = candidateEngine.settleNewFurniture(now: saveNowMs)
                            try await self.persist(candidateEngine.state, now: now, generation: generation)
                            guard self.stateGeneration == generation else { continue }
                            self.pendingFurniturePurchases.removeAll { $0.furnitureID == furniturePurchase.furnitureID }
                            self.commitSavedFurniturePurchase(
                                furniture: furniture,
                                price: price,
                                baseState: baseState,
                                candidateEngine: candidateEngine,
                                commitEvents: buyOut.events + settleOut.events,
                                saveNowMs: saveNowMs
                            )
                        case .priceChanged(let currentPrice):
                            self.pendingFurniturePurchases.removeAll { $0.furnitureID == furniturePurchase.furnitureID }
                            self.notices.show(GameStrings.format("shop.priceChanged", currentPrice))
                            if hadPendingWrite {
                                try await self.persist(self.state, now: now, generation: generation)
                            }
                        case .notEnoughCoins:
                            self.pendingFurniturePurchases.removeAll { $0.furnitureID == furniturePurchase.furnitureID }
                            let wishOut = self.engine.setWishlist(furniturePurchase.furnitureID, now: saveNowMs)
                            self.syncStateAndApply(events: wishOut.events, save: false)
                            self.notices.show(GameStrings.format("shop.wishlistPinned", GameStrings.furnitureName(furniturePurchase.furnitureID)))
                            try await self.persist(self.state, now: now, generation: generation)
                        case .roomLocked(let room):
                            self.pendingFurniturePurchases.removeAll { $0.furnitureID == furniturePurchase.furnitureID }
                            let lv = DiaryProgression.unlockLevel(for: .room(room), balance: self.engine.balance)
                            self.notices.show(GameStrings.format("room.lockedNotice", lv))
                            if hadPendingWrite {
                                try await self.persist(self.state, now: now, generation: generation)
                            }
                        case .themeLocked(let lv):
                            self.pendingFurniturePurchases.removeAll { $0.furnitureID == furniturePurchase.furnitureID }
                            self.notices.show(GameStrings.format("shop.themeLocked", lv))
                            if hadPendingWrite {
                                try await self.persist(self.state, now: now, generation: generation)
                            }
                        case .xueqiuLevel(let lv):
                            self.pendingFurniturePurchases.removeAll { $0.furnitureID == furniturePurchase.furnitureID }
                            self.notices.show(GameStrings.format("shop.xueqiuLocked", lv))
                            if hadPendingWrite {
                                try await self.persist(self.state, now: now, generation: generation)
                            }
                        case .owned, .notForSale:
                            self.pendingFurniturePurchases.removeAll { $0.furnitureID == furniturePurchase.furnitureID }
                            if hadPendingWrite {
                                try await self.persist(self.state, now: now, generation: generation)
                            }
                        }
                    } else {
                        self.saveNeedsWrite = false
                        let snapshot = self.state
                        try await self.persist(snapshot, now: now, generation: generation)
                    }
                    self.saveRetry.succeeded()
                    self.saveError = nil
                } catch {
                    self.saveNeedsWrite = false
                    let hadAutomaticAttemptLeft = self.saveRetry.failures < SaveRetryState.maximumAutomaticAttempts
                    _ = self.saveRetry.failed(at: now)
                    if hadAutomaticAttemptLeft {
                        self.saveError = GameStrings.text("save.writeFailed")
                        self.scheduleAutomaticSaveRetry()
                    } else {
                        self.saveError = GameStrings.text("save.writeFailedManual")
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
        saveNowMs: Int64,
        commitEvents: [DiaryGameEvent]
    ) {
        let commitNowMs = max(saveNowMs, max(self.state.updatedAt, self.nowMs))
        var granted = true
        if self.state == baseState && commitNowMs == saveNowMs {
            let currentAdConfig = self.engine.adConfig
            self.engine = candidateEngine
            self.engine.adConfig = currentAdConfig
            self.syncStateAndApply(events: commitEvents, save: false)
        } else {
            let liveOut = self.engine.finishAd(
                claimID: completion.claimID,
                result: completion.result,
                now: commitNowMs
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

    private func commitSavedWeekendDelivery(
        delivery: PendingOrderDelivery,
        deliveredOrder: CustomerOrder,
        baseState: DiaryGameState,
        candidateEngine: DiaryGameEngine,
        commitEvents: [DiaryGameEvent],
        wage: Int,
        gift: FurnitureID?,
        saveNowMs: Int64
    ) {
        let commitNowMs = max(saveNowMs, max(self.state.updatedAt, self.nowMs))
        var finalWage = wage
        var finalGift = gift

        if self.state == baseState {
            let currentAdConfig = self.engine.adConfig
            self.engine = candidateEngine
            self.engine.adConfig = currentAdConfig
            let dayOut = self.engine.refreshDay(now: commitNowMs)
            if dayOut.didMutate {
                self.syncStateAndApply(events: commitEvents + dayOut.events, save: false)
                self.saveNeedsWrite = true
            } else {
                self.syncStateAndApply(events: commitEvents, save: false)
            }
        } else {
            let liveOut = self.engine.deliverWeekendOrder(
                expectedID: delivery.orderID,
                fallbackOrder: deliveredOrder,
                preferredCells: delivery.reservedCells,
                now: commitNowMs
            )
            guard case .delivered(_, let liveWage, let liveGift, _) = liveOut.value else { return }
            finalWage = liveWage
            finalGift = liveGift
            self.syncStateAndApply(events: liveOut.events, save: false)
            self.saveNeedsWrite = true
        }

        if case .orderDetail(let sheetOrder) = self.activeSheet, sheetOrder.id == delivery.orderID {
            self.activeSheet = nil
        }
        self.audio.play(.coins, userInitiated: true)
        self.notices.show(GameStrings.format("weekend.delivered", finalWage))
        if let finalGift {
            self.notices.show(GameStrings.format("order.customerGift", GameStrings.furnitureName(finalGift)))
        }
    }

    private func commitSavedSkinPurchase(
        purchase: PendingSkinPurchase,
        skin: RoomSkinID,
        price: Int,
        equippedAtSave: Bool,
        baseState: DiaryGameState,
        candidateEngine: DiaryGameEngine,
        commitEvents: [DiaryGameEvent],
        saveNowMs: Int64
    ) {
        let commitNowMs = max(saveNowMs, max(self.state.updatedAt, self.nowMs))
        let shouldEquipNow = purchase.selectionRevision == self.skinSelectionRevision
        if self.state == baseState && shouldEquipNow == equippedAtSave {
            let currentAdConfig = self.engine.adConfig
            self.engine = candidateEngine
            self.engine.adConfig = currentAdConfig
            let dayOut = self.engine.refreshDay(now: commitNowMs)
            if dayOut.didMutate {
                self.syncStateAndApply(events: commitEvents + dayOut.events, save: false)
                self.saveNeedsWrite = true
            } else {
                self.syncStateAndApply(events: commitEvents, save: false)
            }
        } else {
            let liveOut = self.engine.buyRoomSkin(
                id: skin,
                committedPrice: price,
                equip: shouldEquipNow,
                now: commitNowMs
            )
            guard case .applied = liveOut.value else { return }
            self.syncStateAndApply(events: liveOut.events, save: false)
            self.saveNeedsWrite = true
        }
        self.audio.play(.purchase, userInitiated: true)
        let noticeKey = shouldEquipNow ? "shop.skinAppliedNotice" : "shop.skinBoughtNotice"
        self.notices.show(GameStrings.format(noticeKey, GameStrings.roomSkinName(skin)))
    }

    private func commitSavedFurniturePurchase(
        furniture: FurnitureID,
        price: Int,
        baseState: DiaryGameState,
        candidateEngine: DiaryGameEngine,
        commitEvents: [DiaryGameEvent],
        saveNowMs: Int64
    ) {
        let commitNowMs = max(saveNowMs, max(self.state.updatedAt, self.nowMs))
        if self.state == baseState {
            let currentAdConfig = self.engine.adConfig
            self.engine = candidateEngine
            self.engine.adConfig = currentAdConfig
            let dayOut = self.engine.refreshDay(now: commitNowMs)
            if dayOut.didMutate {
                self.syncStateAndApply(events: commitEvents + dayOut.events, save: false)
                self.saveNeedsWrite = true
            } else {
                self.syncStateAndApply(events: commitEvents, save: false)
            }
        } else {
            let liveBuy = self.engine.buyFurniture(
                id: furniture,
                committedPrice: price,
                now: commitNowMs
            )
            guard case .bought = liveBuy.value else { return }
            let liveSettle = self.engine.settleNewFurniture(now: commitNowMs)
            self.syncStateAndApply(events: liveBuy.events + liveSettle.events, save: false)
            self.saveNeedsWrite = true
        }
        self.audio.play(.purchase, userInitiated: true)
        self.notices.show(GameStrings.format("shop.boughtNotice", GameStrings.furnitureName(furniture)))
        if let def = DiaryCatalog.furnitureDef(furniture) {
            self.activeRoom = def.room
        }
        if self.activeSheet == .shop {
            self.activeSheet = nil
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
        saveNowMs: Int64
    ) {
        let commitNowMs = max(saveNowMs, max(self.state.updatedAt, self.nowMs))
        var finalWage = wage
        var finalGift = gift

        if self.state == baseState {
            let currentAdConfig = self.engine.adConfig
            self.engine = candidateEngine
            self.engine.adConfig = currentAdConfig
            let dayOut = self.engine.refreshDay(now: commitNowMs)
            if dayOut.didMutate {
                self.syncStateAndApply(events: commitEvents + dayOut.events, save: false)
                self.saveNeedsWrite = true
            } else {
                self.syncStateAndApply(events: commitEvents, save: false)
            }
        } else {
            let liveOut = self.engine.deliverOrder(
                orderID: delivery.orderID,
                preferredCells: delivery.reservedCells,
                fixedReplacement: replacement,
                now: commitNowMs
            )
            guard case .delivered(_, let liveWage, let liveGift, _, _) = liveOut.value.result else { return }
            finalWage = liveWage
            finalGift = liveGift
            self.syncStateAndApply(events: liveOut.events, save: false)
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
    }

    private func presentPersistedWageOfferIfEligible(
        for deliveredOrder: CustomerOrder,
        generation: Int,
        floorNowMs: Int64
    ) async {
        var attempts = 0
        var wroteUnshownOfferToDisk = false

        while attempts < 2 {
            attempts += 1
            guard self.stateGeneration == generation,
                  self.canPresentAdOfferOverlay,
                  self.mockAdsEnabled,
                  self.activeAdOffer == nil,
                  self.pendingAdCompletions.isEmpty,
                  self.adService.isReady(slot: .wage) else {
                break
            }
            let offerNowMs = max(floorNowMs, max(self.state.updatedAt, self.nowMs))
            let baseState = self.state
            let offerEngine = self.engine.cloned()
            _ = offerEngine.refreshDay(now: offerNowMs)
            guard let bonus = DiaryAds.wageOffer(
                offerEngine.state,
                order: deliveredOrder,
                config: offerEngine.adConfig,
                now: offerNowMs,
                calendar: self.calendar,
                balance: offerEngine.balance
            ),
            offerEngine.offerStillAllowed(.wage(bonus), now: offerNowMs) else {
                break
            }
            let shownOut = offerEngine.offerShown(.wage(bonus), now: offerNowMs)
            do {
                try await self.persist(offerEngine.state, now: DayClock.date(fromEpochMs: offerNowMs), generation: generation)
                wroteUnshownOfferToDisk = true
            } catch {
                break
            }
            guard self.stateGeneration == generation,
                  self.canPresentAdOfferOverlay,
                  self.mockAdsEnabled,
                  self.activeAdOffer == nil,
                  self.pendingAdCompletions.isEmpty,
                  self.adService.isReady(slot: .wage) else {
                break
            }
            let postSaveNowMs = max(offerNowMs, max(self.state.updatedAt, self.nowMs))
            if DayClock.elapsedMs(from: offerNowMs, to: postSaveNowMs) >= 1_000 {
                continue
            }
            if self.state == baseState {
                let currentAdConfig = self.engine.adConfig
                self.engine = offerEngine
                self.engine.adConfig = currentAdConfig
                self.syncStateAndApply(events: shownOut.events, save: false)
                self.saveNeedsWrite = false
                self.activeAdOffer = .wage(bonus)
                return
            } else {
                _ = self.engine.refreshDay(now: postSaveNowMs)
                guard let liveBonus = DiaryAds.wageOffer(
                    self.engine.state,
                    order: deliveredOrder,
                    config: self.engine.adConfig,
                    now: postSaveNowMs,
                    calendar: self.calendar,
                    balance: self.engine.balance
                ),
                self.engine.offerStillAllowed(.wage(liveBonus), now: postSaveNowMs) else {
                    break
                }
                let liveShown = self.engine.offerShown(.wage(liveBonus), now: postSaveNowMs)
                self.syncStateAndApply(events: liveShown.events, save: false)
                self.saveNeedsWrite = true
                self.activeAdOffer = .wage(liveBonus)
                return
            }
        }

        if wroteUnshownOfferToDisk {
            await self.rollbackUnshownOfferSaveIfNeeded(generation: generation)
        }
    }

    private func rollbackUnshownOfferSaveIfNeeded(generation: Int) async {
        guard self.stateGeneration == generation else {
            self.saveNeedsWrite = true
            return
        }
        do {
            try await self.persist(self.state, now: self.clock(), generation: generation)
        } catch {
            self.saveNeedsWrite = true
        }
    }

    private func scheduleAutomaticSaveRetry() {
        retryTask?.cancel()
        let resolvedIndex = min(saveRetryDelays.count - 1, max(0, saveRetry.failures - 1))
        let delay = saveRetryDelays[resolvedIndex]
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
            ready: isLoaded && hasEntered,
            now: clock()
        )
    }

    private func showTransientPose(_ pose: CatHomePose, for catID: CatID, durationMs: Int) {
        if catID == .xueqiu {
            xueqiuPoseTask?.cancel()
            xueqiuTransientPose = pose
            xueqiuPoseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(durationMs))
                guard let self, !Task.isCancelled else { return }
                self.xueqiuTransientPose = nil
            }
        } else {
            poseTask?.cancel()
            transientCatPose = pose
            poseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(durationMs))
                guard let self, !Task.isCancelled else { return }
                self.transientCatPose = nil
            }
        }
    }

    private func showBubble(key: String, for catID: CatID) {
        if catID == .xueqiu {
            xueqiuBubbleTask?.cancel()
            xueqiuBubbleKey = key
            xueqiuBubbleTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(2200))
                guard let self, !Task.isCancelled else { return }
                self.xueqiuBubbleKey = nil
            }
        } else {
            bubbleTask?.cancel()
            catBubbleKey = key
            bubbleTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(2200))
                guard let self, !Task.isCancelled else { return }
                self.catBubbleKey = nil
            }
        }
    }

    private func showStrayBubble(key: String) {
        strayBubbleTask?.cancel()
        strayBubbleKey = key
        strayBubbleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2200))
            guard let self, !Task.isCancelled else { return }
            self.strayBubbleKey = nil
        }
    }
}
