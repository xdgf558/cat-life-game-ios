import SwiftUI
import CatGameCore

struct DiaryRootView: View {
    @Bindable var store: DiaryAppStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if store.isLoaded {
                Group {
                    switch store.activeScreen {
                    case .home:
                        HomeView(store: store)
                    case .workshop:
                        WorkshopView(store: store)
                    }
                }
                .transition(.opacity)
            } else if let error = store.loadError {
                VStack(spacing: 18) {
                    Image("cat_hungry")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                    Text(GameStrings.text("app.title"))
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(RoomTheme.ink)
                    Text(error)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(RoomTheme.secondary)
                        .multilineTextAlignment(.center)
                    Button(GameStrings.text("common.confirm")) {
                        Task { await store.bootstrap() }
                    }
                    .buttonStyle(WarmButtonStyle())
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoomTheme.cream.ignoresSafeArea())
            } else {
                VStack(spacing: 14) {
                    Image("cat_idle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 144, height: 144)
                        .shadow(color: RoomTheme.ink.opacity(0.14), radius: 10, y: 6)
                    Text(GameStrings.text("app.title"))
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(RoomTheme.ink)
                    ProgressView()
                        .tint(RoomTheme.coral)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoomTheme.cream.ignoresSafeArea())
            }

            // Unsaved progress warning banner with manual retry
            if store.isLoaded, let saveError = store.saveError {
                VStack {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(RoomTheme.coralDeep)
                        Text(saveError)
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(RoomTheme.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button {
                            store.retrySaveNow()
                        } label: {
                            if store.isSaving {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            } else {
                                Text(GameStrings.text("save.retry"))
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                            }
                        }
                        .disabled(store.isSaving)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(RoomTheme.coral, in: Capsule())
                        .accessibilityIdentifier("saveRetryButton")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoomTheme.rewardPaper.opacity(0.98), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(RoomTheme.coral.opacity(0.7), lineWidth: 1.4))
                    .shadow(color: RoomTheme.ink.opacity(0.16), radius: 8, y: 4)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("saveErrorBanner")

                    Spacer(minLength: 0)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(18)
            }

            // Warm hand-crafted Toast strip
            if let toast = store.notices.toast {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(RoomTheme.coral)
                        Text(toast)
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundStyle(RoomTheme.ink)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(WarmGlassBackground(cornerRadius: 20, tintOpacity: 0.90))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 112)
                }
                .allowsHitTesting(false)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(19)
            }

            // Story, Keepsake & Monetization Overlays (highest priority first)
            if store.showingAdoptionModal {
                AdoptionOverlayView {
                    store.dismissAdoptionModal()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(24)
            } else if let arrival = store.arrivalModal {
                OutingArrivalOverlayView(arrival: arrival) {
                    store.dismissArrivalModal()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(23)
            } else if let story = store.currentStoryModal {
                CustomerStoryOverlayView(story: story) {
                    store.dismissCurrentStoryModal()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(22)
            } else if let milestone = store.milestoneModal {
                MilestoneOverlayView(milestone: milestone, daysTogether: store.daysTogether) {
                    store.dismissMilestoneModal()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(21)
            } else if let photoID = store.currentPhotoModalID {
                PhotoRevealOverlayView(
                    photoID: photoID,
                    capturedAt: store.state.diary.photoDates[photoID],
                    onKeep: { store.dismissCurrentPhotoModal() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(20)
            } else if let levelUp = store.currentLevelUpModal {
                LevelUpOverlayView(item: levelUp) {
                    store.dismissCurrentLevelUpModal()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(20)
            } else if let offer = store.activeAdOffer {
                AdOfferOverlayView(
                    offer: offer,
                    currentCoins: store.state.coins,
                    onWatch: { store.watchActiveAd() },
                    onRefuse: { store.refuseActiveAd() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(25)
            }

            if let slot = store.playingMockAdSlot {
                MockAdPlaybackOverlayView(slot: slot) { result in
                    store.finishMockAdPlayback(with: result)
                }
                .transition(.opacity)
                .zIndex(30)
            }
        }
        .animation(.easeOut(duration: 0.22), value: store.activeScreen)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: store.saveError)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.notices.toast)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: store.currentPhotoModalID)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: store.activeAdOffer != nil)
        .animation(.easeOut(duration: 0.2), value: store.playingMockAdSlot != nil)
        .sheet(item: $store.activeSheet) { sheet in
            switch sheet {
            case .shop:
                ShopSheetView(store: store)
            case .diary:
                DiarySheetView(store: store)
            case .settings:
                SettingsSheetView(store: store)
            case .orderDetail(let order):
                OrderDetailSheetView(store: store, order: order)
            case .basket:
                BasketSheetView(store: store)
            }
        }
        .task {
            await store.bootstrap()
        }
        .onChange(of: scenePhase) { _, phase in
            store.setForeground(phase == .active)
        }
    }
}
