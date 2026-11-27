import Foundation

// MARK: - Reward Ledger (idempotent grant + crash recovery)

public enum DiaryLedger {
    private static let ledgerKeep = 50
    private static let claimedKeysKeep = 200

    public static func createPending(
        _ state: inout DiaryGameState,
        slot: AdSlot,
        reward: AdReward,
        now: Int64,
        key: String
    ) -> String {
        let id = "c\(state.dayKey)-\(state.ads.nextClaimSeq)"
        state.ads.nextClaimSeq += 1
        state.ads.ledger.append(
            AdClaim(id: id, key: key, slot: slot, reward: reward, status: .pending, createdAt: now, dayKey: state.dayKey)
        )
        prune(&state)
        return id
    }

    public static func findClaim(_ state: DiaryGameState, id: String) -> AdClaim? {
        state.ads.ledger.first { $0.id == id }
    }

    public static func isClaimed(_ state: DiaryGameState, key: String) -> Bool {
        state.ads.claimedKeys.contains(key)
    }

    public static func pendingClaims(_ state: DiaryGameState) -> [AdClaim] {
        state.ads.ledger.filter { $0.status == .pending }
    }

    public static func grantOnce(_ state: inout DiaryGameState, id: String) -> Bool {
        guard let idx = state.ads.ledger.firstIndex(where: { $0.id == id }),
              state.ads.ledger[idx].status == .pending else {
            return false
        }
        let claim = state.ads.ledger[idx]
        if isClaimed(state, key: claim.key) {
            state.ads.ledger[idx].status = .cancelled
            return false
        }
        state.ads.ledger[idx].status = .granted
        applyReward(&state, reward: claim.reward)
        if claim.dayKey == state.dayKey {
            state.ads.used[claim.slot, default: 0] += 1
        }
        state.ads.claimedKeys.append(claim.key)
        if state.ads.claimedKeys.count > claimedKeysKeep {
            state.ads.claimedKeys.removeFirst(state.ads.claimedKeys.count - claimedKeysKeep)
        }
        if case .materials(_, _, let orderID) = claim.reward, let orderID {
            if !state.orders.materialAdOrderIDs.contains(orderID) {
                state.orders.materialAdOrderIDs.append(orderID)
            }
        }
        return true
    }

    public static func cancelClaim(_ state: inout DiaryGameState, id: String) -> Bool {
        guard let idx = state.ads.ledger.firstIndex(where: { $0.id == id }),
              state.ads.ledger[idx].status == .pending else {
            return false
        }
        state.ads.ledger[idx].status = .cancelled
        return true
    }

    /// Cancels unfinished pending claims on launch without granting unverified rewards.
    @discardableResult
    public static func recoverPendingOnStartup(_ state: inout DiaryGameState) -> Int {
        var count = 0
        for idx in state.ads.ledger.indices where state.ads.ledger[idx].status == .pending {
            state.ads.ledger[idx].status = .cancelled
            count += 1
        }
        return count
    }

    private static func applyReward(_ state: inout DiaryGameState, reward: AdReward) {
        switch reward {
        case .coins(let amount):
            state.coins += amount
        case .materials(let item, let count, _):
            for _ in 0..<count { DiaryBoard.placeItem(&state, item: item) }
        }
    }

    private static func prune(_ state: inout DiaryGameState) {
        guard state.ads.ledger.count > ledgerKeep else { return }
        let excess = state.ads.ledger.count - ledgerKeep
        var removed = 0
        state.ads.ledger = state.ads.ledger.filter { claim in
            if removed < excess && claim.status != .pending {
                removed += 1
                return false
            }
            return true
        }
    }
}

// MARK: - Ad Offers & Frequency Caps

public enum AdQuotaBlock: String, Equatable, Sendable {
    case disabled
    case newbie
    case limit
    case refused
    case interval
}

public struct MaterialOffer: Equatable, Sendable {
    public let targetID: Int
    public let target: MergeItem
    public let orderID: String?
    public let item: MergeItem
    public let count: Int
    public let completedUnits: Int
    public let totalUnits: Int
    public let catIsHungry: Bool

    public var key: String { "material:target:\(targetID)" }
}

public struct WageOffer: Equatable, Sendable {
    public let orderID: String
    public let amount: Int
    public let wishlistShortAfter: Int?
    public let furniture: FurnitureID?
    public let furniturePrice: Int?

    public var key: String { "wage:order:\(orderID)" }
}

public enum AdOffer: Equatable, Sendable {
    case material(MaterialOffer)
    case wage(WageOffer)

    public var slot: AdSlot {
        switch self {
        case .material: .material
        case .wage: .wage
        }
    }

    public var key: String {
        switch self {
        case .material(let offer): offer.key
        case .wage(let offer): offer.key
        }
    }

    public var reward: AdReward {
        switch self {
        case .material(let offer):
            .materials(item: offer.item, count: offer.count, orderID: offer.orderID)
        case .wage(let offer):
            .coins(amount: offer.amount)
        }
    }
}

