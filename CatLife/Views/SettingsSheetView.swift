import SwiftUI
import CatGameCore

/// Settings menu with second-level pages, mirroring the WeChat `settingsSheet` structure:
/// 声音 · 通用 · 存档 · 关于 (+ 测试 while ads are simulated).
struct SettingsSheetView: View {
    enum Page: Hashable {
        case sound
        case language
        case save
        case releases
        case privacy
    }

    @Bindable var store: DiaryAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Page] = []
    @State private var audioDraft: AudioSettings = AudioSettings()
    @State private var confirmReset = false

    static let supportEmail = URL(string: "mailto:brodstem@protonmail.com")!

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    group(GameStrings.text("settings.group.sound")) {
                        navRow(.sound, symbol: "music.note", tint: RoomTheme.coral,
                               title: GameStrings.text("settings.row.audio"), value: audioSummary,
                               id: "settingsSoundRow")
                    }

                    group(GameStrings.text("settings.group.general")) {
                        navRow(.language, symbol: "globe", tint: RoomTheme.sky,
                               title: GameStrings.text("settings.language"), value: languageLabel(store.state.settings.language),
                               id: "settingsLanguageRow")
                    }

                    group(GameStrings.text("settings.group.save")) {
                        navRow(.save, symbol: "externaldrive.fill", tint: RoomTheme.woodDeep,
                               title: GameStrings.text("settings.row.saveLocal"),
                               value: store.saveError == nil ? GameStrings.text("settings.save.ok") : GameStrings.text("settings.save.pending"),
                               id: "settingsSaveRow")
                        Button {
                            confirmReset = true
                        } label: {
                            rowLabel(symbol: "arrow.counterclockwise", tint: RoomTheme.coralDeep,
                                     title: GameStrings.text("settings.reset"), value: nil, danger: true, chevron: false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settingsResetRow")
                    }

                    group(GameStrings.text("settings.group.about")) {
                        navRow(.releases, symbol: "sparkles", tint: RoomTheme.gold,
                               title: GameStrings.text("settings.releases"), value: AppVersion.current.version,
                               id: "settingsReleasesRow")
                        navRow(.privacy, symbol: "hand.raised.fill", tint: RoomTheme.mint,
                               title: GameStrings.text("privacy.title"), value: nil,
                               id: "settingsPrivacyRow")
                        Link(destination: Self.supportEmail) {
                            rowLabel(symbol: "envelope.fill", tint: RoomTheme.lilac,
                                     title: GameStrings.text("settings.row.contact"), value: nil, danger: false, chevron: true)
                        }
                        .buttonStyle(.plain)
                    }

                    group(GameStrings.text("settings.group.test")) {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle(isOn: $store.mockAdsEnabled) {
                                HStack(spacing: 12) {
                                    GameIconTile(symbol: "play.rectangle.fill", tint: RoomTheme.secondary,
                                                 background: RoomTheme.secondary.opacity(0.14), size: 32)
                                    Text(GameStrings.text("settings.adDebug"))
                                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                                        .foregroundStyle(RoomTheme.ink)
                                }
                            }
                            .tint(RoomTheme.coral)
                            Text(GameStrings.text("settings.adDebugDesc"))
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(RoomTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 44)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Text(AppVersion.current.localizedDisplay)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(RoomTheme.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(16)
            }
            .background(RoomTheme.cream.ignoresSafeArea())
            .navigationTitle(GameStrings.text("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(GameStrings.text("common.done")) {
                        store.audio.endMusicPreview()
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(RoomTheme.coralDeep)
                }
            }
            .navigationDestination(for: Page.self) { page in
                destination(page)
            }
            .onAppear {
                audioDraft = store.state.settings.audio
            }
            .onDisappear {
                store.audio.endMusicPreview()
            }
            .alert(GameStrings.text("settings.resetConfirmTitle"), isPresented: $confirmReset) {
                Button(GameStrings.text("common.cancel"), role: .cancel) {}
                Button(GameStrings.text("common.confirm"), role: .destructive) {
                    store.resetProgress()
                    dismiss()
                }
            } message: {
                Text(GameStrings.text("settings.resetConfirmMessage"))
            }
        }
        .tint(RoomTheme.coralDeep)
    }

    // MARK: - Second-level pages

    @ViewBuilder
    private func destination(_ page: Page) -> some View {
        switch page {
        case .sound:
            ScrollView {
                SettingsSoundPage(
                    settings: $audioDraft,
                    track: store.audio.currentTrack,
                    musicPlaying: store.audio.musicPlaying,
                    saving: store.isSaving,
                    previewDisabled: false,
                    onChange: { store.updateAudioSettings(audioDraft, commit: false) },
                    onCommit: { store.updateAudioSettings(audioDraft, commit: true) },
                    onMusicPreview: { store.audio.toggleMusicPreview() },
                    onEffectsPreview: { store.audio.play(.merge, userInitiated: true) },
                    onCatPreview: { store.audio.play(.catHappy, userInitiated: true) }
                )
                .padding(16)
            }
            .background(RoomTheme.cream.ignoresSafeArea())
            .navigationTitle(GameStrings.text("settings.row.audio"))
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear { store.audio.endMusicPreview() }

        case .language:
            ScrollView {
                VStack(spacing: 8) {
                    ForEach([GameLanguage?.none, .simplifiedChinese, .traditionalChinese, .english], id: \.self) { lang in
                        Button {
                            store.updateLanguage(lang)
                        } label: {
                            HStack {
                                Text(languageLabel(lang))
                                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                                    .foregroundStyle(RoomTheme.ink)
                                Spacer()
                                if store.state.settings.language == lang {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(RoomTheme.coral)
                                }
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 52)
                            .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(store.state.settings.language == lang ? RoomTheme.coral : RoomTheme.wood.opacity(0.5),
                                            lineWidth: store.state.settings.language == lang ? 1.6 : 1)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(store.state.settings.language == lang ? .isSelected : [])
                    }
                }
                .padding(16)
            }
            .background(RoomTheme.cream.ignoresSafeArea())
            .navigationTitle(GameStrings.text("settings.language"))
            .navigationBarTitleDisplayMode(.inline)

        case .save:
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    PaperCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(GameStrings.text("settings.row.saveLocal"), systemImage: "iphone")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(RoomTheme.ink)
                            Text(GameStrings.text("settings.save.desc"))
                                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                                .foregroundStyle(RoomTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    PaperCard {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: store.saveError == nil ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(store.saveError == nil ? RoomTheme.mint : RoomTheme.coralDeep)
                                Text(store.saveError ?? GameStrings.text("settings.save.ok"))
                                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                                    .foregroundStyle(RoomTheme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(GameStrings.format("settings.save.lastSaved", lastSavedText))
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(RoomTheme.secondary)
                            if store.saveError != nil {
                                Button {
                                    store.retrySaveNow()
                                } label: {
                                    if store.isSaving {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(.white)
                                            .frame(minWidth: 72)
                                    } else {
                                        Text(GameStrings.text("save.retry"))
                                    }
                                }
                                .disabled(store.isSaving)
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .buttonStyle(WarmButtonStyle())
                                .padding(.top, 4)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(RoomTheme.cream.ignoresSafeArea())
            .navigationTitle(GameStrings.text("settings.row.saveLocal"))
            .navigationBarTitleDisplayMode(.inline)

        case .releases:
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(AppRelease.recent) { release in
                        PaperCard {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(GameStrings.format("settings.versionFormat", release.version, "\(release.build)"))
                                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                                        .foregroundStyle(RoomTheme.coralDeep)
                                    Spacer()
                                    Text(release.localizedDate)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(RoomTheme.secondary)
                                }
                                let titleKey = "release.\(release.build).title"
                                let bodyKey = "release.\(release.build).body"
                                if GameStrings.text(titleKey) != titleKey {
                                    Text(GameStrings.text(titleKey))
                                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                                        .foregroundStyle(RoomTheme.ink)
                                }
                                if GameStrings.text(bodyKey) != bodyKey {
                                    Text(GameStrings.text(bodyKey))
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(RoomTheme.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(RoomTheme.cream.ignoresSafeArea())
            .navigationTitle(GameStrings.text("settings.releases"))
            .navigationBarTitleDisplayMode(.inline)

        case .privacy:
            PrivacySummaryView()
        }
    }

    // MARK: - Rows

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                .foregroundStyle(RoomTheme.secondary)
                .padding(.leading, 6)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 6) {
                content()
            }
        }
    }

    private func navRow(_ page: Page, symbol: String, tint: Color, title: String, value: String?, id: String) -> some View {
        NavigationLink(value: page) {
            rowLabel(symbol: symbol, tint: tint, title: title, value: value, danger: false, chevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func rowLabel(symbol: String, tint: Color, title: String, value: String?, danger: Bool, chevron: Bool) -> some View {
        HStack(spacing: 12) {
            GameIconTile(symbol: symbol, tint: tint, background: tint.opacity(0.14), size: 32)
            Text(title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(danger ? RoomTheme.coralDeep : RoomTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            if let value {
                Text(value)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(RoomTheme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(RoomTheme.secondary.opacity(0.7))
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(RoomTheme.wood.opacity(0.45), lineWidth: 1))
        .contentShape(Rectangle())
    }

    // MARK: - Values

    private var audioSummary: String {
        let audio = store.state.settings.audio
        let on = GameStrings.text("settings.on")
        let off = GameStrings.text("settings.off")
        return GameStrings.format("settings.value.audio", audio.musicEnabled ? on : off, audio.effectsEnabled ? on : off)
    }

    private func languageLabel(_ lang: GameLanguage?) -> String {
        switch lang {
        case .none: GameStrings.text("settings.langSystem")
        case .simplifiedChinese: GameStrings.text("settings.langZH")
        case .traditionalChinese: GameStrings.text("settings.langZHT")
        case .english: GameStrings.text("settings.langEN")
        }
    }

    private var lastSavedText: String {
        guard let date = store.lastPersistedAt else {
            return GameStrings.text("settings.save.notYet")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: GameLocalization.shared.language.rawValue)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
