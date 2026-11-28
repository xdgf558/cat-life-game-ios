import Foundation

public struct FurnitureDef: Equatable, Sendable {
    public let id: FurnitureID
    public let room: RoomID
    /// `nil` for customer-gifted furniture not sold in the shop.
    public let price: Int?
    public let theme: FurnitureTheme
    public let xueqiuLevel: Int?
    public let defaultX: Double
    public let defaultBottom: Double
    public let layer: FurnitureLayer

    public init(
        id: FurnitureID,
        room: RoomID,
        price: Int?,
        theme: FurnitureTheme = .basic,
        xueqiuLevel: Int? = nil,
        defaultX: Double,
        defaultBottom: Double,
        layer: FurnitureLayer
    ) {
        self.id = id
        self.room = room
        self.price = price
        self.theme = theme
        self.xueqiuLevel = xueqiuLevel
        self.defaultX = defaultX
        self.defaultBottom = defaultBottom
        self.layer = layer
    }
}

public struct RoomSkinDef: Equatable, Identifiable, Sendable {
    public let id: RoomSkinID
    public let price: Int

    public init(id: RoomSkinID, price: Int) {
        self.id = id
        self.price = price
    }
}

public struct TreasureDef: Equatable, Identifiable, Sendable {
    public let id: TreasureID
    public let rarity: TreasureRarity
    /// Preferred outing spot (`nil` for legend-tier items unlocked by packing Lv.4–5 items).
    public let spot: OutingSpot?

    public init(id: TreasureID, rarity: TreasureRarity, spot: OutingSpot?) {
        self.id = id
        self.rarity = rarity
        self.spot = spot
    }
}

public struct CustomerDef: Equatable, Sendable {
    public let id: CustomerID
    public let gift: FurnitureID
}

public enum PhotoCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case toy
    case furniture
    case food
    case daily
    case xueqiu
    case duo

    public static let coreCategories: [PhotoCategory] = [.toy, .furniture, .food, .daily]
}

public enum DailyCondition: String, Codable, Hashable, Sendable {
    case any
    case morning
    case night
    case rain
    case happy
    case toyCollector
}

public enum DuoCondition: String, Codable, Hashable, Sendable {
    case box
    case bothLevel3
    case daytime
    case sunnySpot
    case bothPlayed5
    case afterOuting
}

public enum PhotoTrigger: Equatable, Hashable, Sendable {
    case firstItem(MergeItem)
    case firstFurniture(FurnitureID)
    case playCount(Int)
    case toyWornOut
    case feedCount(Int)
    case fullBelly
    case firstHungry
    case daily(DailyCondition)
    case adopted
    case petCount(Int)
    case anyFurniture([FurnitureID])
    case duo(DuoCondition)
}

public struct PhotoDef: Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let category: PhotoCategory
    public let trigger: PhotoTrigger
    public let cat: CatID

    public init(id: String, category: PhotoCategory, trigger: PhotoTrigger, cat: CatID = .xiaoju) {
        self.id = id
        self.category = category
        self.trigger = trigger
        self.cat = cat
    }

    public var isRare: Bool {
        if case .daily(let condition) = trigger { return condition != .any }
        return false
    }
}

public enum AlbumTier: String, Codable, CaseIterable, Hashable, Sendable {
    case cozy
    case season
    case dream

    public var stars: String {
        switch self {
        case .cozy: "★"
        case .season: "★★"
        case .dream: "★★★"
        }
    }
}

public struct AlbumDateRange: Equatable, Hashable, Sendable {
    public let month: Int
    public let from: Int
    public let to: Int
}

public struct AlbumReq: Equatable, Hashable, Sendable {
    public var furniture: FurnitureID?
    public var day: Bool
    public var night: Bool
    public var asleep: Bool
    public var hours: ClosedRange<Int>? // [from, to) represented as from...(to-1)
    public var rain: Bool
    public var happy: Bool
    public var months: [Int]?
    public var dates: AlbumDateRange?
    public var daysTogether: Int?
    public var allGifts: Bool
    public var bedroom: Bool
    public var allOthers: Bool

