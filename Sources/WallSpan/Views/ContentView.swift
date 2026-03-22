import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var screenService = ScreenService()
    @StateObject private var catalog = WallpaperCatalog()
    @State private var selectedItem: WallpaperItem?
    @State private var wallpaperMode: WallpaperMode = .sameOnAll
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var statusMessage: String?
    @State private var dynamicTimer: Timer?
    @State private var lastFrameIndex: Int = -1

    var body: some View {
        VStack(spacing: 0) {
            // Top: Monitor arrangement
            GroupBox("Monitors") {
                MonitorPreview(
                    monitors: screenService.monitors,
                    boundingRect: screenService.boundingRect
                )
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            Divider()

            // Middle: Wallpaper gallery (scrollable)
            ScrollView {
                WallpaperGallery(
                    items: catalog.items,
                    selectedItem: $selectedItem,
                    onAddExternal: pickImage
                )
                .padding()
            }

            Divider()

            // Bottom: Controls
            HStack(spacing: 16) {
                // Selected image info
                if let item = selectedItem {
                    HStack(spacing: 8) {
                        if let nsImage = NSImage(contentsOf: item.thumbnailURL) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 48, height: 32)
                                .clipped()
                                .cornerRadius(4)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                                .font(.caption.bold())
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Text(item.category.rawValue)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                if dynamicTimer != nil {
                                    Text("· Dynamic")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                } else {
                    Text("Select a wallpaper")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Status message
                if let status = statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.green)
                        .transition(.opacity)
                }

                // Mode picker
                Picker("", selection: $wallpaperMode) {
                    ForEach(WallpaperMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)

                // Apply
                Button("Apply") {
                    applyWallpaper()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedItem == nil)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
        }
        .frame(minWidth: 640, minHeight: 520)
        .onAppear {
            catalog.reload()
        }
        .onDisappear {
            stopDynamicTimer()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a wallpaper image"
        if panel.runModal() == .OK, let url = panel.url {
            catalog.addExternal(url)
            selectedItem = catalog.items.first(where: { $0.url == url })
        }
    }

    private func applyWallpaper() {
        guard let item = selectedItem else { return }

        // Stop any existing dynamic timer
        stopDynamicTimer()

        do {
            switch wallpaperMode {
            case .sameOnAll:
                try WallpaperService.setSameOnAll(imageURL: item.url)
            case .spanned:
                try WallpaperService.setSpanned(imageURL: item.url, monitors: screenService.monitors)

                // If this is a dynamic wallpaper, start a timer to update the frame
                let frames = ImageSplitter.frameCount(for: item.url)
                if frames > 1 {
                    startDynamicTimer(imageURL: item.url, totalFrames: frames)
                }
            }

            withAnimation {
                statusMessage = dynamicTimer != nil ? "Applied! (dynamic — updates with time)" : "Applied!"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation { statusMessage = nil }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                catalog.reload()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - Dynamic wallpaper timer

    private func startDynamicTimer(imageURL: URL, totalFrames: Int) {
        lastFrameIndex = ImageSplitter.currentFrameIndex(for: imageURL)

        // Check every 15 minutes if the solar frame needs to change
        dynamicTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { _ in
            let newIndex = ImageSplitter.currentFrameIndex(for: imageURL)
            guard newIndex != lastFrameIndex else { return }
            lastFrameIndex = newIndex

            do {
                try WallpaperService.setSpanned(
                    imageURL: imageURL,
                    monitors: screenService.monitors
                )
            } catch {
                // Silently fail on timer updates
            }
        }
    }

    private func stopDynamicTimer() {
        dynamicTimer?.invalidate()
        dynamicTimer = nil
    }
}
