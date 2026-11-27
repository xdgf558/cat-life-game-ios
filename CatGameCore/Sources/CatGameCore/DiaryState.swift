import Foundation

public struct CustomerOrder: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let customer: CustomerID
    public let items: [MergeItem]
    public let wage: Int

    public init(id: String, customer: CustomerID, items: [MergeItem], wage: Int) {
        self.id = id
        self.customer = customer
        self.items = items
        self.wage = wage
    }
}

public struct CraftTarget: Codable, Equatable, Sendable {
    public let id: Int
    public let item: MergeItem
    public let orderID: String?

    public init(id: Int, item: MergeItem, orderID: String? = nil) {
        self.id = id
        self.item = item
        self.orderID = orderID
    }
}

public enum AdReward: Codable, Equatable, Sendable {
    case materials(item: MergeItem, count: Int, orderID: String?)
    case coins(amount: Int)
}

public enum ClaimStatus: String, Codable, Equatable, Sendable {
    case pending
    case granted
    case cancelled
}

public struct AdClaim: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let key: String
    public let slot: AdSlot
    public let reward: AdReward
    public var status: ClaimStatus
    public let createdAt: Int64
    public let dayKey: Int
}

public struct OwnedToy: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(item.rawID)-\(usesLeft)" }
    public let item: MergeItem
    public var usesLeft: Int

    public init(item: MergeItem, usesLeft: Int) {
        self.item = item
        self.usesLeft = usesLeft
    }
}

public struct BasketItem: Codable, Equatable, Sendable {
    public let item: MergeItem
    public let usesLeft: Int?

    public init(item: MergeItem, usesLeft: Int? = nil) {
        self.item = item
        self.usesLeft = usesLeft
    }
}

public struct OutingState: Codable, Equatable, Sendable {
    public let departAt: Int64
    public let returnAt: Int64
    public let packedItem: MergeItem?
    public let spot: OutingSpot

    public init(departAt: Int64, returnAt: Int64, packedItem: MergeItem?, spot: OutingSpot) {
        self.departAt = departAt
        self.returnAt = returnAt
        self.packedItem = packedItem
        self.spot = spot
    }
}

public struct NeighborNote: Codable, Equatable, Sendable {
    public let customer: CustomerID
    public let noteIndex: Int

    public init(customer: CustomerID, noteIndex: Int) {
        self.customer = customer
        self.noteIndex = noteIndex
    }

    public var localizationKey: String {
        String(format: "neighborNote.%@.%02d", customer.rawValue, noteIndex + 1)
    }
}

public struct OutingArrival: Codable, Equatable, Sendable {
    public let returnedAt: Int64
    public let spot: OutingSpot
    public let packedItem: MergeItem?
    public let treasure: TreasureID
    public let isNewTreasure: Bool
    public let count: Int
    public let bonusCoins: Int
    public let bonusMood: Double
    public let bonusPhoto: String?
    public let neighborNote: NeighborNote?

    public init(
        returnedAt: Int64,
        spot: OutingSpot,
        packedItem: MergeItem?,
        treasure: TreasureID,
        isNewTreasure: Bool,
        count: Int,
        bonusCoins: Int,
        bonusMood: Double,
        bonusPhoto: String?,
        neighborNote: NeighborNote?
    ) {
        self.returnedAt = returnedAt
        self.spot = spot
        self.packedItem = packedItem
        self.treasure = treasure
        self.isNewTreasure = isNewTreasure
        self.count = count
        self.bonusCoins = bonusCoins
        self.bonusMood = bonusMood
        self.bonusPhoto = bonusPhoto
        self.neighborNote = neighborNote
    }
}

public struct TreasureRecord: Codable, Equatable, Sendable {
    public var count: Int
    public var firstAt: Int64
    public var lastAt: Int64?

    public init(count: Int, firstAt: Int64, lastAt: Int64? = nil) {
        self.count = count
        self.firstAt = firstAt
        self.lastAt = lastAt
    }
}

public struct StrayState: Codable, Equatable, Sendable {
    public var trust: Int
    public var lastSeenAt: Int64?
    public var present: Bool
    public var ate: MergeItem?