    public init(
        furniture: FurnitureID? = nil,
        day: Bool = false,
        night: Bool = false,
        asleep: Bool = false,
        hours: ClosedRange<Int>? = nil,
        rain: Bool = false,
        happy: Bool = false,
        months: [Int]? = nil,
        dates: AlbumDateRange? = nil,
        daysTogether: Int? = nil,
        allGifts: Bool = false,
        bedroom: Bool = false,
        allOthers: Bool = false
    ) {
        self.furniture = furniture
        self.day = day
        self.night = night
        self.asleep = asleep
        self.hours = hours
        self.rain = rain
        self.happy = happy
        self.months = months
        self.dates = dates
        self.daysTogether = daysTogether
        self.allGifts = allGifts
        self.bedroom = bedroom
        self.allOthers = allOthers
    }
}

public struct AlbumPhotoDef: Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let tier: AlbumTier
    public let req: AlbumReq

    public init(id: String, tier: AlbumTier, req: AlbumReq) {
        self.id = id
        self.tier = tier
        self.req = req
    }
}

public struct OfflineNoteDef: Equatable, Identifiable, Sendable {
    public let id: String
    public let weather: SceneLight?
    public let furniture: FurnitureID?
}

public enum CatBubbleMood: String, CaseIterable, Sendable {
    case normal
    case sleep
    case hungry
}

public enum DiaryCatalog {
    public static let customers: [CustomerDef] = [
        .init(id: .ajian, gift: .giftAjian),
        .init(id: .grandma, gift: .giftGrandma),
        .init(id: .petshop, gift: .giftPetshop),
    ]

    public static func customer(_ id: CustomerID) -> CustomerDef {
        customers.first { $0.id == id }!
    }

    public static let roomSkins: [RoomSkinDef] = [
        .init(id: .defaultSkin, price: 0),
        .init(id: .honey, price: 800),
        .init(id: .mint, price: 800),
        .init(id: .sakura, price: 800),
    ]

    public static func roomSkinDef(_ id: RoomSkinID) -> RoomSkinDef {
        roomSkins.first { $0.id == id } ?? .init(id: .defaultSkin, price: 0)
    }