public enum DiaryAds {
    public static func remainingForSlot(_ state: DiaryGameState, slot: AdSlot, config: AdRemoteConfig) -> Int {
        let pending = DiaryLedger.pendingClaims(state)
        func used(_ s: AdSlot) -> Int {
            (state.ads.used[s] ?? 0) + pending.filter { $0.slot == s && $0.dayKey == state.dayKey }.count
        }
        let totalUsed = AdSlot.allCases.reduce(0) { $0 + used($1) }
        return max(0, min(config.dailyLimit(for: slot) - used(slot), config.totalDailyLimit - totalUsed))
    }

    public static func quotaBlock(
        _ state: DiaryGameState,
        slot: AdSlot,
        config: AdRemoteConfig,
        now: Int64
    ) -> AdQuotaBlock? {
        if !config.adEnabled { return .disabled }
        if state.orders.completedTotal < config.newbieOrdersRequired { return .newbie }
        if remainingForSlot(state, slot: slot, config: config) <= 0 { return .limit }
        if state.ads.disabledToday.contains(slot) { return .refused }
        if let last = state.ads.lastOfferAt, DayClock.elapsedMs(from: last, to: now) < config.minOfferIntervalMs {
            return .interval
        }
        return nil
    }

    public static func markOfferShown(_ state: inout DiaryGameState, now: Int64) {
        state.ads.lastOfferAt = max(state.ads.lastOfferAt ?? now, now)
    }

    public static func recordRefusal(_ state: inout DiaryGameState, slot: AdSlot, config: AdRemoteConfig) {
        let next = (state.ads.refusals[slot] ?? 0) + 1
        state.ads.refusals[slot] = next
        if next >= config.refusalLimit && !state.ads.disabledToday.contains(slot) {
            state.ads.disabledToday.append(slot)
        }
    }

    public static func recordAccept(_ state: inout DiaryGameState, slot: AdSlot) {
        state.ads.refusals[slot] = 0
    }

    public static func materialGap(
        _ state: DiaryGameState,
        target: MergeItem,
        order: CustomerOrder? = nil,
        reservedCells: Set<Int> = []
    ) -> Int {
        var available: [MergeItem] = []
        for (idx, cell) in state.board.cells.enumerated() where !reservedCells.contains(idx) {
            if let item = cell { available.append(item) }
        }
        available.append(contentsOf: state.board.pending)
        if let order {
            // Reserve exact copies already fulfilling slots in this order so duplicate or
            // same-chain items don't hide the gap for remaining unsatisfied slots.
            var targetUnsatisfied = 0
            for needed in order.items {
                if let idx = available.firstIndex(of: needed) {
                    available.remove(at: idx)
                } else if needed == target {
                    targetUnsatisfied += 1
                }
            }
            guard targetUnsatisfied > 0 else { return 0 }
        } else if available.contains(target) {
            return 0
        }
        var units = 0
        for item in available where item.chain == target.chain && item.level < target.level {
            units += item.energyValue
        }
        return max(0, target.energyValue - units)
    }

    private static func materialOrderKey(orderID: String, chain: MergeChain) -> String {
        "\(orderID):\(chain.rawValue)"
    }

    public static func materialOffer(
        _ state: DiaryGameState,
        config: AdRemoteConfig,
        now: Int64,
        balance: DiaryBalance = .default,
        reservedCells: Set<Int> = [],
        excludedOrderIDs: Set<String> = []
    ) -> MaterialOffer? {
        guard let target = state.target else { return nil }
        if let orderID = target.orderID, excludedOrderIDs.contains(orderID) { return nil }
        let chain = target.item.chain
        guard DiaryProgression.chainUnlocked(state, chain: chain, balance: balance) else { return nil }
        if state.ads.offeredTargetIDs.contains(target.id) { return nil }
        if let orderID = target.orderID,
           state.ads.offeredMaterialKeys.contains(materialOrderKey(orderID: orderID, chain: chain)) {
            return nil
        }
        if DiaryLedger.isClaimed(state, key: "material:target:\(target.id)") { return nil }
        let activeOrder = target.orderID.flatMap { id in state.orders.active.first(where: { $0.id == id }) }
        let gap = materialGap(state, target: target.item, order: activeOrder, reservedCells: reservedCells)
        guard gap > 0 && gap <= config.materialMaxCount else { return nil }
        var energyCopy = state
        let energy = DiaryEnergy.settle(&energyCopy, now: now, balance: balance)
        guard !state.tutorialActive && energy < gap else { return nil }
        if quotaBlock(state, slot: .material, config: config, now: now) != nil { return nil }

        let totalUnits = target.item.energyValue
        return MaterialOffer(
            targetID: target.id,
            target: target.item,
            orderID: target.orderID,
            item: MergeItem(chain: chain, level: 1),
            count: gap,
            completedUnits: max(0, totalUnits - gap),
            totalUnits: totalUnits,
            catIsHungry: chain == .food && DiaryHome.isHungry(state.primaryCat, balance: balance)
        )
    }

