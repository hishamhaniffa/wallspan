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
                            Text(item.category.rawValue)
                                .font(.caption2)
                                .foregroundColor(.secondary)
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

        do {
            switch wallpaperMode {
            case .sameOnAll:
                try WallpaperService.setSameOnAll(imageURL: item.url)
            case .spanned:
                try WallpaperService.setSpanned(imageURL: item.url, monitors: screenService.monitors)
            }
            withAnimation {
                statusMessage = "Applied!"
            }
            // Clear status after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    statusMessage = nil
                }
            }
            // Refresh catalog to update current wallpapers
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                catalog.reload()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
