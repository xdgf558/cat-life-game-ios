#if os(macOS)
import SwiftUI
import CatGameCore

@MainActor
struct MacTitleView: View {
    let store: GameStore
    let scene: RoomScene?
    let preferences: MacPreferences
    let hadSave: Bool
    let isActive: Bool
    let onContinue: () -> Void
    let onNew: () -> Void
    let onLoad: () -> Void
    let onSettings: () -> Void
    let onQuit: () -> Void
    private var newGameButton: some View {
        Button(action: onNew) { Label(GameStrings.text("mac.title.new"), systemImage: "plus.circle.fill").frame(maxWidth: .infinity) }
            .buttonStyle(hadSave ? AnyMacButtonStyle.soft : .primary).accessibilityIdentifier("macNewGame")
    }
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 24) {
                    GameIcon(asset: "cat-avatar", symbol: "cat.fill", size: 90).padding(12).background(RoomTheme.paleMint, in: RoundedRectangle(cornerRadius: 28))
                    Text(GameStrings.text("mac.title.name")).font(.system(size: 44, weight: .heavy, design: .rounded)).lineSpacing(6)
                    Text(GameStrings.text("mac.title.tagline")).font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(RoomTheme.secondary)
                    if store.loadFailed {
                        MacPanel {
                            Label(GameStrings.text(store.needsNewerVersion ? "save.newerVersionTitle" : "mac.title.loadFailed"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(RoomTheme.coral)
                            Button(GameStrings.text("common.retry")) { Task { await store.load() } }.buttonStyle(.borderedProminent).tint(RoomTheme.mint)
                            Button(GameStrings.text("mac.title.load"), action: onLoad).buttonStyle(.bordered)
                        }
                    } else if store.isLoading {
                        ProgressView(value: store.startupProgress).tint(RoomTheme.mint)
                        Text(GameStrings.text(store.startupPhase)).font(.caption)
                    } else {
                        if hadSave {
                            Button(action: onContinue) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label(GameStrings.text("mac.title.continue"), systemImage: "play.fill").font(.title3.weight(.heavy))
                                    Text(GameStrings.format("mac.title.summary", store.snapshot?.player.level ?? 1, store.snapshot?.cats.count ?? 0)).font(.caption)
                                    if let date = store.snapshot?.meta.lastSyncAt { Text(date, format: .dateTime.year().month().day().hour().minute()).font(.caption2) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(MintButtonStyle()).keyboardShortcut(.defaultAction).accessibilityIdentifier("macContinue")
                        }
                        if hadSave { newGameButton } else { newGameButton.keyboardShortcut(.defaultAction) }
                        HStack(spacing: 12) {
                            Button(action: onLoad) { Label(GameStrings.text("mac.title.load"), systemImage: "folder.fill") }.buttonStyle(SoftButtonStyle())
                            Button(action: onSettings) { Label(GameStrings.text("mac.page.settings"), systemImage: "gearshape.fill") }.buttonStyle(SoftButtonStyle())
                            Button(action: onQuit) { Label(GameStrings.text("mac.title.quit"), systemImage: "power") }.buttonStyle(SoftButtonStyle())
                        }
                    }
                    Spacer(minLength: 5)
                    Label(GameStrings.text("mac.save.steamOffline"), systemImage: "externaldrive.fill").font(.caption).foregroundStyle(RoomTheme.secondary)
                    Text(AppVersion.current.localizedDisplay).font(.caption2).foregroundStyle(RoomTheme.secondary)
                }.frame(width: min(430, geometry.size.width * 0.34)).padding(36)
                VStack(spacing: 0) {
                    if !store.isLoading, store.snapshot != nil, let scene {
                        MacRoomCanvas(store: store, scene: scene, isActive: isActive, readOnlyPreview: true, frameLimit: 30, contextMenus: false, hoverHints: false)
                            .clipShape(RoundedRectangle(cornerRadius: 30))
                    } else {
                        Image("room-empty").resizable().scaledToFit().padding(24)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    Text(GameStrings.text("mac.title.preview")).font(.caption).foregroundStyle(RoomTheme.secondary).padding(16)
                }.background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 30)).overlay(RoundedRectangle(cornerRadius: 30).stroke(.white, lineWidth: 3)).padding(.vertical, 48).padding(.trailing, 36)
            }
        }.background(LinearGradient(colors: [RoomTheme.cream, RoomTheme.paleMint.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .accessibilityIdentifier("macTitlePage")
    }
}
private enum AnyMacButtonStyle: ButtonStyle {
    case soft, primary
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(self == .primary ? .white : RoomTheme.ink)
            .padding(16).background(self == .primary ? RoomTheme.mint : RoomTheme.paper, in: RoundedRectangle(cornerRadius: 20))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
#endif
