import SwiftUI
import CatGameCore

/// Start screen ported from the WeChat mini-game cover (`overlays/loading.ts`):
/// window-side Xiaoju on an open diary, hand-lettered title, and a single
/// "open the diary" button that doubles as the load progress bar.
/// The game only starts after the player taps it. No account is needed: saves stay on device.
struct CoverView: View {
    @Bindable var store: DiaryAppStore
    let onEnter: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownProgress: Double = 0.08
    @State private var breathe = false
    @State private var showingPrivacy = false

    /// Vertical band of the background art occupied by Xiaoju and the diary (ears ~37.5%, diary edge ~72.5%).
    private let subjectTop: CGFloat = 0.375
    private let subjectBottom: CGFloat = 0.725

    private var isNewDiary: Bool {
        store.state.tutorialActive && store.state.diary.photos.isEmpty
    }

    var body: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top
            let safeBottom = geo.safeAreaInsets.bottom
            let size = CGSize(width: geo.size.width, height: geo.size.height + safeTop + safeBottom)
            let titleW = min(size.width - 56, 340)
            let titleH = titleW * 0.4
            let titleTop = safeTop + 18
            let buttonBottom = size.height - safeBottom - 96
            let bg = backgroundRect(in: size, focusTop: titleTop + titleH - 16, focusBottom: buttonBottom - 64)

            ZStack(alignment: .topLeading) {
                RoomTheme.cream

                Image("cover_bg")
                    .resizable()
                    .frame(width: bg.width, height: bg.height)
                    .position(x: bg.midX, y: bg.midY)
                    .accessibilityHidden(true)

                // Cream wash under the button and footer so text stays legible over the table.
                LinearGradient(
                    stops: [
                        .init(color: RoomTheme.cream.opacity(0), location: 0),
                        .init(color: RoomTheme.cream.opacity(0.78), location: 0.4),
                        .init(color: RoomTheme.cream.opacity(0.95), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: size.width, height: size.height - (buttonBottom - 90))
                .position(x: size.width / 2, y: (buttonBottom - 90 + size.height) / 2)
                .allowsHitTesting(false)

                Image("cover_title")
                    .resizable()
                    .scaledToFit()
                    .frame(width: titleW, height: titleH)
                    .position(x: size.width / 2, y: titleTop + titleH / 2)
                    .accessibilityLabel(GameStrings.text("app.title"))
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 14) {
                    if let error = store.loadError {
                        loadErrorCard(error)
                    } else {
                        enterButton
                    }

                    Button {
                        showingPrivacy = true
                    } label: {
                        Text(GameStrings.text("cover.privacy"))
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .underline()
                            .foregroundStyle(RoomTheme.ink)
                            .frame(minHeight: 44)
                            .padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("coverPrivacyButton")

                    Text(AppVersion.current.localizedDisplay)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(RoomTheme.secondary)
                }
                .frame(width: min(size.width - 56, 320))
                .position(x: size.width / 2, y: buttonBottom + 26)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingPrivacy) {
            NavigationStack {
                PrivacySummaryView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(GameStrings.text("common.done")) { showingPrivacy = false }
                                .fontWeight(.bold)
                                .foregroundStyle(RoomTheme.coralDeep)
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .task {
            // Ease the bar toward 90% while the save loads; the real "done" jumps it to 100%.
            while !Task.isCancelled && !store.isLoaded {
                try? await Task.sleep(for: .milliseconds(60))
                shownProgress = min(0.9, shownProgress + (0.9 - shownProgress) * 0.08)
            }
            withAnimation(.easeOut(duration: 0.25)) { shownProgress = 1 }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var enterButton: some View {
        if store.isLoaded {
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                onEnter()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 20, weight: .bold))
                    Text(isNewDiary
                         ? GameStrings.text("cover.enterNew")
                         : GameStrings.format("cover.enterDay", max(1, store.daysTogether)))
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(WarmButtonStyle())
            .scaleEffect(breathe ? 1.025 : 1.0)
            .accessibilityIdentifier("coverEnterButton")
        } else {
            ZStack(alignment: .leading) {
                Capsule().fill(RoomTheme.paper.opacity(0.92))
                GeometryReader { bar in
                    Capsule()
                        .fill(RoomTheme.coral.opacity(0.35))
                        .frame(width: max(52, bar.size.width * shownProgress))
                }
                Text(GameStrings.format("cover.loading", Int(shownProgress * 100)))
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(RoomTheme.coralDeep)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 52)
            .overlay(Capsule().stroke(RoomTheme.wood.opacity(0.6), lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("coverLoadingBar")
        }
    }

    private func loadErrorCard(_ error: String) -> some View {
        VStack(spacing: 10) {
            Text(error)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(RoomTheme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(GameStrings.text("cover.retry")) {
                Task { await store.bootstrap() }
            }
            .font(.system(size: 16, weight: .heavy, design: .rounded))
            .frame(maxWidth: .infinity)
            .buttonStyle(WarmButtonStyle())
            .accessibilityIdentifier("coverRetryButton")
        }
        .padding(14)
        .background(RoomTheme.paper.opacity(0.96), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(RoomTheme.coral.opacity(0.6), lineWidth: 1.2))
    }

    /// Fill the screen, then slide the art vertically so Xiaoju and the diary sit between the title and the button.
    private func backgroundRect(in size: CGSize, focusTop: CGFloat, focusBottom: CGFloat) -> CGRect {
        let ratio: CGFloat = 2340.0 / 1081.0
        var w = size.width
        var h = w * ratio
        if h < size.height {
            h = size.height
            w = h / ratio
        }
        let centered = (focusTop + focusBottom) / 2 - (subjectTop + subjectBottom) / 2 * h
        let minY = size.height - h // never leave a gap at the bottom
        let y = min(0, max(minY, centered))
        return CGRect(x: (size.width - w) / 2, y: y, width: w, height: h)
    }
}

/// Short in-app privacy summary (full policy lives in PRIVACY.md on GitHub).
struct PrivacySummaryView: View {
    static let policyURL = URL(string: "https://github.com/xdgf558/cat-life-game-ios/blob/main/PRIVACY.md")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(1...4, id: \.self) { i in
                    PaperCard {
                        Text(GameStrings.text("privacy.p\(i)"))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(RoomTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Link(destination: Self.policyURL) {
                    HStack {
                        Text(GameStrings.text("privacy.fullPolicy"))
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .foregroundStyle(RoomTheme.coralDeep)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(RoomTheme.wood.opacity(0.55), lineWidth: 1))
                }
            }
            .padding(16)
        }
        .background(RoomTheme.cream.ignoresSafeArea())
        .navigationTitle(GameStrings.text("privacy.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
