import AppKit
import CoreGraphics
import UniformTypeIdentifiers

enum ImageSplitError: LocalizedError {
    case cannotLoadImage
    case cannotCreateCGImage
    case cannotCropImage
    case cannotWriteImage

    var errorDescription: String? {
        switch self {
        case .cannotLoadImage: return "Could not load the selected image."
        case .cannotCreateCGImage: return "Could not process the image."
        case .cannotCropImage: return "Could not crop the image for a monitor."
        case .cannotWriteImage: return "Could not save the cropped image."
        }
    }
}

struct ImageSplitter {
    /// Splits a source image into portions for each monitor based on their arrangement.
    /// Uses "cover" scaling: the image fills the entire combined monitor area while maintaining
    /// aspect ratio, then each monitor's portion is cropped from that.
    static func splitImage(_ imageURL: URL, across monitors: [MonitorInfo]) throws -> [Int: URL] {
        guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw ImageSplitError.cannotLoadImage
        }

        let imageW = CGFloat(cgImage.width)
        let imageH = CGFloat(cgImage.height)

        // Compute bounding rect of all screens (in screen points)
        let boundingRect = monitors.reduce(CGRect.null) { $0.union($1.frame) }
        let totalW = boundingRect.width
        let totalH = boundingRect.height

        // "Cover" scaling: find how the image maps onto the total monitor area
        // Scale so the image fully covers the combined area (no letterboxing)
        let scaleX = imageW / totalW
        let scaleY = imageH / totalH
        let coverScale = min(scaleX, scaleY)  // min = cover (image overflows in one dimension)

        // The visible portion of the image (centered) in image pixel coordinates
        let visibleW = totalW * coverScale
        let visibleH = totalH * coverScale
        let offsetX = (imageW - visibleW) / 2.0
        let offsetY = (imageH - visibleH) / 2.0

        // Use a unique subdirectory per apply so the wallpaper agent doesn't cache stale paths
        let baseDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WallSpan/crops", isDirectory: true)
        let cropDir = baseDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: cropDir, withIntermediateDirectories: true)

        // Clean up old crop directories
        if let old = try? FileManager.default.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: nil) {
            for dir in old where dir.lastPathComponent != cropDir.lastPathComponent {
                try? FileManager.default.removeItem(at: dir)
            }
        }

        var results: [Int: URL] = [:]

        for monitor in monitors {
            // Monitor position relative to bounding rect (in screen points)
            let monX = monitor.frame.origin.x - boundingRect.origin.x
            let monY = monitor.frame.origin.y - boundingRect.origin.y
            let monW = monitor.frame.width
            let monH = monitor.frame.height

            // Map to image pixel coordinates within the visible area
            // Flip Y: macOS screen origin is bottom-left, CGImage origin is top-left
            let cropX = offsetX + monX * coverScale
            let cropY = offsetY + (totalH - monY - monH) * coverScale
            let cropW = monW * coverScale
            let cropH = monH * coverScale

            let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
                .integral
                .intersection(CGRect(x: 0, y: 0, width: imageW, height: imageH))

            guard !cropRect.isEmpty, let cropped = cgImage.cropping(to: cropRect) else {
                throw ImageSplitError.cannotCropImage
            }

            let fileURL = cropDir.appendingPathComponent("monitor_\(monitor.id).png")

            guard let dest = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw ImageSplitError.cannotWriteImage
            }
            CGImageDestinationAddImage(dest, cropped, nil)
            guard CGImageDestinationFinalize(dest) else {
                throw ImageSplitError.cannotWriteImage
            }

            results[monitor.id] = fileURL
        }

        return results
    }
}
