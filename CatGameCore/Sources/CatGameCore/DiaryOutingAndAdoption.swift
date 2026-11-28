import Foundation

// MARK: - Cat Outing, Door Basket & Treasures

public enum BasketSource: String, Sendable {
    case food
    case toy
}

public enum BasketFailure: String, Equatable, Sendable {
    case locked
    case notFound
    case tooLow
    case empty
}

public enum BasketActionResult: Equatable, Sendable {
    case updated(MergeItem)
    case failed(BasketFailure)
}

public enum RecallCatFailure: String, Equatable, Sendable {
    case notOut
    case usedToday
}

public enum RecallCatResult: Equatable, Sendable {
    case recalled
    case failed(RecallCatFailure)
}

public struct OutingSettleResult: Equatable, Sendable {
    public let departed: OutingState?
    public let arrived: OutingArrival?

    public init(departed: OutingState? = nil, arrived: OutingArrival? = nil) {
        self.departed = departed
        self.arrived = arrived
    }
}

public enum DiaryOuting {
    private static let rarityWeight: [TreasureRarity: Int] = [
        .common: 6,
        .rare: 2,
        .legend: 1,
    ]

    private static let spotNeighbor: [OutingSpot: CustomerID] = [
        .workshopAjian: .ajian,
        .shopGrandma: .grandma,
        .petshopWindow: .petshop,
    ]

    public static func outingUnlocked(_ state: DiaryGameState, balance: DiaryBalance = .default) -> Bool {
        !state.tutorialActive && state.progressLevel >= balance.outing.minLevel
    }

    public static func isCatOut(_ state: DiaryGameState, now: Int64) -> Bool {
        guard let outing = state.home.outing else { return false }
        return now < outing.returnAt
    }

    public static func basketCandidate(_ item: MergeItem, balance: DiaryBalance = .default) -> Bool {
        item.level >= balance.cat.minUsableLevel
    }

    public static func outingRNG(for state: DiaryGameState, salt: Int64) -> SeededRNG {
        let lastSec = UInt32(truncatingIfNeeded: (state.home.lastVisitAt ?? 0) / 1_000)
        let trips = UInt32(truncatingIfNeeded: state.home.outingsToday + 1) &* 2_654_435_761
        let saltTerm = UInt32(truncatingIfNeeded: salt + 1) &* 40_503
        return SeededRNG(seed: lastSec ^ trips ^ saltTerm)
    }

    public static func spotFor<R: RandomSource>(item: MergeItem?, rng: inout R) -> OutingSpot {
        guard let item else {
            return rng.pick(from: OutingSpot.allCases) ?? .alley
        }
        switch item.chain {
        case .food:
            return rng.pick(from: [.shopGrandma, .petshopWindow, .alley]) ?? .shopGrandma
        case .cloth:
            return rng.pick(from: [.garden, .garden, .alley]) ?? .garden
        case .wood:
            return rng.pick(from: [.workshopAjian, .workshopAjian, .alley]) ?? .workshopAjian
        }
    }

    public static func pickTreasure<R: RandomSource>(
        spot: OutingSpot,
        packed: MergeItem?,
        rng: inout R
    ) -> TreasureID {
        let high = (packed?.level ?? 0) >= 4
        let pool: [(id: TreasureID, weight: Int)] = DiaryCatalog.treasures
            .filter { $0.rarity != .legend || high }
            .map { def in
                let base = rarityWeight[def.rarity] ?? 1
                return (def.id, base * (def.spot == spot ? 3 : 1))
            }
        let total = pool.reduce(0) { $0 + $1.weight }
        var u = rng.nextUnit() * Double(total)
        for entry in pool {
            u -= Double(entry.weight)
            if u < 0 { return entry.id }
        }
        return pool.last?.id ?? .ginkgo
    }

    public static func pickNeighborNote(
        _ state: DiaryGameState,
        outing: OutingState,
        balance: DiaryBalance = .default
    ) -> NeighborNote? {
        var rng = outingRNG(for: state, salt: 11 + (outing.returnAt / 1_000))
        guard rng.nextUnit() < balance.outing.neighborNoteChance else { return nil }
        let known = DiaryProgression.unlockedCustomers(state, balance: balance)
        guard !known.isEmpty else { return nil }
        let preferred = spotNeighbor[outing.spot]
        let customer: CustomerID = if let preferred, known.contains(preferred) {
            preferred
        } else {
            rng.pick(from: known) ?? known[0]
        }
        let idx = rng.nextInt(in: 0...2)
        return NeighborNote(customer: customer, noteIndex: idx)
    }

