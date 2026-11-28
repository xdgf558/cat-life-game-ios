import SwiftUI
import CatGameCore

private struct InspectingPhotoItem: Identifiable {
    let id: String
    let isRare: Bool
    let tier: AlbumTier?
}

struct DiarySheetView: View {
    private enum DiaryTab: String, CaseIterable, Identifiable {
        case core
        case xueqiu
        case album
        case treasures
        var id: String { rawValue }
    }

    @Bindable var store: DiaryAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: DiaryTab = .core
    @State private var selectedCategory: PhotoCategory?
    @State private var selectedAlbumTier: AlbumTier?
    @State private var inspectingPhoto: InspectingPhotoItem?
    @State private var inspectingTreasure: TreasureDef?

    private var filteredCorePhotos: [PhotoDef] {
        guard let category = selectedCategory else { return DiaryCatalog.photos }
        return DiaryCatalog.photos.filter { $0.category == category }
    }

    private var filteredAlbumPhotos: [AlbumPhotoDef] {
        guard let tier = selectedAlbumTier else { return DiaryCatalog.albumPhotos }
        return DiaryCatalog.albumPhotos.filter { $0.tier == tier }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    scrapbookHeaderCard
                    sectionTabBar

                    switch selectedTab {
                    case .core:
                        coreCategoryFilterBar
                        photoGrid(
                            items: filteredCorePhotos.map { ($0.id, $0.isRare, nil as AlbumTier?, GameStrings.text("diary.lockedHint")) }
                        )
                    case .xueqiu:
                        photoGrid(
                            items: DiaryCatalog.extraPhotos.map { ($0.id, $0.isRare, nil as AlbumTier?, GameStrings.text("diary.lockedHint")) }
                        )
                    case .album:
                        if !store.isAlbumOpen {
                            lockedCard(icon: "sparkles", text: GameStrings.text("diary.albumLocked"))
                        } else {
                            albumTierFilterBar
                            photoGrid(
                                items: filteredAlbumPhotos.map { ($0.id, false, $0.tier as AlbumTier?, GameStrings.albumPhotoHint($0.id)) }
                            )
                        }
                    case .treasures:
                        treasuresSection
                    }
                }
                .padding(16)
            }
            .background(RoomTheme.cream.ignoresSafeArea())
            .navigationTitle(GameStrings.text("diary.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(GameStrings.text("common.done")) { dismiss() }
                        .fontWeight(.bold)
                        .foregroundStyle(RoomTheme.coralDeep)
                }
            }
            .sheet(item: $inspectingPhoto) { item in
                PhotoDetailSheet(
                    photoID: item.id,
                    isRare: item.isRare,
                    tier: item.tier,
                    capturedAt: store.state.diary.photoDates[item.id],
                    createdAt: store.state.createdAt
                )
            }
            .sheet(item: $inspectingTreasure) { treasure in
                TreasureDetailSheet(
                    treasure: treasure,
                    count: DiaryOuting.treasureTimes(store.state, id: treasure.id)
                )
            }
        }
    }

    /// One compact line (days together · progress) + thin bar + keepsake badges, so photos start in the first screen.
    private var scrapbookHeaderCard: some View {
        let progress = store.photoProgress
        let reached = store.reachedMilestones
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(GameStrings.format("diary.daysTogether", store.daysTogether))
                    .font(.system(size: 15.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(RoomTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(GameStrings.format("diary.progressFormat", progress.got, progress.total))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(RoomTheme.coralDeep)
                    .lineLimit(1)
            }

            GeometryReader { bar in
                ZStack(alignment: .leading) {
                    Capsule().fill(RoomTheme.track)
                    Capsule()
                        .fill(LinearGradient(colors: [RoomTheme.coral, RoomTheme.gold], startPoint: .leading, endPoint: .trailing))
                        .frame(width: bar.size.width * min(1, CGFloat(progress.got) / CGFloat(max(1, progress.total))))
                }
            }
            .frame(height: 6)

            if !reached.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(reached) { m in
                            Button {
                                dismiss()
                                store.showMilestone(m)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "rosette")
                                        .font(.system(size: 10.5, weight: .bold))
                                        .foregroundStyle(RoomTheme.gold)
                                    Text(GameStrings.milestoneTitle(m))
                                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                                        .foregroundStyle(RoomTheme.ink)
                                }
                                .padding(.horizontal, 9)
                                .frame(minHeight: 28)
                                .background(RoomTheme.rewardPaper, in: Capsule())
                                .overlay(Capsule().stroke(RoomTheme.gold.opacity(0.65), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(GameStrings.text("milestone.sectionTitle") + " · " + GameStrings.milestoneTitle(m))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(RoomTheme.wood.opacity(0.6), lineWidth: 1))
    }

    /// Four equal-width tabs (title + count) so none is clipped, in any language.
    private var sectionTabBar: some View {
        HStack(spacing: 4) {
            tabPill(.core, title: GameStrings.text("diary.tab.core"), badge: "\(store.photoProgress.got)/\(store.photoProgress.total)")
            tabPill(.xueqiu, title: GameStrings.text("diary.tab.xueqiu"), badge: "\(store.extraPhotoProgress.got)/\(store.extraPhotoProgress.total)")
            tabPill(.album, title: GameStrings.text("diary.tab.album"), badge: store.isAlbumOpen ? "\(store.albumProgress.got)/\(store.albumProgress.total)" : "🔒")
            tabPill(.treasures, title: GameStrings.text("diary.tab.treasures"), badge: "\(store.treasureCount)/\(DiaryCatalog.treasures.count)")
        }
        .padding(4)
        .background(RoomTheme.chipBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func tabPill(_ tab: DiaryTab, title: String, badge: String) -> some View {
        let active = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(badge)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .opacity(0.85)
            }
            .foregroundStyle(active ? .white : RoomTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(RoomTheme.coral)
                        .shadow(color: RoomTheme.coralDeep.opacity(0.45), radius: 0, y: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var coreCategoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterPill(title: GameStrings.text("common.all"), active: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(PhotoCategory.coreCategories, id: \.self) { category in
                    filterPill(title: GameStrings.photoCategoryName(category), active: selectedCategory == category) {
                        selectedCategory = category
                    }
                }
            }
        }
    }

    private var albumTierFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterPill(title: GameStrings.text("common.all"), active: selectedAlbumTier == nil) {
                    selectedAlbumTier = nil
                }
                ForEach(AlbumTier.allCases, id: \.self) { tier in
                    filterPill(title: "\(tier.stars) \(GameStrings.albumTierName(tier))", active: selectedAlbumTier == tier) {
                        selectedAlbumTier = tier
                    }
                }
            }
        }
    }

    private func filterPill(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                .foregroundStyle(active ? .white : RoomTheme.ink)
                .padding(.horizontal, 13)
                .padding(.vertical, 6.5)
                .background(active ? RoomTheme.gold : RoomTheme.paper, in: Capsule())
                .overlay(Capsule().stroke(active ? .clear : RoomTheme.wood.opacity(0.75), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func lockedCard(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(RoomTheme.gold)
            Text(text)
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .foregroundStyle(RoomTheme.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(RoomTheme.wood.opacity(0.55), lineWidth: 1.1))
    }

    private func photoGrid(items: [(id: String, isRare: Bool, tier: AlbumTier?, hint: String)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 102), spacing: 11)], spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                polaroidGridCard(id: item.id, isRare: item.isRare, tier: item.tier, lockedHint: item.hint, index: index)
            }
        }
        .padding(.top, 2)
    }

    private func polaroidGridCard(id: String, isRare: Bool, tier: AlbumTier?, lockedHint: String, index: Int) -> some View {
        let unlocked = store.state.diary.photos.contains(id)
        let tilt: Double = unlocked ? (index.isMultiple(of: 2) ? -1.1 : 1.1) : 0
        let highlighted = unlocked && (isRare || tier == .dream || tier == .season)

        return Button {
            if unlocked {
                inspectingPhoto = InspectingPhotoItem(id: id, isRare: isRare, tier: tier)
            }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    if unlocked {
                        Image(id)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 82)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(RoomTheme.track.opacity(0.75))
                            .frame(height: 82)
                            .overlay {
                                Image(systemName: "camera.aperture")
                                    .font(.system(size: 20))
                                    .foregroundStyle(RoomTheme.secondary.opacity(0.38))
                            }
                    }

                    if unlocked, let tier {
                        Text(tier.stars)
                            .font(.system(size: 8.5, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(RoomTheme.gold, in: Capsule())
                            .padding(4)
                    } else if unlocked && isRare {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(RoomTheme.gold, in: Circle())
                            .padding(4)
                    }
                }

                Text(unlocked ? GameStrings.photoTitle(id) : lockedHint)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(unlocked ? RoomTheme.ink : RoomTheme.secondary.opacity(0.78))
                    .lineLimit(1)
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 5)
            .background(unlocked ? Color.white : RoomTheme.paper.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(highlighted ? RoomTheme.gold.opacity(0.85) : RoomTheme.wood.opacity(0.55), lineWidth: highlighted ? 1.5 : 1)
            )
            .shadow(color: RoomTheme.ink.opacity(unlocked ? 0.13 : 0.04), radius: unlocked ? 5 : 2, y: unlocked ? 3 : 1)
            .rotationEffect(.degrees(tilt))
        }
        .buttonStyle(CraftIconBadgeButtonStyle())
        .disabled(!unlocked)
    }

    private var treasuresSection: some View {
        VStack(spacing: 12) {
            Text(DiaryOuting.outingUnlocked(store.state)
                ? GameStrings.format("diary.treasureProgress", store.treasureCount, DiaryCatalog.treasures.count)
                : GameStrings.text("diary.treasureLocked"))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(RoomTheme.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 98), spacing: 10)], spacing: 10) {
                ForEach(DiaryCatalog.treasures) { treasure in
                    let count = DiaryOuting.treasureTimes(store.state, id: treasure.id)
                    let found = count > 0
                    Button {
                        if found { inspectingTreasure = treasure }
                    } label: {
                        VStack(spacing: 6) {
                            ZStack(alignment: .topTrailing) {
                                if found {
                                    Image(treasure.id.assetName)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 58, height: 58)
                                } else {
                                    Circle()
                                        .fill(RoomTheme.track.opacity(0.8))
                                        .frame(width: 56, height: 56)
                                        .overlay {
                                            Text("?")
                                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                                .foregroundStyle(RoomTheme.secondary.opacity(0.5))
                                        }
                                }
                                if found {
                                    Text(GameStrings.format("diary.treasureCount", count))
                                        .font(.system(size: 9.5, weight: .black, design: .rounded))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(treasure.rarity == .legend ? RoomTheme.gold : RoomTheme.coral, in: Capsule())
                                }
                            }
                            Text(found ? GameStrings.treasureName(treasure.id) : "？？？")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(found ? RoomTheme.ink : RoomTheme.secondary.opacity(0.65))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 6)
                        .background(found ? RoomTheme.paper : RoomTheme.paper.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(found && treasure.rarity != .common ? RoomTheme.gold.opacity(0.7) : RoomTheme.wood.opacity(0.5), lineWidth: 1.1)
                        )
                    }
                    .buttonStyle(CraftIconBadgeButtonStyle())
                    .disabled(!found)
                }
            }
        }
    }
}