    public init(trust: Int = 0, lastSeenAt: Int64? = nil, present: Bool = false, ate: MergeItem? = nil) {
        self.trust = trust
        self.lastSeenAt = lastSeenAt
        self.present = present
        self.ate = ate
    }
}

public struct CatFlags: Codable, Equatable, Sendable {
    public var toyWornOut: Bool
    public var hungry: Bool
    public var fullBelly: Bool

    public init(toyWornOut: Bool = false, hungry: Bool = false, fullBelly: Bool = false) {
        self.toyWornOut = toyWornOut
        self.hungry = hungry
        self.fullBelly = fullBelly
    }
}

public struct DiaryCatState: Codable, Equatable, Sendable {
    public let id: CatID
    public var satiety: Double
    public var mood: Double
    public var xp: Int
    public var level: Int
    public var updatedAt: Int64
    public var lastPetAt: Int64?
    public var playCount: Int
    public var feedCount: Int
    public var petCount: Int
    public var itemsTried: [MergeItem]
    public var furnitureUsed: [FurnitureID]
    public var flags: CatFlags

    public init(id: CatID, now: Int64, balance: DiaryBalance = .default) {
        self.id = id
        self.satiety = 80
        self.mood = balance.cat.moodBaseline
        self.xp = 0
        self.level = 1
        self.updatedAt = now
        self.lastPetAt = nil
        self.playCount = 0
        self.feedCount = 0
        self.petCount = 0
        self.itemsTried = []
        self.furnitureUsed = []
        self.flags = CatFlags()
    }
}

public enum WishGoal: Codable, Equatable, Hashable, Sendable {
    case play(MergeItem)
    case feed(MergeItem)
    case pet
}

public struct DailyWish: Codable, Equatable, Sendable {
    public let dayKey: Int
    public let goal: WishGoal
    public var completed: Bool

    public init(dayKey: Int, goal: WishGoal, completed: Bool = false) {
        self.dayKey = dayKey
        self.goal = goal
        self.completed = completed
    }
}

public struct PlacedFurniture: Codable, Equatable, Identifiable, Sendable {
    public let id: FurnitureID
    public var room: RoomID
    public var x: Double
    public var bottom: Double
    public var flip: Bool

    public init(id: FurnitureID, room: RoomID, x: Double, bottom: Double, flip: Bool = false) {
        self.id = id
        self.room = room
        self.x = x
        self.bottom = bottom
        self.flip = flip
    }
}

public struct EnergyState: Codable, Equatable, Sendable {
    public var current: Int
    public var updatedAt: Int64
}

public struct BoardState: Codable, Equatable, Sendable {
    public var cells: [MergeItem?]
    public var pending: [MergeItem]
}

public struct OrdersState: Codable, Equatable, Sendable {
    public var active: [CustomerOrder]
    public var nextID: Int
    public var rerollsUsedToday: Int
    public var completedTotal: Int
    public var customerProgress: [CustomerID: Int]
    public var materialAdOrderIDs: [String]
    public var storiesSeen: [String]
    public var weekendOrder: CustomerOrder?
    public var weekendDoneWeek: Int?
    public var storyBackpay: Int

    public init(
        active: [CustomerOrder],
        nextID: Int,
        rerollsUsedToday: Int,
        completedTotal: Int,
        customerProgress: [CustomerID: Int],
        materialAdOrderIDs: [String],
        storiesSeen: [String] = [],
        weekendOrder: CustomerOrder? = nil,
        weekendDoneWeek: Int? = nil,
        storyBackpay: Int = 0
    ) {
        self.active = active
        self.nextID = nextID
        self.rerollsUsedToday = rerollsUsedToday
        self.completedTotal = completedTotal
        self.customerProgress = customerProgress
        self.materialAdOrderIDs = materialAdOrderIDs
        self.storiesSeen = storiesSeen
        self.weekendOrder = weekendOrder
        self.weekendDoneWeek = weekendDoneWeek
        self.storyBackpay = storyBackpay
    }

