import Foundation

public enum DiaryGameEvent: Equatable, Sendable {
    case dayStarted(Int)
    case itemGenerated(chain: MergeChain, item: MergeItem, cell: Int)
    case itemsMerged(item: MergeItem, cell: Int)
    case itemSold(item: MergeItem, price: Int)
    case pendingClaimed(MergeItem)
    case orderDelivered(order: CustomerOrder, wage: Int, bonusOffer: WageOffer?)
    case giftReceived(customer: CustomerID, furniture: FurnitureID)
    case storyUnlocked(StoryUnlock)
    case orderRerolled(oldID: String, order: CustomerOrder)
    case furnitureBought(furniture: FurnitureID, price: Int)
    case roomSkinApplied(skin: RoomSkinID, price: Int)
    case broughtHome(MergeItem)
    case catPlayed(cat: CatID, item: MergeItem, wornOut: Bool)
    case catFed(cat: CatID, item: MergeItem)
    case catPetted(cat: CatID)
    case furnitureFirstUse(cat: CatID, furniture: FurnitureID)
    case homeVisited(offlineNoteID: String?)
    case catDeparted(spot: OutingSpot, packedItem: MergeItem?)
    case catReturned(OutingArrival)
    case catRecalled
    case strayArrived(trust: Int, ate: MergeItem?)
    case strayMet(trust: Int, ate: MergeItem?, adopted: Bool)
    case basketChanged(MergeItem?)
    case photoTaken(cat: CatID, photoID: String)
    case levelUp(cat: CatID, level: Int, unlocks: [UnlockRule])
    case wishCompleted(cat: CatID, goal: WishGoal, bonusXP: Int)
    case tutorialFinished
    case adOffered(AdOffer)
    case adRefused(AdSlot)
    case adStarted(slot: AdSlot, claimID: String)
    case adGranted(slot: AdSlot, claimID: String, reward: AdReward)
    case adCancelled(slot: AdSlot, claimID: String, reason: AdPlayResult)
}

public struct EngineCommandOutput<Value: Sendable>: Sendable {
    public let value: Value
    public let events: [DiaryGameEvent]
    public let didMutate: Bool
}

/// Pure, synchronous state machine mirroring `cat-work-diary/src/core/game.ts`.
public final class DiaryGameEngine {
    public private(set) var state: DiaryGameState
    public let balance: DiaryBalance
    public var adConfig: AdRemoteConfig
    public let calendar: Calendar
    private var rng: any RandomSource
    private var atHome: Bool

    public init(
        state: DiaryGameState,
        balance: DiaryBalance = .default,
        adConfig: AdRemoteConfig = .default,
        rng: any RandomSource = SystemRandomSource(),
        calendar: Calendar = .current,
        atHome: Bool = false
    ) {
        self.state = state
        self.balance = balance
        self.adConfig = adConfig
        self.rng = rng
        self.calendar = calendar
        self.atHome = atHome
    }

    public func cloned() -> DiaryGameEngine {
        DiaryGameEngine(
            state: state,
            balance: balance,
            adConfig: adConfig,
            rng: rng,
            calendar: calendar,
            atHome: atHome
        )
    }

    public func sceneLight(now: Int64) -> SceneLight {
        DiaryHome.sceneLight(now: now, savedDayKey: state.dayKey, balance: balance, calendar: calendar)
    }

    public func petCooldownLeft(now: Int64, catID: CatID = .primary) -> Int64 {
        guard let cat = state.cats[catID] else { return 0 }
        return DiaryHome.petCooldownLeft(cat, now: now, balance: balance)
    }

    @discardableResult
    public func start(now: Int64) -> EngineCommandOutput<Void> {
        run(now: now) { _ in
            DiaryLedger.recoverPendingOnStartup(&state)
            DiaryOrders.ensureOrders(&state, rng: &rng, balance: balance)
        }
    }

    @discardableResult
    public func refreshDay(now: Int64) -> EngineCommandOutput<Bool> {
        let nextKey = DayClock.monotonicDayKey(now: now, lastDayKey: state.dayKey, calendar: calendar)
        guard nextKey != state.dayKey else {
            return EngineCommandOutput(value: false, events: [], didMutate: false)
        }
        return run(now: now) { _ in true }
    }

    // MARK: - Workshop

