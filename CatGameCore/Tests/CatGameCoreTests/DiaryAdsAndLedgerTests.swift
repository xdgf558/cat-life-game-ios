import XCTest
@testable import CatGameCore

final class DiaryAdsAndLedgerTests: XCTestCase {
    private let t0: Int64 = 1_760_000_000_000

    private func readyState() -> DiaryGameState {
        var state = DiaryGameState.fresh(now: t0)
        state.tutorialActive = false
        state.orders.completedTotal = 2 // past newbie guard
        state.energy.current = 0
        state.energy.updatedAt = t0
        return state
    }

    func testNewbieGuardBlocksOffersBeforeTwoCompletedOrders() {
        var state = DiaryGameState.fresh(now: t0)
        state.tutorialActive = false
        state.orders.completedTotal = 1
        XCTAssertEqual(DiaryAds.quotaBlock(state, slot: .wage, config: .default, now: t0), .newbie)
        state.orders.completedTotal = 2
        XCTAssertNil(DiaryAds.quotaBlock(state, slot: .wage, config: .default, now: t0))
    }

    func testMaterialOfferAutoTargetsOrderItemAndMutualExclusionBlocksWageBonus() {
        var state = readyState()
        let ball = MergeItem(chain: .cloth, level: 3) // costs 4 tier-1 units
        state.board.cells[0] = MergeItem(chain: .cloth, level: 2) // 2 units already on board -> gap = 2
        let order = CustomerOrder(id: "o10", customer: .ajian, items: [ball], wage: 25)
        state.orders.active = [order]

        let engine = DiaryGameEngine(state: state, adConfig: .default, rng: SeededRNG(seed: 1))
        let offerOut = engine.materialOfferFor(chain: .cloth, now: t0)
        guard let offer = offerOut.value else { return XCTFail("Expected auto material offer") }
        XCTAssertEqual(offer.count, 2)
        XCTAssertEqual(offer.completedUnits, 2)
        XCTAssertEqual(offer.totalUnits, 4)

        _ = engine.offerShown(.material(offer), now: t0)
        let claimID = engine.startAd(offer: .material(offer), now: t0).value
        XCTAssertNotNil(claimID)

        // Finishing once grants 2 cloth_1; repeating the same claimID must be a no-op!
        XCTAssertTrue(engine.finishAd(claimID: claimID!, result: .ended, now: t0 + 1000).value)
        XCTAssertFalse(engine.finishAd(claimID: claimID!, result: .ended, now: t0 + 1000).value)
        XCTAssertEqual(engine.state.ads.used[.material], 1)

        // Merge into ball and deliver order -> wage bonus must be suppressed (mutual exclusion).
        _ = engine.moveItem(from: 1, to: 2, now: t0 + 2000)
        _ = engine.moveItem(from: 0, to: 2, now: t0 + 2000)
        let deliverOut = engine.deliverOrder(orderID: "o10", now: t0 + 120_000)
        XCTAssertNil(deliverOut.value.bonusOffer)
    }

    func testRefusalLimitAndDailyReset() {
        let engine = DiaryGameEngine(state: readyState(), adConfig: .default)
        for _ in 0..<3 { _ = engine.refuseAd(slot: .wage, now: t0) }
        XCTAssertEqual(DiaryAds.quotaBlock(engine.state, slot: .wage, config: .default, now: t0), .refused)
        // Next day resets refusal & daily counts.
        let tomorrow = t0 + DayClock.dayMs + DayClock.hourMs
        _ = engine.refreshDay(now: tomorrow)
        XCTAssertNil(DiaryAds.quotaBlock(engine.state, slot: .wage, config: .default, now: tomorrow))
    }

