import AppKit
import CoreGraphics

struct MonitorInfo: Identifiable {
    let id: Int
    let displayUUID: String
    let frame: CGRect
    let localizedName: String
    let isMain: Bool
    let backingScaleFactor: CGFloat
    let screen: NSScreen

    init(screen: NSScreen) {
        let deviceID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        self.id = Int(deviceID)
        self.frame = screen.frame
        self.localizedName = screen.localizedName
        self.isMain = screen == NSScreen.main
        self.backingScaleFactor = screen.backingScaleFactor
        self.screen = screen

        // Get the UUID that macOS uses in the wallpaper store plist
        if let cfUUID = CGDisplayCreateUUIDFromDisplayID(deviceID)?.takeUnretainedValue() {
            self.displayUUID = CFUUIDCreateString(nil, cfUUID) as String
        } else {
            self.displayUUID = ""
        }
    }
}
