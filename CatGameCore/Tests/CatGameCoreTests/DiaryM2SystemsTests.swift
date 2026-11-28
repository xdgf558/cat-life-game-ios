import XCTest
@testable import CatGameCore

final class DiaryM2SystemsTests: XCTestCase {
    private var utcCal: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func makeUTCDate(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0) -> Int64 {
        var comps = DateComponents()
        comps.calendar = utcCal
        comps.timeZone = utcCal.timeZone
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        return DayClock.epochMs(comps.date!)
    }

    func testCatalogCountsForM2() {
        XCTAssertEqual(DiaryCatalog.photos.count, 36)
        XCTAssertEqual(DiaryCatalog.xueqiuPhotos.count, 12)
        XCTAssertEqual(DiaryCatalog.duoPhotos.count, 6)
        XCTAssertEqual(DiaryCatalog.albumPhotos.count, 36)
        XCTAssertEqual(Set(DiaryCatalog.allPhotoIDs).count, 90)
        XCTAssertEqual(DiaryCatalog.treasures.count, 18)
        XCTAssertEqual(DiaryCatalog.themeShopFurniture.count, 16)
        XCTAssertEqual(DiaryCatalog.roomSkins.count, 4)
    }

    func testM1SaveDecodesCleanlyIntoM2WithStoryBackpayAndValidation() async throws {
        let t0 = makeUTCDate(year: 2026, month: 11, day: 27, hour: 12)
        var state = DiaryGameState.fresh(now: t0, calendar: utcCal)
        state.tutorialActive = false
        state.coins = 50
        state.orders.customerProgress[.ajian] = 35 // qualifies for 10, 20, 35 (backpay 150)

        // Strip M2-only keys and set schemaVersion = 1 to simulate a real M1 (2.0.0 build 70) save file.
        let encoded = try JSONEncoder().encode(state)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        root["schemaVersion"] = 1
        var home = try XCTUnwrap(root["home"] as? [String: Any])
        for key in ["stray", "skinsOwned", "activeSkin", "basket", "outing", "pendingArrival",
                    "treasures", "outingsToday", "outingsDay", "recallUsedToday", "awaySatiety", "awayMood"] {
            home.removeValue(forKey: key)
        }
        root["home"] = home
        var orders = try XCTUnwrap(root["orders"] as? [String: Any])
        for key in ["storiesSeen", "weekendOrder", "weekendDoneWeek", "storyBackpay"] {
            orders.removeValue(forKey: key)
        }
        root["orders"] = orders

        let m1Data = try JSONSerialization.data(withJSONObject: root)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let repo = DiarySaveRepository(directory: dir)
        try m1Data.write(to: repo.saveURL, options: .atomic)

        let loaded = try await repo.loadOrCreate(now: DayClock.date(fromEpochMs: t0), calendar: utcCal)
        XCTAssertTrue(loaded.isValid)
        XCTAssertEqual(loaded.schemaVersion, DiaryGameState.currentSchemaVersion)
        XCTAssertEqual(loaded.schemaVersion, 2, "M2 must persist an independent schemaVersion so 2.0.0 refuses to overwrite it")
        XCTAssertEqual(loaded.home.activeSkin, .defaultSkin)
        XCTAssertEqual(loaded.home.skinsOwned, [.defaultSkin])
        XCTAssertEqual(loaded.orders.storiesSeen, ["ajian:10", "ajian:20", "ajian:35"])
        XCTAssertEqual(loaded.orders.storyBackpay, 150)

        let engine = DiaryGameEngine(state: loaded, calendar: utcCal)
        let backpay = engine.takeStoryBackpay(now: t0)
        XCTAssertEqual(backpay.value, 150)
        XCTAssertEqual(engine.state.coins, 200)
        XCTAssertEqual(engine.state.orders.storyBackpay, 0)
        // Second call is idempotent (0).
        XCTAssertEqual(engine.takeStoryBackpay(now: t0).value, 0)

        // Saving upgraded state writes schemaVersion == 2 and preserves M2 progress without paying backpay again.
        var m2State = engine.state
        m2State.coins = 650
        m2State.home.skinsOwned = [.defaultSkin, .honey]
        m2State.home.activeSkin = .honey
        m2State.home.treasures[.ginkgo] = TreasureRecord(count: 2, firstAt: t0, lastAt: t0)
        try await repo.save(m2State, now: DayClock.date(fromEpochMs: t0 + 600_000))

        let savedRaw = try Data(contentsOf: repo.saveURL)
        let savedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: savedRaw) as? [String: Any])
        XCTAssertEqual(savedJSON["schemaVersion"] as? Int, 2)

        // A 2.0.0 build only supports schemaVersion == 1, so `2 > 1` triggers unsupportedSchemaVersion without overwriting.
        let reloadedM2 = try await repo.loadOrCreate(now: DayClock.date(fromEpochMs: t0 + 700_000), calendar: utcCal)
        XCTAssertEqual(reloadedM2.coins, 650)
        XCTAssertEqual(reloadedM2.orders.storyBackpay, 0)
        XCTAssertEqual(reloadedM2.home.activeSkin, .honey)
        XCTAssertEqual(DiaryOuting.treasureTimes(reloadedM2, id: .ginkgo), 2)

        // Corrupt v2 save missing `storiesSeen` must fail decoding and recover backup instead of repaying backpay!
        try await repo.save(reloadedM2, now: DayClock.date(fromEpochMs: t0 + 1_200_000))
        var corruptV2 = savedJSON
        var corruptOrders = try XCTUnwrap(corruptV2["orders"] as? [String: Any])
        corruptOrders.removeValue(forKey: "storiesSeen")
        corruptV2["orders"] = corruptOrders
        try JSONSerialization.data(withJSONObject: corruptV2).write(to: repo.saveURL, options: .atomic)

        let recovered = try await repo.loadOrCreate(now: DayClock.date(fromEpochMs: t0 + 1_300_000), calendar: utcCal)
        let disp = await repo.lastLoadDisposition
        XCTAssertEqual(disp, .recoveredBackup)
        XCTAssertEqual(recovered.coins, 650)
        XCTAssertEqual(recovered.orders.storyBackpay, 0)
        XCTAssertEqual(recovered.home.activeSkin, .honey)
    }

    func testLayoutPlacementBoundsFlipStoreAndReset() {
        let t0 = makeUTCDate(year: 2026, month: 11, day: 27, hour: 12)
        var state = DiaryGameState.fresh(now: t0, calendar: utcCal)
        state.tutorialActive = false
        state.primaryCat.level = 8
        state.home.furnitureOwned = [.windowCushion, .catBed]
        DiaryLayout.placeNewFurniture(&state, id: .windowCushion)
        DiaryLayout.placeNewFurniture(&state, id: .catBed)

        // Move windowCushion to balcony with out-of-bounds coords -> clamped inside balcony floor bounds.
        let placed = DiaryLayout.placeFurniture(&state, id: .windowCushion, room: .balcony, x: 5.0, bottom: -1.0)
        if case .placed(let item) = placed {
            let b = DiaryLayout.bounds(for: .balcony, layer: .floor)
            XCTAssertEqual(item.room, .balcony)
            XCTAssertEqual(item.x, b.maxX, accuracy: 0.0001)
            XCTAssertEqual(item.bottom, b.minY, accuracy: 0.0001)
        } else {
            XCTFail("Expected placement on unlocked balcony")
        }

        XCTAssertEqual(DiaryLayout.toggleFurnitureFlip(&state, id: .windowCushion), .flipped(true))
        XCTAssertEqual(DiaryLayout.storeFurniture(&state, id: .catBed), .stored)
        XCTAssertEqual(DiaryLayout.storedFurniture(in: state), [.catBed])

        // Reset bedroom restores catBed from storage to bedroom default!
        DiaryLayout.resetRoomLayout(&state, room: .bedroom)
        XCTAssertEqual(DiaryLayout.placement(of: .catBed, in: state)?.room, .bedroom)
        XCTAssertTrue(DiaryLayout.storedFurniture(in: state).isEmpty)

        // Reset livingroom pulls windowCushion back from balcony and resets flip.
        DiaryLayout.resetRoomLayout(&state, room: .livingroom)
        let restored = DiaryLayout.placement(of: .windowCushion, in: state)
        XCTAssertEqual(restored?.room, .livingroom)
        XCTAssertEqual(restored?.flip, false)
    }

    func testThemesNightSaleQuotedPriceAndWageOfferInvalidation() {
        let saleTime = makeUTCDate(year: 2026, month: 11, day: 27, hour: 22, minute: 30)
        let afterMidnight = makeUTCDate(year: 2026, month: 11, day: 28, hour: 0, minute: 5)
        XCTAssertTrue(DiaryThemes.isNightSaleTime(now: saleTime, calendar: utcCal))
        XCTAssertFalse(DiaryThemes.isNightSaleTime(now: afterMidnight, calendar: utcCal))

        let saleGoods = DiaryThemes.nightSale(now: saleTime, calendar: utcCal)
        XCTAssertTrue((1...3).contains(saleGoods.count))
        // Pick a concrete night-sale furniture item (find a day where a winter/spring item is on sale).
        var targetFurn: FurnitureID?
        var targetSaleTime = saleTime
        for dayOffset in 0..<10 {
            let candidateTime = saleTime + Int64(dayOffset) * DayClock.dayMs
            for good in DiaryThemes.nightSale(now: candidateTime, calendar: utcCal) {
                if case .furniture(let id) = good, DiaryCatalog.furnitureDef(id)?.xueqiuLevel == nil {
                    targetFurn = id
                    targetSaleTime = candidateTime
                    break
                }
            }
            if targetFurn != nil { break }
        }
        guard let furnID = targetFurn, let basePrice = DiaryCatalog.furnitureDef(furnID)?.price else {
            return XCTFail("Expected a themed furniture item on night sale")
        }
        let discounted = DiaryThemes.priceNow(furniture: furnID, now: targetSaleTime, calendar: utcCal)
        XCTAssertLessThan(discounted, basePrice)

        var state = DiaryGameState.fresh(now: targetSaleTime, calendar: utcCal)
        state.tutorialActive = false
        state.primaryCat.level = 8
        state.coins = discounted
        state.orders.completedTotal = 5
        state.home.wishlist = furnID

        // Trying to buy after midnight with the stale discounted quote must fail with priceChanged!
        let nextDayTime = targetSaleTime + 2 * DayClock.hourMs
        let buyRes = DiaryOrders.buyFurniture(&state, id: furnID, now: nextDayTime, quoted: discounted, calendar: utcCal)
        XCTAssertEqual(buyRes, .priceChanged(basePrice))
        XCTAssertEqual(state.coins, discounted)

        // Small wage offer granted only because night-sale discount made it reachable becomes invalid after midnight!
        state.coins = discounted - 10
        let smallOrder = CustomerOrder(id: "o9", customer: .ajian, items: [MergeItem(chain: .cloth, level: 3)], wage: 10)
        var adCfg = AdRemoteConfig.default
        adCfg.adEnabled = true
        let offer = DiaryAds.wageOffer(state, order: smallOrder, config: adCfg, now: targetSaleTime, calendar: utcCal)
        XCTAssertNotNil(offer)
        XCTAssertTrue(DiaryAds.wageOfferStillValid(state, offer: offer!, config: adCfg, now: targetSaleTime, calendar: utcCal))
        XCTAssertEqual(DiaryAds.wageOfferInvalidReason(state, offer: offer!, config: adCfg, now: nextDayTime, calendar: utcCal), .priceUp)

        // Room skin purchase & equip
        state.coins = 1000
        let skinBuy = DiaryThemes.buyRoomSkin(&state, id: .honey, now: nextDayTime, calendar: utcCal)
        XCTAssertEqual(skinBuy, .applied(skin: .honey, price: 800))
        XCTAssertEqual(state.home.activeSkin, .honey)
        XCTAssertEqual(DiaryThemes.equipRoomSkin(&state, id: .defaultSkin), .applied(skin: .defaultSkin, price: 0))
        XCTAssertEqual(state.home.activeSkin, .defaultSkin)
    }

    func testOutingBasketAwaySettlementTreasuresAndRecall() {
        let tStart = makeUTCDate(year: 2026, month: 11, day: 27, hour: 10)
        var state = DiaryGameState.fresh(now: tStart, calendar: utcCal)
        state.tutorialActive = false
        state.primaryCat.level = 6 // unlocks Entrance + Outing
        state.home.toys = [OwnedToy(item: MergeItem(chain: .cloth, level: 4), usesLeft: 2)]
        state.home.food = [MergeItem(chain: .food, level: 4)]

        // Pack toy, then swap with food -> toy returns preserving usesLeft == 2!
        XCTAssertEqual(DiaryOuting.packBasket(&state, source: .toy, index: 0), .updated(MergeItem(chain: .cloth, level: 4)))
        XCTAssertTrue(state.home.toys.isEmpty)
        XCTAssertEqual(DiaryOuting.packBasket(&state, source: .food, index: 0), .updated(MergeItem(chain: .food, level: 4)))
        XCTAssertEqual(state.home.toys.first?.usesLeft, 2)

        // Find a departure timestamp where Xiaoju departs and returns after 6 hours away.
        var returned: OutingArrival?
        for offsetMin in stride(from: 0, through: 120, by: 5) {
            var copy = state
            let leaveAt = tStart + Int64(offsetMin) * DayClock.minuteMs
            copy.home.lastVisitAt = leaveAt
            copy.home.awaySatiety = 80
            copy.home.awayMood = 60
            let settled = DiaryOuting.settleAway(&copy, now: leaveAt + 6 * DayClock.hourMs, calendar: utcCal)
            if let arr = settled.arrived {
                returned = arr
                XCTAssertNil(copy.home.basket, "Packed food should be taken on outing")
                XCTAssertEqual(DiaryOuting.treasureCount(copy), 1)
                XCTAssertNotNil(copy.home.pendingArrival)
                XCTAssertNotNil(DiaryOuting.claimArrival(&copy))
                XCTAssertNil(copy.home.pendingArrival)
                break
            }
        }
        XCTAssertNotNil(returned, "Expected Xiaoju to depart & return across deterministic seeds")

        // Recall while out: works once per day, resets next day.
        state.home.outing = OutingState(departAt: tStart, returnAt: tStart + 2 * DayClock.hourMs, packedItem: nil, spot: .alley)
        XCTAssertEqual(DiaryHome.pet(&state, now: tStart + 10_000), .failed(.outing))
        XCTAssertEqual(DiaryOuting.recallCat(&state, now: tStart + 10_000), .recalled)
        XCTAssertNil(state.home.outing)
        XCTAssertTrue(state.home.recallUsedToday)
        state.home.outing = OutingState(departAt: tStart, returnAt: tStart + 2 * DayClock.hourMs, packedItem: nil, spot: .alley)
        XCTAssertEqual(DiaryOuting.recallCat(&state, now: tStart + 20_000), .failed(.usedToday))
        _ = state.rollDay(now: tStart + DayClock.dayMs, calendar: utcCal)
        XCTAssertFalse(state.home.recallUsedToday)
    }

    func testXueqiuStrayAdoptionAndSoloPhotos() {
        var t = makeUTCDate(year: 2026, month: 11, day: 27, hour: 10)
        var state = DiaryGameState.fresh(now: t, calendar: utcCal)
        state.tutorialActive = false
        state.primaryCat.level = 7 // unlocks Stray Xueqiu

        // Visit 1: no food required, Xueqiu peeks.
        let arr1 = DiaryAdoption.settleStray(&state, now: t)
        XCTAssertEqual(arr1, StrayArrival(trust: 0, ate: nil))
        guard case .met(let trust1, _, let adopted1, _, _) = DiaryAdoption.interactStray(&state, now: t) else {
            return XCTFail("Expected trust 1")
        }
        XCTAssertEqual(trust1, 1)
        XCTAssertFalse(adopted1)

        // Cooldown blocks early revisit even with food.
        state.home.basket = BasketItem(item: MergeItem(chain: .food, level: 3))
        XCTAssertNil(DiaryAdoption.settleStray(&state, now: t + DayClock.hourMs))

        // Visits 2..5 with food every 4 hours -> adopts on 5th interaction and unlocks photo_xq_01!
        for step in 2...5 {
            t += 4 * DayClock.hourMs
            state.home.basket = BasketItem(item: MergeItem(chain: .food, level: 3))
            let arr = DiaryAdoption.settleStray(&state, now: t)
            XCTAssertNotNil(arr)
            XCTAssertNil(state.home.basket, "Xueqiu eats basket food on arrival")
            guard case .met(let trust, _, let adopted, let photos, _) = DiaryAdoption.interactStray(&state, now: t) else {
                return XCTFail("Expected interaction \(step)")
            }
            XCTAssertEqual(trust, step)
            if step < 5 {
                XCTAssertFalse(adopted)
            } else {
                XCTAssertTrue(adopted)
                XCTAssertNotNil(state.cats[.xueqiu])
                XCTAssertNil(state.home.stray)
                XCTAssertTrue(photos.contains("photo_xq_01"))
            }
        }
        // Core diary progress remains unaffected by Xueqiu photos.
        XCTAssertEqual(DiaryHome.photoProgress(state).got, 0)
        XCTAssertEqual(DiaryHome.extraPhotoProgress(state).got, 1)
    }

    func testTreasureAlbumUnlockAndGregorianSeasonChecks() {
        // Use a non-Gregorian calendar (Japanese) to verify month/day season checks stay accurate!
        var jpCal = Calendar(identifier: .japanese)
        jpCal.timeZone = TimeZone(secondsFromGMT: 0)!
        let springNoon = makeUTCDate(year: 2026, month: 4, day: 15, hour: 12)
        let nightTime = makeUTCDate(year: 2026, month: 4, day: 15, hour: 23)

        var state = DiaryGameState.fresh(now: springNoon, calendar: jpCal)
        state.tutorialActive = false
        XCTAssertFalse(DiaryAlbum.isOpen(state))

        for photo in DiaryCatalog.photos {
            state.addPhoto(photo.id, now: springNoon)
        }
        XCTAssertTrue(DiaryAlbum.isOpen(state))

        let springPhoto = DiaryCatalog.albumPhotoDef("photo_season_01")!
        XCTAssertTrue(DiaryAlbum.reqMet(state, photo: springPhoto, now: springNoon, calendar: jpCal))
        XCTAssertFalse(DiaryAlbum.reqMet(state, photo: springPhoto, now: nightTime, calendar: jpCal))

        // Dream photo requires asleep (night + not hungry) & happy (>= 80).
        let dreamPhoto = DiaryCatalog.albumPhotoDef("photo_dream_01")!
        state.primaryCat.satiety = 80
        state.primaryCat.mood = 85
        XCTAssertTrue(DiaryAlbum.reqMet(state, photo: dreamPhoto, now: nightTime, calendar: jpCal))
        var rng = SequenceRNG([0.01, 0.0]) // falls in dream bucket (< 0.04)
        let rolled = DiaryAlbum.rollAlbumPhoto(&state, now: nightTime, rng: &rng, calendar: jpCal)
        XCTAssertEqual(rolled, "photo_dream_01")
    }

    func testWeekendOrderDeliveryAndCustomerStories() {
        // 2026-11-28 is a Saturday!
        let sat = makeUTCDate(year: 2026, month: 11, day: 28, hour: 14)
        let mon = makeUTCDate(year: 2026, month: 11, day: 30, hour: 10)
        XCTAssertTrue(DayClock.isWeekend(dayKey: 20_261_128))
        XCTAssertFalse(DayClock.isWeekend(dayKey: 20_261_130))
        XCTAssertEqual(DayClock.weekKey(for: 20_261_128), 20_261_123)

        var state = DiaryGameState.fresh(now: sat, calendar: utcCal)
        state.tutorialActive = false
        state.primaryCat.level = 7
        DiaryOrders.syncWeekendOrder(&state)
        let weekend = try! XCTUnwrap(state.orders.weekendOrder)
        XCTAssertEqual(weekend.id, "w20261123")
        XCTAssertEqual(weekend.items.count, 2)

        // Put required items on board & set customer progress to 34 so weekend delivery triggers story #3 (+150 coins)!
        state.orders.customerProgress[weekend.customer] = 34
        for (idx, item) in weekend.items.enumerated() {
            state.board.cells[idx] = item
        }
        let engine = DiaryGameEngine(state: state, calendar: utcCal)
        let out = engine.deliverWeekendOrder(expectedID: weekend.id, now: sat)
        guard case .delivered(_, let wage, _, let story) = out.value else {
            return XCTFail("Expected weekend delivery")
        }
        XCTAssertEqual(story?.milestone, 35)
        XCTAssertEqual(story?.bonusCoins, 150)
        XCTAssertEqual(engine.state.coins, wage + 150)
        XCTAssertNil(engine.state.orders.weekendOrder)
        XCTAssertEqual(engine.state.orders.weekendDoneWeek, 20_261_123)

        // Next Monday clears weekendOrder cleanly.
        _ = engine.refreshDay(now: mon)
        XCTAssertNil(engine.state.orders.weekendOrder)
    }

    func testInvalidM2FieldsFailValidation() {
        let t0 = makeUTCDate(year: 2026, month: 11, day: 27, hour: 12)
        var s1 = DiaryGameState.fresh(now: t0, calendar: utcCal)
        s1.home.outing = OutingState(departAt: t0 + 10_000, returnAt: t0, packedItem: nil, spot: .alley)
        XCTAssertFalse(s1.isValid, "returnAt < departAt must be rejected")

        var s2 = DiaryGameState.fresh(now: t0, calendar: utcCal)
        s2.home.activeSkin = .honey // not in skinsOwned
        XCTAssertFalse(s2.isValid, "Active unowned room skin must be rejected")

        var s3 = DiaryGameState.fresh(now: t0, calendar: utcCal)
        s3.home.awaySatiety = .nan
        XCTAssertFalse(s3.isValid, "Non-finite awaySatiety must be rejected")

        var s4 = DiaryGameState.fresh(now: t0, calendar: utcCal)
        s4.home.stray = StrayState(trust: 99, lastSeenAt: nil, present: true, ate: nil)
        XCTAssertFalse(s4.isValid, "Out-of-range stray trust must be rejected")
    }

    func testExpiredWeekendOrderClearsTargetAndBlocksMaterialAd() throws {
        // 2026-11-29 23:59:30 UTC (Sunday) -> +60s = 2026-11-30 00:00:30 UTC (Monday, < 1 energy tick).
        let sun = makeUTCDate(year: 2026, month: 11, day: 29, hour: 23, minute: 59) + 30_000
        let mon = sun + 60_000

        var state = DiaryGameState.fresh(now: sun, calendar: utcCal)
        state.tutorialActive = false
        state.primaryCat.level = 7
        state.orders.completedTotal = 5
        state.energy.current = 0
        state.energy.updatedAt = sun
        // Fill regular active orders with items from another chain so auto-target won't mask the expired weekend order.
        DiaryOrders.syncWeekendOrder(&state)
        let weekend = try XCTUnwrap(state.orders.weekendOrder)
        let targetItem = try XCTUnwrap(weekend.items.first)
        let otherChain: MergeChain = targetItem.chain == .cloth ? .wood : .cloth
        state.orders.active = [
            CustomerOrder(id: "o1", customer: .ajian, items: [MergeItem(chain: otherChain, level: 4)], wage: 20)
        ]
        // Leave exactly 1 base unit short of `targetItem` so Sunday material ad offers count == 1.
        let unitsNeeded = targetItem.energyValue - 1
        var remaining = unitsNeeded
        var cellIdx = 0
        for lvl in stride(from: targetItem.level - 1, through: 1, by: -1) {
            let unitVal = MergeItem(chain: targetItem.chain, level: lvl).energyValue
            while remaining >= unitVal {
                state.board.cells[cellIdx] = MergeItem(chain: targetItem.chain, level: lvl)
                cellIdx += 1
                remaining -= unitVal
            }
        }
        DiaryOrders.setTarget(&state, item: targetItem, orderID: weekend.id)

        var adCfg = AdRemoteConfig.default
        adCfg.adEnabled = true
        let sundayOffer = DiaryAds.materialOffer(state, config: adCfg, now: sun)
        XCTAssertEqual(sundayOffer?.orderID, weekend.id)
        XCTAssertEqual(sundayOffer?.count, 1)

        // Monday arrives -> syncWeekendOrder clears weekendOrder AND clears the associated target!
        let engine = DiaryGameEngine(state: state, adConfig: adCfg, calendar: utcCal)
        _ = engine.refreshDay(now: mon)
        XCTAssertNil(engine.state.orders.weekendOrder)
        XCTAssertNil(engine.state.target, "Expiring weekend order must clear its craft target")
        XCTAssertNil(engine.materialOfferFor(chain: targetItem.chain, now: mon).value)

        // Defense-in-depth: even with a stale target pointing to an expired weekend order, materialOffer and startAd must reject it!
        var staleState = engine.state
        staleState.energy.current = 0
        staleState.energy.updatedAt = mon
        DiaryOrders.setTarget(&staleState, item: targetItem, orderID: weekend.id)
        XCTAssertNil(DiaryAds.materialOffer(staleState, config: adCfg, now: mon))

        if let sundayOffer {
            let staleEngine = DiaryGameEngine(state: staleState, adConfig: adCfg, calendar: utcCal)
            XCTAssertNil(staleEngine.startAd(offer: .material(sundayOffer), now: mon).value)
        }
    }

    func testRepeatTreasureArrivalReportsActualClampedMoodGain() {
        let departAt = makeUTCDate(year: 2026, month: 11, day: 28, hour: 10)
        let returnAt = makeUTCDate(year: 2026, month: 11, day: 28, hour: 12)
        let outing = OutingState(departAt: departAt, returnAt: returnAt, packedItem: nil, spot: .garden)

        func runArrival(initialMood: Double) -> (arrival: OutingArrival, finalMood: Double) {
            var state = DiaryGameState.fresh(now: departAt, calendar: utcCal)
            state.tutorialActive = false
            state.primaryCat.level = 6
            state.primaryCat.mood = initialMood
            // Pre-own every treasure so whichever treasure is rolled is guaranteed to be a repeat treasure.
            for id in TreasureID.allCases {
                state.home.treasures[id] = TreasureRecord(count: 1, firstAt: departAt - DayClock.dayMs, lastAt: nil)
            }
            let arrival = DiaryOuting.arrive(&state, outing: outing, calendar: utcCal)
            return (arrival, state.primaryCat.mood)
        }

        let nearCap = runArrival(initialMood: 99.0)
        XCTAssertEqual(nearCap.finalMood, 100.0, accuracy: 0.0001)
        XCTAssertEqual(nearCap.arrival.bonusMood, 1.0, accuracy: 0.0001)

        let atCap = runArrival(initialMood: 100.0)
        XCTAssertEqual(atCap.finalMood, 100.0, accuracy: 0.0001)
        XCTAssertEqual(atCap.arrival.bonusMood, 0.0, accuracy: 0.0001)

        let normal = runArrival(initialMood: 80.0)
        XCTAssertEqual(normal.finalMood, 85.0, accuracy: 0.0001)
        XCTAssertEqual(normal.arrival.bonusMood, 5.0, accuracy: 0.0001)
    }
}