    private static func diaryComplete(_ state: DiaryGameState) -> Bool {
        let owned = Set(state.diary.photos)
        return DiaryCatalog.photos.allSatisfy { owned.contains($0.id) }
    }

    public static func arrive(
        _ state: inout DiaryGameState,
        outing: OutingState,
        calendar: Calendar = .current,
        balance: DiaryBalance = .default
    ) -> OutingArrival {
        let cfg = balance.outing
        var rng = outingRNG(for: state, salt: 7 + (outing.returnAt / 1_000))
        let treasure = pickTreasure(spot: outing.spot, packed: outing.packedItem, rng: &rng)
        let existing = state.home.treasures[treasure]
        let isNew = existing == nil
        let count = treasureTimes(state, id: treasure) + 1
        state.home.treasures[treasure] = TreasureRecord(
            count: count,
            firstAt: existing?.firstAt ?? outing.returnAt,
            lastAt: outing.returnAt
        )
        let bonusCoins = treasure == .coin ? cfg.coinTreasureBonus : 0
        state.coins += bonusCoins
        var cat = state.primaryCat
        let beforeMood = cat.mood
        let intendedBonus = isNew ? 0.0 : cfg.repeatMoodBonus
        cat.mood = min(100.0, cat.mood + intendedBonus)
        let bonusMood = max(0.0, cat.mood - beforeMood)
        state.primaryCat = cat

        var bonusPhoto: String? = nil
        let high = (outing.packedItem?.level ?? 0) >= 4
        if !diaryComplete(state),
           rng.nextUnit() < (high ? cfg.bonusPhotoChanceHigh : cfg.bonusPhotoChance) {
            let candidates = DiaryHome.dailyCandidates(state, at: outing.returnAt, calendar: calendar, balance: balance)
            if let picked = rng.pick(from: candidates) {
                bonusPhoto = picked
                state.addPhoto(picked, now: outing.returnAt)
            }
        }
        let note = pickNeighborNote(state, outing: outing, balance: balance)
        let arrival = OutingArrival(
            returnedAt: outing.returnAt,
            spot: outing.spot,
            packedItem: outing.packedItem,
            treasure: treasure,
            isNewTreasure: isNew,
            count: count,
            bonusCoins: bonusCoins,
            bonusMood: bonusMood,
            bonusPhoto: bonusPhoto,
            neighborNote: note
        )
        state.home.outing = nil
        state.home.pendingArrival = arrival
        return arrival
    }

    public static func settleAway(
        _ state: inout DiaryGameState,
        now: Int64,
        calendar: Calendar = .current,
        balance: DiaryBalance = .default
    ) -> OutingSettleResult {
        let cfg = balance.outing
        if let activeOuting = state.home.outing {
            guard now >= activeOuting.returnAt else { return OutingSettleResult() }
            DiaryHome.settleTrip(&state, trip: activeOuting, until: activeOuting.returnAt, depart: false, balance: balance)
            let arrival = arrive(&state, outing: activeOuting, calendar: calendar, balance: balance)
            return OutingSettleResult(departed: nil, arrived: arrival)
        }
        guard state.home.pendingArrival == nil, outingUnlocked(state, balance: balance) else {
            return OutingSettleResult()
        }
        guard let last = state.home.lastVisitAt,
              now >= last,
              DayClock.elapsedMs(from: last, to: now) >= cfg.minAwayMs else {
            return OutingSettleResult()
        }
        var rng = outingRNG(for: state, salt: 1)
        let roll = rng.nextUnit()
        let delayMs = Int64((Double(cfg.minAwayMs) * (0.3 + 0.7 * rng.nextUnit())).rounded())
        let departAt = last + delayMs
        let departHour = DayClock.gregorianComponents(for: departAt, calendar: calendar).hour
        if DiaryHome.isNightHour(departHour) { return OutingSettleResult() }

        let day = DayClock.dayKey(for: departAt, calendar: calendar)
        let count = state.home.outingsDay == day ? state.home.outingsToday : 0
        if count >= cfg.maxPerDay || DiaryHome.satietyAt(state, cat: state.primaryCat, at: departAt, balance: balance) < balance.cat.hungryBelow {
            return OutingSettleResult()
        }
        let chance = state.home.basket != nil ? cfg.basketChance : cfg.baseChance
        guard roll < chance else { return OutingSettleResult() }

        let span = max(0, cfg.maxDurationMs - cfg.minDurationMs)
        let duration = cfg.minDurationMs + Int64(floor(rng.nextUnit() * Double(span + 1)))
        let packedItem = state.home.basket?.item
        state.home.basket = nil
        let outing = OutingState(
            departAt: departAt,
            returnAt: departAt + duration,
            packedItem: packedItem,
            spot: spotFor(item: packedItem, rng: &rng)
        )
        state.home.outingsDay = day
        state.home.outingsToday = count + 1
        state.home.outing = outing
        DiaryHome.settleTrip(&state, trip: outing, until: min(now, outing.returnAt), depart: true, balance: balance)
        if now >= outing.returnAt {
            let arrival = arrive(&state, outing: outing, calendar: calendar, balance: balance)
            return OutingSettleResult(departed: outing, arrived: arrival)
        }
        return OutingSettleResult(departed: outing, arrived: nil)
    }