    public static let furniture: [FurnitureDef] = [
        // Basic purchasable (12)
        .init(id: .windowCushion, room: .livingroom, price: 120, defaultX: 0.16, defaultBottom: 0.63, layer: .floor),
        .init(id: .cardboardBox, room: .livingroom, price: 150, defaultX: 0.19, defaultBottom: 0.79, layer: .floor),
        .init(id: .plant, room: .livingroom, price: 180, defaultX: 0.07, defaultBottom: 0.72, layer: .floor),
        .init(id: .tunnel, room: .livingroom, price: 200, defaultX: 0.78, defaultBottom: 0.80, layer: .floor),
        .init(id: .sofaCover, room: .livingroom, price: 220, defaultX: 0.80, defaultBottom: 0.60, layer: .wall),
        .init(id: .foodBowl, room: .livingroom, price: 250, defaultX: 0.30, defaultBottom: 0.86, layer: .floor),
        .init(id: .catBed, room: .bedroom, price: 280, defaultX: 0.20, defaultBottom: 0.75, layer: .floor),
        .init(id: .rug, room: .bedroom, price: 320, defaultX: 0.48, defaultBottom: 0.87, layer: .flat),
        .init(id: .hammock, room: .bedroom, price: 380, defaultX: 0.80, defaultBottom: 0.40, layer: .wall),
        .init(id: .waterFountain, room: .livingroom, price: 450, defaultX: 0.68, defaultBottom: 0.86, layer: .floor),
        .init(id: .bookshelf, room: .bedroom, price: 520, defaultX: 0.80, defaultBottom: 0.87, layer: .floor),
        .init(id: .wallShelf, room: .livingroom, price: 600, defaultX: 0.72, defaultBottom: 0.33, layer: .wall),
        // Customer gifts (3)
        .init(id: .giftAjian, room: .livingroom, price: nil, defaultX: 0.68, defaultBottom: 0.67, layer: .floor),
        .init(id: .giftGrandma, room: .livingroom, price: nil, defaultX: 0.30, defaultBottom: 0.63, layer: .floor),
        .init(id: .giftPetshop, room: .bedroom, price: nil, defaultX: 0.77, defaultBottom: 0.74, layer: .floor),
        // Winter theme furniture (8, unlocks Lv.8 with Balcony; 2 require Xueqiu intimacy)
        .init(id: .winterKotatsu, room: .livingroom, price: 780, theme: .winter, xueqiuLevel: 5, defaultX: 0.42, defaultBottom: 0.66, layer: .floor),
        .init(id: .winterHeater, room: .livingroom, price: 620, theme: .winter, defaultX: 0.90, defaultBottom: 0.71, layer: .floor),
        .init(id: .winterTeaTray, room: .livingroom, price: 480, theme: .winter, defaultX: 0.13, defaultBottom: 0.86, layer: .floor),
        .init(id: .winterKnitBed, room: .bedroom, price: 680, theme: .winter, xueqiuLevel: 3, defaultX: 0.62, defaultBottom: 0.80, layer: .floor),
        .init(id: .winterLamp, room: .bedroom, price: 560, theme: .winter, defaultX: 0.08, defaultBottom: 0.70, layer: .floor),
        .init(id: .winterBlanketRack, room: .bedroom, price: 520, theme: .winter, defaultX: 0.36, defaultBottom: 0.68, layer: .floor),
        .init(id: .winterFireplaceMat, room: .livingroom, price: 660, theme: .winter, defaultX: 0.50, defaultBottom: 0.85, layer: .flat),
        .init(id: .winterFairyLights, room: .balcony, price: 900, theme: .winter, defaultX: 0.45, defaultBottom: 0.30, layer: .wall),
        // Spring theme furniture (8)
        .init(id: .springSakuraPot, room: .balcony, price: 820, theme: .spring, defaultX: 0.84, defaultBottom: 0.68, layer: .floor),
        .init(id: .springRattanChair, room: .balcony, price: 950, theme: .spring, xueqiuLevel: 5, defaultX: 0.24, defaultBottom: 0.72, layer: .floor),
        .init(id: .springFlowerRack, room: .balcony, price: 680, theme: .spring, defaultX: 0.56, defaultBottom: 0.62, layer: .floor),
        .init(id: .springWindchime, room: .balcony, price: 460, theme: .spring, defaultX: 0.60, defaultBottom: 0.46, layer: .wall),
        .init(id: .springPicnicMat, room: .balcony, price: 540, theme: .spring, xueqiuLevel: 3, defaultX: 0.50, defaultBottom: 0.86, layer: .flat),
        .init(id: .springTeaTable, room: .livingroom, price: 720, theme: .spring, defaultX: 0.86, defaultBottom: 0.77, layer: .floor),
        .init(id: .springCloudPillow, room: .bedroom, price: 650, theme: .spring, defaultX: 0.40, defaultBottom: 0.80, layer: .floor),
        .init(id: .springCurtain, room: .bedroom, price: 780, theme: .spring, defaultX: 0.72, defaultBottom: 0.26, layer: .wall),
    ]

    private static let furnitureMap: [FurnitureID: FurnitureDef] = Dictionary(
        uniqueKeysWithValues: furniture.map { ($0.id, $0) }
    )

    public static func furnitureDef(_ id: FurnitureID) -> FurnitureDef? {
        furnitureMap[id]
    }

    public static var shopFurniture: [FurnitureDef] {
        furniture.filter { $0.price != nil }
    }

