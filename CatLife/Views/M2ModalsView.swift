import SwiftUI
import CatGameCore
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Entrance Door Basket Sheet

struct BasketSheetView: View {
    @Bindable var store: DiaryAppStore
    @Environment(\.dismiss) private var dismiss

    private struct Candidate: Identifiable {
        let id: String
        let source: BasketSource
        let index: Int
        let item: MergeItem
        let usesLeft: Int?
    }

    private var candidates: [Candidate] {
        var list: [Candidate] = []
        for (idx, item) in store.state.home.food.enumerated() where DiaryOuting.basketCandidate(item) {
            list.append(Candidate(id: "food-\(idx)-\(item.rawID)", source: .food, index: idx, item: item, usesLeft: nil))
        }
        for (idx, toy) in store.state.home.toys.enumerated() where DiaryOuting.basketCandidate(toy.item) {
            list.append(Candidate(id: "toy-\(idx)-\(toy.item.rawID)-\(toy.usesLeft)", source: .toy, index: idx, item: toy.item, usesLeft: toy.usesLeft))
        }
        return list
    }

    private let columns = [GridItem(.adaptive(minimum: 74), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text(GameStrings.text("outing.basketSubtitle"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(RoomTheme.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    // Current basket contents
                    HStack(spacing: 12) {
                        ZStack(alignment: .bottomTrailing) {
                            Image(store.state.home.basket != nil ? "ui_basket_full" : "ui_basket_empty")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 56, height: 56)
                            if let basket = store.state.home.basket {
                                Image(basket.item.assetName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 28, height: 28)
                                    .padding(2)
                                    .background(RoomTheme.paper, in: Circle())
                            }
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            if let basket = store.state.home.basket {
                                Text(GameStrings.format("outing.basketCurrent", GameStrings.itemName(basket.item)))
                                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                                    .foregroundStyle(RoomTheme.ink)
                                if let uses = basket.usesLeft {
                                    Text(GameStrings.format("home.toyUsesFormat", uses))
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(RoomTheme.secondary)
                                }
                            } else {
                                Text(GameStrings.text("outing.basketEmpty"))
                                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(RoomTheme.secondary)
                            }
                        }

                        Spacer()

                        if store.state.home.basket != nil {
                            Button(GameStrings.text("outing.basketUnpack")) {
                                store.unpackBasket()
                            }
                            .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(RoomTheme.coralDeep)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoomTheme.paleCoral, in: Capsule())
                        }
                    }
                    .padding(14)
                    .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(RoomTheme.wood.opacity(0.65), lineWidth: 1.2))

                    Text(candidates.isEmpty ? GameStrings.text("outing.basketNoItems") : GameStrings.text("outing.basketPickHint"))
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(RoomTheme.secondary)
                        .multilineTextAlignment(.center)

                    if !candidates.isEmpty {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(candidates) { entry in
                                Button {
                                    store.packBasket(source: entry.source, index: entry.index)
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(entry.item.assetName)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 44, height: 44)
                                        Text(GameStrings.itemName(entry.item))
                                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                            .foregroundStyle(RoomTheme.ink)
                                            .lineLimit(1)
                                        if let uses = entry.usesLeft {
                                            Text("×\(uses)")
                                                .font(.system(size: 10, weight: .black, design: .rounded))
                                                .foregroundStyle(RoomTheme.coralDeep)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 6)
                                    .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(RoomTheme.wood.opacity(0.6), lineWidth: 1))
                                }
                                .buttonStyle(CraftIconBadgeButtonStyle())
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(RoomTheme.cream.ignoresSafeArea())
            .navigationTitle(GameStrings.text("outing.basketTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(GameStrings.text("common.done")) { dismiss() }
                        .fontWeight(.bold)
                        .foregroundStyle(RoomTheme.coralDeep)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Outing Arrival Celebration Overlay

struct OutingArrivalOverlayView: View {
    let arrival: OutingArrival
    let onKeep: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.52).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    Text(GameStrings.text("outing.arrivalTitle"))
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(RoomTheme.ink)

                    Text(GameStrings.format("outing.arrivalSpot", GameStrings.outingSpotName(arrival.spot)))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(RoomTheme.secondary)

                    ZStack(alignment: .topTrailing) {
                        Image(arrival.treasure.assetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 126, height: 126)
                            .padding(14)
                            .background(RoomTheme.rewardPaper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(RoomTheme.wood.opacity(0.6), lineWidth: 1.2))

                        Text(arrival.isNewTreasure
                            ? GameStrings.text("outing.arrivalNew")
                            : GameStrings.format("outing.arrivalRepeat", arrival.count))
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(arrival.isNewTreasure ? .white : RoomTheme.ink)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(arrival.isNewTreasure ? RoomTheme.coral : RoomTheme.gold, in: Capsule())
                            .offset(x: 8, y: -8)
                    }

                    Text(GameStrings.treasureName(arrival.treasure))
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(RoomTheme.ink)

                    Text(arrival.isNewTreasure
                        ? GameStrings.treasureFirst(arrival.treasure)
                        : GameStrings.treasureRepeat(arrival.treasure))
                        .font(.system(size: 13.5, weight: .medium, design: .rounded))
                        .foregroundStyle(RoomTheme.secondary)
                        .multilineTextAlignment(.center)

                    let extras: [String] = [
                        arrival.packedItem.map { GameStrings.format("outing.arrivalPacked", GameStrings.itemName($0)) },
                        arrival.bonusMood > 0 ? GameStrings.format("outing.arrivalMood", Int(arrival.bonusMood.rounded())) : nil,
                        arrival.bonusCoins > 0 ? GameStrings.format("outing.arrivalCoins", arrival.bonusCoins) : nil,
                    ].compactMap { $0 }
                    if !extras.isEmpty {
                        Text(extras.joined(separator: " · "))
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(RoomTheme.coralDeep)
                    }

                    if let note = arrival.neighborNote {
                        HStack(spacing: 10) {
                            Image(note.customer.avatarAssetName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 46, height: 46)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(RoomTheme.wood, lineWidth: 1.5))
                            Text(GameStrings.text(note.localizationKey))
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(RoomTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoomTheme.rewardPaper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(RoomTheme.wood, style: StrokeStyle(lineWidth: 1.3, dash: [5, 4]))
                        )
                    }

                    Button(GameStrings.text("outing.arrivalKeep"), action: onKeep)
                        .buttonStyle(WarmButtonStyle(fill: RoomTheme.coral, shadowColor: RoomTheme.coralDeep))
                        .padding(.top, 4)
                }
                .padding(22)
                .background(WatercolorPanelBackground())
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// MARK: - Second Cat Adoption Celebration Overlay

struct AdoptionOverlayView: View {
    let onKeep: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.52).ignoresSafeArea()
            VStack(spacing: 16) {
                Image("cat_xueqiu_happy")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .padding(10)
                    .background(RoomTheme.rewardPaper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                Text(GameStrings.text("adoption.title"))
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundStyle(RoomTheme.ink)
                    .multilineTextAlignment(.center)

                Text(GameStrings.text("adoption.body"))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(RoomTheme.secondary)
                    .multilineTextAlignment(.center)

                Button(GameStrings.text("adoption.keep"), action: onKeep)
                    .buttonStyle(WarmButtonStyle(fill: RoomTheme.coral, shadowColor: RoomTheme.coralDeep))
            }
            .padding(24)
            .background(WatercolorPanelBackground())
            .padding(.horizontal, 26)
        }
    }
}

// MARK: - Customer Serialized Story Overlay

struct CustomerStoryOverlayView: View {
    let story: StoryUnlock
    let onKeep: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.50).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(story.customer.avatarAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(RoomTheme.gold, lineWidth: 2.5))

                Text(GameStrings.format("story.modalTitle", GameStrings.customerName(story.customer)))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(RoomTheme.ink)

                Text(GameStrings.format("story.milestoneTag", story.milestone))
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(RoomTheme.coralDeep)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(RoomTheme.paleCoral, in: Capsule())

                Text(GameStrings.customerStoryText(customer: story.customer, index: story.index))
                    .font(.system(size: 14.5, weight: .medium, design: .rounded))
                    .foregroundStyle(RoomTheme.ink)
                    .multilineTextAlignment(.leading)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoomTheme.rewardPaper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(RoomTheme.rewardBorder, lineWidth: 1.2))