    public func tapGenerator(chain: MergeChain, now: Int64) -> EngineCommandOutput<GeneratorTapResult> {
        run(now: now) { events in
            let result = DiaryBoard.tapGenerator(&state, chain: chain, now: now, rng: &rng, balance: balance)
            if case .generated(let item, let cell) = result {
                events.append(.itemGenerated(chain: chain, item: item, cell: cell))
            }
            return result
        }
    }

    public func moveItem(from: Int, to: Int, now: Int64) -> EngineCommandOutput<MoveItemResult> {
        run(now: now) { events in
            let result = DiaryBoard.moveItem(&state, from: from, to: to)
            if case .merged(let item) = result {
                events.append(.itemsMerged(item: item, cell: to))
            }
            return result
        }
    }

    public func claimPending(now: Int64) -> EngineCommandOutput<MergeItem?> {
        run(now: now) { events in
            let item = DiaryBoard.claimPending(&state)
            if let item { events.append(.pendingClaimed(item)) }
            return item
        }
    }

    public func sellItem(at index: Int, now: Int64) -> EngineCommandOutput<Int> {
        run(now: now) { events in
            let item = state.board.cells.indices.contains(index) ? state.board.cells[index] : nil
            let price = DiaryBoard.sellItem(&state, at: index, balance: balance)
            if let item, price > 0 { events.append(.itemSold(item: item, price: price)) }
            return price
        }
    }

    public func setTarget(item: MergeItem, orderID: String? = nil, now: Int64) -> EngineCommandOutput<Void> {
        run(now: now) { _ in
            DiaryOrders.setTarget(&state, item: item, orderID: orderID)
        }
    }

    public func clearTarget(now: Int64) -> EngineCommandOutput<Void> {
        run(now: now) { _ in
            DiaryOrders.clearTarget(&state)
        }
    }

    // MARK: - Orders & Shop

    public func deliverOrder(
        orderID: String,
        preferredCells: [Int] = [],
        fixedReplacement: CustomerOrder? = nil,
        now: Int64
    ) -> EngineCommandOutput<(result: DeliverOrderResult, bonusOffer: WageOffer?)> {
        run(now: now) { events in
            let result = DiaryOrders.deliverOrder(
                &state,
                orderID: orderID,
                preferredCells: preferredCells,
                fixedReplacement: fixedReplacement,
                rng: &rng,
                balance: balance
            )
            guard case .delivered(let order, let wage, let gift, let story, _) = result else {
                return (result, nil)
            }
            let bonus = DiaryAds.wageOffer(state, order: order, config: adConfig, now: now, calendar: calendar, balance: balance)
            events.append(.orderDelivered(order: order, wage: wage, bonusOffer: bonus))
            if let gift { events.append(.giftReceived(customer: order.customer, furniture: gift)) }
            if let story { events.append(.storyUnlocked(story)) }
            return (result, bonus)
        }
    }

    public func deliverWeekendOrder(
        expectedID: String? = nil,
        fallbackOrder: CustomerOrder? = nil,
        preferredCells: [Int] = [],
        now: Int64
    ) -> EngineCommandOutput<DeliverWeekendOrderResult> {
        run(now: now) { events in
            let result = DiaryOrders.deliverWeekendOrder(
                &state,
                expectedID: expectedID,
                fallbackOrder: fallbackOrder,
                preferredCells: preferredCells,
                balance: balance
            )
            if case .delivered(let order, let wage, let gift, let story) = result {
                events.append(.orderDelivered(order: order, wage: wage, bonusOffer: nil))
                if let gift { events.append(.giftReceived(customer: order.customer, furniture: gift)) }
                if let story { events.append(.storyUnlocked(story)) }
            }
            return result
        }
    }

    public func takeStoryBackpay(now: Int64) -> EngineCommandOutput<Int> {
        let amount = state.orders.storyBackpay
        guard amount > 0 else {
            return EngineCommandOutput(value: 0, events: [], didMutate: false)
        }
        return run(now: now) { _ in
            let credited = state.orders.storyBackpay
            state.coins += credited
            state.orders.storyBackpay = 0
            return credited
        }
    }

    public func rerollOrder(orderID: String, now: Int64) -> EngineCommandOutput<CustomerOrder?> {
        run(now: now) { events in
            let fresh = DiaryOrders.rerollOrder(&state, orderID: orderID, rng: &rng, balance: balance)
            if let fresh { events.append(.orderRerolled(oldID: orderID, order: fresh)) }
            return fresh
        }
    }