    public static func packBasket(
        _ state: inout DiaryGameState,
        source: BasketSource,
        index: Int,
        balance: DiaryBalance = .default
    ) -> BasketActionResult {
        guard outingUnlocked(state, balance: balance) else { return .failed(.locked) }
        let picked: BasketItem
        switch source {
        case .food:
            guard state.home.food.indices.contains(index) else { return .failed(.notFound) }
            let item = state.home.food[index]
            guard basketCandidate(item, balance: balance) else { return .failed(.tooLow) }
            state.home.food.remove(at: index)
            picked = BasketItem(item: item, usesLeft: nil)
        case .toy:
            guard state.home.toys.indices.contains(index) else { return .failed(.notFound) }
            let toy = state.home.toys[index]
            guard basketCandidate(toy.item, balance: balance) else { return .failed(.tooLow) }
            state.home.toys.remove(at: index)
            picked = BasketItem(item: toy.item, usesLeft: toy.usesLeft)
        }
        if let existing = state.home.basket {
            returnToHome(&state, basket: existing, balance: balance)
        }
        state.home.basket = picked
        return .updated(picked.item)
    }

    private static func returnToHome(_ state: inout DiaryGameState, basket: BasketItem, balance: DiaryBalance) {
        if basket.item.isFood {
            state.home.food.append(basket.item)
        } else {
            let uses = max(1, min(balance.cat.toyUses, basket.usesLeft ?? balance.cat.toyUses))
            state.home.toys.append(OwnedToy(item: basket.item, usesLeft: uses))
        }
    }

    public static func unpackBasket(_ state: inout DiaryGameState, balance: DiaryBalance = .default) -> BasketActionResult {
        guard let existing = state.home.basket else { return .failed(.empty) }
        returnToHome(&state, basket: existing, balance: balance)
        state.home.basket = nil
        return .updated(existing.item)
    }

    public static func recallCat(_ state: inout DiaryGameState, now: Int64) -> RecallCatResult {
        guard isCatOut(state, now: now) else { return .failed(.notOut) }
        guard !state.home.recallUsedToday else { return .failed(.usedToday) }
        state.home.outing = nil
        state.home.recallUsedToday = true
        return .recalled
    }

    public static func claimArrival(_ state: inout DiaryGameState) -> OutingArrival? {
        let arrival = state.home.pendingArrival
        state.home.pendingArrival = nil
        return arrival
    }

    public static func treasureTimes(_ state: DiaryGameState, id: TreasureID) -> Int {
        guard let rec = state.home.treasures[id] else { return 0 }
        return max(1, rec.count)
    }

    public static func treasureCount(_ state: DiaryGameState) -> Int {
        TreasureID.allCases.filter { treasureTimes(state, id: $0) > 0 }.count
    }
}

// MARK: - Second Cat "Xueqiu" Stray Encounter & Adoption