private struct PhotoDetailSheet: View {
    let photoID: String
    let isRare: Bool
    let tier: AlbumTier?
    let capturedAt: Int64?
    let createdAt: Int64
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ZStack(alignment: .top) {
                        VStack(spacing: 14) {
                            Image(photoID)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(RoomTheme.wood.opacity(0.35), lineWidth: 1))

                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(GameStrings.photoTitle(photoID))
                                        .font(.system(size: 21, weight: .heavy, design: .rounded))
                                        .foregroundStyle(RoomTheme.ink)
                                    if let tier {
                                        Text("\(tier.stars) \(GameStrings.albumTierName(tier))")
                                            .font(.system(size: 10.5, weight: .black))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(RoomTheme.gold, in: Capsule())
                                    } else if isRare {
                                        Text(GameStrings.text("diary.rareBadge"))
                                            .font(.system(size: 10.5, weight: .black))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(RoomTheme.gold, in: Capsule())
                                    }
                                    Spacer()
                                }

                                Text(GameStrings.photoCaption(photoID))
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(RoomTheme.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                if let capturedAt {
                                    Text(DayClock.date(fromEpochMs: capturedAt).formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(RoomTheme.secondary.opacity(0.7))
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                        .padding(.top, 4)
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.bottom, 6)
                        }
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(RoomTheme.wood.opacity(0.45), lineWidth: 1))
                        .shadow(color: RoomTheme.ink.opacity(0.18), radius: 14, y: 8)

