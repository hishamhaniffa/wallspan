import SwiftUI

struct MonitorPreview: View {
    let monitors: [MonitorInfo]
    let boundingRect: CGRect

    var body: some View {
        GeometryReader { geo in
            let scale = computeScale(viewSize: geo.size)

            ZStack {
                ForEach(monitors) { monitor in
                    let rect = monitorRect(monitor, scale: scale, viewSize: geo.size)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(monitor.isMain ? Color.accentColor : Color.secondary, lineWidth: monitor.isMain ? 2.5 : 1)
                        )
                        .overlay(
                            VStack(spacing: 2) {
                                Text(monitor.localizedName)
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                Text("\(Int(monitor.frame.width))×\(Int(monitor.frame.height))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                if monitor.isMain {
                                    Text("Main")
                                        .font(.caption2)
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(4)
                        )
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .frame(minHeight: 160)
    }

    private func computeScale(viewSize: CGSize) -> CGFloat {
        guard boundingRect.width > 0, boundingRect.height > 0 else { return 1 }
        let pad: CGFloat = 20
        return min(
            (viewSize.width - pad * 2) / boundingRect.width,
            (viewSize.height - pad * 2) / boundingRect.height
        )
    }

    private func monitorRect(_ monitor: MonitorInfo, scale: CGFloat, viewSize: CGSize) -> CGRect {
        // Position relative to bounding rect origin
        let relX = (monitor.frame.origin.x - boundingRect.origin.x) * scale
        // Flip Y: macOS bottom-left origin → SwiftUI top-left origin
        let relY = (boundingRect.maxY - monitor.frame.maxY) * scale

        let totalW = boundingRect.width * scale
        let totalH = boundingRect.height * scale

        // Center in view
        let offsetX = (viewSize.width - totalW) / 2
        let offsetY = (viewSize.height - totalH) / 2

        return CGRect(
            x: relX + offsetX,
            y: relY + offsetY,
            width: monitor.frame.width * scale,
            height: monitor.frame.height * scale
        )
    }
}