    enum CodingKeys: String, CodingKey {
        case active, nextID, rerollsUsedToday, completedTotal, customerProgress, materialAdOrderIDs
        case storiesSeen, weekendOrder, weekendDoneWeek, storyBackpay
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        active = try c.decode([CustomerOrder].self, forKey: .active)
        nextID = try c.decode(Int.self, forKey: .nextID)
        rerollsUsedToday = try c.decode(Int.self, forKey: .rerollsUsedToday)
        completedTotal = try c.decode(Int.self, forKey: .completedTotal)
        customerProgress = try c.decode([CustomerID: Int].self, forKey: .customerProgress)
        materialAdOrderIDs = try c.decode([String].self, forKey: .materialAdOrderIDs)
        // Preserve compatibility with M1 saves that predate stories & weekend commissions.
        if let seen = try c.decodeIfPresent([String].self, forKey: .storiesSeen) {
            storiesSeen = seen
            storyBackpay = try c.decodeIfPresent(Int.self, forKey: .storyBackpay) ?? 0
        } else {
            storiesSeen = DiaryStories.storiesSeen(for: customerProgress)
            storyBackpay = DiaryStories.storyBackpay(for: customerProgress)
        }
        weekendOrder = try c.decodeIfPresent(CustomerOrder.self, forKey: .weekendOrder)
        weekendDoneWeek = try c.decodeIfPresent(Int.self, forKey: .weekendDoneWeek)
    }
}

public struct HomeState: Codable, Equatable, Sendable {
    public var toys: [OwnedToy]
    public var food: [MergeItem]
    public var furnitureOwned: [FurnitureID]
    public var layout: [PlacedFurniture]
    public var lastVisitAt: Int64?
    public var wishlist: FurnitureID?
    public var wish: DailyWish?
    // M2 additions (decoded with safe defaults for M1 saves)
    public var stray: StrayState?
    public var skinsOwned: [RoomSkinID]
    public var activeSkin: RoomSkinID
    public var basket: BasketItem?
    public var outing: OutingState?
    public var pendingArrival: OutingArrival?
    public var treasures: [TreasureID: TreasureRecord]
    public var outingsToday: Int
    public var outingsDay: Int
    public var recallUsedToday: Bool
    public var awaySatiety: Double?
    public var awayMood: Double?

    public init(
        toys: [OwnedToy],
        food: [MergeItem],
        furnitureOwned: [FurnitureID],
        layout: [PlacedFurniture],
        lastVisitAt: Int64?,
        wishlist: FurnitureID?,
        wish: DailyWish?,
        stray: StrayState? = nil,
        skinsOwned: [RoomSkinID] = [.defaultSkin],
        activeSkin: RoomSkinID = .defaultSkin,
        basket: BasketItem? = nil,
        outing: OutingState? = nil,
        pendingArrival: OutingArrival? = nil,
        treasures: [TreasureID: TreasureRecord] = [:],
        outingsToday: Int = 0,
        outingsDay: Int = 0,
        recallUsedToday: Bool = false,
        awaySatiety: Double? = nil,
        awayMood: Double? = nil
    ) {
        self.toys = toys
        self.food = food
        self.furnitureOwned = furnitureOwned
        self.layout = layout
        self.lastVisitAt = lastVisitAt
        self.wishlist = wishlist
        self.wish = wish
        self.stray = stray
        self.skinsOwned = skinsOwned
        self.activeSkin = activeSkin
        self.basket = basket
        self.outing = outing
        self.pendingArrival = pendingArrival
        self.treasures = treasures
        self.outingsToday = outingsToday
        self.outingsDay = outingsDay
        self.recallUsedToday = recallUsedToday
        self.awaySatiety = awaySatiety
        self.awayMood = awayMood
    }