public struct StrayArrival: Equatable, Sendable {
    public let trust: Int
    public let ate: MergeItem?

    public init(trust: Int, ate: MergeItem?) {
        self.trust = trust
        self.ate = ate
    }
}

public enum StrayInteractResult: Equatable, Sendable {
    case met(trust: Int, ate: MergeItem?, adopted: Bool, newPhotos: [String], levelUps: [Int])
    case notHere
}

public enum XueqiuHangout: Equatable, Sendable {
    case follow
    case room(RoomID)
}

public enum DiaryAdoption {
    public static func strayUnlocked(_ state: DiaryGameState, balance: DiaryBalance = .default) -> Bool {
        !state.tutorialActive
            && state.cats[.xueqiu] == nil
            && state.progressLevel >= balance.adoption.minLevel
            && DiaryProgression.roomUnlocked(state, room: .entrance, balance: balance)
    }

    private static func basketFood(_ state: DiaryGameState) -> MergeItem? {
        guard let basket = state.home.basket, basket.item.isFood else { return nil }
        return basket.item
    }

    public static func settleStray(
        _ state: inout DiaryGameState,
        now: Int64,
        balance: DiaryBalance = .default
    ) -> StrayArrival? {
        guard strayUnlocked(state, balance: balance) else { return nil }
        var stray = state.home.stray ?? StrayState()
        if stray.present {
            state.home.stray = stray
            return nil
        }
        if let lastSeen = stray.lastSeenAt {
            guard now >= lastSeen,
                  DayClock.elapsedMs(from: lastSeen, to: now) >= balance.adoption.visitCooldownMs else {
                state.home.stray = stray
                return nil
            }
        }
        let food = basketFood(state)
        let isLastStep = stray.trust >= balance.adoption.trustToAdopt - 1
        if stray.trust > 0 && food == nil && !(isLastStep && DiaryHome.isRainyDay(dayKey: state.dayKey, balance: balance)) {
            state.home.stray = stray
            return nil
        }
        let ate: MergeItem? = (stray.trust > 0) ? food : nil
        if ate != nil {
            state.home.basket = nil
        }
        stray.present = true
        stray.ate = ate
        state.home.stray = stray
        return StrayArrival(trust: stray.trust, ate: ate)
    }

    public static func interactStray(
        _ state: inout DiaryGameState,
        now: Int64,
        balance: DiaryBalance = .default
    ) -> StrayInteractResult {
        guard var stray = state.home.stray, stray.present, state.cats[.xueqiu] == nil else {
            return .notHere
        }
        let ate = stray.ate
        stray.trust += 1
        stray.present = false
        stray.ate = nil
        stray.lastSeenAt = now
        let adopted = stray.trust >= balance.adoption.trustToAdopt
        if !adopted {
            state.home.stray = stray
            return .met(trust: stray.trust, ate: ate, adopted: false, newPhotos: [], levelUps: [])
        }
        state.cats[.xueqiu] = DiaryCatState(id: .xueqiu, now: now, balance: balance)
        state.home.stray = nil
        let newPhotos = DiaryHome.collectPhotos(&state, catID: .xueqiu, now: now)
        var xueqiu = state.cats[.xueqiu]!
        let levelUps = newPhotos.isEmpty
            ? []
            : DiaryProgression.addXP(&xueqiu, amount: newPhotos.count * balance.cat.xpFirstReaction, balance: balance)
        state.cats[.xueqiu] = xueqiu
        return .met(trust: stray.trust, ate: ate, adopted: true, newPhotos: newPhotos, levelUps: levelUps)
    }

    public static func xueqiuHangout(
        _ state: DiaryGameState,
        visitAt: Int64,
        balance: DiaryBalance = .default
    ) -> XueqiuHangout {
        var rng = SeededRNG(seed: UInt32(truncatingIfNeeded: visitAt / 1_000) &* 40_503 &+ 3)
        if rng.nextUnit() < balance.adoption.followChance {
            return .follow
        }
        let rooms = [RoomID.livingroom, .bedroom, .balcony].filter {
            DiaryProgression.roomUnlocked(state, room: $0, balance: balance)
        }
        return .room(rng.pick(from: rooms) ?? .livingroom)
    }
}