    public func buyFurniture(id: FurnitureID, quoted: Int? = nil, now: Int64) -> EngineCommandOutput<BuyFurnitureResult> {
        run(now: now) { events in
            let result = DiaryOrders.buyFurniture(&state, id: id, now: now, quoted: quoted, calendar: calendar, balance: balance)
            if case .bought(let furniture, let price) = result {
                events.append(.furnitureBought(furniture: furniture, price: price))
            }
            return result
        }
    }

    public func buyRoomSkin(id: RoomSkinID, quoted: Int? = nil, now: Int64) -> EngineCommandOutput<RoomSkinActionResult> {
        run(now: now) { events in
            let result = DiaryThemes.buyRoomSkin(&state, id: id, now: now, quoted: quoted, calendar: calendar, balance: balance)
            if case .applied(let skin, let price) = result {
                events.append(.roomSkinApplied(skin: skin, price: price))
            }
            return result
        }
    }

    public func equipRoomSkin(id: RoomSkinID, now: Int64) -> EngineCommandOutput<RoomSkinActionResult> {
        run(now: now) { events in
            let result = DiaryThemes.equipRoomSkin(&state, id: id)
            if case .applied(let skin, let price) = result {
                events.append(.roomSkinApplied(skin: skin, price: price))
            }
            return result
        }
    }

    public func setWishlist(_ id: FurnitureID?, now: Int64) -> EngineCommandOutput<Void> {
        run(now: now) { _ in
            state.home.wishlist = id
        }
    }

    // MARK: - Home, Decorate, Outing & Adoption

    public func bringHome(cellIndex: Int, now: Int64) -> EngineCommandOutput<BringHomeResult> {
        run(now: now) { events in
            let result = DiaryHome.bringHome(&state, cellIndex: cellIndex, balance: balance)
            if case .brought(let item) = result { events.append(.broughtHome(item)) }
            return result
        }
    }

    public func playWithToy(index: Int, now: Int64, catID: CatID = .primary) -> EngineCommandOutput<PlayToyResult> {
        run(now: now) { events in
            let result = DiaryHome.playWithToy(&state, toyIndex: index, now: now, catID: catID, balance: balance)
            if case .played(let reaction, let item, let wornOut) = result {
                events.append(.catPlayed(cat: catID, item: item, wornOut: wornOut))
                if reaction.wishBonus > 0 {
                    events.append(.wishCompleted(cat: catID, goal: .play(item), bonusXP: reaction.wishBonus))
                }
                emitReaction(cat: catID, photos: reaction.newPhotos, levelUps: reaction.levelUps, into: &events)
            }
            return result
        }
    }

    public func feed(index: Int, now: Int64, catID: CatID = .primary) -> EngineCommandOutput<FeedCatResult> {
        run(now: now) { events in
            let result = DiaryHome.feed(&state, foodIndex: index, now: now, catID: catID, balance: balance)
            if case .fed(let reaction, let item) = result {
                events.append(.catFed(cat: catID, item: item))
                if reaction.wishBonus > 0 {
                    events.append(.wishCompleted(cat: catID, goal: .feed(item), bonusXP: reaction.wishBonus))
                }
                emitReaction(cat: catID, photos: reaction.newPhotos, levelUps: reaction.levelUps, into: &events)
            }
            return result
        }
    }

    public func pet(now: Int64, catID: CatID = .primary) -> EngineCommandOutput<PetCatResult> {
        run(now: now) { events in
            let result = DiaryHome.pet(&state, now: now, catID: catID, balance: balance)
            if case .petted(let reaction) = result {
                events.append(.catPetted(cat: catID))
                if reaction.wishBonus > 0 {
                    events.append(.wishCompleted(cat: catID, goal: .pet, bonusXP: reaction.wishBonus))
                }
                emitReaction(cat: catID, photos: reaction.newPhotos, levelUps: reaction.levelUps, into: &events)
            }
            return result
        }
    }

    public func visitHome(now: Int64) -> EngineCommandOutput<HomeVisitResult> {
        run(now: now) { events in
            atHome = true
            let visit = DiaryHome.visitHome(&state, now: now, rng: &rng, balance: balance, calendar: calendar)
            if let departed = visit.outingDeparted {
                events.append(.catDeparted(spot: departed.spot, packedItem: departed.packedItem))
            }
            if let arrived = visit.outingArrived {
                events.append(.catReturned(arrived))
            }
            events.append(.homeVisited(offlineNoteID: visit.offlineNoteID))
            // Settle stray Xueqiu AFTER Xiaoju outing so basket ownership is first-come-first-served.
            if let stray = DiaryAdoption.settleStray(&state, now: now, balance: balance) {
                events.append(.strayArrived(trust: stray.trust, ate: stray.ate))
            }
            for catVisit in visit.cats {
                for f in catVisit.furnitureUsed {
                    events.append(.furnitureFirstUse(cat: catVisit.cat, furniture: f))
                }
                emitReaction(cat: catVisit.cat, photos: catVisit.newPhotos, levelUps: catVisit.levelUps, into: &events)
            }
            if let albumPhoto = visit.albumPhoto {
                events.append(.photoTaken(cat: .primary, photoID: albumPhoto))
            }
            return visit
        }
    }

