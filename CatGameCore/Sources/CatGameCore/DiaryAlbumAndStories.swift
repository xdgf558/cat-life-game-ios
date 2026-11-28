import Foundation

// MARK: - 36-Photo Treasure Album

public enum DiaryAlbum {
    public static func isOpen(_ state: DiaryGameState) -> Bool {
        let progress = DiaryHome.photoProgress(state)
        return progress.total > 0 && progress.got == progress.total
    }

    public static func progress(_ state: DiaryGameState, tier: AlbumTier? = nil) -> (got: Int, total: Int) {
        let owned = Set(state.diary.photos)
        let list = tier == nil ? DiaryCatalog.albumPhotos : DiaryCatalog.albumPhotos.filter { $0.tier == tier }
        return (list.filter { owned.contains($0.id) }.count, list.count)
    }

    public static func reqMet(
        _ state: DiaryGameState,
        photo: AlbumPhotoDef,
        now: Int64,
        calendar: Calendar = .current,
        balance: DiaryBalance = .default
    ) -> Bool {
        let r = photo.req
        let comps = DayClock.gregorianComponents(for: now, calendar: calendar)
        if let furn = r.furniture, DiaryLayout.placement(of: furn, in: state) == nil {
            return false
        }
        if r.day && !(comps.hour >= 7 && comps.hour < 17) {
            return false
        }
        if r.night && !DiaryHome.isNightHour(comps.hour) {
            return false
        }
        if r.asleep && (!DiaryHome.isNightHour(comps.hour) || DiaryHome.isHungry(state.primaryCat, balance: balance)) {
            return false
        }
        if let hours = r.hours, !hours.contains(comps.hour) {
            return false
        }
        if r.rain && !DiaryHome.isRainyDay(dayKey: state.dayKey, balance: balance) {
            return false
        }
        if r.happy && state.primaryCat.mood < balance.cat.rareMomentMoodAbove {
            return false
        }
        if let months = r.months, !months.contains(comps.month) {
            return false
        }
        if let dates = r.dates, !(comps.month == dates.month && comps.day >= dates.from && comps.day <= dates.to) {
            return false
        }
        if let minDays = r.daysTogether, DayClock.daysTogether(createdAt: state.createdAt, now: now, calendar: calendar) < minDays {
            return false
        }
        if r.allGifts && !DiaryCatalog.giftFurnitureIDs.allSatisfy({ state.home.furnitureOwned.contains($0) }) {
            return false
        }
        if r.bedroom && !DiaryProgression.roomUnlocked(state, room: .bedroom, balance: balance) {
            return false
        }
        if r.allOthers {
            let owned = Set(state.diary.photos)
            let othersComplete = DiaryCatalog.albumPhotos.allSatisfy { $0.id == photo.id || owned.contains($0.id) }
            if !othersComplete { return false }
        }
        return true
    }

    public static func rollAlbumPhoto<R: RandomSource>(
        _ state: inout DiaryGameState,
        now: Int64,
        rng: inout R,
        calendar: Calendar = .current,
        balance: DiaryBalance = .default
    ) -> String? {
        guard !state.tutorialActive, isOpen(state) else { return nil }
        let owned = Set(state.diary.photos)
        let roll = rng.nextUnit()
        let tiers: [(AlbumTier, Double)] = [
            (.dream, balance.album.dream),
            (.season, balance.album.season),
            (.cozy, balance.album.cozy),
        ]
        var cursor = 0.0
        for (tier, chance) in tiers {
            let end = cursor + chance
            if roll >= cursor && roll < end {
                let candidates = DiaryCatalog.albumPhotos.filter {
                    $0.tier == tier
                        && !owned.contains($0.id)
                        && reqMet(state, photo: $0, now: now, calendar: calendar, balance: balance)
                }
                guard let picked = rng.pick(from: candidates) else { return nil }
                state.addPhoto(picked.id, now: now)
                return picked.id
            }
            cursor = end
        }
        return nil
    }
}

// MARK: - Customer Serialized Stories & Weekend Commissions

public struct StoryUnlock: Codable, Equatable, Identifiable, Sendable {
    public let customer: CustomerID
    public let milestone: Int
    public let index: Int
    public let bonusCoins: Int

    public var id: String { "\(customer.rawValue):\(milestone)" }

    public init(customer: CustomerID, milestone: Int, index: Int, bonusCoins: Int) {
        self.customer = customer
        self.milestone = milestone
        self.index = index
        self.bonusCoins = bonusCoins
    }
}

public enum DiaryStories {
    public static func storyKey(customer: CustomerID, milestone: Int) -> String {
        "\(customer.rawValue):\(milestone)"
    }

    public static func storiesUnlocked(
        _ state: DiaryGameState,
        customer: CustomerID,
        balance: DiaryBalance = .default
    ) -> Int {
        let done = state.orders.customerProgress[customer] ?? 0
        return balance.stories.milestones.filter { done >= $0 }.count
    }

    public static func ordersToNextStory(
        _ state: DiaryGameState,
        customer: CustomerID,
        balance: DiaryBalance = .default
    ) -> Int? {
        let done = state.orders.customerProgress[customer] ?? 0
        guard let next = balance.stories.milestones.first(where: { done < $0 }) else { return nil }
        return next - done
    }

