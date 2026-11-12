import SwiftUI

struct SaveTransferUpdateButton: View {
    @Environment(\.openURL) private var openURL
    @State private var cannotOpen = false

    private var updateURL: URL {
        #if os(macOS)
        URL(string: "https://github.com/xdgf558/cat-life-game-ios/releases")!
        #else
        URL(string: "itms-beta://")!
        #endif
    }
    private var updateTitleKey: String {
        #if os(macOS)
        "mac.update.project"
        #else
        "saveTransfer.updateTestFlight"
        #endif
    }
    private var unavailableTitleKey: String {
        #if os(macOS)
        "mac.update.unavailable"
        #else
        "saveTransfer.updateUnavailable"
        #endif
    }
    private var helpTitleKey: String {
        #if os(macOS)
        "mac.update.retry"
        #else
        "saveTransfer.updateHelp"
        #endif
    }
    var body: some View {
        Button {
            openURL(updateURL) { accepted in cannotOpen = !accepted }
        } label: {
            Label(GameStrings.text(updateTitleKey), systemImage: "arrow.down.app.fill")
                .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .foregroundStyle(.white)
                .background(RoomTheme.gold, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.4), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .alert(GameStrings.text(unavailableTitleKey), isPresented: $cannotOpen) {
            Button(GameStrings.text(helpTitleKey)) {
                #if os(macOS)
                openURL(updateURL)
                #else
                openURL(URL(string: "https://testflight.apple.com/")!)
                #endif
            }
            Button(GameStrings.text("common.close"), role: .cancel) {}
        } message: {
            #if os(macOS)
            Text(GameStrings.text("mac.update.manual"))
            #else
            Text(GameStrings.text("saveTransfer.updateManual"))
            #endif
        }
    }
}
