#if os(macOS)
import AppKit
import SwiftUI

@main
struct CatLifeMacApp: App {
    @NSApplicationDelegateAdaptor(MacApplicationDelegate.self) private var delegate
    var body: some Scene {
        Window("打工养猫日记", id: "main") {
            MacDesktopRoot(delegate: delegate).frame(minWidth: 1280, minHeight: 720)
        }
        .defaultSize(width: 1440, height: 900)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button(GameStrings.text("mac.page.settings")) { NotificationCenter.default.post(name: .macOpenSettings69, object: nil) }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
extension Notification.Name { static let macOpenSettings69 = Notification.Name("CatLifeMac.openSettings") }
@MainActor
final class MacApplicationDelegate: NSObject, NSApplicationDelegate {
    var requestQuit: (() -> NSApplication.TerminateReply)?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { requestQuit?() ?? .terminateNow }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#endif