    func testCrashRecoveryCancelsPendingWithoutGrantingOrUsingQuota() {
        var state = readyState()
        let offer = WageOffer(orderID: "o99", amount: 30, wishlistShortAfter: nil, furniture: nil, furniturePrice: nil)
        let claimID = DiaryLedger.createPending(&state, slot: .wage, reward: .coins(amount: 30), now: t0, key: offer.key)
        XCTAssertEqual(DiaryAds.remainingForSlot(state, slot: .wage, config: .default), 1)

        let recovered = DiaryLedger.recoverPendingOnStartup(&state)
        XCTAssertEqual(recovered, 1)
        XCTAssertEqual(state.coins, 0)
        XCTAssertEqual(DiaryLedger.findClaim(state, id: claimID)?.status, .cancelled)
        XCTAssertEqual(DiaryAds.remainingForSlot(state, slot: .wage, config: .default), 2)
    }

    func testSmallWageSuppressedUnlessCompletingWishlist() {
        var state = readyState()
        let smallOrder = CustomerOrder(id: "o5", customer: .ajian, items: [MergeItem(chain: .cloth, level: 3)], wage: 10)
        XCTAssertNil(DiaryAds.wageOffer(state, order: smallOrder, config: .default, now: t0))

        // Set wishlist window_cushion (120) with 110 coins -> 10 bonus finishes exact shortfall!
        state.coins = 110
        state.home.wishlist = .windowCushion
        let offer = DiaryAds.wageOffer(state, order: smallOrder, config: .default, now: t0)
        XCTAssertEqual(offer?.wishlistShortAfter, 0)
        XCTAssertEqual(offer?.furniture, .windowCushion)
    }

    func testDuplicateAndSameChainOrderItemsComputeRemainingMaterialGap() {
        var state = readyState()
        let ball = MergeItem(chain: .cloth, level: 3) // 4 tier-1 units
        let wand = MergeItem(chain: .cloth, level: 4) // 8 tier-1 units

        // Order asks for two identical cloth_3 items; board only has one.
        let dupOrder = CustomerOrder(id: "o20", customer: .ajian, items: [ball, ball], wage: 20)
        state.orders.active = [dupOrder]
        state.board.cells[0] = ball

        XCTAssertFalse(DiaryOrders.canDeliver(state, order: dupOrder))
        XCTAssertEqual(DiaryOrders.orderItemsOnBoard(state, order: dupOrder), [true, false])
        XCTAssertEqual(DiaryAds.materialGap(state, target: ball, order: dupOrder), 4)

        let engine = DiaryGameEngine(state: state, adConfig: .default, rng: SeededRNG(seed: 2))
        let offerOut = engine.materialOfferFor(chain: .cloth, now: t0)
        guard let offer = offerOut.value else { return XCTFail("Expected material offer for second duplicate item") }
        XCTAssertEqual(offer.target, ball)
        XCTAssertEqual(offer.orderID, "o20")
        XCTAssertEqual(offer.count, 4)

        // Adding a lower-tier cloth_2 (2 units) reduces the gap for the second ball from 4 to 2.
        state.board.cells[1] = MergeItem(chain: .cloth, level: 2)
        XCTAssertEqual(DiaryAds.materialGap(state, target: ball, order: dupOrder), 2)

        // Adding the second ball satisfies the order completely -> gap becomes 0.
        state.board.cells[2] = ball
        XCTAssertEqual(DiaryAds.materialGap(state, target: ball, order: dupOrder), 0)

        // Same-chain mixed-tier order [cloth_3, cloth_4] with one cloth_3 on board:
        // cloth_3 is reserved for slot 0 and must not be counted toward cloth_4's gap.
        var mixedState = readyState()
        let mixedOrder = CustomerOrder(id: "o21", customer: .grandma, items: [ball, wand], wage: 30)
        mixedState.orders.active = [mixedOrder]
        mixedState.board.cells[0] = ball
        XCTAssertEqual(DiaryAds.materialGap(mixedState, target: ball, order: mixedOrder), 0)
        XCTAssertEqual(DiaryAds.materialGap(mixedState, target: wand, order: mixedOrder), 8)
    }

