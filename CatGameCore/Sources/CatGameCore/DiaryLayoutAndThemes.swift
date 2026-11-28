import Foundation

// MARK: - Room Layout & Free Decorate Mode

public struct RoomBounds: Equatable, Sendable {
    public let minX: Double
    public let maxX: Double
    public let minY: Double
    public let maxY: Double

    public init(minX: Double, maxX: Double, minY: Double, maxY: Double) {
        self.minX = minX
        self.maxX = maxX
        self.minY = minY
        self.maxY = maxY
    }
}

public enum LayoutFailure: String, Equatable, Sendable {
    case notOwned
    case roomLocked
    case notPlaced
}

public enum PlaceFurnitureResult: Equatable, Sendable {
    case placed(PlacedFurniture)
    case failed(LayoutFailure)
}

public enum FlipFurnitureResult: Equatable, Sendable {
    case flipped(Bool)
    case failed(LayoutFailure)
}

public enum StoreFurnitureResult: Equatable, Sendable {
    case stored
    case failed(LayoutFailure)
}

public enum DiaryLayout {
    public static func bounds(for room: RoomID, layer: FurnitureLayer) -> RoomBounds {
        switch (room, layer) {
        case (.livingroom, .flat): return RoomBounds(minX: 0.14, maxX: 0.86, minY: 0.62, maxY: 0.88)
        case (.livingroom, .floor): return RoomBounds(minX: 0.06, maxX: 0.92, minY: 0.56, maxY: 0.88)
        case (.livingroom, .wall): return RoomBounds(minX: 0.10, maxX: 0.90, minY: 0.24, maxY: 0.68)

        case (.bedroom, .flat): return RoomBounds(minX: 0.14, maxX: 0.86, minY: 0.66, maxY: 0.88)
        case (.bedroom, .floor): return RoomBounds(minX: 0.06, maxX: 0.92, minY: 0.60, maxY: 0.88)
        case (.bedroom, .wall): return RoomBounds(minX: 0.10, maxX: 0.90, minY: 0.24, maxY: 0.68)

        case (.entrance, .flat): return RoomBounds(minX: 0.14, maxX: 0.60, minY: 0.64, maxY: 0.88)
        case (.entrance, .floor): return RoomBounds(minX: 0.06, maxX: 0.90, minY: 0.60, maxY: 0.88)
        case (.entrance, .wall): return RoomBounds(minX: 0.10, maxX: 0.58, minY: 0.26, maxY: 0.50)

        case (.balcony, .flat): return RoomBounds(minX: 0.14, maxX: 0.86, minY: 0.64, maxY: 0.88)
        case (.balcony, .floor): return RoomBounds(minX: 0.06, maxX: 0.92, minY: 0.58, maxY: 0.88)
        case (.balcony, .wall): return RoomBounds(minX: 0.20, maxX: 0.80, minY: 0.22, maxY: 0.52)
        }
    }

    public static func defaultPlacement(for id: FurnitureID) -> PlacedFurniture? {
        guard let def = DiaryCatalog.furnitureDef(id) else { return nil }
        return PlacedFurniture(id: id, room: def.room, x: def.defaultX, bottom: def.defaultBottom, flip: false)
    }

    public static func clampPlacement(
        id: FurnitureID,
        room: RoomID,
        x: Double,
        bottom: Double
    ) -> (x: Double, bottom: Double) {
        let layer = DiaryCatalog.furnitureDef(id)?.layer ?? .floor
        let b = bounds(for: room, layer: layer)
        let cx = x.isFinite ? min(b.maxX, max(b.minX, x)) : b.minX
        let cy = bottom.isFinite ? min(b.maxY, max(b.minY, bottom)) : b.minY
        return (cx, cy)
    }

    public static func placement(of id: FurnitureID, in state: DiaryGameState) -> PlacedFurniture? {
        state.home.layout.first { $0.id == id }
    }

    public static func storedFurniture(in state: DiaryGameState) -> [FurnitureID] {
        let placedIDs = Set(state.home.layout.map(\.id))
        return state.home.furnitureOwned.filter { !placedIDs.contains($0) }
    }

    public static func placeNewFurniture(_ state: inout DiaryGameState, id: FurnitureID) {
        guard placement(of: id, in: state) == nil, let def = defaultPlacement(for: id) else { return }
        state.home.layout.append(def)
    }