    public static func autoMaterialTarget(
        _ state: DiaryGameState,
        chain: MergeChain,
        config: AdRemoteConfig,
        balance: DiaryBalance = .default,
        reservedCells: Set<Int> = [],
        excludedOrderIDs: Set<String> = []
    ) -> (item: MergeItem, orderID: String)? {
        guard DiaryProgression.chainUnlocked(state, chain: chain, balance: balance) else { return nil }
        var best: (item: MergeItem, orderID: String, gap: Int)? = nil
        for order in state.orders.active where !excludedOrderIDs.contains(order.id) {
            if state.ads.offeredMaterialKeys.contains(materialOrderKey(orderID: order.id, chain: chain)) { continue }
            for item in order.items where item.chain == chain {
                let gap = materialGap(state, target: item, order: order, reservedCells: reservedCells)
                guard gap >= 1 && gap <= config.materialMaxCount else { continue }
                if best == nil || gap < best!.gap {
                    best = (item, order.id, gap)
                }
            }
        }
        return best.map { ($0.item, $0.orderID) }
    }

    public static func markMaterialOfferShown(_ state: inout DiaryGameState, offer: MaterialOffer, now: Int64) {
        if !state.ads.offeredTargetIDs.contains(offer.targetID) {
            state.ads.offeredTargetIDs.append(offer.targetID)
        }
        if let orderID = offer.orderID {
            let key = materialOrderKey(orderID: orderID, chain: offer.target.chain)
            if !state.ads.offeredMaterialKeys.contains(key) {
                state.ads.offeredMaterialKeys.append(key)
            }
        }
        markOfferShown(&state, now: now)
    }

    public enum WageOfferInvalidReason: String, Equatable, Sendable {
        case affordable
        case priceUp
    }

    public static func nearestFurniture(
        _ state: DiaryGameState,
        now: Int64? = nil,
        calendar: Calendar = .current,
        balance: DiaryBalance = .default
    ) -> FurnitureDef? {
        func effectivePrice(_ def: FurnitureDef) -> Int {
            now.map { DiaryThemes.priceNow(furniture: def.id, now: $0, calendar: calendar, balance: balance) } ?? (def.price ?? 0)
        }
        return DiaryCatalog.shopFurniture
            .filter { def in
                !state.home.furnitureOwned.contains(def.id)
                    && DiaryThemes.furnitureLock(state, id: def.id, balance: balance) == nil
            }
            .sorted { lhs, rhs in
                let lp = effectivePrice(lhs)
                let rp = effectivePrice(rhs)
                let lGap = max(0, lp - state.coins)
                let rGap = max(0, rp - state.coins)
                if lGap != rGap { return lGap < rGap }
                return lp < rp
            }
            .first
    }

    public static func wageOfferInvalidReason(
        _ state: DiaryGameState,
        offer: WageOffer,
        config: AdRemoteConfig,
        now: Int64,
        calendar: Calendar = .current,
        balance: DiaryBalance = .default
    ) -> WageOfferInvalidReason? {
        if offer.amount >= config.wageMinAmount || offer.wishlistShortAfter != 0 {
            return nil
        }
        let short = DiaryOrders.wishlistShortfall(state, now: now, calendar: calendar, balance: balance)
        if short == 0 { return .affordable }
        if let short, short <= offer.amount { return nil }
        return .priceUp
    }

    public static func wageOfferStillValid(
        _ state: DiaryGameState,
        offer: WageOffer,
        config: AdRemoteConfig,
        now: Int64,
        calendar: Calendar = .current,
        balance: DiaryBalance = .default
    ) -> Bool {
        wageOfferInvalidReason(state, offer: offer, config: config, now: now, calendar: calendar, balance: balance) == nil
    }

    public static func wageOffer(
        _ state: DiaryGameState,
        order: CustomerOrder,
        config: AdRemoteConfig,
        now: Int64,
        calendar: Calendar = .current,
        balance: DiaryBalance = .default
    ) -> WageOffer? {
        if state.orders.materialAdOrderIDs.contains(order.id) { return nil }
        if DiaryLedger.isClaimed(state, key: "wage:order:\(order.id)") { return nil }
        if quotaBlock(state, slot: .wage, config: config, now: now) != nil { return nil }

        let short = DiaryOrders.wishlistShortfall(state, now: now, calendar: calendar, balance: balance)
        let after = short.map { max(0, $0 - order.wage) }
        // Skip small orders unless doubling completes the player's wishlisted furniture.
        if order.wage < config.wageMinAmount && !(short != nil && short! > 0 && after == 0) {
            return nil
        }
        let anchoredDef: FurnitureDef? = if short != nil, let wish = state.home.wishlist {
            DiaryCatalog.furnitureDef(wish)
        } else {
            nearestFurniture(state, now: now, calendar: calendar, balance: balance)
        }
        let effectivePrice = anchoredDef.map {
            DiaryThemes.priceNow(furniture: $0.id, now: now, calendar: calendar, balance: balance)
        }
        return WageOffer(
            orderID: order.id,
            amount: order.wage,
            wishlistShortAfter: after,
            furniture: anchoredDef?.id,
            furniturePrice: effectivePrice
        )
    }
}
