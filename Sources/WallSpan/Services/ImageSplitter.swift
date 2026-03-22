import AppKit
import CoreGraphics
import ImageIO
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

    /// Returns the number of frames in a HEIC image (1 for static, 8+ for dynamic)
    static func frameCount(for imageURL: URL) -> Int {
        guard let src = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else { return 1 }
        return CGImageSourceGetCount(src)
    }

    /// Returns true if the image has dynamic solar metadata
    static func isDynamic(_ imageURL: URL) -> Bool {
        return SolarCalculator.extractSolarMetadata(from: imageURL) != nil
    }

    /// Returns the correct frame index for the current time using solar metadata.
    /// Falls back to frame 0 for non-dynamic images.
    static func currentFrameIndex(for imageURL: URL) -> Int {
        guard let metadata = SolarCalculator.extractSolarMetadata(from: imageURL) else { return 0 }
        return SolarCalculator.currentFrameIndex(for: metadata)
    }

    /// Splits a source image into portions for each monitor based on their arrangement.
    /// For dynamic HEIC wallpapers, picks the correct solar frame for the current time.
    static func splitImage(
        _ imageURL: URL,
        across monitors: [MonitorInfo],
        frameIndex: Int? = nil
    ) throws -> [Int: URL] {
        guard let src = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else {
            throw ImageSplitError.cannotLoadImage
        }

        let totalFrames = CGImageSourceGetCount(src)
        let idx: Int
        if let forced = frameIndex {
            idx = min(forced, totalFrames - 1)
        } else {
            idx = currentFrameIndex(for: imageURL)
        }

        guard let cgImage = CGImageSourceCreateImageAtIndex(src, idx, nil) else {
            throw ImageSplitError.cannotLoadImage
        }

        let imageW = CGFloat(cgImage.width)
        let imageH = CGFloat(cgImage.height)

        // Compute bounding rect of all screens (in screen points)
        let boundingRect = monitors.reduce(CGRect.null) { $0.union($1.frame) }
        let totalW = boundingRect.width
        let totalH = boundingRect.height

        // "Cover" scaling: scale so the image fully covers the combined area
        let scaleX = imageW / totalW
        let scaleY = imageH / totalH
        let coverScale = min(scaleX, scaleY)

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
            let monX = monitor.frame.origin.x - boundingRect.origin.x
            let monY = monitor.frame.origin.y - boundingRect.origin.y
            let monW = monitor.frame.width
            let monH = monitor.frame.height

            // Map to image pixel coordinates; flip Y (macOS bottom-left → CGImage top-left)
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
