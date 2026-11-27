import Foundation
import Observation
import CatGameCore

@Observable
@MainActor
final class GameLocalization {
    static let shared = GameLocalization()
    var language: GameLanguage = .preferred(in: Locale.preferredLanguages)

    private init() {}
}

@MainActor
enum GameStrings {
    static func text(_ key: String) -> String {
        let dictionary: [String: String]
        switch GameLocalization.shared.language {
        case .simplifiedChinese: dictionary = chinese
        case .traditionalChinese: dictionary = traditionalChinese
        case .english: dictionary = english
        }
        return dictionary[key] ?? chinese[key] ?? key
    }

    static func format(_ key: String, _ values: CVarArg...) -> String {
        String(
            format: text(key),
            locale: Locale(identifier: GameLocalization.shared.language.rawValue),
            arguments: values
        )
    }

    static func itemName(_ item: MergeItem) -> String {
        text("item.\(item.rawID)")
    }

    static func chainName(_ chain: MergeChain) -> String {
        text("chain.\(chain.rawValue)")
    }

    static func generatorName(_ chain: MergeChain) -> String {
        text("gen.\(chain.rawValue)")
    }

    static func furnitureName(_ id: FurnitureID) -> String {
        text("furn.\(id.rawValue)")
    }

    static func roomSkinName(_ id: RoomSkinID) -> String {
        text("skin.\(id.rawValue)")
    }

    static func catName(_ id: CatID) -> String {
        text("cat.\(id.rawValue)")
    }

    static func customerName(_ id: CustomerID) -> String {
        text("customer.\(id.rawValue)")
    }

    static func roomName(_ id: RoomID) -> String {
        text("room.\(id.rawValue)")
    }

    static func photoTitle(_ id: String) -> String {
        text("photo.\(id).title")
    }

    static func photoCaption(_ id: String) -> String {
        text("photo.\(id).caption")
    }

    static func albumPhotoHint(_ id: String) -> String {
        text("album.hint.\(id)")
    }

    static func albumTierName(_ tier: AlbumTier) -> String {
        text("album.tier.\(tier.rawValue)")
    }

    static func photoCategoryName(_ category: PhotoCategory) -> String {
        text("diary.cat.\(category.rawValue)")
    }

    static func treasureName(_ id: TreasureID) -> String {
        text("treasure.\(id.rawValue).name")
    }

    static func treasureFirst(_ id: TreasureID) -> String {
        text("treasure.\(id.rawValue).first")
    }

    static func treasureRepeat(_ id: TreasureID) -> String {
        text("treasure.\(id.rawValue).repeat")
    }

    static func outingSpotName(_ spot: OutingSpot) -> String {
        text("outing.spot.\(spot.rawValue)")
    }

    static func customerStoryText(customer: CustomerID, index: Int) -> String {
        text(String(format: "story.%@.%02d", customer.rawValue, index + 1))
    }

    static func weekendOrderLine(for customer: CustomerID) -> String {
        text("weekend.line.\(customer.rawValue)")
    }

    static func milestoneTitle(_ id: MilestoneID) -> String {
        text("milestone.\(id.rawValue).title")
    }

    static func milestoneBody(_ id: MilestoneID) -> String {
        text("milestone.\(id.rawValue).body")
    }

    static func wishLabel(_ goal: WishGoal) -> String {
        switch goal {
        case .pet: text("wish.goal.pet")
        case .play(let item): format("wish.goal.play", itemName(item))
        case .feed(let item): format("wish.goal.feed", itemName(item))
        }
    }

    static func wishHint(_ goal: WishGoal, bonusXP: Int) -> String {
        switch goal {
        case .pet: format("wish.hint.pet", bonusXP)
        case .play(let item): format("wish.hint.play", itemName(item), bonusXP)
        case .feed(let item): format("wish.hint.feed", itemName(item), bonusXP)
        }
    }

    static func unlockDescription(_ rule: UnlockRule) -> String {
        switch rule.kind {
        case .chain(let chain): format("unlock.chain", generatorName(chain))
        case .room(let room): format("unlock.room", roomName(room))
        case .customer(let customer): format("unlock.customer", customerName(customer))
        }
    }
}