    enum CodingKeys: String, CodingKey {
        case toys, food, furnitureOwned, layout, lastVisitAt, wishlist, wish
        case stray, skinsOwned, activeSkin
        case basket, outing, pendingArrival, treasures, outingsToday, outingsDay, recallUsedToday
        case awaySatiety, awayMood
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        toys = try c.decode([OwnedToy].self, forKey: .toys)
        food = try c.decode([MergeItem].self, forKey: .food)
        furnitureOwned = try c.decode([FurnitureID].self, forKey: .furnitureOwned)
        layout = try c.decode([PlacedFurniture].self, forKey: .layout)
        lastVisitAt = try c.decodeIfPresent(Int64.self, forKey: .lastVisitAt)
        wishlist = try c.decodeIfPresent(FurnitureID.self, forKey: .wishlist)
        wish = try c.decodeIfPresent(DailyWish.self, forKey: .wish)
        stray = try c.decodeIfPresent(StrayState.self, forKey: .stray)
        skinsOwned = try c.decodeIfPresent([RoomSkinID].self, forKey: .skinsOwned) ?? [.defaultSkin]
        activeSkin = try c.decodeIfPresent(RoomSkinID.self, forKey: .activeSkin) ?? .defaultSkin
        basket = try c.decodeIfPresent(BasketItem.self, forKey: .basket)
        outing = try c.decodeIfPresent(OutingState.self, forKey: .outing)
        pendingArrival = try c.decodeIfPresent(OutingArrival.self, forKey: .pendingArrival)
        treasures = try c.decodeIfPresent([TreasureID: TreasureRecord].self, forKey: .treasures) ?? [:]
        outingsToday = try c.decodeIfPresent(Int.self, forKey: .outingsToday) ?? 0
        outingsDay = try c.decodeIfPresent(Int.self, forKey: .outingsDay) ?? 0
        recallUsedToday = try c.decodeIfPresent(Bool.self, forKey: .recallUsedToday) ?? false
        awaySatiety = try c.decodeIfPresent(Double.self, forKey: .awaySatiety)
        awayMood = try c.decodeIfPresent(Double.self, forKey: .awayMood)
    }
}

public struct DiaryAlbumState: Codable, Equatable, Sendable {
    public var photos: [String]
    public var photoDates: [String: Int64]
}

public struct AdsState: Codable, Equatable, Sendable {
    public var used: [AdSlot: Int]
    public var refusals: [AdSlot: Int]
    public var disabledToday: [AdSlot]
    public var lastOfferAt: Int64?
    public var offeredTargetIDs: [Int]
    public var offeredMaterialKeys: [String]
    public var ledger: [AdClaim]
    public var nextClaimSeq: Int
    public var claimedKeys: [String]

    public static func empty() -> AdsState {
        AdsState(
            used: [.material: 0, .wage: 0],
            refusals: [.material: 0, .wage: 0],
            disabledToday: [],
            lastOfferAt: nil,
            offeredTargetIDs: [],
            offeredMaterialKeys: [],
            ledger: [],
            nextClaimSeq: 1,
            claimedKeys: []
        )
    }
}

public enum TutorialStep: String, Equatable, Sendable {
    case meet
    case gather
    case merge
    case bringHome
    case play
    case finish
    case done
}