                if story.bonusCoins > 0 {
                    HStack(spacing: 6) {
                        AssetOrSymbol(asset: "ui_coin", symbol: "dollarsign.circle.fill", size: 18, tint: RoomTheme.gold)
                        Text(GameStrings.format("story.bonusCoins", story.bonusCoins))
                            .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(RoomTheme.coralDeep)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(RoomTheme.gold.opacity(0.18), in: Capsule())
                }

                Button(GameStrings.text("milestone.keep"), action: onKeep)
                    .buttonStyle(WarmButtonStyle(fill: RoomTheme.mint, shadowColor: RoomTheme.darkMint))
            }
            .padding(24)
            .background(WatercolorPanelBackground())
            .padding(.horizontal, 26)
        }
    }
}

// MARK: - Milestone Keepsake Overlay

struct MilestoneOverlayView: View {
    let milestone: MilestoneID
    let daysTogether: Int
    let onKeep: () -> Void

    private var heroAsset: String {
        switch milestone {
        case .growJunior: "cat_junior_happy"
        case .growAdult: "cat_adult_happy"
        case .diaryHalf, .diaryFull: "ui_diary"
        default: "cat_happy"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.52).ignoresSafeArea()
            VStack(spacing: 15) {
                Image(heroAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 124, height: 124)

                Text(GameStrings.milestoneTitle(milestone))
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundStyle(RoomTheme.ink)

                Text(GameStrings.milestoneBody(milestone))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(RoomTheme.secondary)
                    .multilineTextAlignment(.center)

                Text(GameStrings.format("diary.daysTogether", daysTogether))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(RoomTheme.coralDeep)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(RoomTheme.paleCoral, in: Capsule())

                Button(GameStrings.text("milestone.keep"), action: onKeep)
                    .buttonStyle(WarmButtonStyle(fill: RoomTheme.coral, shadowColor: RoomTheme.coralDeep))
            }
            .padding(24)
            .background(WatercolorPanelBackground())
            .padding(.horizontal, 26)
        }
    }
}

