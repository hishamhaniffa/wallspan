import Foundation
import CoreLocation
import ImageIO

/// Extracts solar metadata from dynamic HEIC wallpapers and calculates
/// which frame to display based on the current sun position.
struct SolarCalculator {

    struct SolarEntry {
        let altitude: Double  // sun altitude in degrees
        let azimuth: Double   // sun azimuth in degrees
        let frameIndex: Int
    }

    struct SolarMetadata {
        let entries: [SolarEntry]
        let lightFrame: Int
        let darkFrame: Int
    }

    // MARK: - Extract metadata from HEIC

    /// Reads the apple_desktop:solar XMP metadata from a HEIC file.
    /// Returns nil for non-dynamic images.
    static func extractSolarMetadata(from imageURL: URL) -> SolarMetadata? {
        guard let data = try? Data(contentsOf: imageURL) else { return nil }

        // Find XMP block
        guard let xmpStart = data.range(of: Data("<x:xmpmeta".utf8)),
              let xmpEnd = data.range(of: Data("</x:xmpmeta>".utf8)) else { return nil }

        let xmpData = data[xmpStart.lowerBound..<xmpEnd.upperBound]
        guard let xmp = String(data: xmpData, encoding: .utf8) else { return nil }

        // Extract base64-encoded solar plist
        guard let match = xmp.range(of: #"apple_desktop:solar="([^"]*)""#, options: .regularExpression),
              let b64Start = xmp[match].range(of: "\""),
              let b64End = xmp[match].range(of: "\"", options: .backwards) else { return nil }

        let b64 = String(xmp[xmp.index(after: b64Start.lowerBound)..<b64End.lowerBound])
        guard let decoded = Data(base64Encoded: b64),
              let plist = try? PropertyListSerialization.propertyList(from: decoded, format: nil) as? [String: Any] else {
            return nil
        }

        // Parse appearance info
        var lightFrame = 0, darkFrame = 1
        if let ap = plist["ap"] as? [String: Any] {
            lightFrame = ap["l"] as? Int ?? 0
            darkFrame = ap["d"] as? Int ?? 1
        }

        // Parse solar index entries
        guard let si = plist["si"] as? [[String: Any]] else { return nil }
        let entries = si.compactMap { entry -> SolarEntry? in
            guard let a = entry["a"] as? Double,
                  let z = entry["z"] as? Double,
                  let i = entry["i"] as? Int else { return nil }
            return SolarEntry(altitude: a, azimuth: z, frameIndex: i)
        }.sorted { $0.azimuth < $1.azimuth }

        guard !entries.isEmpty else { return nil }
        return SolarMetadata(entries: entries, lightFrame: lightFrame, darkFrame: darkFrame)
    }

    // MARK: - Sun position calculation

    /// Calculate the sun's altitude and azimuth for a given location and time.
    static func sunPosition(latitude: Double, longitude: Double, date: Date) -> (altitude: Double, azimuth: Double) {
        let calendar = Calendar.current
        let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        let tz = Double(calendar.timeZone.secondsFromGMT(for: date)) / 3600.0
        let hour = Double(calendar.component(.hour, from: date))
            + Double(calendar.component(.minute, from: date)) / 60.0
            + Double(calendar.component(.second, from: date)) / 3600.0

        // Solar declination
        let decl = 23.45 * sin((360.0 / 365.0 * (284.0 + dayOfYear)) * .pi / 180.0)

        // Equation of time
        let b = (360.0 / 365.0 * (dayOfYear - 81.0)) * .pi / 180.0
        let eot = 9.87 * sin(2 * b) - 7.53 * cos(b) - 1.5 * sin(b)

        // Local solar time
        let lstm = 15.0 * tz
        let tc = 4.0 * (longitude - lstm) + eot
        let lst = hour + tc / 60.0
        let hra = 15.0 * (lst - 12.0)

        let latRad = latitude * .pi / 180.0
        let declRad = decl * .pi / 180.0
        let hraRad = hra * .pi / 180.0

        // Altitude
        let sinAlt = sin(latRad) * sin(declRad) + cos(latRad) * cos(declRad) * cos(hraRad)
        let altitude = asin(sinAlt) * 180.0 / .pi

        // Azimuth
        let cosAz = (sin(declRad) - sin(altitude * .pi / 180.0) * sin(latRad))
            / (cos(altitude * .pi / 180.0) * cos(latRad))
        var azimuth = acos(max(-1, min(1, cosAz))) * 180.0 / .pi
        if hra > 0 { azimuth = 360.0 - azimuth }

        return (altitude, azimuth)
    }

    // MARK: - Frame selection

    /// Returns the frame index to display for the given solar metadata and sun position.
    static func frameIndex(for metadata: SolarMetadata, sunAltitude: Double, sunAzimuth: Double) -> Int {
        let entries = metadata.entries
        guard entries.count > 1 else { return entries.first?.frameIndex ?? 0 }

        // Find the two bracketing entries by azimuth and pick the closer one
        for i in 0..<entries.count - 1 {
            if entries[i].azimuth <= sunAzimuth && sunAzimuth <= entries[i + 1].azimuth {
                let t = (sunAzimuth - entries[i].azimuth) / (entries[i + 1].azimuth - entries[i].azimuth)
                return t < 0.5 ? entries[i].frameIndex : entries[i + 1].frameIndex
            }
        }

        // Sun azimuth is outside the table range — wrap around
        // Before first entry or after last entry = night
        if sunAzimuth < entries.first!.azimuth {
            return entries.last!.frameIndex
        }
        return entries.last!.frameIndex
    }

    /// Convenience: returns the frame index for the current time and a default location.
    /// If location services are unavailable, uses a mid-latitude estimate based on timezone.
    static func currentFrameIndex(for metadata: SolarMetadata) -> Int {
        let (lat, lon) = estimateLocation()
        let (alt, az) = sunPosition(latitude: lat, longitude: lon, date: Date())
        return frameIndex(for: metadata, sunAltitude: alt, sunAzimuth: az)
    }

    /// Estimate latitude/longitude from the system timezone offset.
    private static func estimateLocation() -> (latitude: Double, longitude: Double) {
        let tz = TimeZone.current
        let offset = Double(tz.secondsFromGMT()) / 3600.0
        // Rough longitude from UTC offset (15° per hour)
        let lon = offset * 15.0
        // Default to ~25° latitude (covers most populated zones reasonably)
        let lat = 25.0
        return (lat, lon)
    }
}