    public static func placeFurniture(
        _ state: inout DiaryGameState,
        id: FurnitureID,
        room: RoomID,
        x: Double,
        bottom: Double,
        flip: Bool? = nil,
        balance: DiaryBalance = .default
    ) -> PlaceFurnitureResult {
        guard state.home.furnitureOwned.contains(id) else { return .failed(.notOwned) }
        guard DiaryProgression.roomUnlocked(state, room: room, balance: balance) else { return .failed(.roomLocked) }
        let clamped = clampPlacement(id: id, room: room, x: x, bottom: bottom)
        let resolvedFlip = flip ?? placement(of: id, in: state)?.flip ?? false
        let placed = PlacedFurniture(id: id, room: room, x: clamped.x, bottom: clamped.bottom, flip: resolvedFlip)
        state.home.layout.removeAll { $0.id == id }
        state.home.layout.append(placed)
        return .placed(placed)
    }

    public static func toggleFurnitureFlip(_ state: inout DiaryGameState, id: FurnitureID) -> FlipFurnitureResult {
        guard let idx = state.home.layout.firstIndex(where: { $0.id == id }) else { return .failed(.notPlaced) }
        state.home.layout[idx].flip.toggle()
        return .flipped(state.home.layout[idx].flip)
    }

    public static func storeFurniture(_ state: inout DiaryGameState, id: FurnitureID) -> StoreFurnitureResult {
        guard placement(of: id, in: state) != nil else { return .failed(.notPlaced) }
        state.home.layout.removeAll { $0.id == id }
        return .stored
    }

    public static func resetRoomLayout(_ state: inout DiaryGameState, room: RoomID) {
        let affected = state.home.furnitureOwned.filter { id in
            DiaryCatalog.furnitureDef(id)?.room == room || placement(of: id, in: state)?.room == room
        }
        let affectedSet = Set(affected)
        state.home.layout.removeAll { affectedSet.contains($0.id) }
        for id in affected {
            if let def = defaultPlacement(for: id) {
                state.home.layout.append(def)
            }
        }
    }
}

// MARK: - Theme Furniture, Room Skins & Night Flash Sale (22:00-24:00)

public enum ThemeGoodID: Equatable, Hashable, Sendable {
    case furniture(FurnitureID)
    case skin(RoomSkinID)
}

public enum FurnitureLock: Equatable, Sendable {
    case room(RoomID)
    case theme(level: Int)
    case xueqiu(level: Int)
}

public enum RoomSkinActionResult: Equatable, Sendable {
    case applied(skin: RoomSkinID, price: Int)
    case owned
    case themeLocked(Int)
    case notEnoughCoins
    case notOwned
    case priceChanged(Int)
}

public enum DiaryThemes {
    public static let themeGoods: [ThemeGoodID] = {
        let furn = DiaryCatalog.themeShopFurniture.map { ThemeGoodID.furniture($0.id) }
        let skins = DiaryCatalog.roomSkins.filter { $0.price > 0 }.map { ThemeGoodID.skin($0.id) }
        return furn + skins
    }()

    public static func themeUnlockLevel(balance: DiaryBalance = .default) -> Int {
        DiaryProgression.unlockLevel(for: .room(.balcony), balance: balance)
    }

    public static func themesUnlocked(_ state: DiaryGameState, balance: DiaryBalance = .default) -> Bool {
        state.progressLevel >= themeUnlockLevel(balance: balance)
    }

    public static func furnitureLock(
        _ state: DiaryGameState,
        id: FurnitureID,
        balance: DiaryBalance = .default
    ) -> FurnitureLock? {
        guard let def = DiaryCatalog.furnitureDef(id) else { return nil }
        if def.theme != .basic && !themesUnlocked(state, balance: balance) {
            return .theme(level: themeUnlockLevel(balance: balance))
        }
        if !DiaryProgression.roomUnlocked(state, room: def.room, balance: balance) {
            return .room(def.room)
        }
        if let requiredXueqiu = def.xueqiuLevel, (state.cats[.xueqiu]?.level ?? 0) < requiredXueqiu {
            return .xueqiu(level: requiredXueqiu)
        }
        return nil
    }