    public static var basicShopFurniture: [FurnitureDef] {
        furniture.filter { $0.price != nil && $0.theme == .basic }
    }

    public static var themeShopFurniture: [FurnitureDef] {
        furniture.filter { $0.price != nil && $0.theme != .basic }
    }

    public static var giftFurnitureIDs: [FurnitureID] {
        furniture.filter { $0.price == nil }.map(\.id)
    }

    public static let treasures: [TreasureDef] = [
        .init(id: .ginkgo, rarity: .common, spot: .garden),
        .init(id: .clover, rarity: .rare, spot: .garden),
        .init(id: .daisy, rarity: .common, spot: .garden),
        .init(id: .pinecone, rarity: .common, spot: .garden),
        .init(id: .feather, rarity: .common, spot: .alley),
        .init(id: .pebble, rarity: .common, spot: .alley),
        .init(id: .button, rarity: .common, spot: .alley),
        .init(id: .marble, rarity: .rare, spot: .alley),
        .init(id: .yarn, rarity: .common, spot: .alley),
        .init(id: .woodcurl, rarity: .common, spot: .workshopAjian),
        .init(id: .woodbell, rarity: .rare, spot: .workshopAjian),
        .init(id: .cork, rarity: .common, spot: .workshopAjian),
        .init(id: .fishpaper, rarity: .common, spot: .shopGrandma),
        .init(id: .candywrap, rarity: .common, spot: .shopGrandma),
        .init(id: .coin, rarity: .rare, spot: .shopGrandma),
        .init(id: .bellribbon, rarity: .rare, spot: .petshopWindow),
        .init(id: .ticket, rarity: .rare, spot: .alley),
        .init(id: .seashell, rarity: .legend, spot: nil),
    ]

    private static let treasureMap: [TreasureID: TreasureDef] = Dictionary(
        uniqueKeysWithValues: treasures.map { ($0.id, $0) }
    )

    public static func treasureDef(_ id: TreasureID) -> TreasureDef {
        treasureMap[id]!
    }

    public static let tutorialToy = MergeItem(chain: .cloth, level: 3)
    public static let tutorialPhotoID = "photo_toy_01"

    /// Core 36 diary photos (Xiaoju only; controls core progress & Treasure Album unlock).
    public static let photos: [PhotoDef] = {
        var list: [PhotoDef] = [
            .init(id: "photo_toy_01", category: .toy, trigger: .firstItem(MergeItem(chain: .cloth, level: 3))),
            .init(id: "photo_toy_02", category: .toy, trigger: .firstItem(MergeItem(chain: .cloth, level: 4))),
            .init(id: "photo_toy_03", category: .toy, trigger: .firstItem(MergeItem(chain: .cloth, level: 5))),
            .init(id: "photo_toy_04", category: .toy, trigger: .firstItem(MergeItem(chain: .wood, level: 3))),
            .init(id: "photo_toy_05", category: .toy, trigger: .firstItem(MergeItem(chain: .wood, level: 4))),
            .init(id: "photo_toy_06", category: .toy, trigger: .firstItem(MergeItem(chain: .wood, level: 5))),
            .init(id: "photo_toy_07", category: .toy, trigger: .playCount(10)),
            .init(id: "photo_toy_08", category: .toy, trigger: .toyWornOut),
        ]
        for def in furniture where def.price != nil && def.theme == .basic {
            list.append(.init(id: "photo_furn_\(def.id.rawValue)", category: .furniture, trigger: .firstFurniture(def.id)))
        }
        list.append(contentsOf: [
            .init(id: "photo_food_01", category: .food, trigger: .firstItem(MergeItem(chain: .food, level: 3))),
            .init(id: "photo_food_02", category: .food, trigger: .firstItem(MergeItem(chain: .food, level: 4))),
            .init(id: "photo_food_03", category: .food, trigger: .firstItem(MergeItem(chain: .food, level: 5))),
            .init(id: "photo_food_04", category: .food, trigger: .feedCount(5)),
            .init(id: "photo_food_05", category: .food, trigger: .fullBelly),
            .init(id: "photo_food_06", category: .food, trigger: .firstHungry),
            .init(id: "photo_daily_01", category: .daily, trigger: .daily(.morning)),
            .init(id: "photo_daily_02", category: .daily, trigger: .daily(.rain)),
            .init(id: "photo_daily_03", category: .daily, trigger: .daily(.night)),
            .init(id: "photo_daily_04", category: .daily, trigger: .daily(.any)),
            .init(id: "photo_daily_05", category: .daily, trigger: .daily(.any)),
            .init(id: "photo_daily_06", category: .daily, trigger: .daily(.any)),
            .init(id: "photo_daily_07", category: .daily, trigger: .daily(.happy)),
            .init(id: "photo_daily_08", category: .daily, trigger: .daily(.any)),
            .init(id: "photo_daily_09", category: .daily, trigger: .daily(.any)),
            .init(id: "photo_daily_10", category: .daily, trigger: .daily(.toyCollector)),
        ])
        return list
    }()