// MARK: - Native Polaroid Postcard Renderer & ShareLink

struct PolaroidPostcardView: View {
    let photoID: String
    let title: String
    let caption: String
    let capturedAt: Int64?
    let createdAt: Int64
    let calendar: Calendar

    private var albumTier: AlbumTier? { DiaryCatalog.albumPhotoDef(photoID)?.tier }
    private var isRare: Bool { DiaryCatalog.photoDef(photoID)?.isRare == true }

    private var dayNumber: Int? {
        guard let capturedAt else { return nil }
        return DayClock.daysTogether(createdAt: createdAt, now: capturedAt, calendar: calendar)
    }

    private var weatherSymbol: String? {
        guard let capturedAt else { return nil }
        let dk = DayClock.dayKey(for: capturedAt, calendar: calendar)
        if DiaryHome.isRainyDay(dayKey: dk) { return "cloud.rain.fill" }
        if DiaryHome.isNightHour(DayClock.hour(for: capturedAt, calendar: calendar)) { return "moon.fill" }
        return "sun.max.fill"
    }

    private var formattedDate: String {
        guard let capturedAt else { return GameStrings.text("postcard.memoryDate") }
        let c = DayClock.gregorianComponents(for: capturedAt, calendar: calendar)
        return String(format: "%04d.%02d.%02d", c.year, c.month, c.day)
    }