    func testMaterialOfferIgnoresReservedBoardCellsAndExcludedPendingOrders() {
        var state = readyState()
        let ball = MergeItem(chain: .cloth, level: 3) // 4 units
        let wand = MergeItem(chain: .cloth, level: 4) // 8 units
        let pendingOrder = CustomerOrder(id: "o30", customer: .ajian, items: [ball], wage: 10)
        let activeOrder = CustomerOrder(id: "o31", customer: .grandma, items: [wand], wage: 20)
        state.orders.active = [pendingOrder, activeOrder]
        // Cell 0 holds `ball`, which is already reserved for `pendingOrder` ("o30").
        state.board.cells[0] = ball

        XCTAssertEqual(
            DiaryAds.materialGap(state, target: wand, order: activeOrder, reservedCells: [0]),
            8,
            "Reserved cell 0 must not reduce the material gap of another order"
        )

        let engine = DiaryGameEngine(state: state, adConfig: .default, rng: SeededRNG(seed: 7))
        let out = engine.materialOfferFor(
            chain: .cloth,
            now: t0,
            reservedCells: [0],
            excludedOrderIDs: ["o30"]
        )
        guard let offer = out.value else { return XCTFail("Expected material offer for o31") }
        XCTAssertEqual(offer.orderID, "o31")
        XCTAssertEqual(offer.target, wand)
        XCTAssertEqual(offer.count, 8)
    }

    func testPreMidnightAdClaimGrantedAfterMidnightDoesNotConsumeNextDayQuota() {
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0)!

        var comps = DateComponents()
        comps.calendar = utcCal
        comps.timeZone = utcCal.timeZone
        comps.year = 2026
        comps.month = 11
        comps.day = 26
        comps.hour = 23
        comps.minute = 59
        comps.second = 50
        let beforeMidnightMs = DayClock.epochMs(comps.date!)
        let afterMidnightMs = beforeMidnightMs + 20_000 // 2026-11-27 00:00:10 UTC

        var state = DiaryGameState.fresh(now: beforeMidnightMs, calendar: utcCal)
        state.tutorialActive = false
        state.orders.completedTotal = 2

        let engine = DiaryGameEngine(state: state, adConfig: .default, calendar: utcCal)
        let offer = AdOffer.wage(WageOffer(orderID: "o1", amount: 25, wishlistShortAfter: nil, furniture: nil, furniturePrice: nil))
        guard let claimID = engine.startAd(offer: offer, now: beforeMidnightMs).value else {
            return XCTFail("Expected pending claim before midnight")
        }
        XCTAssertEqual(DiaryLedger.findClaim(engine.state, id: claimID)?.dayKey, 20_261_126)

        // Ad playback or save commit completes after midnight -> reward grants, but Day 2 quota stays untouched!
        let finishOut = engine.finishAd(claimID: claimID, result: .ended, now: afterMidnightMs)
        XCTAssertTrue(finishOut.value)
        XCTAssertEqual(engine.state.coins, 25)
        XCTAssertEqual(engine.state.dayKey, 20_261_127)
        XCTAssertEqual(engine.state.ads.used[.wage], 0)
        XCTAssertEqual(DiaryAds.remainingForSlot(engine.state, slot: .wage, config: .default), 2)
    }

    func testClockRollbackByOneSecondDoesNotBypassAdCooldown() {
        var state = readyState()
        let ball = MergeItem(chain: .cloth, level: 3)
        let order = CustomerOrder(id: "o40", customer: .ajian, items: [ball], wage: 10)
        state.orders.active = [order]
        state.ads.lastOfferAt = t0

        // Rolling the system clock backward by 1 second must still enforce `.interval` cooldown!
        let rolledBack = t0 - 1_000
        XCTAssertEqual(DiaryAds.quotaBlock(state, slot: .material, config: .default, now: rolledBack), .interval)
        XCTAssertEqual(DiaryAds.quotaBlock(state, slot: .wage, config: .default, now: rolledBack), .interval)

        let engine = DiaryGameEngine(state: state, adConfig: .default, rng: SeededRNG(seed: 3))
        XCTAssertNil(engine.materialOfferFor(chain: .cloth, now: rolledBack).value)

        // Once 90 seconds have genuinely elapsed forward from `lastOfferAt`, offers resume.
        let afterCooldown = t0 + AdRemoteConfig.default.minOfferIntervalMs
        XCTAssertNil(DiaryAds.quotaBlock(state, slot: .material, config: .default, now: afterCooldown))
    }
}