    /// Xueqiu's 12 solo photos.
    public static let xueqiuPhotos: [PhotoDef] = [
        .init(id: "photo_xq_01", category: .xueqiu, trigger: .adopted, cat: .xueqiu),
        .init(id: "photo_xq_02", category: .xueqiu, trigger: .petCount(3), cat: .xueqiu),
        .init(id: "photo_xq_03", category: .xueqiu, trigger: .firstItem(MergeItem(chain: .food, level: 3)), cat: .xueqiu),
        .init(id: "photo_xq_04", category: .xueqiu, trigger: .firstItem(MergeItem(chain: .food, level: 4)), cat: .xueqiu),
        .init(id: "photo_xq_05", category: .xueqiu, trigger: .firstItem(MergeItem(chain: .food, level: 5)), cat: .xueqiu),
        .init(id: "photo_xq_06", category: .xueqiu, trigger: .firstItem(MergeItem(chain: .cloth, level: 3)), cat: .xueqiu),
        .init(id: "photo_xq_07", category: .xueqiu, trigger: .firstItem(MergeItem(chain: .cloth, level: 4)), cat: .xueqiu),
        .init(id: "photo_xq_08", category: .xueqiu, trigger: .anyFurniture([.catBed, .windowCushion]), cat: .xueqiu),
        .init(id: "photo_xq_09", category: .xueqiu, trigger: .anyFurniture([.wallShelf, .bookshelf]), cat: .xueqiu),
        .init(id: "photo_xq_10", category: .xueqiu, trigger: .daily(.any), cat: .xueqiu),
        .init(id: "photo_xq_11", category: .xueqiu, trigger: .daily(.rain), cat: .xueqiu),
        .init(id: "photo_xq_12", category: .xueqiu, trigger: .daily(.night), cat: .xueqiu),
    ]

    /// 6 Duo photos featuring both Xiaoju & Xueqiu.
    public static let duoPhotos: [PhotoDef] = [
        .init(id: "photo_duo_01", category: .duo, trigger: .duo(.box)),
        .init(id: "photo_duo_02", category: .duo, trigger: .duo(.bothLevel3)),
        .init(id: "photo_duo_03", category: .duo, trigger: .duo(.daytime)),
        .init(id: "photo_duo_04", category: .duo, trigger: .duo(.sunnySpot)),
        .init(id: "photo_duo_05", category: .duo, trigger: .duo(.bothPlayed5)),
        .init(id: "photo_duo_06", category: .duo, trigger: .duo(.afterOuting)),
    ]

    public static let extraPhotos: [PhotoDef] = xueqiuPhotos + duoPhotos

