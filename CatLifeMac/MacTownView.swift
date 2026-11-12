import AppKit
import SwiftUI
import CatGameCore

@MainActor
struct MacTownView: View {
    let store: GameStore
    let onEnter: (TownPlace) -> Void
    var preferences: MacPreferences? = nil
    var onNeighbor: ((String) -> Void)? = nil
    @State private var selected: TownPlace = .board
    @State private var layer: TownLayer = .all
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragOrigin: CGSize?
    @State private var magnifyOrigin: CGFloat?
    @State private var inspectedNeighbor: NeighborDefinition?
    private var status: TownMapStatus { TownMapStatus(snapshot: store.snapshot) }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            map.frame(maxWidth: .infinity, maxHeight: .infinity)
            sidebar.frame(width: 325)
        }.font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(RoomTheme.ink)
            .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macTownPage")
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MacContentCommand"))) { note in
                guard inspectedNeighbor == nil, let raw = note.object as? String, let command = MacCommand(rawValue: raw) else { return }
                if command == .confirm { enter(selected) }
            }
            .sheet(item: $inspectedNeighbor) { neighbor in
                NavigationStack {
                    NeighborDetailView(store: store, neighborID: neighbor.id)
                        .toolbar { ToolbarItem(placement: .cancellationAction) {
                            Button(GameStrings.text("common.close")) { inspectedNeighbor = nil }
                        } }
                }.frame(width: 640, height: 620)
            }
            .onChange(of: store.saveSceneGeneration) { _, _ in inspectedNeighbor = nil }
    }

    private var map: some View {
        VStack(spacing: 0) {
            toolbar.padding(14)
            GeometryReader { geometry in
                mapContents(size: geometry.size)
                    .background(MacTownWheel69 { delta in
                        let factor = MacRoomPointer.zoomFactor(delta: delta, reversed: preferences?.wheelReversed ?? false)
                        scale = min(2, max(1, scale * factor))
                        offset = MacTownViewport69.clamped(offset, size: geometry.size, scale: scale)
                    })
                    .clipped()
            }
            footer.padding(12)
        }
        .background(LinearGradient(colors: [RoomTheme.sky.opacity(0.18), TownPalette.grass], startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white, lineWidth: 3))
        .accessibilityIdentifier("macTownMap")
    }

    private var toolbar: some View {
        HStack(spacing: 7) {
            ForEach(TownLayer.allCases) { value in
                Button { layer = value } label: {
                    Text(GameStrings.text(value.titleKey)).font(.caption.weight(.heavy))
                        .padding(.horizontal, 13).padding(.vertical, 10)
                        .foregroundStyle(layer == value ? .white : RoomTheme.ink)
                        .background(layer == value ? RoomTheme.mint : RoomTheme.paper, in: Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("macTownLayer_\(value.rawValue)")
                    .accessibilityAddTraits(layer == value ? .isSelected : [])
            }
            Spacer(minLength: 0)
            TimelineView(.periodic(from: .now, by: 60)) { clock in
                Label {
                    Text(clock.date, format: .dateTime.hour().minute()).monospacedDigit()
                } icon: { Image(systemName: TownMapLayout.isNight(clock.date) ? "moon.stars.fill" : "sun.max.fill") }
                    .font(.caption.weight(.heavy)).foregroundStyle(RoomTheme.secondary)
                    .padding(11).background(RoomTheme.paper, in: Capsule())
            }
        }
    }

    private func mapContents(size: CGSize) -> some View {
        ZStack {
            mapGround
            ForEach(TownPlace.allCases) { place in
                let point = MacTownViewport69.position(place)
                marker(place, size: min(size.width * 0.15, size.height * (place.isEmpty ? 0.12 : 0.165)))
                    .position(x: point.x * size.width, y: point.y * size.height)
                    .opacity(layer == .all || layer == place.layer ? 1 : 0.25)
            }
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(scale).offset(offset)
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 6).onChanged { value in
            if dragOrigin == nil { dragOrigin = offset }
            offset = MacTownViewport69.clamped(CGSize(width: (dragOrigin?.width ?? 0) + value.translation.width,
                height: (dragOrigin?.height ?? 0) + value.translation.height), size: size, scale: scale)
        }.onEnded { _ in dragOrigin = nil })
        .simultaneousGesture(MagnifyGesture().onChanged { value in
            if magnifyOrigin == nil { magnifyOrigin = scale }
            scale = min(2, max(1, (magnifyOrigin ?? 1) * value.magnification))
            offset = MacTownViewport69.clamped(offset, size: size, scale: scale)
        }.onEnded { _ in magnifyOrigin = nil })
    }

    private var mapGround: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            var river = Path()
            river.move(to: CGPoint(x: -20, y: h * 0.275))
            river.addCurve(to: CGPoint(x: w + 20, y: h * 0.285), control1: CGPoint(x: w * 0.35, y: h * 0.34), control2: CGPoint(x: w * 0.6, y: h * 0.22))
            context.stroke(river, with: .color(RoomTheme.sky.opacity(0.6)), style: StrokeStyle(lineWidth: h * 0.075, lineCap: .round))
            var roads = Path()
            for y in [0.16, 0.46, 0.75] {
                roads.move(to: CGPoint(x: w * 0.13, y: h * y))
                roads.addLine(to: CGPoint(x: w * 0.87, y: h * y))
            }
            roads.move(to: CGPoint(x: w * 0.5, y: h * 0.12))
            roads.addLine(to: CGPoint(x: w * 0.5, y: h * 0.92))
            context.stroke(roads, with: .color(TownPalette.woodEdge.opacity(0.5)), style: StrokeStyle(lineWidth: 27, lineCap: .round))
            context.stroke(roads, with: .color(RoomTheme.track), style: StrokeStyle(lineWidth: 20, lineCap: .round))
            let bridge = CGRect(x: w * 0.5 - 25, y: h * 0.275 - 21, width: 50, height: 42)
            context.fill(Path(roundedRect: bridge, cornerRadius: 8), with: .color(TownPalette.woodEdge))
            for dy in stride(from: 8.0, through: 34.0, by: 9) {
                var plank = Path()
                plank.move(to: CGPoint(x: bridge.minX + 4, y: bridge.minY + dy))
                plank.addLine(to: CGPoint(x: bridge.maxX - 4, y: bridge.minY + dy))
                context.stroke(plank, with: .color(RoomTheme.wood), lineWidth: 3)
            }
            for p in [CGPoint(x: 0.05, y: 0.17), CGPoint(x: 0.94, y: 0.17), CGPoint(x: 0.07, y: 0.47), CGPoint(x: 0.93, y: 0.47), CGPoint(x: 0.06, y: 0.76)] {
                let tree = CGRect(x: p.x * w - 12, y: p.y * h - 15, width: 24, height: 30)
                context.fill(Path(ellipseIn: tree), with: .color(RoomTheme.darkMint.opacity(0.25)))
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }

    private func marker(_ place: TownPlace, size: CGFloat) -> some View {
        Button { selected = place } label: {
            VStack(spacing: 1) {
                GameIcon(asset: place.asset, symbol: place.symbol, size: size, tint: place.tint)
                    .opacity(place.isFuture ? 0.65 : 1)
                    .background {
                        if selected == place { Ellipse().fill(RoomTheme.gold.opacity(0.22)).frame(width: size * 1.1, height: size * 0.4).offset(y: size * 0.3) }
                    }
                Text(GameStrings.text(place.titleKey)).font(.system(size: 12, weight: .heavy)).padding(.horizontal, 11).padding(.vertical, 6)
                    .foregroundStyle(RoomTheme.ink).background(selected == place ? RoomTheme.wood : RoomTheme.paper, in: Capsule())
                    .overlay(Capsule().strokeBorder(selected == place ? RoomTheme.gold : .white, lineWidth: 2))
            }
            .overlay(alignment: .topTrailing) {
                if let badge = status.badge(for: place, now: store.now) {
                    Text(badge).font(.system(size: 9, weight: .heavy)).padding(.horizontal, 7).padding(.vertical, 4)
                        .foregroundStyle(.white).background(status.badgeTint(for: place), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white, lineWidth: 2)).offset(x: 15, y: -8)
                }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).simultaneousGesture(TapGesture(count: 2).onEnded { enter(place) })
            .help(preferences?.hoverHints == false ? "" : GameStrings.text("mac.town.placeHint"))
            .accessibilityLabel(GameStrings.text(place.titleKey))
            .accessibilityValue(status.badge(for: place, now: store.now) ?? GameStrings.text(place.statusKey(sickCount: status.sickCount)))
            .accessibilityIdentifier("macTownPlace_\(place.rawValue)")
            .accessibilityAddTraits(selected == place ? .isSelected : [])
            .accessibilityAction(named: Text(GameStrings.text(place.actionKey))) { enter(place) }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(GameStrings.text("mac.town.mouseHint")).font(.caption2).foregroundStyle(RoomTheme.secondary)
            Spacer(minLength: 0)
            Button { selected = .home; scale = 1; offset = .zero; enter(.home) } label: { Label(GameStrings.text("town.goHome") + " " + keyLabel(.returnHome), systemImage: "house.fill") }
                .buttonStyle(.bordered).accessibilityIdentifier("macTownHome")
            Button { scale = 1; offset = .zero } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .accessibilityLabel(GameStrings.text("mac.town.resetMap")).help(GameStrings.text("mac.town.resetMap"))
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(spacing: 14) {
                placeDetail
                neighbors
            }
        }
    }

    private var placeDetail: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 15) {
                GameIcon(asset: selected.asset, symbol: selected.symbol, size: 72, tint: selected.tint)
                    .padding(8).background(selected.tile, in: RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 8) {
                    Text(GameStrings.text(selected.titleKey)).font(.system(size: 24, weight: .heavy)).accessibilityIdentifier("macTownDetailTitle")
                    Text(status.badge(for: selected, now: store.now) ?? GameStrings.text(selected.statusKey(sickCount: status.sickCount)))
                        .font(.caption.weight(.bold)).foregroundStyle(status.badgeTint(for: selected))
                }
            }
            Text(selected == .home ? GameStrings.format("town.homeDescription", store.homeDisplayName) : GameStrings.text(selected.descriptionKey))
                .font(.subheadline).foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
            if selected == .board || selected == .plaza { eventSummary }
            Button { enter(selected) } label: {
                Label(GameStrings.text(selected.actionKey) + "  " + keyLabel(.confirm), systemImage: selected.symbol).frame(maxWidth: .infinity)
            }.buttonStyle(MintButtonStyle()).disabled(selected.isFuture || selected.isEmpty || store.isBusy)
                .accessibilityIdentifier("macTownEnter")
        }.macContentCard69()
    }

    @ViewBuilder private var eventSummary: some View {
        if let state = store.snapshot {
            if let event = TownEventCatalog.current(in: state) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(GameStrings.format("townEvents.letterFrom", TownEventPresentation.sender(event.neighborID)))
                        .font(.caption).foregroundStyle(RoomTheme.coralDeep)
                    Text(GameStrings.text(event.titleKey)).font(.headline)
                    Text(GameStrings.text(state.community.events.todayReceipt == nil ? "townEvents.available" : "townEvents.completed"))
                        .font(.caption).foregroundStyle(RoomTheme.secondary)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoomTheme.letterPaper, in: RoundedRectangle(cornerRadius: 16))
            }
            if let milestone = TownEventCatalog.milestones.first {
                VStack(alignment: .leading, spacing: 7) {
                    Text(GameStrings.format("townEvents.progress", state.community.events.totalCompleted, milestone.target)).font(.caption).foregroundStyle(RoomTheme.friendshipDeep)
                    ProgressView(value: Double(min(state.community.events.totalCompleted, milestone.target)), total: Double(milestone.target)).tint(RoomTheme.friendship)
                }
            }
        }
    }

    private var neighbors: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(GameStrings.text("community.title"), systemImage: "person.2.fill").font(.headline)
                Spacer(minLength: 0)
                Text(GameStrings.format("townMap.visitCount", status.unvisitedNeighbors.count)).font(.caption).foregroundStyle(RoomTheme.secondary)
            }
            ForEach(CommunityCatalog.neighbors) { neighbor in neighborRow(neighbor) }
        }.macContentCard69()
    }

    private func neighborRow(_ neighbor: NeighborDefinition) -> some View {
        let relation = store.snapshot?.community.relationship(for: neighbor.id) ?? NeighborRelationship()
        return Button { if let onNeighbor { onNeighbor(neighbor.id) } else { inspectedNeighbor = neighbor } } label: {
            HStack(spacing: 10) {
                CommunityPortrait(neighbor: neighbor, size: 44).overlay(alignment: .topTrailing) {
                    if !relation.visitedToday { Circle().fill(RoomTheme.mint).frame(width: 10, height: 10).overlay(Circle().stroke(.white, lineWidth: 2)) }
                }
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(GameStrings.text(neighbor.nameKey)).font(.headline)
                        Text(GameStrings.text(relation.stage.nameKey)).font(.caption).foregroundStyle(CommunityPalette.tint(neighbor))
                        Spacer(minLength: 0)
                        Text("\(relation.friendship)").font(.caption).foregroundStyle(RoomTheme.secondary)
                    }
                    ProgressView(value: Double(relation.friendship), total: 100).tint(RoomTheme.friendship)
                }.frame(maxWidth: .infinity)
            }.padding(.vertical, 5).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("macNeighbor_\(neighbor.id)")
            .accessibilityHint(GameStrings.text("mac.town.neighborHint"))
    }

    private func keyLabel(_ command: MacCommand) -> String { (preferences?.binding(for: command) ?? command.defaultBinding).label }

    private func enter(_ place: TownPlace) {
        guard !store.isBusy, !place.isFuture, !place.isEmpty else { return }
        selected = place
        onEnter(place)
    }
}