    public func leaveHome(now: Int64) -> EngineCommandOutput<Void> {
        run(now: now) { _ in
            guard atHome else { return }
            markPresence(now: now)
            atHome = false
        }
    }

    public func stayHome(now: Int64) -> EngineCommandOutput<Void> {
        run(now: now) { _ in }
    }

    public func checkOuting(now: Int64) -> EngineCommandOutput<OutingArrival?> {
        run(now: now) { _ in
            state.home.outing == nil ? state.home.pendingArrival : nil
        }
    }

    public func claimArrival(now: Int64) -> EngineCommandOutput<OutingArrival?> {
        run(now: now) { events in
            let arrival = DiaryOuting.claimArrival(&state)
            if let bonusPhoto = arrival?.bonusPhoto {
                var cat = state.primaryCat
                let ups = DiaryProgression.addXP(&cat, amount: balance.cat.xpFirstReaction, balance: balance)
                state.primaryCat = cat
                emitReaction(cat: .primary, photos: [bonusPhoto], levelUps: ups, into: &events)
            }
            return arrival
        }
    }

    public func packBasket(source: BasketSource, index: Int, now: Int64) -> EngineCommandOutput<BasketActionResult> {
        run(now: now) { events in
            let result = DiaryOuting.packBasket(&state, source: source, index: index, balance: balance)
            if case .updated(let item) = result {
                events.append(.basketChanged(item))
            }
            return result
        }
    }

    public func unpackBasket(now: Int64) -> EngineCommandOutput<BasketActionResult> {
        run(now: now) { events in
            let result = DiaryOuting.unpackBasket(&state, balance: balance)
            if case .updated = result {
                events.append(.basketChanged(nil))
            }
            return result
        }
    }

    public func recallCat(now: Int64) -> EngineCommandOutput<RecallCatResult> {
        run(now: now) { events in
            let activeOuting = state.home.outing
            let result = DiaryOuting.recallCat(&state, now: now)
            if case .recalled = result, let activeOuting {
                let truncated = OutingState(
                    departAt: activeOuting.departAt,
                    returnAt: max(activeOuting.departAt, now),
                    packedItem: activeOuting.packedItem,
                    spot: activeOuting.spot
                )
                var cat = state.primaryCat
                DiaryHome.settleAroundTrip(&cat, trip: truncated, now: now, balance: balance)
                state.primaryCat = cat
                events.append(.catRecalled)
            }
            return result
        }
    }

    public func checkStray(now: Int64) -> EngineCommandOutput<StrayArrival?> {
        run(now: now) { events in
            let stray = DiaryAdoption.settleStray(&state, now: now, balance: balance)
            if let stray {
                events.append(.strayArrived(trust: stray.trust, ate: stray.ate))
            }
            return stray
        }
    }

    public func meetStray(now: Int64) -> EngineCommandOutput<StrayInteractResult> {
        run(now: now) { events in
            let result = DiaryAdoption.interactStray(&state, now: now, balance: balance)
            if case .met(let trust, let ate, let adopted, let newPhotos, let levelUps) = result {
                events.append(.strayMet(trust: trust, ate: ate, adopted: adopted))
                emitReaction(cat: .xueqiu, photos: newPhotos, levelUps: levelUps, into: &events)
            }
            return result
        }
    }

    public func placeFurniture(
        id: FurnitureID,
        room: RoomID,
        x: Double,
        bottom: Double,
        flip: Bool? = nil,
        now: Int64
    ) -> EngineCommandOutput<PlaceFurnitureResult> {
        run(now: now) { _ in
            DiaryLayout.placeFurniture(&state, id: id, room: room, x: x, bottom: bottom, flip: flip, balance: balance)
        }
    }

