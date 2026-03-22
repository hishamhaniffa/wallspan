import AppKit
import Combine

final class ScreenService: ObservableObject {
    @Published var monitors: [MonitorInfo] = []
    @Published var boundingRect: CGRect = .zero

    private var cancellable: AnyCancellable?

    init() {
        refresh()
        cancellable = NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        monitors = NSScreen.screens.map { MonitorInfo(screen: $0) }
        boundingRect = monitors.reduce(CGRect.null) { $0.union($1.frame) }
    }
}