    var body: some View {
        let paperColor = albumTier == .dream ? Color(red: 1.0, green: 0.976, blue: 0.922) : Color(red: 0.992, green: 0.973, blue: 0.937)
        let goldAccent = Color(red: 0.788, green: 0.588, blue: 0.184)

        ZStack {
            paperColor

            if albumTier == .dream || albumTier == .season {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(albumTier == .dream ? goldAccent : goldAccent.opacity(0.55), lineWidth: albumTier == .dream ? 3 : 2)
                    .padding(12)
            }

            VStack(alignment: .leading, spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    Image(photoID)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 300, height: 225)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(RoomTheme.wood.opacity(0.45), lineWidth: 1.5))

                    // Tilted circular postmark stamp
                    ZStack {
                        Circle()
                            .fill(paperColor.opacity(0.9))
                            .frame(width: 56, height: 56)
                        Circle()
                            .stroke(RoomTheme.coralDeep.opacity(0.75), lineWidth: 1.8)
                            .frame(width: 52, height: 52)
                        Circle()
                            .stroke(RoomTheme.coralDeep.opacity(0.55), lineWidth: 1)
                            .frame(width: 44, height: 44)
                        VStack(spacing: 1) {
                            Image(systemName: weatherSymbol ?? "pawprint.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(RoomTheme.coralDeep.opacity(0.82))
                            Text(dayNumber.map { GameStrings.format("postcard.dayStamp", $0) } ?? GameStrings.text("postcard.memoryStamp"))
                                .font(.system(size: 8.5, weight: .black, design: .rounded))
                                .foregroundStyle(RoomTheme.coralDeep.opacity(0.82))
                        }
                    }
                    .rotationEffect(.degrees(-10))
                    .offset(x: 10, y: -10)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .foregroundStyle(RoomTheme.ink)
                        if let tier = albumTier {
                            Text("\(tier.stars) \(GameStrings.albumTierName(tier))")
                                .font(.system(size: 10.5, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(goldAccent, in: Capsule())
                        } else if isRare {
                            Text(GameStrings.text("diary.rareBadge"))
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(RoomTheme.gold, in: Capsule())
                        }
                    }

                    Text(caption)
                        .font(.system(size: 13.5, weight: .medium, design: .rounded))
                        .foregroundStyle(RoomTheme.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)

                Spacer(minLength: 6)

                HStack {
                    Spacer()
                    Text("\(formattedDate) · \(GameStrings.text("app.title"))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(RoomTheme.secondary.opacity(0.75))
                }
            }
            .padding(24)
        }
        .frame(width: 348, height: 464)
    }
}

struct PostcardShareButton: View {
    let photoID: String
    let capturedAt: Int64?
    let createdAt: Int64
    let calendar: Calendar

    @State private var renderedImage: Image?

    var body: some View {
        let title = GameStrings.photoTitle(photoID)
        Group {
            if let renderedImage {
                ShareLink(
                    item: renderedImage,
                    preview: SharePreview(title, image: renderedImage)
                ) {
                    Label(GameStrings.text("postcard.share"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(SoftPaperButtonStyle())
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .task(id: "\(photoID)-\(GameLocalization.shared.language.rawValue)") {
            renderPostcard()
        }
    }

    @MainActor
    private func renderPostcard() {
        let card = PolaroidPostcardView(
            photoID: photoID,
            title: GameStrings.photoTitle(photoID),
            caption: GameStrings.photoCaption(photoID),
            capturedAt: capturedAt,
            createdAt: createdAt,
            calendar: calendar
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2.0
        #if canImport(UIKit)
        if let uiImage = renderer.uiImage {
            renderedImage = Image(uiImage: uiImage)
        }
        #endif
    }
}