    /// 36 Treasure Album photos (18 Cozy ★, 12 Season ★★, 6 Dream ★★★), unlocked after completing the 36 core photos.
    public static let albumPhotos: [AlbumPhotoDef] = [
        // Cozy (18)
        .init(id: "photo_cozy_01", tier: .cozy, req: .init(furniture: .windowCushion, day: true)),
        .init(id: "photo_cozy_02", tier: .cozy, req: .init(furniture: .tunnel)),
        .init(id: "photo_cozy_03", tier: .cozy, req: .init(furniture: .plant)),
        .init(id: "photo_cozy_04", tier: .cozy, req: .init(furniture: .sofaCover)),
        .init(id: "photo_cozy_05", tier: .cozy, req: .init(furniture: .foodBowl)),
        .init(id: "photo_cozy_06", tier: .cozy, req: .init(furniture: .waterFountain)),
        .init(id: "photo_cozy_07", tier: .cozy, req: .init(furniture: .wallShelf)),
        .init(id: "photo_cozy_08", tier: .cozy, req: .init(furniture: .catBed)),
        .init(id: "photo_cozy_09", tier: .cozy, req: .init(furniture: .rug)),
        .init(id: "photo_cozy_10", tier: .cozy, req: .init(furniture: .hammock)),
        .init(id: "photo_cozy_11", tier: .cozy, req: .init(furniture: .bookshelf)),
        .init(id: "photo_cozy_12", tier: .cozy, req: .init(furniture: .giftAjian)),
        .init(id: "photo_cozy_13", tier: .cozy, req: .init(furniture: .giftGrandma)),
        .init(id: "photo_cozy_14", tier: .cozy, req: .init(furniture: .giftPetshop)),
        .init(id: "photo_cozy_15", tier: .cozy, req: .init(hours: 17...18)),
        .init(id: "photo_cozy_16", tier: .cozy, req: .init()),
        .init(id: "photo_cozy_17", tier: .cozy, req: .init()),
        .init(id: "photo_cozy_18", tier: .cozy, req: .init(bedroom: true)),
        // Season (12)
        .init(id: "photo_season_01", tier: .season, req: .init(day: true, months: [3, 4, 5])),
        .init(id: "photo_season_02", tier: .season, req: .init(months: [6, 7, 8])),
        .init(id: "photo_season_03", tier: .season, req: .init(months: [9, 10, 11])),
        .init(id: "photo_season_04", tier: .season, req: .init(rain: true, months: [12, 1, 2])),
        .init(id: "photo_season_05", tier: .season, req: .init(furniture: .catBed, night: true, rain: true)),
        .init(id: "photo_season_06", tier: .season, req: .init(day: true, rain: true, happy: true)),
        .init(id: "photo_season_07", tier: .season, req: .init(night: true, happy: true)),
        .init(id: "photo_season_08", tier: .season, req: .init(hours: 5...8, happy: true)),
        .init(id: "photo_season_09", tier: .season, req: .init(daysTogether: 30)),
        .init(id: "photo_season_10", tier: .season, req: .init(dates: .init(month: 12, from: 20, to: 31))),
        .init(id: "photo_season_11", tier: .season, req: .init(night: true, dates: .init(month: 1, from: 1, to: 7))),
        .init(id: "photo_season_12", tier: .season, req: .init(allGifts: true)),
        // Dream (6)
        .init(id: "photo_dream_01", tier: .dream, req: .init(asleep: true, happy: true)),
        .init(id: "photo_dream_02", tier: .dream, req: .init(asleep: true, happy: true)),
        .init(id: "photo_dream_03", tier: .dream, req: .init(asleep: true, happy: true)),
        .init(id: "photo_dream_04", tier: .dream, req: .init(asleep: true, happy: true)),
        .init(id: "photo_dream_05", tier: .dream, req: .init(asleep: true, happy: true)),
        .init(id: "photo_dream_06", tier: .dream, req: .init(asleep: true, happy: true, allOthers: true)),
    ]

    public static var allPhotoIDs: [String] {
        photos.map(\.id) + extraPhotos.map(\.id) + albumPhotos.map(\.id)
    }

