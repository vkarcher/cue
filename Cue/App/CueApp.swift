import SwiftUI

@main
struct CueApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var status = NetworkServiceStatus()
    @State private var television = TelevisionControl()

    var body: some Scene {
        Window("Cue", id: "main") {
            MainWindow(status: status, television: television)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuContent(status: status) {
                delegate.allowsTermination = true
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(nsImage: menuBarImage)
                // The daemon evaluates every 5 seconds, so a 2 second refresh is enough to follow it.
                .polling(every: .seconds(2)) { status.refresh() }
                .task { await followGeForceNow(NSWorkspace.didLaunchApplicationNotification) { television.gameStarted() } }
                .task { await followGeForceNow(NSWorkspace.didTerminateApplicationNotification) { await television.gameEnded() } }
        }
    }

    /// The cross of the app icon alone: Wi-Fi waves in the menu bar read as the Mac's own network status.
    /// A dot in the corner while in game, dimmed when paused or not installed.
    private var menuBarImage: NSImage {
        let isActive = status.isInstalled && status.isEnabled
        let mark = Canvas { context, size in
            let arm = CGSize(width: 15, height: 5.2)
            let center = CGPoint(x: 8, y: size.height / 2)
            var cross = Path(roundedRect: CGRect(x: center.x - arm.width / 2, y: center.y - arm.height / 2, width: arm.width, height: arm.height), cornerRadius: 1.3)
            cross.addRoundedRect(in: CGRect(x: center.x - arm.height / 2, y: center.y - arm.width / 2, width: arm.height, height: arm.width), cornerSize: CGSize(width: 1.3, height: 1.3))
            context.fill(cross, with: .color(.black.opacity(isActive ? 1 : 0.35)))
            // The hollow center tells a controller cross from a plus sign.
            context.blendMode = .destinationOut
            context.fill(Path(ellipseIn: CGRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3)), with: .color(.black))
            context.blendMode = .normal
            if status.isSessionActive {
                context.fill(Path(ellipseIn: CGRect(x: 13, y: center.y - 8, width: 5, height: 5)), with: .color(.black))
            }
        }
        let renderer = ImageRenderer(content: mark.frame(width: 18, height: 16))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
    }

    /// Closing the GeForce NOW window quits its main process, so termination means the session is over.
    private func followGeForceNow(_ event: Notification.Name, perform action: @escaping () async -> Void) async {
        for await notification in NSWorkspace.shared.notificationCenter.notifications(named: event) {
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard application?.bundleIdentifier == "com.nvidia.gfnpc.mall", status.isEnabled else { continue }
            television.record(event == NSWorkspace.didLaunchApplicationNotification
                ? String(localized: "GeForce NOW started")
                : String(localized: "GeForce NOW quit"))
            await action()
        }
    }
}

/// Quitting from the window or the Dock only closes the window; the menu bar item keeps running.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var allowsTermination = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Logout, restart and shutdown carry a quit reason and must never be refused.
        let quitReason = NSAppleEventManager.shared().currentAppleEvent?.attributeDescriptor(forKeyword: kAEQuitReason)
        if allowsTermination || quitReason != nil { return .terminateNow }
        sender.windows.filter { $0.isVisible && $0.canBecomeMain }.forEach { $0.close() }
        return .terminateCancel
    }
}

struct MenuContent: View {
    let status: NetworkServiceStatus
    let quit: () -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Automatic activation", isOn: status.isEnabledBinding)
            .disabled(!status.isInstalled)
        Divider()
        Button("Open Cue") {
            NSApplication.shared.setActivationPolicy(.regular)
            openWindow(id: "main")
            // The cooperative activate() is refused while some apps (Warp) keep focus, so the window is also raised itself.
            DispatchQueue.main.async {
                NSApplication.shared.activate(ignoringOtherApps: true)
                let window = NSApplication.shared.windows.first { $0.canBecomeMain && $0.isVisible }
                window?.makeKeyAndOrderFront(nil)
                window?.orderFrontRegardless()
            }
        }
        Button("Quit", action: quit)
            .keyboardShortcut("q")
    }
}