                        WashiTapeStrip(tint: RoomTheme.coral.opacity(0.48), width: 64)
                            .offset(y: -6)
                    }

                    PostcardShareButton(
                        photoID: photoID,
                        capturedAt: capturedAt,
                        createdAt: createdAt,
                        calendar: .current
                    )
                }
                .padding(22)
            }
            .background(RoomTheme.cream.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(GameStrings.text("common.close")) { dismiss() }
                        .fontWeight(.bold)
                        .foregroundStyle(RoomTheme.coralDeep)
                }
            }
        }
    }
}

private struct TreasureDetailSheet: View {
    let treasure: TreasureDef
    let count: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(treasure.id.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .padding(16)
                    .background(RoomTheme.rewardPaper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                Text(GameStrings.treasureName(treasure.id))
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundStyle(RoomTheme.ink)

                Text(GameStrings.format("outing.arrivalRepeat", count))
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(RoomTheme.coralDeep)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(RoomTheme.paleCoral, in: Capsule())

                Text(GameStrings.treasureFirst(treasure.id))
                    .font(.system(size: 14.5, weight: .medium, design: .rounded))
                    .foregroundStyle(RoomTheme.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(RoomTheme.cream.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(GameStrings.text("common.close")) { dismiss() }
                        .fontWeight(.bold)
                        .foregroundStyle(RoomTheme.coralDeep)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