/// Map pan never changes game state or persists a presentation coordinate.
enum MacTownViewport69 {
    static func clamped(_ offset: CGSize, size: CGSize, scale: CGFloat) -> CGSize {
        let x = max(0, size.width * (scale - 1) / 2)
        let y = max(0, size.height * (scale - 1) / 2)
        return CGSize(width: min(x, max(-x, offset.width)), height: min(y, max(-y, offset.height)))
    }
    static func position(_ place: TownPlace) -> CGPoint {
        switch place {
        case .work: CGPoint(x: 0.21, y: 0.14)
        case .cafe: CGPoint(x: 0.5, y: 0.12)
        case .shop: CGPoint(x: 0.8, y: 0.14)
        case .board: CGPoint(x: 0.21, y: 0.42)
        case .plaza: CGPoint(x: 0.5, y: 0.42)
        case .market: CGPoint(x: 0.8, y: 0.42)
        case .street: CGPoint(x: 0.16, y: 0.68)
        case .home: CGPoint(x: 0.5, y: 0.67)
        case .hospital: CGPoint(x: 0.82, y: 0.68)
        case .adoption: CGPoint(x: 0.35, y: 0.88)
        case .lot1: CGPoint(x: 0.65, y: 0.88)
        case .lot2: CGPoint(x: 0.86, y: 0.9)
        }
    }
}

/// Observe wheel events inside the map while leaving native SwiftUI buttons clickable.
private struct MacTownWheel69: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.onScroll = onScroll
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak coordinator = context.coordinator] event in
            let handled = MainActor.assumeIsolated {
                guard let coordinator, let view = coordinator.view, let window = view.window,
                      event.window === window, view.bounds.contains(view.convert(event.locationInWindow, from: nil)) else { return false }
                coordinator.onScroll?(event.scrollingDeltaY)
                return true
            }
            return handled ? nil : event
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.onScroll = onScroll }
    func makeCoordinator() -> Coordinator { Coordinator() }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil
    }
    @MainActor final class Coordinator {
        weak var view: NSView?
        var onScroll: ((CGFloat) -> Void)?
        var monitor: Any?
    }
}
