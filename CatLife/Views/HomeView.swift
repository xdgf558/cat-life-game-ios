import SwiftUI
import CatGameCore

struct HomeView: View {
    @Bindable var store: DiaryAppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var catPressed = false
    @State private var xueqiuPressed = false
    @State private var idleBreathe = false
    @State private var heartBursts: [FloatingHeart] = []

    // Decorate mode transient UI state
    @State private var selectedFurnitureID: FurnitureID?
    @State private var draggingFurnitureID: FurnitureID?
    @State private var dragStartPos: (x: Double, bottom: Double)?
    @State private var dragPreviewPos: (x: Double, bottom: Double)?
    @State private var resetArmedRoom: RoomID?

    private var activeCatState: DiaryCatState {
        store.state.cats[store.effectiveSelectedCatID] ?? store.state.primaryCat
    }
    private var primaryStage: CatGrowthStage { CatGrowthStage.stage(forLevel: store.state.primaryCat.level) }
    private var tutorialStep: TutorialStep { store.state.tutorialStep }
    private var isTutorial: Bool { store.state.tutorialActive }

    private var roomFurniture: [PlacedFurniture] {
        store.state.home.layout
            .filter { $0.room == store.activeRoom }
            .sorted { lhs, rhs in
                let lLayer = layerOrder(DiaryCatalog.furnitureDef(lhs.id)?.layer ?? .floor)
                let rLayer = layerOrder(DiaryCatalog.furnitureDef(rhs.id)?.layer ?? .floor)
                if lLayer != rLayer { return lLayer < rLayer }
                return lhs.bottom < rhs.bottom
            }
    }

    private func layerOrder(_ layer: FurnitureLayer) -> Int {
        switch layer { case .flat: 0; case .wall: 1; case .floor: 2 }
    }