    private static let photoMap: [String: PhotoDef] = Dictionary(
        uniqueKeysWithValues: (photos + extraPhotos).map { ($0.id, $0) }
    )

    private static let albumPhotoMap: [String: AlbumPhotoDef] = Dictionary(
        uniqueKeysWithValues: albumPhotos.map { ($0.id, $0) }
    )

    public static func photoDef(_ id: String) -> PhotoDef? {
        photoMap[id]
    }

    public static func albumPhotoDef(_ id: String) -> AlbumPhotoDef? {
        albumPhotoMap[id]
    }

    public static func isExtraPhoto(_ id: String) -> Bool {
        extraPhotos.contains { $0.id == id }
    }

    public static func catPhotos(for catID: CatID) -> [PhotoDef] {
        catID == .primary ? photos : xueqiuPhotos.filter { $0.cat == catID }
    }

    /// 30 offline notes keyed by localization ID (`note.01`...`note.30`).
    public static let offlineNotes: [OfflineNoteDef] = [
        .init(id: "note.01", weather: nil, furniture: nil),
        .init(id: "note.02", weather: nil, furniture: nil),
        .init(id: "note.03", weather: nil, furniture: nil),
        .init(id: "note.04", weather: nil, furniture: nil),
        .init(id: "note.05", weather: nil, furniture: nil),
        .init(id: "note.06", weather: nil, furniture: nil),
        .init(id: "note.07", weather: nil, furniture: nil),
        .init(id: "note.08", weather: nil, furniture: nil),
        .init(id: "note.09", weather: nil, furniture: nil),
        .init(id: "note.10", weather: nil, furniture: nil),
        .init(id: "note.11", weather: nil, furniture: nil),
        .init(id: "note.12", weather: nil, furniture: nil),
        .init(id: "note.13", weather: .rain, furniture: nil),
        .init(id: "note.14", weather: .rain, furniture: nil),
        .init(id: "note.15", weather: .rain, furniture: nil),
        .init(id: "note.16", weather: .rain, furniture: nil),
        .init(id: "note.17", weather: .rain, furniture: nil),
        .init(id: "note.18", weather: .rain, furniture: nil),
        .init(id: "note.19", weather: .night, furniture: nil),
        .init(id: "note.20", weather: .night, furniture: nil),
        .init(id: "note.21", weather: .night, furniture: nil),
        .init(id: "note.22", weather: .night, furniture: nil),
        .init(id: "note.23", weather: .night, furniture: nil),
        .init(id: "note.24", weather: .night, furniture: nil),
        .init(id: "note.25", weather: nil, furniture: .plant),
        .init(id: "note.26", weather: nil, furniture: .windowCushion),
        .init(id: "note.27", weather: nil, furniture: .bookshelf),
        .init(id: "note.28", weather: nil, furniture: .waterFountain),
        .init(id: "note.29", weather: nil, furniture: .sofaCover),
        .init(id: "note.30", weather: nil, furniture: .tunnel),
    ]

    public static func bubbleKeys(for mood: CatBubbleMood, cat: CatID = .primary) -> [String] {
        let prefix = cat == .xueqiu ? "bubble.xueqiu" : "bubble"
        switch mood {
        case .normal: return (1...10).map { String(format: "\(prefix).normal.%02d", $0) }
        case .sleep: return (1...4).map { String(format: "\(prefix).sleep.%02d", $0) }
        case .hungry: return (1...3).map { String(format: "\(prefix).hungry.%02d", $0) }
        }
    }

    public static func pickBubbleKey(
        mood: CatBubbleMood,
        cat: CatID = .primary,
        excluding last: String?,
        randomUnit: Double
    ) -> String {
        let pool = bubbleKeys(for: mood, cat: cat)
        let choices = pool.count > 1 ? pool.filter { $0 != last } : pool
        let idx = min(choices.count - 1, max(0, Int(floor(randomUnit * Double(choices.count)))))
        return choices[idx]
    }
}