    public func toggleFurnitureFlip(id: FurnitureID, now: Int64) -> EngineCommandOutput<FlipFurnitureResult> {
        run(now: now) { _ in
            DiaryLayout.toggleFurnitureFlip(&state, id: id)
        }
    }

    public func storeFurniture(id: FurnitureID, now: Int64) -> EngineCommandOutput<StoreFurnitureResult> {
        run(now: now) { _ in
            DiaryLayout.storeFurniture(&state, id: id)
        }
    }

    public func resetRoomLayout(room: RoomID, now: Int64) -> EngineCommandOutput<Void> {
        run(now: now) { _ in
            DiaryLayout.resetRoomLayout(&state, room: room)
        }
    }

    public func settleNewFurniture(now: Int64) -> EngineCommandOutput<NewFurnitureReaction> {
        run(now: now) { events in
            let result = DiaryHome.settleNewFurniture(&state, now: now, balance: balance)
            for reaction in result.reactions {
                for f in reaction.furnitureUsed {
                    events.append(.furnitureFirstUse(cat: reaction.cat, furniture: f))
                }
                emitReaction(cat: reaction.cat, photos: reaction.newPhotos, levelUps: reaction.levelUps, into: &events)
            }
            return result
        }
    }

    public func finishTutorial(now: Int64) -> EngineCommandOutput<Void> {
        run(now: now) { events in
            guard state.tutorialActive else { return }
            state.tutorialActive = false
            DiaryWishEngine.ensureDailyWish(&state, balance: balance)
            events.append(.tutorialFinished)
        }
    }

    public func updateSettings(_ settings: GameSettings, now: Int64) -> EngineCommandOutput<Void> {
        run(now: now) { _ in
            state.settings = settings
        }
    }

    public func resetProgress(now: Int64) -> EngineCommandOutput<Void> {
        let keptSettings = state.settings
        state = DiaryGameState.fresh(now: now, balance: balance, calendar: calendar)
        state.settings = keptSettings
        atHome = false
        DiaryOrders.ensureOrders(&state, rng: &rng, balance: balance)
        return EngineCommandOutput(value: (), events: [], didMutate: true)
    }

    // MARK: - Ads

    public func materialOfferFor(
        chain: MergeChain,
        now: Int64,
        reservedCells: Set<Int> = [],
        excludedOrderIDs: Set<String> = [],
        canShow: (MaterialOffer) -> Bool = { _ in true }
    ) -> EngineCommandOutput<MaterialOffer?> {
        run(now: now) { _ in
            let current = state.target
            if let current, current.item.chain == chain,
               let offer = DiaryAds.materialOffer(
                   state,
                   config: adConfig,
                   now: now,
                   balance: balance,
                   reservedCells: reservedCells,
                   excludedOrderIDs: excludedOrderIDs
               ),
               canShow(offer) {
                return offer
            }
            guard let auto = DiaryAds.autoMaterialTarget(
                state,
                chain: chain,
                config: adConfig,
                balance: balance,
                reservedCells: reservedCells,
                excludedOrderIDs: excludedOrderIDs
            ) else {
                return nil
            }
            if let current, current.item == auto.item && current.orderID == auto.orderID {
                return nil
            }
            let prevTargetID = state.nextTargetID
            DiaryOrders.setTarget(&state, item: auto.item, orderID: auto.orderID)
            if let offer = DiaryAds.materialOffer(
                state,
                config: adConfig,
                now: now,
                balance: balance,
                reservedCells: reservedCells,
                excludedOrderIDs: excludedOrderIDs
            ),
               canShow(offer) {
                return offer
            }
            state.target = current
            state.nextTargetID = prevTargetID
            return nil
        }
    }

    public func wageOfferStillValid(_ offer: AdOffer, now: Int64) -> Bool {
        guard case .wage(let wage) = offer else { return true }
        return DiaryAds.wageOfferStillValid(state, offer: wage, config: adConfig, now: now, calendar: calendar, balance: balance)
    }

    public func wageOfferInvalidReason(_ offer: AdOffer, now: Int64) -> DiaryAds.WageOfferInvalidReason? {
        guard case .wage(let wage) = offer else { return nil }
        return DiaryAds.wageOfferInvalidReason(state, offer: wage, config: adConfig, now: now, calendar: calendar, balance: balance)
    }

    public func offerStillAllowed(_ offer: AdOffer, now: Int64) -> Bool {
        if DiaryAds.quotaBlock(state, slot: offer.slot, config: adConfig, now: now) != nil { return false }
        if DiaryLedger.isClaimed(state, key: offer.key) { return false }
        if !wageOfferStillValid(offer, now: now) { return false }
        return true
    }

