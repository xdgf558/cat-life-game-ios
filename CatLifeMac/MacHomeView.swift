#if os(macOS)
import SwiftUI
import CatGameCore

@MainActor
struct MacHomeView: View {
    let store: GameStore
    let scene: RoomScene
    let preferences: MacPreferences
    let isActive: Bool
    let onTasks: () -> Void
    let onInventory: () -> Void
    let onCats: () -> Void
    let onRest: (String) -> Void
    let onContext: (MacRoomContextAction) -> Void
    let onFixedStructure: (MacRoomStructure) -> Void
    @State private var need = CatNeedPresentation()
    @State private var cameraRevision = 0
    @State private var recent: [String] = []
    private var daily: [GameTaskDefinition] {
        guard let snapshot = store.snapshot else { return [] }
        return Array(GameTaskCatalog.all.filter { $0.category == .daily && GameTaskCatalog.isUnlocked($0, in: snapshot) && !GameTaskCatalog.isClaimed($0, in: snapshot) }.prefix(3))
    }
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 16) {
                stage.frame(maxWidth: .infinity, maxHeight: .infinity)
                ScrollView {
                    VStack(spacing: 14) {
                        catCard
                        tasks
                        if let cat = store.cat, let memory = cat.habits.pinnedMemory { PinnedHabitPrompt(store: store, cat: cat, memory: memory) }
                        MacPanel(title: GameStrings.text("mac.home.recent")) {
                            if recent.isEmpty { Text(GameStrings.text("mac.home.quiet")).foregroundStyle(RoomTheme.secondary) }
                            ForEach(Array(recent.suffix(3).enumerated()), id: \.offset) { _, text in Label(text, systemImage: "leaf.fill").font(.caption).foregroundStyle(RoomTheme.secondary) }
                        }
                    }
                }.frame(width: geometry.size.width < 1270 ? 320 : 372)
                    .scrollIndicators(.hidden)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macHomePage")
        .onChange(of: store.toast) { _, message in if let message { recent.append(message); if recent.count > 3 { recent.removeFirst() } } }
    }
    private var stage: some View {
        GeometryReader { geometry in
            ZStack {
                MacRoomCanvas(store: store, scene: scene, isActive: isActive, frameLimit: preferences.frameLimit,
                              wheelReversed: preferences.wheelReversed, contextMenus: preferences.contextMenus,
                              hoverHints: preferences.hoverHints,
                              isDaylight: !preferences.followDaylight || !MacTitleMetricsV2.isNight(at: store.now),
                              needPresentation: need,
                              onRestRequest: onRest, onContextAction: onContext,
                              onViewChanged: { cameraRevision += 1 }, onFixedStructure: onFixedStructure)
                CatNeedBubble(reducedMotion: preferences.reduceMotion, store: store, presentation: need, canvasSize: geometry.size,
                              isActive: isActive, canAct: { !store.isBusy }, bottomInset: 96)
            }
            .overlay(alignment: .top) { stageHeader.padding(16) }
            .overlay(alignment: .bottom) { stageFooter.padding(16) }
        }
        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white, lineWidth: 3).allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .accessibilityElement(children: .contain)
    }
    private var stageHeader: some View {
        HStack(spacing: 10) {
            if (store.snapshot?.home.roomLevel ?? 1) >= 6 {
                HStack(spacing: 4) {
                    ForEach(HomeFloor.allCases, id: \.self) { floor in
                        Button { Task { _ = await store.changeHomeFloor(to: floor) } } label: {
                            Text(GameStrings.text(floor == .ground ? "mac.floor.ground" : "mac.floor.upper"))
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .background(store.visibleHomeFloor == floor ? RoomTheme.paleMint : RoomTheme.paper, in: Capsule())
                        }.buttonStyle(.plain).disabled(store.isBusy)
                            .accessibilityIdentifier("macFloor_" + floor.rawValue)
                    }
                }.padding(3).background(.white.opacity(0.7), in: Capsule())
            } else {
                Label(GameStrings.text("mac.floor.ground"), systemImage: "house.fill").font(.headline)
            }
            Text(GameStrings.format("mac.home.cats", store.snapshot?.cats.count ?? 0))
                .font(.caption).foregroundStyle(RoomTheme.secondary)
            Spacer(minLength: 8)
            Button { store.beginDecorating() } label: {
                HStack(spacing: 8) {
                    Label(GameStrings.text("layout.edit"), systemImage: "sofa.fill")
                    MacKeyCap(value: preferences.binding(for: .decorate).label)
                }
            }.buttonStyle(MacCompactButtonStyle()).disabled(store.isBusy)
                .accessibilityIdentifier("macDecorate")
        }
    }

    private var stageFooter: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { angleControls.padding(6).background(.regularMaterial, in: Capsule()); Spacer(minLength: 6); zoomControls }
            VStack(spacing: 8) { angleControls.padding(6).background(.regularMaterial, in: Capsule()); zoomControls }
        }
    }

    private var angleControls: some View {
        HStack(spacing: 9) {
            Button { scene.turnRoomView(by: -1); cameraRevision += 1 } label: {
                HStack(spacing: 7) { Image(systemName: "chevron.left"); MacKeyCap(value: preferences.binding(for: .viewLeft).label) }
            }.buttonStyle(MacCompactButtonStyle()).accessibilityLabel(GameStrings.text("mac.command.viewLeft"))
                .accessibilityIdentifier("macViewLeft")
            Text(GameStrings.text(scene.roomViewAngle == .front ? "roomView.angle.front" : scene.roomViewAngle == .left ? "roomView.angle.left" : "roomView.angle.right"))
                .font(.system(size: 13, weight: .heavy, design: .rounded)).fixedSize().id(cameraRevision)
            Button { scene.turnRoomView(by: 1); cameraRevision += 1 } label: {
                HStack(spacing: 7) { Image(systemName: "chevron.right"); MacKeyCap(value: preferences.binding(for: .viewRight).label) }
            }.buttonStyle(MacCompactButtonStyle()).accessibilityLabel(GameStrings.text("mac.command.viewRight"))
                .accessibilityIdentifier("macViewRight")
        }.fixedSize(horizontal: true, vertical: false)
    }

    private var zoomControls: some View {
        HStack(spacing: 8) {
            Button { scene.showWholeRoom(); cameraRevision += 1 } label: {
                HStack(spacing: 7) { Label(GameStrings.text("mac.home.whole"), systemImage: "arrow.up.left.and.arrow.down.right") }
            }.buttonStyle(MacCompactButtonStyle()).accessibilityIdentifier("macWholeRoom")
            Button { scene.showCatCloseUp(); cameraRevision += 1 } label: {
                HStack(spacing: 7) {
                    Label(GameStrings.text("mac.home.close"), systemImage: "plus.magnifyingglass")
                    MacKeyCap(value: preferences.binding(for: .focusCat).label)
                }
            }.buttonStyle(MacCompactButtonStyle()).accessibilityIdentifier("macCloseUp")
        }.fixedSize(horizontal: true, vertical: false)
    }

    private func companionSummary(_ cat: CatState) -> String {
        var details = [GameStrings.text("hospital.coat.\(cat.appearance.rawValue)"),
                       GameStrings.text("catGrowth.bond.\(CatBondStage.stage(for: cat.intimacy).rawValue)")]
        if let growth = cat.growthState {
            details.append(CatGrowthPresentation.age(growth.ageDays(at: store.snapshot?.meta.lastSyncAt ?? store.now)))
        }
        return details.joined(separator: " · ")
    }

    private var catCard: some View {
        MacPanel {
            if let cat = store.cat {
                HStack(spacing: 12) {
                    Button { store.inspectCat() } label: { GameIcon(asset: CatArtwork.asset("cat-avatar", appearance: cat.appearance), symbol: "cat.fill", size: 64).background(RoomTheme.paleMint, in: Circle()) }.buttonStyle(.plain).accessibilityIdentifier("macCatProfile")
                    VStack(alignment: .leading, spacing: 7) {
                        Text(GameStrings.catName(cat)).font(.system(size: 22, weight: .heavy, design: .rounded))
                        Text(companionSummary(cat)).font(.caption).foregroundStyle(RoomTheme.secondary).lineLimit(2)
                        Button(action: onCats) { Label(GameStrings.text("mac.home.switchCat"), systemImage: "arrow.triangle.2.circlepath") }.buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                metric("stat.satiety", value: cat.satiety, color: RoomTheme.gold)
                metric("stat.cleanliness", value: cat.cleanliness, color: RoomTheme.sky)
                metric("stat.mood", value: cat.mood, color: RoomTheme.friendship)
                metric("mac.home.energy", value: cat.energy, color: RoomTheme.mint)
                if cat.healthState?.illness != nil { Button { store.openHospital(catID: cat.id) } label: { Label(GameStrings.text("hospital.healthAlert"), systemImage: "cross.case.fill") }.foregroundStyle(RoomTheme.coral) }
                if let rest = cat.activeRest {
                    HStack {
                        Label(GameStrings.text("mac.home.resting"), systemImage: "moon.zzz.fill")
                        Spacer()
                        Text("\(max(0, Int(rest.endsAt.timeIntervalSince(store.now))))s").monospacedDigit()
                        Button(GameStrings.text("mac.home.wake")) { scene.leaveFurnitureRest() }
                    }.font(.caption)
                }
                HStack(spacing: 8) {
                    care("care.feed", asset: "bowl-full", key: .feed) { store.feed() }.accessibilityIdentifier("macFeed")
                    care("care.clean", asset: "icon-clean", key: .clean) { store.clean() }.accessibilityIdentifier("macClean")
                    care("care.play", asset: "icon-play", key: .play) { store.presentPlayChoices() }.accessibilityIdentifier("macPlay")
                }.disabled(store.isBusy).frame(minHeight: 85)
                Button(action: onInventory) { Label(GameStrings.text("inventory.title"), systemImage: "backpack.fill").frame(maxWidth: .infinity) }.buttonStyle(SoftButtonStyle()).accessibilityIdentifier("macOpenInventory")
            }
        }
    }
    private func metric(_ key: String, value: Int, color: Color) -> some View {
        HStack(spacing: 9) {
            Text(GameStrings.text(key)).frame(width: 70, alignment: .leading)
                .lineLimit(1).minimumScaleFactor(0.85)
            MacCapsuleProgress(value: Double(value), tint: color)
            Text("\(value)").font(.caption.weight(.bold)).monospacedDigit().frame(width: 27, alignment: .trailing)
        }.font(.caption).accessibilityElement(children: .ignore)
            .accessibilityLabel(GameStrings.text(key)).accessibilityValue("\(value) / 100")
            .accessibilityIdentifier("macHomeStat_" + key)
    }
    private func care(_ title: String, asset: String, key: MacCommand, action: @escaping () -> Void) -> some View {
        let stock = key == .feed ? store.snapshot?.inventory.food ?? 0
            : key == .clean ? store.snapshot?.inventory.litter ?? 0 : store.snapshot?.inventory.toys ?? 0
        return Button(action: action) {
            VStack(spacing: 6) {
                GameIcon(asset: asset, symbol: "pawprint.fill", size: 34)
                Text(GameStrings.text(title)).font(.system(size: 13, weight: .heavy))
            }.frame(maxWidth: .infinity).padding(.top, 22).padding(.bottom, 10)
                .background(RoomTheme.paleMint.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                .overlay(alignment: .topLeading) { MacKeyCap(value: preferences.binding(for: key).label).padding(5) }
                .overlay(alignment: .topTrailing) {
                    Text("×\(stock)").font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(RoomTheme.secondary).padding(7).accessibilityHidden(true)
                }
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityLabel(GameStrings.text(title))
            .accessibilityValue(GameStrings.format("shop.owned", stock))
    }
    private var tasks: some View {
        MacPanel {
            HStack { Text(GameStrings.text("mac.home.tasks")).font(.headline); Spacer(); Button(GameStrings.text("mac.home.all"), action: onTasks).buttonStyle(.plain).accessibilityIdentifier("macShowTasks").foregroundStyle(RoomTheme.darkMint) }
            if daily.isEmpty { Label(GameStrings.text("mac.home.tasksDone"), systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(RoomTheme.darkMint) }
            if let snapshot = store.snapshot {
                ForEach(daily) { task in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(GameStrings.text("task.\(task.id).title")).font(.caption.weight(.bold))
                            MacCapsuleProgress(value: Double(GameTaskCatalog.progress(for: task, in: snapshot)), total: Double(task.target), tint: RoomTheme.mint)
                        }
                        if GameTaskCatalog.isClaimable(task, in: snapshot) {
                            Button(GameStrings.text("tasks.claim")) { Task { _ = await store.claimTask(id: task.id, expectedDayKey: snapshot.tasks.dailyDayKey) } }.buttonStyle(.borderedProminent).tint(RoomTheme.mint).disabled(store.isBusy)
                        } else { Text("\(min(task.target, GameTaskCatalog.progress(for: task, in: snapshot)))/\(task.target)").font(.caption).foregroundStyle(RoomTheme.secondary) }
                    }
                }
            }
        }
    }
}
#endif