public struct DiaryGameState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var createdAt: Int64
    public var updatedAt: Int64
    public var dayKey: Int
    public var coins: Int
    public var tutorialActive: Bool
    public var energy: EnergyState
    public var board: BoardState
    public var target: CraftTarget?
    public var nextTargetID: Int
    public var orders: OrdersState
    public var cats: [CatID: DiaryCatState]
    public var home: HomeState
    public var diary: DiaryAlbumState
    public var ads: AdsState
    public var settings: GameSettings

    public static func fresh(
        now: Int64,
        balance: DiaryBalance = .default,
        calendar: Calendar = .current
    ) -> DiaryGameState {
        DiaryGameState(
            schemaVersion: currentSchemaVersion,
            createdAt: now,
            updatedAt: now,
            dayKey: DayClock.dayKey(for: now, calendar: calendar),
            coins: 0,
            tutorialActive: true,
            energy: EnergyState(current: balance.energy.max, updatedAt: now),
            board: BoardState(cells: Array(repeating: nil, count: balance.board.cellCount), pending: []),
            target: nil,
            nextTargetID: 1,
            orders: OrdersState(
                active: [],
                nextID: 1,
                rerollsUsedToday: 0,
                completedTotal: 0,
                customerProgress: [.ajian: 0, .grandma: 0, .petshop: 0],
                materialAdOrderIDs: []
            ),
            cats: [.xiaoju: DiaryCatState(id: .xiaoju, now: now, balance: balance)],
            home: HomeState(
                toys: [],
                food: [],
                furnitureOwned: [],
                layout: [],
                lastVisitAt: nil,
                wishlist: nil,
                wish: nil
            ),
            diary: DiaryAlbumState(photos: [], photoDates: [:]),
            ads: .empty(),
            settings: GameSettings()
        )
    }

    public var primaryCat: DiaryCatState {
        get { cats[.xiaoju] ?? DiaryCatState(id: .xiaoju, now: updatedAt) }
        set { cats[.xiaoju] = newValue }
    }

    public var residentCatIDs: [CatID] {
        CatID.allCases.filter { cats[$0] != nil }
    }

    public var progressLevel: Int { primaryCat.level }

    public var isValid: Bool {
        guard schemaVersion == Self.currentSchemaVersion else { return false }
        guard coins >= 0, DayClock.isValidDayKey(dayKey) else { return false }
        guard DayClock.isValidTimestamp(createdAt),
              DayClock.isValidTimestamp(updatedAt),
              DayClock.isValidTimestamp(energy.updatedAt) else {
            return false
        }
        if let lastVisitAt = home.lastVisitAt, !DayClock.isValidTimestamp(lastVisitAt) {
            return false
        }
        if let wish = home.wish, !DayClock.isValidDayKey(wish.dayKey) {
            return false
        }
        if let lastOfferAt = ads.lastOfferAt, !DayClock.isValidTimestamp(lastOfferAt) {
            return false
        }
        for claim in ads.ledger {
            guard DayClock.isValidTimestamp(claim.createdAt),
                  DayClock.isValidDayKey(claim.dayKey) else {
                return false
            }
        }
        for capturedAt in diary.photoDates.values where !DayClock.isValidTimestamp(capturedAt) {
            return false
        }
        guard nextTargetID >= 1,
              orders.nextID >= 1,
              orders.rerollsUsedToday >= 0,
              orders.completedTotal >= 0,
              orders.storyBackpay >= 0,
              ads.nextClaimSeq >= 1 else {
            return false
        }
        if let weekendDone = orders.weekendDoneWeek, !DayClock.isValidDayKey(weekendDone) {
            return false
        }
        if let weekend = orders.weekendOrder, (weekend.wage <= 0 || weekend.items.isEmpty) {
            return false
        }
        let maxToyUses = DiaryBalance.default.cat.toyUses
        for toy in home.toys {
            guard toy.usesLeft >= 1, toy.usesLeft <= maxToyUses else { return false }
        }
        if let basket = home.basket {
            guard basket.item.level >= DiaryBalance.default.cat.minUsableLevel else { return false }
            if basket.item.isFood {
                guard basket.usesLeft == nil else { return false }
            } else if let uses = basket.usesLeft {
                guard uses >= 1, uses <= maxToyUses else { return false }
            }
        }
        if let outing = home.outing {
            guard DayClock.isValidTimestamp(outing.departAt),
                  DayClock.isValidTimestamp(outing.returnAt),
                  outing.returnAt >= outing.departAt else {
                return false
            }
        }
        if let arrival = home.pendingArrival {
            guard DayClock.isValidTimestamp(arrival.returnedAt),
                  arrival.count >= 1,
                  arrival.bonusCoins >= 0,
                  arrival.bonusMood.isFinite, arrival.bonusMood >= 0 else {
                return false
            }
        }
        for record in home.treasures.values {
            guard record.count >= 1, DayClock.isValidTimestamp(record.firstAt) else { return false }
            if let lastAt = record.lastAt, !DayClock.isValidTimestamp(lastAt) { return false }
        }
        guard home.outingsToday >= 0,
              (home.outingsDay == 0 || DayClock.isValidDayKey(home.outingsDay)) else {
            return false
        }
        if let awaySatiety = home.awaySatiety,
           (!awaySatiety.isFinite || !(0.0...100.0).contains(awaySatiety)) {
            return false
        }
        if let awayMood = home.awayMood,
           (!awayMood.isFinite || !(0.0...100.0).contains(awayMood)) {
            return false
        }
        if let stray = home.stray {
            guard stray.trust >= 0, stray.trust <= DiaryBalance.default.adoption.trustToAdopt else {
                return false
            }
            if let lastSeenAt = stray.lastSeenAt, !DayClock.isValidTimestamp(lastSeenAt) {
                return false
            }
            if let ate = stray.ate, !ate.isFood {
                return false
            }
        }
        guard home.skinsOwned.contains(.defaultSkin),
              home.skinsOwned.contains(home.activeSkin) else {
            return false
        }
        let ownedSet = Set(home.furnitureOwned)
        for placed in home.layout {
            guard ownedSet.contains(placed.id),
                  placed.x.isFinite, (0.0...1.0).contains(placed.x),
                  placed.bottom.isFinite, (0.0...1.0).contains(placed.bottom) else {
                return false
            }
        }
        guard board.cells.count == DiaryBalance.default.board.cellCount else { return false }
        guard energy.current >= 0, energy.current <= DiaryBalance.default.energy.max else { return false }
        guard cats[.xiaoju] != nil else { return false }
        let maxLevel = DiaryBalance.default.cat.maxLevel
        for cat in cats.values {
            guard cat.level >= 1, cat.level <= maxLevel, cat.xp >= 0,
                  cat.playCount >= 0, cat.feedCount >= 0, cat.petCount >= 0,
                  DayClock.isValidTimestamp(cat.updatedAt),
                  cat.satiety.isFinite, (0.0...100.0).contains(cat.satiety),
                  cat.mood.isFinite, (0.0...100.0).contains(cat.mood) else {
                return false
            }
            if let lastPetAt = cat.lastPetAt, !DayClock.isValidTimestamp(lastPetAt) {
                return false
            }
        }
        return true
    }

    @discardableResult
    public mutating func rollDay(now: Int64, calendar: Calendar = .current) -> Bool {
        let key = DayClock.monotonicDayKey(now: now, lastDayKey: dayKey, calendar: calendar)
        guard key != dayKey else { return false }
        dayKey = key
        orders.rerollsUsedToday = 0
        ads.used = [.material: 0, .wage: 0]
        ads.refusals = [.material: 0, .wage: 0]
        ads.disabledToday = []
        ads.offeredTargetIDs = []
        ads.offeredMaterialKeys = []
        home.recallUsedToday = false
        return true
    }

    public mutating func addPhoto(_ id: String, now: Int64) {
        if !diary.photos.contains(id) {
            diary.photos.append(id)
        }
        if diary.photoDates[id] == nil {
            diary.photoDates[id] = now
        }
    }

    /// Derived tutorial step (matches `src/core/tutorial.ts`, never gets stuck).
    public var tutorialStep: TutorialStep {
        guard tutorialActive else { return .done }
        if diary.photos.contains(DiaryCatalog.tutorialPhotoID) { return .finish }
        if home.toys.contains(where: { $0.item == DiaryCatalog.tutorialToy }) { return .play }

        var clothValue = 0
        var started = !board.pending.isEmpty
        for item in board.cells.compactMap({ $0 }) {
            if item == DiaryCatalog.tutorialToy { return .bringHome }
            started = true
            if item.chain == .cloth && item.level < DiaryCatalog.tutorialToy.level {
                clothValue += item.energyValue
            }
        }
        if clothValue >= DiaryCatalog.tutorialToy.energyValue { return .merge }
        let cat = primaryCat
        let metCat = cat.lastPetAt != nil || cat.playCount > 0 || cat.feedCount > 0
            || !home.toys.isEmpty || !home.food.isEmpty
        return (started || metCat) ? .gather : .meet
    }
}
