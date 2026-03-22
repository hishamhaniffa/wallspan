import AppKit
import UniformTypeIdentifiers

struct WallpaperItem: Identifiable, Hashable {
    let id: String
    let url: URL           // full-res image for applying
    let thumbnailURL: URL  // for preview in the grid
    let name: String
    let category: Category

    enum Category: String, CaseIterable {
        case current = "Current"
        case system = "System"
        case external = "External"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: WallpaperItem, rhs: WallpaperItem) -> Bool {
        lhs.id == rhs.id
    }
}

final class WallpaperCatalog: ObservableObject {
    @Published var items: [WallpaperItem] = []

    private static let systemDir = URL(fileURLWithPath: "/System/Library/Desktop Pictures")
    private static let wallpapersDir = URL(fileURLWithPath: "/System/Library/Desktop Pictures/.wallpapers")
    private static let thumbnailDir = URL(fileURLWithPath: "/System/Library/Desktop Pictures/.thumbnails")
    private static let userAssetDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.mobileAssetDesktop")
    }()
    private static let wallpaperStoreIndex: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }()

    func reload() {
        var all: [WallpaperItem] = []
        var seenPaths = Set<String>()

        // 1. Current wallpapers per screen
        for (index, screen) in NSScreen.screens.enumerated() {
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { continue }
            guard seenPaths.insert(url.path).inserted else { continue }
            all.append(WallpaperItem(
                id: "current-\(index)-\(url.path)",
                url: url,
                thumbnailURL: url,
                name: url.deletingPathExtension().lastPathComponent,
                category: .current
            ))
        }

        // 2. Also check the wallpaper store plist for the configured wallpaper
        let storeItems = loadFromWallpaperStore()
        for item in storeItems {
            if seenPaths.insert(item.url.path).inserted {
                all.append(item)
            }
        }

        // 3. System wallpapers
        let systemItems = loadSystemWallpapers()
        all.append(contentsOf: systemItems)

        items = all
    }

    func addExternal(_ url: URL) {
        let item = WallpaperItem(
            id: "external-\(url.path)",
            url: url,
            thumbnailURL: url,
            name: url.deletingPathExtension().lastPathComponent,
            category: .external
        )
        if !items.contains(where: { $0.url == url }) {
            items.insert(item, at: 0)
        }
    }

    // MARK: - Wallpaper Store (Ventura+ user selections)

    private func loadFromWallpaperStore() -> [WallpaperItem] {
        guard let dict = NSDictionary(contentsOf: Self.wallpaperStoreIndex) as? [String: Any] else {
            return []
        }
        var results: [WallpaperItem] = []
        extractWallpaperFiles(from: dict, into: &results)
        return results
    }

    private func extractWallpaperFiles(from dict: [String: Any], into results: inout [WallpaperItem]) {
        // Recursively find all "Files" arrays containing "relative" URL strings
        for (key, value) in dict {
            if key == "Files", let files = value as? [[String: Any]] {
                for file in files {
                    if let relativePath = file["relative"] as? String,
                       let url = URL(string: relativePath),
                       FileManager.default.fileExists(atPath: url.path) {
                        let name = url.deletingPathExtension().lastPathComponent
                        let item = WallpaperItem(
                            id: "current-store-\(url.path)",
                            url: url,
                            thumbnailURL: url,
                            name: name,
                            category: .current
                        )
                        if !results.contains(where: { $0.url == url }) {
                            results.append(item)
                        }
                    }
                }
            } else if let nested = value as? [String: Any] {
                extractWallpaperFiles(from: nested, into: &results)
            } else if let array = value as? [[String: Any]] {
                for element in array {
                    extractWallpaperFiles(from: element, into: &results)
                }
            }
        }
    }

    // MARK: - System Wallpapers

    private func loadSystemWallpapers() -> [WallpaperItem] {
        let fm = FileManager.default
        var results: [WallpaperItem] = []
        var addedNames = Set<String>()

        // Priority 1: .wallpapers/ bundles (Sequoia Sunrise, Sonoma, etc.) — high res HEIC/PNG
        if let subdirs = try? fm.contentsOfDirectory(
            at: Self.wallpapersDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for subdir in subdirs {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: subdir.path, isDirectory: &isDir), isDir.boolValue else { continue }
                let name = subdir.lastPathComponent

                // Find the best image: prefer .heic, then .png, skip .mov
                let bundleFiles = (try? fm.contentsOfDirectory(
                    at: subdir,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )) ?? []

                let heic = bundleFiles.first(where: {
                    $0.pathExtension.lowercased() == "heic" && !$0.lastPathComponent.contains("Thumbnail")
                })
                let thumbnail2x = bundleFiles.first(where: {
                    $0.lastPathComponent.contains("Thumbnail@2x")
                })
                let thumbnail = bundleFiles.first(where: {
                    $0.lastPathComponent.contains("Thumbnail") && !$0.lastPathComponent.contains("@2x")
                })

                guard let fullRes = heic else { continue }
                let thumbURL = thumbnail2x ?? thumbnail ?? fullRes

                addedNames.insert(name)
                results.append(WallpaperItem(
                    id: "system-wallpapers-\(name)",
                    url: fullRes,
                    thumbnailURL: thumbURL,
                    name: name,
                    category: .system
                ))
            }
        }

        // Priority 2: Full-res loose .heic/.jpg/.png in root (Sonoma.heic, iMac Blue.heic, etc.)
        if let contents = try? fm.contentsOfDirectory(
            at: Self.systemDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for fileURL in contents where isImageFile(fileURL) {
                let name = fileURL.deletingPathExtension().lastPathComponent
                guard !addedNames.contains(name) else { continue }
                addedNames.insert(name)
                results.append(WallpaperItem(
                    id: "system-root-\(name)",
                    url: fileURL,
                    thumbnailURL: fileURL,
                    name: name,
                    category: .system
                ))
            }
        }

        // Priority 3: Downloaded mobile assets (~/Library/Application Support/com.apple.mobileAssetDesktop/)
        if let contents = try? fm.contentsOfDirectory(
            at: Self.userAssetDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for fileURL in contents where isImageFile(fileURL) {
                let name = fileURL.deletingPathExtension().lastPathComponent
                guard !addedNames.contains(name) else { continue }
                addedNames.insert(name)
                results.append(WallpaperItem(
                    id: "system-asset-\(name)",
                    url: fileURL,
                    thumbnailURL: fileURL,
                    name: name,
                    category: .system
                ))
            }
        }

        // Priority 4: .madesktop plists — only for items not yet found
        if let contents = try? fm.contentsOfDirectory(
            at: Self.systemDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for fileURL in contents where fileURL.pathExtension == "madesktop" {
                guard let plist = NSDictionary(contentsOf: fileURL) as? [String: Any],
                      let thumbnailPath = plist["thumbnailPath"] as? String else { continue }

                let name = fileURL.deletingPathExtension().lastPathComponent
                guard !addedNames.contains(name) else { continue }
                addedNames.insert(name)

                let thumbURL = URL(fileURLWithPath: thumbnailPath)
                guard fm.fileExists(atPath: thumbURL.path) else { continue }

                // Only include if full-res is actually downloaded — thumbnails are too small to use
                let fullResURL = Self.userAssetDir.appendingPathComponent("\(name).heic")
                guard fm.fileExists(atPath: fullResURL.path) else { continue }

                results.append(WallpaperItem(
                    id: "system-madesktop-\(name)",
                    url: fullResURL,
                    thumbnailURL: thumbURL,
                    name: name,
                    category: .system
                ))
            }
        }

        results.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return results
    }

    private func isImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["heic", "jpg", "jpeg", "png", "tiff", "webp"].contains(ext)
    }
}
