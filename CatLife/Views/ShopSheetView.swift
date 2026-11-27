import SwiftUI
import CatGameCore

struct ShopSheetView: View {
    private enum ShopTab: String, CaseIterable, Identifiable {
        case basic
        case themes
        case skins
        var id: String { rawValue }
    }

    @Bindable var store: DiaryAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: ShopTab = .basic

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("", selection: $selectedTab) {
                        Text(GameStrings.text("shop.tab.basic")).tag(ShopTab.basic)
                        Text(GameStrings.text("shop.tab.themes")).tag(ShopTab.themes)
                        Text(GameStrings.text("shop.tab.skins")).tag(ShopTab.skins)
                    }
                    .pickerStyle(.segmented)

                    if store.isNightSaleActive && selectedTab != .basic {
                        HStack(spacing: 8) {
                            Image(systemName: "moon.stars.fill")
                                .foregroundStyle(RoomTheme.gold)
                            Text(GameStrings.text("shop.nightSaleBanner"))
                                .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                                .foregroundStyle(RoomTheme.ink)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoomTheme.rewardPaper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(RoomTheme.gold.opacity(0.7), lineWidth: 1.2))
                    }

                    switch selectedTab {
                    case .basic:
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(DiaryCatalog.basicShopFurniture, id: \.id) { def in
                                furnitureCard(def)
                            }
                        }
                    case .themes:
                        themeSection(title: GameStrings.text("shop.theme.winter"), items: DiaryCatalog.themeShopFurniture.filter { $0.theme == .winter })
                        themeSection(title: GameStrings.text("shop.theme.spring"), items: DiaryCatalog.themeShopFurniture.filter { $0.theme == .spring })
                    case .skins:
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(DiaryCatalog.roomSkins) { def in
                                skinCard(def)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(RoomTheme.cream.ignoresSafeArea())
            .navigationTitle(GameStrings.text("shop.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 5) {
                        AssetOrSymbol(asset: "ui_coin", symbol: "dollarsign.circle.fill", size: 18, tint: RoomTheme.gold)
                        Text("\(store.state.coins)")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(RoomTheme.ink)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 6)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(GameStrings.text("common.done")) { dismiss() }
                        .fontWeight(.bold)
                        .foregroundStyle(RoomTheme.coralDeep)
                }
            }
        }
    }

    private func themeSection(title: String, items: [FurnitureDef]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15.5, weight: .heavy, design: .rounded))
                .foregroundStyle(RoomTheme.ink)
                .padding(.horizontal, 4)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items, id: \.id) { def in
                    furnitureCard(def)
                }
            }
        }
    }

    private func furnitureCard(_ def: FurnitureDef) -> some View {
        let owned = store.state.home.furnitureOwned.contains(def.id)
        let lock = DiaryThemes.furnitureLock(store.state, id: def.id)
        let basePrice = def.price ?? 0
        let price = store.currentFurniturePrice(def.id)
        let onSale = store.isFurnitureOnSale(def.id) && price < basePrice
        let canAfford = store.state.coins >= price
        let isWish = store.state.home.wishlist == def.id

        return VStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [RoomTheme.rewardPaper, RoomTheme.cream],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 108)

                Ellipse()
                    .fill(RoomTheme.wood.opacity(0.32))
                    .frame(width: 72, height: 14)
                    .blur(radius: 3)
                    .offset(y: 34)

                Image(def.id.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 82, height: 82)
                    .opacity(lock == nil ? 1.0 : 0.45)

                VStack {
                    HStack {
                        Text(GameStrings.roomName(def.room))
                            .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(RoomTheme.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(RoomTheme.paper.opacity(0.9), in: Capsule())
                        Spacer()
                        if onSale && !owned {
                            Text(GameStrings.text("shop.saleBadge"))
                                .font(.system(size: 9.5, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(RoomTheme.coral, in: Capsule())
                        } else if !owned && lock == nil {
                            Button {
                                store.toggleWishlist(def.id)
                            } label: {
                                Image(systemName: isWish ? "heart.fill" : "heart")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(isWish ? RoomTheme.heartPink : RoomTheme.secondary.opacity(0.65))
                                    .frame(width: 28, height: 28)
                                    .background(RoomTheme.paper.opacity(0.92), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer()
                }
                .padding(7)
            }

            VStack(spacing: 2) {
                Text(GameStrings.furnitureName(def.id))
                    .font(.system(size: 14.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(RoomTheme.ink)
                    .lineLimit(1)

                if onSale && !owned {
                    Text("\(basePrice)")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .strikethrough()
                        .foregroundStyle(RoomTheme.secondary.opacity(0.7))
                } else if isWish && !owned {
                    Text(GameStrings.text("shop.wishlistTag"))
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(RoomTheme.coralDeep)
                }
            }

            if owned {
                Label(GameStrings.text("shop.owned"), systemImage: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(RoomTheme.darkMint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoomTheme.paleMint, in: Capsule())
            } else if let lock {
                let lockText: String = switch lock {
                case .room(let room):
                    GameStrings.format("common.lvFormat", DiaryProgression.unlockLevel(for: .room(room)))
                case .theme(let lv):
                    GameStrings.format("shop.themeLocked", lv)
                case .xueqiu(let lv):
                    GameStrings.format("shop.xueqiuLocked", lv)
                }
                Label(lockText, systemImage: "lock.fill")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(RoomTheme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                    .background(RoomTheme.track, in: Capsule())
            } else {
                Button {
                    store.buyFurniture(def.id, quoted: price)
                } label: {
                    HStack(spacing: 4) {
                        AssetOrSymbol(asset: "ui_coin", symbol: "dollarsign.circle.fill", size: 14, tint: canAfford ? .white : RoomTheme.gold)
                        Text(canAfford ? "\(price)" : GameStrings.format("shop.shortCoins", price - store.state.coins))
                            .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(canAfford ? .white : RoomTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8.5)
                    .background(
                        Capsule().fill(canAfford ? (onSale ? RoomTheme.coral : RoomTheme.mint) : RoomTheme.chipBg)
                            .shadow(color: canAfford ? (onSale ? RoomTheme.coralDeep : RoomTheme.darkMint).opacity(0.6) : .clear, radius: 0, y: 2)
                    )
                }
                .buttonStyle(CraftIconBadgeButtonStyle())
            }
        }
        .padding(10)
        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    (onSale && !owned) ? RoomTheme.gold : (isWish && !owned ? RoomTheme.coral : RoomTheme.wood.opacity(0.65)),
                    lineWidth: (onSale || (isWish && !owned)) ? 1.8 : 1.1
                )
        )
        .shadow(color: RoomTheme.ink.opacity(0.08), radius: 5, y: 3)
    }

    private func skinCard(_ def: RoomSkinDef) -> some View {
        let owned = store.state.home.skinsOwned.contains(def.id)
        let equipped = store.state.home.activeSkin == def.id
        let unlocked = DiaryThemes.themesUnlocked(store.state) || def.id == .defaultSkin
        let price = store.currentSkinPrice(def.id)
        let onSale = store.isSkinOnSale(def.id) && price < def.price
        let canAfford = store.state.coins >= price

        return VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(skinSwatchColor(def.id))
                    .frame(height: 92)
                    .overlay {
                        if let deco = def.id.decoAssetName {
                            Image(deco)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 68, height: 68)
                        } else {
                            Image(systemName: "house.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(RoomTheme.wood)
                        }
                    }

                if onSale && !owned {
                    Text(GameStrings.text("shop.saleBadge"))
                        .font(.system(size: 9.5, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoomTheme.coral, in: Capsule())
                        .padding(6)
                }
            }

            VStack(spacing: 2) {
                Text(GameStrings.roomSkinName(def.id))
                    .font(.system(size: 14.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(RoomTheme.ink)
                if onSale && !owned {
                    Text("\(def.price)")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .strikethrough()
                        .foregroundStyle(RoomTheme.secondary.opacity(0.7))
                }
            }

            if equipped {
                Label(GameStrings.text("shop.skinEquipped"), systemImage: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(RoomTheme.darkMint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoomTheme.paleMint, in: Capsule())
            } else if owned {
                Button(GameStrings.text("shop.skinUse")) {
                    store.equipRoomSkin(def.id)
                }
                .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8.5)
                .background(RoomTheme.coral, in: Capsule())
            } else if !unlocked {
                Label(GameStrings.format("shop.themeLocked", DiaryThemes.themeUnlockLevel()), systemImage: "lock.fill")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(RoomTheme.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoomTheme.track, in: Capsule())
            } else {
                Button {
                    store.buyRoomSkin(def.id, quoted: price)
                } label: {
                    HStack(spacing: 4) {
                        AssetOrSymbol(asset: "ui_coin", symbol: "dollarsign.circle.fill", size: 14, tint: canAfford ? .white : RoomTheme.gold)
                        Text(canAfford ? "\(price)" : GameStrings.format("shop.shortCoins", price - store.state.coins))
                            .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(canAfford ? .white : RoomTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8.5)
                    .background(Capsule().fill(canAfford ? (onSale ? RoomTheme.coral : RoomTheme.mint) : RoomTheme.chipBg))
                }
                .buttonStyle(CraftIconBadgeButtonStyle())
            }
        }
        .padding(10)
        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(equipped ? RoomTheme.mint : RoomTheme.wood.opacity(0.65), lineWidth: equipped ? 1.8 : 1.1))
        .shadow(color: RoomTheme.ink.opacity(0.08), radius: 5, y: 3)
    }

    private func skinSwatchColor(_ id: RoomSkinID) -> Color {
        switch id {
        case .defaultSkin: Color(red: 0.953, green: 0.863, blue: 0.722)
        case .honey: Color(red: 0.914, green: 0.722, blue: 0.471).opacity(0.45)
        case .mint: Color(red: 0.749, green: 0.878, blue: 0.776).opacity(0.55)
        case .sakura: Color(red: 0.957, green: 0.788, blue: 0.824).opacity(0.55)
        }
    }
}