    public static func claimStory(
        _ state: inout DiaryGameState,
        customer: CustomerID,
        balance: DiaryBalance = .default
    ) -> StoryUnlock? {
        let done = state.orders.customerProgress[customer] ?? 0
        guard let idx = balance.stories.milestones.firstIndex(of: done) else { return nil }
        let key = storyKey(customer: customer, milestone: done)
        guard !state.orders.storiesSeen.contains(key) else { return nil }
        state.orders.storiesSeen.append(key)
        let bonus = balance.stories.bonusCoins[done] ?? 0
        state.coins += bonus
        return StoryUnlock(customer: customer, milestone: done, index: idx, bonusCoins: bonus)
    }

    public static func storyBackpay(
        for progress: [CustomerID: Int],
        balance: DiaryBalance = .default
    ) -> Int {
        var total = 0
        for customer in DiaryCatalog.customers {
            let done = progress[customer.id] ?? 0
            for m in balance.stories.milestones where done >= m {
                total += balance.stories.bonusCoins[m] ?? 0
            }
        }
        return total
    }

    public static func storiesSeen(
        for progress: [CustomerID: Int],
        balance: DiaryBalance = .default
    ) -> [String] {
        var seen: [String] = []
        for customer in DiaryCatalog.customers {
            let done = progress[customer.id] ?? 0
            for m in balance.stories.milestones where done >= m {
                seen.append(storyKey(customer: customer.id, milestone: m))
            }
        }
        return seen
    }

    public static func weekendWage(for items: [MergeItem], balance: DiaryBalance = .default) -> Int {
        let base = DiaryOrders.wage(for: items, balance: balance)
        let step = Double(max(1, balance.orders.wageRoundTo))
        return max(balance.orders.wageRoundTo, Int((Double(base) * balance.weekend.wageRate / step).rounded()) * balance.orders.wageRoundTo)
    }

    public static func weekendOrder(
        for state: DiaryGameState,
        week: Int,
        balance: DiaryBalance = .default
    ) -> CustomerOrder {
        var rng = SeededRNG(seed: UInt32(truncatingIfNeeded: week))
        let w = balance.weekend
        let customers = DiaryProgression.unlockedCustomers(state, balance: balance)
        let customer = rng.pick(from: customers) ?? .ajian
        let chains = MergeChain.allCases.filter { DiaryProgression.chainUnlocked(state, chain: $0, balance: balance) }
        var items: [MergeItem] = []
        for _ in 0..<w.items {
            let chain = rng.pick(from: chains) ?? .cloth
            let level = rng.nextInt(in: w.minLevel...w.maxLevel)
            items.append(MergeItem(chain: chain, level: level))
        }
        items.sort()
        return CustomerOrder(
            id: "w\(week)",
            customer: customer,
            items: items,
            wage: weekendWage(for: items, balance: balance)
        )
    }

    public static func weekendWeek(for state: DiaryGameState, balance: DiaryBalance = .default) -> Int? {
        guard !state.tutorialActive,
              state.progressLevel >= balance.weekend.level,
              DayClock.isWeekend(dayKey: state.dayKey) else {
            return nil
        }
        let week = DayClock.weekKey(for: state.dayKey)
        if let done = state.orders.weekendDoneWeek, week <= done {
            return nil
        }
        return week
    }
}

// MARK: - Milestones

public enum MilestoneID: String, Codable, CaseIterable, Identifiable, Sendable {
    case diaryHalf
    case diaryFull
    case growJunior
    case growAdult
    case maxLevel
    case day7
    case day30
    case day100

    public var id: String { rawValue }

    public var isDayMilestone: Bool {
        switch self {
        case .day7, .day30, .day100: true
        default: false
        }
    }

    public var isGrowMilestone: Bool {
        self == .growJunior || self == .growAdult
    }

    public static let dayMilestones: [(id: MilestoneID, days: Int)] = [
        (.day7, 7),
        (.day30, 30),
        (.day100, 100),
    ]
}

public enum DiaryMilestones {
    public static func reached(
        _ state: DiaryGameState,
        now: Int64? = nil,
        calendar: Calendar = .current,
        balance: DiaryBalance = .default
    ) -> [MilestoneID] {
        let progress = DiaryHome.photoProgress(state)
        var result: [MilestoneID] = []
        if progress.got > 0 && progress.got >= Int(ceil(Double(progress.total) / 2.0)) {
            result.append(.diaryHalf)
        }
        if progress.got > 0 && progress.got == progress.total {
            result.append(.diaryFull)
        }
        let level = state.primaryCat.level
        if level >= 4 { result.append(.growJunior) }
        if level >= 8 { result.append(.growAdult) }
        if level >= balance.cat.maxLevel { result.append(.maxLevel) }
        let days = DayClock.daysTogether(createdAt: state.createdAt, now: now ?? state.updatedAt, calendar: calendar)
        for entry in MilestoneID.dayMilestones where days >= entry.days {
            result.append(entry.id)
        }
        return result
    }

    public static func nextDayMilestone(
        _ state: DiaryGameState,
        now: Int64,
        seen: [MilestoneID],
        calendar: Calendar = .current,
        balance: DiaryBalance = .default
    ) -> (show: MilestoneID?, seen: [MilestoneID]) {
        let reachedDays = reached(state, now: now, calendar: calendar, balance: balance).filter(\.isDayMilestone)
        let fresh = reachedDays.filter { !seen.contains($0) }
        let kept = MilestoneID.dayMilestones.map(\.id).filter { seen.contains($0) || reachedDays.contains($0) }
        return (fresh.last, kept)
    }
}