    public func offerShown(_ offer: AdOffer, now: Int64) -> EngineCommandOutput<Void> {
        run(now: now) { events in
            switch offer {
            case .material(let m): DiaryAds.markMaterialOfferShown(&state, offer: m, now: now)
            case .wage: DiaryAds.markOfferShown(&state, now: now)
            }
            events.append(.adOffered(offer))
        }
    }

    public func refuseAd(slot: AdSlot, now: Int64) -> EngineCommandOutput<Void> {
        run(now: now) { events in
            DiaryAds.recordRefusal(&state, slot: slot, config: adConfig)
            DiaryAds.markOfferShown(&state, now: now)
            events.append(.adRefused(slot))
        }
    }

    public func startAd(offer: AdOffer, now: Int64) -> EngineCommandOutput<String?> {
        run(now: now) { events in
            guard DiaryLedger.pendingClaims(state).isEmpty else { return nil }
            guard !DiaryLedger.isClaimed(state, key: offer.key) else { return nil }
            guard wageOfferStillValid(offer, now: now) else { return nil }
            if let block = DiaryAds.quotaBlock(state, slot: offer.slot, config: adConfig, now: now),
               block != .interval {
                return nil
            }
            DiaryAds.recordAccept(&state, slot: offer.slot)
            let claimID = DiaryLedger.createPending(&state, slot: offer.slot, reward: offer.reward, now: now, key: offer.key)
            events.append(.adStarted(slot: offer.slot, claimID: claimID))
            return claimID
        }
    }

    public func finishAd(claimID: String, result: AdPlayResult, now: Int64) -> EngineCommandOutput<Bool> {
        run(now: now) { events in
            guard let claim = DiaryLedger.findClaim(state, id: claimID) else { return false }
            DiaryAds.markOfferShown(&state, now: now)
            if result == .ended {
                let granted = DiaryLedger.grantOnce(&state, id: claimID)
                if granted {
                    events.append(.adGranted(slot: claim.slot, claimID: claimID, reward: claim.reward))
                }
                return granted
            }
            if DiaryLedger.cancelClaim(&state, id: claimID) {
                events.append(.adCancelled(slot: claim.slot, claimID: claimID, reason: result))
            }
            return false
        }
    }

    // MARK: - Internal pipeline

    private func markPresence(now: Int64) {
        state.home.lastVisitAt = now
        state.home.awaySatiety = state.primaryCat.satiety
        state.home.awayMood = state.primaryCat.mood
    }

    private func settleOuting(now: Int64, into events: inout [DiaryGameEvent]) {
        let res = DiaryOuting.settleAway(&state, now: now, calendar: calendar, balance: balance)
        if let departed = res.departed {
            events.append(.catDeparted(spot: departed.spot, packedItem: departed.packedItem))
        }
        if let arrived = res.arrived {
            events.append(.catReturned(arrived))
        }
    }

    private func emitReaction(cat: CatID, photos: [String], levelUps: [Int], into events: inout [DiaryGameEvent]) {
        for photo in photos { events.append(.photoTaken(cat: cat, photoID: photo)) }
        for level in levelUps {
            let unlocks = cat == .primary ? DiaryProgression.unlocks(at: level, balance: balance) : []
            events.append(.levelUp(cat: cat, level: level, unlocks: unlocks))
        }
    }

    private func run<T: Sendable>(
        now: Int64,
        action: (inout [DiaryGameEvent]) -> T
    ) -> EngineCommandOutput<T> {
        var events: [DiaryGameEvent] = []
        if state.rollDay(now: now, calendar: calendar) {
            events.append(.dayStarted(state.dayKey))
        }
        DiaryWishEngine.ensureDailyWish(&state, balance: balance)
        DiaryOrders.syncWeekendOrder(&state, balance: balance)
        DiaryEnergy.settle(&state, now: now, balance: balance)
        if !atHome || (state.home.outing.map { now >= $0.returnAt } ?? false) {
            settleOuting(now: now, into: &events)
        }
        if !atHome {
            DiaryHome.captureAwaySnapshot(&state, balance: balance)
        }
        DiaryHome.settleCats(&state, now: now, balance: balance)
        let value = action(&events)
        if atHome {
            markPresence(now: now)
        }
        state.updatedAt = max(state.updatedAt, now)
        return EngineCommandOutput(value: value, events: events, didMutate: true)
    }
}
