import SwiftUI
import AppKit

struct WallpaperGallery: View {
    let items: [WallpaperItem]
    @Binding var selectedItem: WallpaperItem?
    let onAddExternal: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(WallpaperItem.Category.allCases, id: \.self) { category in
                let categoryItems = items.filter { $0.category == category }
                if !categoryItems.isEmpty || category == .external {
                    Section {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(categoryItems) { item in
                                WallpaperTile(
                                    item: item,
                                    isSelected: selectedItem?.id == item.id
                                )
                                .onTapGesture {
                                    selectedItem = item
                                }
                            }

                            if category == .external {
                                addButton
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Text(category.rawValue)
                                .font(.headline)
                            if category == .current {
                                Text("— active on your displays")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, category == .current ? 0 : 6)
                    }
                }
            }

        }
    }

    private var addButton: some View {
        Button(action: onAddExternal) {
            VStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.title2)
                Text("Add Image")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundColor(.secondary.opacity(0.5))
            )
        }
        .buttonStyle(.plain)
    }
}

struct WallpaperTile: View {
    let item: WallpaperItem
    let isSelected: Bool

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 100)

                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 100)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
            .shadow(color: isSelected ? Color.accentColor.opacity(0.4) : .clear, radius: 5)

            Text(item.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
        }
        .task(id: item.id) {
            thumbnail = await generateThumbnail(for: item.thumbnailURL)
        }
    }

    /// Generate a crisp thumbnail respecting Retina (2x) displays
    private func generateThumbnail(for url: URL) async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let image = NSImage(contentsOf: url) else {
                    continuation.resume(returning: nil)
                    return
                }

                // Target size in points; render at 2x for Retina
                let pointSize = NSSize(width: 320, height: 200)
                let pixelSize = NSSize(width: pointSize.width * 2, height: pointSize.height * 2)

                guard let bitmapRep = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: Int(pixelSize.width),
                    pixelsHigh: Int(pixelSize.height),
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .deviceRGB,
                    bytesPerRow: 0,
                    bitsPerPixel: 0
                ) else {
                    continuation.resume(returning: image)
                    return
                }

                bitmapRep.size = pointSize
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)

                // Fill-crop: scale to fill, center crop
                let imageAspect = image.size.width / image.size.height
                let thumbAspect = pointSize.width / pointSize.height
                var drawRect: NSRect

                if imageAspect > thumbAspect {
                    // Image is wider — crop sides
                    let drawWidth = pointSize.height * imageAspect
                    drawRect = NSRect(
                        x: (pointSize.width - drawWidth) / 2,
                        y: 0,
                        width: drawWidth,
                        height: pointSize.height
                    )
                } else {
                    // Image is taller — crop top/bottom
                    let drawHeight = pointSize.width / imageAspect
                    drawRect = NSRect(
                        x: 0,
                        y: (pointSize.height - drawHeight) / 2,
                        width: pointSize.width,
                        height: drawHeight
                    )
                }

                image.draw(
                    in: drawRect,
                    from: NSRect(origin: .zero, size: image.size),
                    operation: .copy,
                    fraction: 1.0
                )

                NSGraphicsContext.restoreGraphicsState()

                let thumb = NSImage(size: pointSize)
                thumb.addRepresentation(bitmapRep)
                continuation.resume(returning: thumb)
            }
        }
    }
}