    public static func isNightSaleTime(
        now: Int64,
        calendar: Calendar = .current,
        balance: DiaryBalance = .default
    ) -> Bool {
        let hour = DayClock.gregorianComponents(for: now, calendar: calendar).hour
        return hour >= balance.themes.saleFromHour && hour < balance.themes.saleToHour
    }

    public static func nightSale(
        now: Int64,
        calendar: Calendar = .current,
        balance: DiaryBalance = .default
    ) -> [ThemeGoodID] {
        guard isNightSaleTime(now: now, calendar: calendar, balance: balance) else { return [] }
        let dayKey = DayClock.dayKey(for: now, calendar: calendar)
        var rng = SeededRNG(seed: UInt32(truncatingIfNeeded: dayKey) &* 7_919 &+ 11)
        let lo = balance.themes.saleMin
        let hi = max(lo, balance.themes.saleMax)
        let count = min(themeGoods.count, lo + Int(floor(rng.nextUnit() * Double(hi - lo + 1))))
        var pool = themeGoods
        var picked: [ThemeGoodID] = []
        while picked.count < count, !pool.isEmpty {
            let idx = min(pool.count - 1, Int(floor(rng.nextUnit() * Double(pool.count))))
            picked.append(pool.remove(at: idx))
        }
        return picked
    }

    public static func salePrice(_ basePrice: Int, balance: DiaryBalance = .default) -> Int {
        let step = Double(max(1, balance.themes.saleRoundTo))
        return Int((Double(basePrice) * balance.themes.saleRate / step).rounded()) * balance.themes.saleRoundTo
    }

    public static func priceNow(
        furniture id: FurnitureID,
        now: Int64,
        calendar: Calendar = .current,
        balance: DiaryBalance = .default
    ) -> Int {
        guard let base = DiaryCatalog.furnitureDef(id)?.price, base > 0 else { return 0 }
        let sale = nightSale(now: now, calendar: calendar, balance: balance)
        return sale.contains(.furniture(id)) ? salePrice(base, balance: balance) : base
    }

    public static func priceNow(
        skin id: RoomSkinID,
        now: Int64,
        calendar: Calendar = .current,
        balance: DiaryBalance = .default
    ) -> Int {
        let base = DiaryCatalog.roomSkinDef(id).price
        guard base > 0 else { return 0 }
        let sale = nightSale(now: now, calendar: calendar, balance: balance)
        return sale.contains(.skin(id)) ? salePrice(base, balance: balance) : base
    }

    public static func isOnNightSale(
        furniture id: FurnitureID,
        now: Int64,
        calendar: Calendar = .current,
        balance: DiaryBalance = .default
    ) -> Bool {
        nightSale(now: now, calendar: calendar, balance: balance).contains(.furniture(id))
    }

    public static func isOnNightSale(
        skin id: RoomSkinID,
        now: Int64,
        calendar: Calendar = .current,
        balance: DiaryBalance = .default
    ) -> Bool {
        nightSale(now: now, calendar: calendar, balance: balance).contains(.skin(id))
    }

    public static func buyRoomSkin(
        _ state: inout DiaryGameState,
        id: RoomSkinID,
        now: Int64,
        quoted: Int? = nil,
        committedPrice: Int? = nil,
        equip: Bool = true,
        calendar: Calendar = .current,
        balance: DiaryBalance = .default
    ) -> RoomSkinActionResult {
        if state.home.skinsOwned.contains(id) { return .owned }
        if !themesUnlocked(state, balance: balance) {
            return .themeLocked(themeUnlockLevel(balance: balance))
        }
        let price: Int
        if let committedPrice {
            price = committedPrice
        } else {
            price = priceNow(skin: id, now: now, calendar: calendar, balance: balance)
            if let quoted, quoted != price {
                return .priceChanged(price)
            }
        }
        guard state.coins >= price else { return .notEnoughCoins }
        state.coins -= price
        state.home.skinsOwned.append(id)
        if equip {
            state.home.activeSkin = id
        }
        return .applied(skin: id, price: price)
    }

    public static func equipRoomSkin(_ state: inout DiaryGameState, id: RoomSkinID) -> RoomSkinActionResult {
        guard state.home.skinsOwned.contains(id) else { return .notOwned }
        state.home.activeSkin = id
        return .applied(skin: id, price: 0)
    }
}
