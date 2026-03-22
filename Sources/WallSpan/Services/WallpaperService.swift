import AppKit
import Foundation

enum WallpaperError: LocalizedError {
    case noScreenFound
    case setFailed(String)

    var errorDescription: String? {
        switch self {
        case .noScreenFound: return "No matching screen found."
        case .setFailed(let msg): return "Failed to set wallpaper: \(msg)"
        }
    }
}

struct WallpaperService {

    private static let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
        .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
        .allowClipping: true
    ]

    /// Sets the same image on all monitors.
    static func setSameOnAll(imageURL: URL) throws {
        for screen in NSScreen.screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(imageURL, for: screen, options: options)
            } catch {
                throw WallpaperError.setFailed("\(screen.localizedName): \(error.localizedDescription)")
            }
        }
    }

    /// Splits the image across monitors based on their arrangement, then sets each portion per-display.
    static func setSpanned(imageURL: URL, monitors: [MonitorInfo]) throws {
        let croppedURLs = try ImageSplitter.splitImage(imageURL, across: monitors)

        for monitor in monitors {
            guard let croppedURL = croppedURLs[monitor.id] else {
                throw WallpaperError.noScreenFound
            }
            do {
                try NSWorkspace.shared.setDesktopImageURL(croppedURL, for: monitor.screen, options: options)
            } catch {
                throw WallpaperError.setFailed("\(monitor.localizedName): \(error.localizedDescription)")
            }
        }
    }
}
