import SwiftUI
import AppKit

@main
struct WallSpanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Force the app to become a regular foreground app with dock icon
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Bring the window to front
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