    var body: some View {
        GeometryReader { geo in
            let fullSize = CGSize(
                width: geo.size.width,
                height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            )
            let frame = SceneCanvasLayout.sceneFrame(in: fullSize, maxCropTop: 0.16)

            ZStack {
                RoomTheme.edgeBackdrop(for: store.sceneLight).ignoresSafeArea()

                // Precision-framed hand-painted room canvas
                ZStack {
                    Image(store.sceneLight.backgroundAssetName(base: store.activeRoom.backgroundBaseKey))
                        .resizable()
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)

                    // Room Skin subtle color tint
                    if let tint = skinTintColor(store.state.home.activeSkin) {
                        tint
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                            .allowsHitTesting(false)
                    }

                    // Room Skin wall decoration (behind wall furniture)
                    if let decoAsset = store.state.home.activeSkin.decoAssetName {
                        let spot = skinDecoSpot(for: store.activeRoom)
                        let dw = frame.width * spot.w
                        Image(decoAsset)
                            .resizable()
                            .scaledToFit()
                            .frame(width: dw, height: dw)
                            .position(
                                x: frame.minX + frame.width * spot.x,
                                y: frame.minY + frame.height * spot.bottom - dw * 0.45
                            )
                            .allowsHitTesting(false)
                    }

                    // Subtle atmospheric vignette in night/rain
                    if store.sceneLight == .night {
                        RadialGradient(
                            colors: [.clear, Color.black.opacity(0.24)],
                            center: .center,
                            startRadius: frame.width * 0.28,
                            endRadius: frame.height * 0.62
                        )
                        .allowsHitTesting(false)
                    } else if store.sceneLight == .rain && !reduceMotion {
                        RainShimmerOverlay()
                            .allowsHitTesting(false)
                    }

                    // Decorate mode live bounds box while dragging
                    if store.isDecorating, let dragID = draggingFurnitureID {
                        let layer = DiaryCatalog.furnitureDef(dragID)?.layer ?? .floor
                        let b = DiaryLayout.bounds(for: store.activeRoom, layer: layer)
                        let bw = frame.width * (b.maxX - b.minX)
                        let bh = frame.height * (b.maxY - b.minY)
                        let cx = frame.minX + frame.width * ((b.minX + b.maxX) / 2.0)
                        let cy = frame.minY + frame.height * ((b.minY + b.maxY) / 2.0)
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            )
                            .frame(width: bw, height: bh)
                            .position(x: cx, y: cy)
                            .allowsHitTesting(false)
                    }

                    // Placed furniture (interactive when decorating)
                    ForEach(roomFurniture) { placed in
                        furnitureActor(placed, in: frame)
                    }

                    // Offline note pin on wall
                    if store.offlineNoteID != nil, !isTutorial, !store.isDecorating, store.activeRoom == .livingroom {
                        Button {
                            store.toggleOfflineNote()
                        } label: {
                            AssetOrSymbol(asset: "ui_note_pin", symbol: "note.text", size: 42, tint: RoomTheme.coral)
                                .shadow(color: RoomTheme.ink.opacity(0.25), radius: 5, y: 3)
                        }
                        .buttonStyle(CraftIconBadgeButtonStyle())
                        .position(
                            x: frame.minX + frame.width * 0.86,
                            y: frame.minY + frame.height * 0.35
                        )
                        .accessibilityLabel(GameStrings.text("home.offlineNoteTitle"))
                    }

                    // Entrance Door Basket (Lv.6+)
                    if !isTutorial, !store.isDecorating, store.activeRoom == .entrance, DiaryOuting.outingUnlocked(store.state) {
                        entranceBasketActor(in: frame)
                    }

                    // Stray Xueqiu at Entrance (Lv.7+, before adoption)
                    if !isTutorial, !store.isDecorating, store.activeRoom == .entrance, store.isStrayPresentAtEntrance {
                        strayActorView(in: frame)
                    }

                    // Resident cats (hidden while decorating)
                    if !store.isDecorating {
                        if !store.isXiaojuOut {
                            xiaojuActorView(in: frame)
                        }
                        if store.isXueqiuInActiveRoom {
                            xueqiuActorView(in: frame)
                        }
                    }

                    // Decorate floating Flip / Store toolbar on selected furniture
                    if store.isDecorating,
                       draggingFurnitureID == nil,
                       let selID = selectedFurnitureID,
                       let placed = roomFurniture.first(where: { $0.id == selID }) {
                        decorateSelectionTools(for: placed, in: frame)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if store.isDecorating {
                        selectedFurnitureID = nil
                    }
                }
                .ignoresSafeArea()

                // Refined Floating Chrome (respecting iPhone safe area)
                VStack(spacing: 10) {
                    if store.isDecorating {
                        decorateTopBar
                    } else {
                        topChrome

                        if isTutorial {
                            tutorialCoachPill
                        }

                        if store.showingOfflineNote, let noteID = store.offlineNoteID {
                            offlineNoteCard(noteID)
                        }

                        if let arrival = store.state.home.pendingArrival, !isTutorial {
                            pendingGiftBanner(arrival)
                        } else if store.isXiaojuOut, let outing = store.state.home.outing, !isTutorial {
                            xiaojuOutBanner(outing)
                        }
                    }

                    Spacer()

                    if !isTutorial && (store.unlockedRooms.count > 1 || (!store.isDecorating && !store.state.home.furnitureOwned.isEmpty)) {
                        roomRow
                    }

                    if store.isDecorating {
                        decorateStorageDock
                    } else {
                        floatingBottomDock
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 8)
            }
        }
        .onChange(of: store.activeRoom) { _, _ in
            selectedFurnitureID = nil
            draggingFurnitureID = nil
            dragPreviewPos = nil
            resetArmedRoom = nil
        }
        .onChange(of: store.isDecorating) { _, active in
            if !active {
                selectedFurnitureID = nil
                draggingFurnitureID = nil
                dragPreviewPos = nil
                resetArmedRoom = nil
            }
        }
        .onAppear {
            store.tickHomePresence()
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                idleBreathe = true
            }
        }
        .task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(15))
                } catch {
                    break
                }
                store.tickHomePresence()
            }
        }
    }

    // MARK: - Room Skin Helpers

    private func skinTintColor(_ skin: RoomSkinID) -> Color? {
        switch skin {
        case .defaultSkin: nil
        case .honey: Color(red: 214/255, green: 138/255, blue: 58/255).opacity(0.11)
        case .mint: Color(red: 118/255, green: 196/255, blue: 156/255).opacity(0.10)
        case .sakura: Color(red: 240/255, green: 150/255, blue: 172/255).opacity(0.10)
        }
    }

    private func skinDecoSpot(for room: RoomID) -> (x: Double, bottom: Double, w: Double) {
        switch room {
        case .livingroom: (0.68, 0.31, 0.20)
        case .bedroom: (0.20, 0.25, 0.18)
        case .entrance: (0.46, 0.36, 0.16)
        case .balcony: (0.36, 0.47, 0.18)
        }
    }

    // MARK: - Furniture Actor & Decorate Gestures

    private func furnitureSize(_ id: FurnitureID, frameWidth: CGFloat) -> CGFloat {
        switch DiaryCatalog.furnitureDef(id)?.layer ?? .floor {
        case .flat: return frameWidth * 0.42
        case .wall: return frameWidth * 0.30
        case .floor: return frameWidth * 0.31
        }
    }

    @ViewBuilder
    private func furnitureActor(_ placed: PlacedFurniture, in frame: CGRect) -> some View {
        let isDragging = draggingFurnitureID == placed.id
        let isSelected = store.isDecorating && selectedFurnitureID == placed.id
        let pos: (x: Double, bottom: Double) = isDragging ? (dragPreviewPos ?? (placed.x, placed.bottom)) : (placed.x, placed.bottom)
        let size = furnitureSize(placed.id, frameWidth: frame.width)
        let px = frame.minX + frame.width * pos.x
        let py = frame.minY + frame.height * pos.bottom - size * 0.42

        ZStack {
            if (DiaryCatalog.furnitureDef(placed.id)?.layer ?? .floor) == .floor {
                Ellipse()
                    .fill(RoomTheme.ink.opacity(isDragging ? 0.24 : 0.16))
                    .frame(width: size * 0.72, height: size * 0.16)
                    .blur(radius: 5)
                    .offset(y: size * 0.40)
            }
            Image(placed.id.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .scaleEffect(x: placed.flip ? -1 : 1, y: 1)
                .scaleEffect(isDragging ? 1.07 : 1.0)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(RoomTheme.coral, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .padding(-4)
                    }
                }
        }
        .position(x: px, y: py)
        .allowsHitTesting(store.isDecorating)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard store.isDecorating else { return }
                    selectedFurnitureID = placed.id
                    if draggingFurnitureID != placed.id {
                        if hypot(value.translation.width, value.translation.height) > 5 {
                            draggingFurnitureID = placed.id
                            dragStartPos = (placed.x, placed.bottom)
                        }
                    }
                    if draggingFurnitureID == placed.id, let start = dragStartPos {
                        let rawX = start.x + Double(value.translation.width / max(1, frame.width))
                        let rawY = start.bottom + Double(value.translation.height / max(1, frame.height))
                        dragPreviewPos = DiaryLayout.clampPlacement(id: placed.id, room: store.activeRoom, x: rawX, bottom: rawY)
                    }
                }
                .onEnded { _ in
                    guard store.isDecorating else { return }
                    if draggingFurnitureID == placed.id, let preview = dragPreviewPos {
                        store.placeFurniture(placed.id, room: store.activeRoom, x: preview.x, bottom: preview.bottom, flip: placed.flip)
                    }
                    draggingFurnitureID = nil
                    dragStartPos = nil
                    dragPreviewPos = nil
                }
        )
    }

    private func decorateSelectionTools(for placed: PlacedFurniture, in frame: CGRect) -> some View {
        let size = furnitureSize(placed.id, frameWidth: frame.width)
        let px = min(frame.maxX - 88, max(frame.minX + 88, frame.minX + frame.width * placed.x))
        let py = max(frame.minY + 128, frame.minY + frame.height * placed.bottom - size * 0.96)
        return HStack(spacing: 8) {
            Button {
                store.toggleFurnitureFlip(placed.id)
            } label: {
                Label(GameStrings.text("decorate.flip"), systemImage: "arrow.left.and.right")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(RoomTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(RoomTheme.paper, in: Capsule())
                    .overlay(Capsule().stroke(RoomTheme.wood, lineWidth: 1.2))
                    .shadow(color: RoomTheme.ink.opacity(0.16), radius: 5, y: 2)
            }
            .buttonStyle(.plain)

            Button {
                store.storeFurniture(placed.id)
                selectedFurnitureID = nil
            } label: {
                Label(GameStrings.text("decorate.store"), systemImage: "archivebox.fill")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(RoomTheme.coral, in: Capsule())
                    .shadow(color: RoomTheme.coralDeep.opacity(0.5), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
        }
        .position(x: px, y: py)
    }

    // MARK: - Entrance Basket & Stray Xueqiu

    private func entranceBasketActor(in frame: CGRect) -> some View {
        let basket = store.state.home.basket
        return Button {
            store.activeSheet = .basket
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(basket != nil ? "ui_basket_full" : "ui_basket_empty")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 68, height: 68)
                    .shadow(color: RoomTheme.ink.opacity(0.22), radius: 5, y: 3)
                if let basket {
                    Image(basket.item.assetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .padding(3)
                        .background(RoomTheme.paper, in: Circle())
                        .overlay(Circle().stroke(RoomTheme.coral, lineWidth: 1.2))
                }
            }
        }
        .buttonStyle(CraftIconBadgeButtonStyle())
        .position(x: frame.minX + frame.width * 0.22, y: frame.minY + frame.height * 0.74)
        .accessibilityLabel(GameStrings.text("outing.basketTitle"))
        .accessibilityIdentifier("entranceBasketButton")
    }

    private func strayActorView(in frame: CGRect) -> some View {
        let trust = store.state.home.stray?.trust ?? 0
        let asset = trust == 0 ? "cat_xueqiu_peek" : "cat_xueqiu_idle"
        let size = frame.width * 0.36
        return ZStack {
            VStack(spacing: 4) {
                if let bubble = store.strayBubbleKey {
                    Text(GameStrings.text(bubble))
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(RoomTheme.ink)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(WarmGlassBackground(cornerRadius: 14, tintOpacity: 0.94))
                }
                Text(GameStrings.format("stray.trustBadge", trust, DiaryBalance.default.adoption.trustToAdopt))
                    .font(.system(size: 10.5, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(RoomTheme.coral, in: Capsule())

                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .shadow(color: RoomTheme.ink.opacity(0.18), radius: 6, y: 4)
            }
        }
        .onTapGesture {
            store.meetStray()
        }
        .position(x: frame.minX + frame.width * 0.74, y: frame.minY + frame.height * 0.67)
        .accessibilityLabel(GameStrings.text("cat.xueqiu"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("entranceStrayButton")
    }

    // MARK: - Resident Cats (Xiaoju & Xueqiu)

    private func xiaojuActorView(in frame: CGRect) -> some View {
        let catSize = frame.width * 0.41 * primaryStage.displayScale
        let cx = frame.minX + frame.width * (store.isXueqiuInActiveRoom ? 0.36 : 0.50)
        let cy = frame.minY + frame.height * 0.69

        return ZStack {
            Ellipse()
                .fill(RoomTheme.ink.opacity(0.20))
                .frame(width: catSize * 0.68, height: catSize * 0.16)
                .blur(radius: 7)
                .offset(y: catSize * 0.38)

            if tutorialStep == .meet && !reduceMotion {
                Circle()
                    .stroke(RoomTheme.coral.opacity(0.55), lineWidth: 3)
                    .frame(width: catSize * 0.85, height: catSize * 0.85)
                    .scaleEffect(idleBreathe ? 1.12 : 0.96)
                    .opacity(idleBreathe ? 0.25 : 0.8)
            }

            Image(store.displayedPose(for: .primary).assetName(stage: primaryStage, cat: .primary))
                .resizable()
                .scaledToFit()
                .frame(width: catSize, height: catSize)
                .scaleEffect(
                    x: catPressed ? 1.06 : 1.0,
                    y: catPressed ? 0.93 : (idleBreathe && !reduceMotion ? 1.018 : 1.0),
                    anchor: .bottom
                )
                .animation(.spring(response: 0.24, dampingFraction: 0.52), value: catPressed)
                .onTapGesture {
                    catPressed = true
                    spawnHearts()
                    store.petCat(.primary)
                    Task {
                        try? await Task.sleep(for: .milliseconds(160))
                        catPressed = false
                    }
                }
                .accessibilityLabel(GameStrings.text("home.tapCatHint"))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("homeCatButton")

            ForEach(heartBursts) { heart in
                Image(systemName: "heart.fill")
                    .font(.system(size: heart.size))
                    .foregroundStyle(RoomTheme.heartPink)
                    .shadow(color: .white.opacity(0.6), radius: 2)
                    .offset(x: heart.offsetX, y: heart.rising ? -catSize * 0.62 + heart.offsetY : -catSize * 0.22)
                    .opacity(heart.rising ? 0 : 0.95)
                    .scaleEffect(heart.rising ? 1.15 : 0.65)
            }

            if let bubbleKey = store.catBubbleKey {
                speechBubble(GameStrings.text(bubbleKey))
                    .offset(y: -catSize * 0.54)
            }
        }
        .position(x: cx, y: cy)
    }

    private func xueqiuActorView(in frame: CGRect) -> some View {
        let catSize = frame.width * 0.37
        let cx = frame.minX + frame.width * 0.74
        let cy = frame.minY + frame.height * 0.70

        return ZStack {
            Ellipse()
                .fill(RoomTheme.ink.opacity(0.18))
                .frame(width: catSize * 0.65, height: catSize * 0.15)
                .blur(radius: 6)
                .offset(y: catSize * 0.38)

            Image(store.displayedPose(for: .xueqiu).assetName(cat: .xueqiu))
                .resizable()
                .scaledToFit()
                .frame(width: catSize, height: catSize)
                .scaleEffect(
                    x: xueqiuPressed ? 1.06 : 1.0,
                    y: xueqiuPressed ? 0.93 : (idleBreathe && !reduceMotion ? 1.015 : 1.0),
                    anchor: .bottom
                )
                .animation(.spring(response: 0.24, dampingFraction: 0.52), value: xueqiuPressed)
                .onTapGesture {
                    xueqiuPressed = true
                    store.petCat(.xueqiu)
                    Task {
                        try? await Task.sleep(for: .milliseconds(160))
                        xueqiuPressed = false
                    }
                }
                .accessibilityLabel(GameStrings.text("home.tapXueqiuHint"))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("homeXueqiuButton")

            if let bubbleKey = store.xueqiuBubbleKey {
                speechBubble(GameStrings.text(bubbleKey))
                    .offset(y: -catSize * 0.54)
            }
        }
        .position(x: cx, y: cy)
    }

    private func speechBubble(_ text: String) -> some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(RoomTheme.ink)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(WarmGlassBackground(cornerRadius: 16, tintOpacity: 0.92))
            BubbleTail()
                .fill(RoomTheme.paper.opacity(0.95))
                .frame(width: 12, height: 6)
        }
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    private func spawnHearts() {
        guard !reduceMotion else { return }
        let base = [
            FloatingHeart(offsetX: -26, offsetY: -10, size: 15),
            FloatingHeart(offsetX: 4, offsetY: -22, size: 18),
            FloatingHeart(offsetX: 28, offsetY: -6, size: 13),
        ]
        heartBursts.append(contentsOf: base)
        let ids = Set(base.map(\.id))
        withAnimation(.easeOut(duration: 0.9)) {
            for idx in heartBursts.indices where ids.contains(heartBursts[idx].id) {
                heartBursts[idx].rising = true
            }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(950))
            heartBursts.removeAll { ids.contains($0.id) }
        }
    }

    // MARK: - Top Chrome & Outing Banners

    private var topChrome: some View {
        let cat = activeCatState
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 7) {
                Button {
                    if store.hasXueqiu {
                        store.selectCat(store.effectiveSelectedCatID == .primary ? .xueqiu : .primary)
                    }
                } label: {
                    HStack(spacing: 9) {
                        ZStack {
                            Circle()
                                .fill(store.effectiveSelectedCatID == .xueqiu ? RoomTheme.paleMint : RoomTheme.paleCoral)
                                .frame(width: 34, height: 34)
                            AssetOrSymbol(asset: "ui_heart", symbol: "heart.fill", size: 22, tint: RoomTheme.coral)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Text(GameStrings.catName(cat.id))
                                    .font(.system(size: 14.5, weight: .heavy, design: .rounded))
                                    .foregroundStyle(RoomTheme.ink)
                                    .lineLimit(1)
                                    .fixedSize()
                                Text(GameStrings.format("common.lvFormat", cat.level))
                                    .font(.system(size: 10.5, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .fixedSize()
                                    .padding(.horizontal, 6.5)
                                    .padding(.vertical, 1.5)
                                    .background(store.effectiveSelectedCatID == .xueqiu ? RoomTheme.mint : RoomTheme.coral, in: Capsule())
                                if store.hasXueqiu {
                                    Image(systemName: "arrow.left.arrow.right")
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundStyle(RoomTheme.secondary)
                                }
                            }
                            let xp = DiaryProgression.xpProgress(for: cat)
                            HStack(spacing: 7) {
                                GeometryReader { bar in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(RoomTheme.track)
                                        Capsule()
                                            .fill(LinearGradient(colors: [RoomTheme.coral, RoomTheme.gold], startPoint: .leading, endPoint: .trailing))
                                            .frame(width: bar.size.width * min(1, CGFloat(xp.current) / CGFloat(max(1, xp.target))))
                                    }
                                }
                                .frame(width: 44, height: 6)

                                compactGauge(symbol: "fork.knife", value: clampedGaugeValue(cat.satiety), tint: cat.satiety < 25 ? RoomTheme.coral : RoomTheme.mint)
                                compactGauge(symbol: "sun.max.fill", value: clampedGaugeValue(cat.mood), tint: RoomTheme.gold)
                            }
                        }
                        .fixedSize()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(WarmGlassBackground(cornerRadius: 22, tintOpacity: 0.84))
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
                .accessibilityElement(children: .combine)
                .accessibilityHint(store.hasXueqiu ? GameStrings.text("home.switchCatHint") : "")

                Spacer(minLength: 2)

                // Coins Capsule
                HStack(spacing: 4) {
                    AssetOrSymbol(asset: "ui_coin", symbol: "dollarsign.circle.fill", size: 17, tint: RoomTheme.gold)
                    Text("\(store.state.coins)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(RoomTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 9)
                .frame(height: 40)
                .background(WarmGlassBackground(cornerRadius: 20, tintOpacity: 0.84))

                if !isTutorial {
                    Button {
                        store.activeSheet = .settings
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(RoomTheme.ink)
                            .frame(width: 40, height: 40)
                            .background(WarmGlassBackground(cornerRadius: 20, tintOpacity: 0.84))
                    }
                    .buttonStyle(CraftIconBadgeButtonStyle())
                    .accessibilityLabel(GameStrings.text("settings.title"))
                    .accessibilityIdentifier("homeSettingsButton")
                }
            }

            // Tilted Sticky Note for Today's Wish
            if let wish = store.state.home.wish, !isTutorial {
                Button {
                    store.notices.show(GameStrings.wishHint(wish.goal, bonusXP: DiaryBalance.default.cat.wishBonusXP))
                } label: {
                    ZStack(alignment: .top) {
                        HStack(spacing: 6) {
                            Image(systemName: wish.completed ? "checkmark.seal.fill" : "sparkle")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(wish.completed ? RoomTheme.mint : RoomTheme.coral)
                            Text("\(GameStrings.text("wish.title")) · \(GameStrings.wishLabel(wish.goal))")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(RoomTheme.ink)
                            if wish.completed {
                                Text(GameStrings.text("wish.doneBadge"))
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(RoomTheme.darkMint)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(RoomTheme.paleMint, in: Capsule())
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 7)
                        .background(RoomTheme.rewardPaper.opacity(0.96), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(RoomTheme.rewardBorder, lineWidth: 1.2))
                        .shadow(color: RoomTheme.ink.opacity(0.12), radius: 5, y: 3)

                        WashiTapeStrip(tint: RoomTheme.gold.opacity(0.45), width: 34)
                            .offset(y: -5)
                    }
                }
                .buttonStyle(CraftIconBadgeButtonStyle())
                .rotationEffect(.degrees(-1.1))
                .padding(.leading, 4)
            }
        }
    }

    private func pendingGiftBanner(_ arrival: OutingArrival) -> some View {
        Button {
            store.openPendingArrival()
        } label: {
            HStack(spacing: 10) {
                Image(arrival.treasure.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                Text(GameStrings.text("outing.pendingGiftBadge"))
                    .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "gift.fill")
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(RoomTheme.coral, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: RoomTheme.coralDeep.opacity(0.5), radius: 6, y: 3)
        }
        .buttonStyle(CraftIconBadgeButtonStyle())
        .accessibilityIdentifier("pendingArrivalButton")
    }

    private func xiaojuOutBanner(_ outing: OutingState) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(GameStrings.text("outing.catOutTitle"))
                    .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(RoomTheme.ink)
                Text(GameStrings.format("outing.catOutDesc", GameStrings.outingSpotName(outing.spot)))
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(RoomTheme.secondary)
            }
            Spacer()
            Button {
                store.recallXiaoju()
            } label: {
                Text(store.state.home.recallUsedToday ? GameStrings.text("outing.recallUsed") : GameStrings.text("outing.recallButton"))
                    .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(store.state.home.recallUsedToday ? RoomTheme.secondary : .white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(store.state.home.recallUsedToday ? RoomTheme.track : RoomTheme.coral, in: Capsule())
            }
            .disabled(store.state.home.recallUsedToday)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(WarmGlassBackground(cornerRadius: 16, tintOpacity: 0.92))
    }

    // MARK: - Decorate Mode Chrome

    private var decorateTopBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text(GameStrings.text("decorate.badge"))
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(RoomTheme.coralDeep)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(WarmGlassBackground(cornerRadius: 18, tintOpacity: 0.94))

                Spacer()

                Button(GameStrings.text("common.done")) {
                    store.exitDecorateMode()
                }
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(RoomTheme.coral, in: Capsule())
                .shadow(color: RoomTheme.coralDeep.opacity(0.45), radius: 4, y: 2)
                .accessibilityIdentifier("decorateDoneButton")
            }

            Text(GameStrings.text("decorate.tip"))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(RoomTheme.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(WarmGlassBackground(cornerRadius: 14, tintOpacity: 0.90))
        }
    }

    private var decorateStorageDock: some View {
        let stored = store.storedFurnitureIDs
        let armed = resetArmedRoom == store.activeRoom
        return HStack(spacing: 10) {
            Button {
                if armed {
                    store.resetRoomLayout(store.activeRoom)
                    selectedFurnitureID = nil
                    resetArmedRoom = nil
                } else {
                    resetArmedRoom = store.activeRoom
                    let targetRoom = store.activeRoom
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        if resetArmedRoom == targetRoom { resetArmedRoom = nil }
                    }
                }
            } label: {
                Text(armed ? GameStrings.text("decorate.resetConfirm") : GameStrings.text("decorate.reset"))
                    .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(armed ? .white : RoomTheme.ink)
                    .multilineTextAlignment(.center)
                    .frame(width: 66, height: 58)
                    .background(armed ? RoomTheme.coral : RoomTheme.cream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(RoomTheme.wood.opacity(0.6), lineWidth: 1))
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if stored.isEmpty {
                        Text(GameStrings.text("decorate.storageEmpty"))
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(RoomTheme.secondary)
                            .padding(.horizontal, 12)
                    } else {
                        ForEach(stored, id: \.self) { id in
                            Button {
                                let layer = DiaryCatalog.furnitureDef(id)?.layer ?? .floor
                                let b = DiaryLayout.bounds(for: store.activeRoom, layer: layer)
                                if store.placeFurniture(id, room: store.activeRoom, x: (b.minX + b.maxX) / 2, bottom: (b.minY + b.maxY) / 2) {
                                    selectedFurnitureID = id
                                }
                            } label: {
                                VStack(spacing: 2) {
                                    Image(id.assetName)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 38, height: 38)
                                    Text(GameStrings.furnitureName(id))
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .foregroundStyle(RoomTheme.ink)
                                        .lineLimit(1)
                                }
                                .frame(width: 58, height: 58)
                                .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(RoomTheme.wood.opacity(0.7), lineWidth: 1))
                            }
                            .buttonStyle(CraftIconBadgeButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(WarmGlassBackground(cornerRadius: 24, tintOpacity: 0.94))
    }

    private func clampedGaugeValue(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(100.0, max(0.0, value)).rounded())
    }

    private func compactGauge(symbol: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 2.5) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(tint)
            Text("\(value)")
                .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(RoomTheme.secondary)
        }
    }

    private var tutorialCoachPill: some View {
        HStack(spacing: 9) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoomTheme.coral, in: Circle())
            Text(GameStrings.text(tutorialStep == .gather ? "tutorial.goWorkshop" : "tutorial.\(tutorialStep.rawValue)"))
                .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                .foregroundStyle(RoomTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(WarmGlassBackground(cornerRadius: 18, tintOpacity: 0.92))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(RoomTheme.coral.opacity(0.65), lineWidth: 1.5))
    }

    private func offlineNoteCard(_ noteID: String) -> some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: 10) {
                AssetOrSymbol(asset: "ui_note_pin", symbol: "note.text", size: 28, tint: RoomTheme.coral)
                VStack(alignment: .leading, spacing: 3) {
                    Text(GameStrings.text("home.offlineNoteTitle"))
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(RoomTheme.secondary)
                    Text(GameStrings.text(noteID))
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(RoomTheme.ink)
                }
                Spacer()
                Button {
                    store.toggleOfflineNote()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(RoomTheme.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(GameStrings.text("common.close"))
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(RoomTheme.rewardPaper.opacity(0.97), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(RoomTheme.rewardBorder, lineWidth: 1.4))
            .shadow(color: RoomTheme.ink.opacity(0.14), radius: 8, y: 4)

            WashiTapeStrip(tint: RoomTheme.coral.opacity(0.45), width: 46)
                .offset(y: -6)
        }
        .padding(.top, 4)
    }

    /// Room tabs plus the decorate entry: both act on the room you're looking at.
    /// Falls back to an icon-only decorate button, then a scrolling tab strip on narrow / large-text layouts.
    @ViewBuilder
    private var roomRow: some View {
        if store.isDecorating {
            ViewThatFits(in: .horizontal) {
                roomSegmentedPill
                ScrollView(.horizontal, showsIndicators: false) { roomSegmentedPill }
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    if store.unlockedRooms.count > 1 { roomSegmentedPill }
                    Spacer(minLength: 8)
                    decorateButton(showLabel: true)
                }
                HStack(spacing: 8) {
                    if store.unlockedRooms.count > 1 { roomSegmentedPill }
                    Spacer(minLength: 6)
                    decorateButton(showLabel: false)
                }
                HStack(spacing: 8) {
                    if store.unlockedRooms.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) { roomSegmentedPill }
                    }
                    decorateButton(showLabel: false)
                }
            }
        }
    }

    @ViewBuilder
    private func decorateButton(showLabel: Bool) -> some View {
        if !store.isDecorating && !store.state.home.furnitureOwned.isEmpty {
            Button {
                store.enterDecorateMode()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "paintbrush.pointed.fill")
                        .font(.system(size: 13, weight: .bold))
                    if showLabel {
                        Text(GameStrings.text("home.decorate"))
                            .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .foregroundStyle(RoomTheme.coralDeep)
                .padding(.horizontal, showLabel ? 12 : 0)
                .frame(minWidth: 38, minHeight: 38)
                .background(WarmGlassBackground(cornerRadius: 19, tintOpacity: 0.86))
            }
            .buttonStyle(CraftIconBadgeButtonStyle())
            .accessibilityLabel(GameStrings.text("home.decorate"))
            .accessibilityIdentifier("homeDecorateButton")
        }
    }

    private var roomSegmentedPill: some View {
        HStack(spacing: 4) {
            ForEach(store.unlockedRooms, id: \.self) { room in
                let selected = store.activeRoom == room
                let hasStrayDot = room == .entrance && store.isStrayPresentAtEntrance
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        store.selectRoom(room)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(GameStrings.roomName(room))
                            .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .fixedSize()
                        if hasStrayDot {
                            Circle()
                                .fill(selected ? Color.white : RoomTheme.coral)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .foregroundStyle(selected ? .white : RoomTheme.ink)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background {
                        if selected {
                            Capsule().fill(RoomTheme.coral)
                                .shadow(color: RoomTheme.coralDeep.opacity(0.45), radius: 0, y: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(WarmGlassBackground(cornerRadius: 24, tintOpacity: 0.84))
    }

    // MARK: - Airy Floating Bottom Dock

    private var floatingBottomDock: some View {
        let progress = store.photoProgress
        return HStack(spacing: 8) {
            if !isTutorial {
                dockNavButton(
                    asset: "ui_diary",
                    symbol: "book.closed.fill",
                    label: GameStrings.text("home.diary"),
                    miniBadge: "\(progress.got)/\(progress.total)"
                ) {
                    store.activeSheet = .diary
                }
                .accessibilityIdentifier("homeDiaryButton")

                dockNavButton(
                    asset: "ui_shop",
                    symbol: "storefront.fill",
                    label: GameStrings.text("home.shop"),
                    miniBadge: store.isNightSaleActive && DiaryThemes.themesUnlocked(store.state) ? GameStrings.text("shop.saleBadge") : nil
                ) {
                    store.activeSheet = .shop
                }
                .accessibilityIdentifier("homeShopButton")

                RoundedRectangle(cornerRadius: 1)
                    .fill(RoomTheme.wood.opacity(0.55))
                    .frame(width: 1.5, height: 42)
            }

            // Recessed Warm Tray for Toys & Food
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    if store.state.home.toys.isEmpty && store.state.home.food.isEmpty {
                        Text(GameStrings.text("home.trayEmpty"))
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(RoomTheme.secondary)
                            .padding(.horizontal, 8)
                    } else {
                        ForEach(Array(store.state.home.toys.enumerated()), id: \.offset) { idx, toy in
                            trayTile(item: toy.item, durabilityDots: toy.usesLeft) {
                                store.playWithToy(at: idx)
                            }
                        }
                        ForEach(Array(store.state.home.food.enumerated()), id: \.offset) { idx, food in
                            trayTile(item: food, durabilityDots: nil) {
                                store.feedCat(at: idx)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(RoomTheme.cream.opacity(0.65), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(RoomTheme.wood.opacity(0.45), lineWidth: 1))

            // Elevated Coral Workshop CTA
            Button {
                store.switchScreen(to: .workshop)
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 19, weight: .bold))
                    Text(GameStrings.text("home.workshop"))
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(width: 66, height: 64)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [RoomTheme.coral.opacity(0.92), RoomTheme.coral],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: RoomTheme.coralDeep.opacity(0.9), radius: 0, y: 3)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.42), lineWidth: 1.4)
                }
                .overlay {
                    if tutorialStep == .gather && !reduceMotion {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(RoomTheme.gold, lineWidth: 2.5)
                            .scaleEffect(idleBreathe ? 1.08 : 1.0)
                            .opacity(idleBreathe ? 0.35 : 0.95)
                    }
                }
            }
            .buttonStyle(CraftIconBadgeButtonStyle())
            .accessibilityIdentifier("homeWorkshopButton")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(WarmGlassBackground(cornerRadius: 26, tintOpacity: 0.88))
    }

    private func dockNavButton(asset: String, symbol: String, label: String, miniBadge: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    AssetOrSymbol(asset: asset, symbol: symbol, size: 30, tint: RoomTheme.ink)
                        .frame(width: 44, height: 42)
                        .background(RoomTheme.paper, in: Circle())
                        .overlay(Circle().stroke(RoomTheme.wood.opacity(0.75), lineWidth: 1.2))
                        .shadow(color: RoomTheme.ink.opacity(0.08), radius: 3, y: 2)
                    if let miniBadge {
                        Text(miniBadge)
                            .font(.system(size: 8.5, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1)
                            .background(RoomTheme.coral, in: Capsule())
                            .offset(x: 5, y: -3)
                    }
                }
                Text(label)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(RoomTheme.ink)
                    .lineLimit(1)
            }
            .frame(width: 50)
        }
        .buttonStyle(CraftIconBadgeButtonStyle())
    }

    private func trayTile(item: MergeItem, durabilityDots: Int?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(item.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .shadow(color: RoomTheme.ink.opacity(0.14), radius: 2, y: 1.5)

                Text(GameStrings.itemName(item))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(RoomTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 3)
            .frame(width: 58, height: 58)
            .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(RoomTheme.wood.opacity(0.75), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if let uses = durabilityDots {
                    Text(GameStrings.format("home.toyUses", uses))
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(RoomTheme.coral, in: Capsule())
                        .offset(x: 3, y: -4)
                }
            }
            .shadow(color: RoomTheme.ink.opacity(0.08), radius: 2, y: 1)
        }
        .buttonStyle(CraftIconBadgeButtonStyle())
        .accessibilityLabel(durabilityDots.map { GameStrings.itemName(item) + " · " + GameStrings.format("home.toyUses", $0) } ?? GameStrings.itemName(item))
    }
}

private struct FloatingHeart: Identifiable {
    let id = UUID()
    let offsetX: CGFloat
    let offsetY: CGFloat
    let size: CGFloat
    var rising = false
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct RainShimmerOverlay: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for i in 0..<18 {
                    let seed = Double(i) * 137.5
                    let x = CGFloat((seed.truncatingRemainder(dividingBy: 100.0) / 100.0)) * size.width
                    let speed = 180.0 + Double(i % 4) * 40.0
                    let y = CGFloat(((phase * speed + seed * 9.0).truncatingRemainder(dividingBy: Double(size.height * 0.52))))
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x - 5, y: y + 18))
                    ctx.stroke(p, with: .color(.white.opacity(0.22)), lineWidth: 1.1)
                }
            }
        }
    }
}
