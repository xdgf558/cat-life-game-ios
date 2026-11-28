import SwiftUI
import CatGameCore

@MainActor
struct SettingsSoundPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var settings: AudioSettings
    let track: GameMusicTrack
    let musicPlaying: Bool
    let saving: Bool
    let previewDisabled: Bool
    let onChange: () -> Void
    let onCommit: () -> Void
    let onMusicPreview: () -> Void
    let onEffectsPreview: () -> Void
    let onCatPreview: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            nowPlaying
            control(.music, preview: onMusicPreview)
            control(.effects, preview: onEffectsPreview)
            control(.cat, preview: onCatPreview)
            VStack(spacing: 0) {
                option("audio.sceneMusic", symbol: "map.fill", tint: RoomTheme.darkMint,
                       keyPath: \.sceneMusic, id: "audioSceneMusicToggle")
                Divider().overlay(RoomTheme.wood.opacity(0.2))
                option("audio.nightQuiet", symbol: "moon.stars.fill", tint: RoomTheme.lilac,
                       keyPath: \.nightQuiet, id: "audioNightQuietToggle")
                Divider().overlay(RoomTheme.wood.opacity(0.2))
                option("audio.haptics", symbol: "iphone.radiowaves.left.and.right", tint: RoomTheme.coral,
                       keyPath: \.haptics, id: "audioHapticsToggle")
            }
            .padding(.horizontal, 14).padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 24).fill(RoomTheme.paper)
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white, lineWidth: 2))
                    .shadow(color: RoomTheme.ink.opacity(0.08), radius: 0, y: 4)
            }
            if saving {
                ProgressView(GameStrings.text("common.saving"))
                    .font(.footnote).tint(RoomTheme.coralDeep)
                    .accessibilityIdentifier("audioSaveStatus")
            }
            Text(GameStrings.text("audio.systemHint"))
                .font(.footnote).foregroundStyle(RoomTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var nowPlaying: some View {
        HStack(spacing: 12) {
            TimelineView(.animation(minimumInterval: 0.1, paused: !musicPlaying || reduceMotion)) { context in
                ZStack {
                    Circle().fill(RoomTheme.coralDeep)
                    Circle().stroke(.white, lineWidth: 3)
                    Circle().fill(RoomTheme.paper).frame(width: 14, height: 14)
                    Circle().fill(.white.opacity(0.35)).frame(width: 4, height: 4).offset(y: -12)
                }
                .rotationEffect(.degrees(musicPlaying && !reduceMotion ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) * 90 : 0))
            }
            .frame(width: 38, height: 38).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(GameStrings.text(musicPlaying ? "audio.nowPlaying" : "audio.paused") + " · " + GameStrings.text(track.sceneKey))
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                Text(track.title).font(.system(size: 15, weight: .heavy))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onMusicPreview) {
                Image(systemName: musicPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(RoomTheme.paper, in: Circle())
            }
            .buttonStyle(.plain).foregroundStyle(RoomTheme.coralDeep)
            .disabled(previewDisabled || !settings.musicEnabled || settings.musicVolume == 0)
            .accessibilityLabel(GameStrings.text(musicPlaying ? "audio.pauseMusic" : "audio.resumeMusic"))
            .accessibilityIdentifier("audioNowPlayingButton")
        }
        .padding(.horizontal, 14).padding(.vertical, 10).foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: 20).fill(RoomTheme.coral)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.5), lineWidth: 1.5))
                .shadow(color: RoomTheme.coralDeep, radius: 0, y: 3)
        }
        .accessibilityIdentifier("audioNowPlayingCard")
    }

    private func control(_ channel: SettingsAudioControl.Channel, preview: @escaping () -> Void) -> some View {
        SettingsAudioControl(channel: channel, compact: false, settings: $settings,
                             onChange: onChange, onCommit: onCommit,
                             onPreview: preview, previewDisabled: previewDisabled)
    }

    private func option(_ key: String, symbol: String, tint: Color,
                        keyPath: WritableKeyPath<AudioSettings, Bool>, id: String) -> some View {
        Toggle(isOn: Binding(get: { settings[keyPath: keyPath] }, set: { value in
            guard settings[keyPath: keyPath] != value else { return }
            settings[keyPath: keyPath] = value
            onChange()
            onCommit()
        })) {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(tint).frame(width: 22).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(GameStrings.text(key)).font(.system(size: 14, weight: .heavy))
                    Text(GameStrings.text(key + "Detail")).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(RoomTheme.coral).padding(.vertical, 12)
        .accessibilityIdentifier(id)
    }
}
