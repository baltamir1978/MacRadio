import AppKit
import CryptoKit
import Foundation
import os
#if canImport(WidgetKit)
import WidgetKit
#endif

/// State shared between the app and its widget extension through the App Group container.
///
/// Plain files rather than `UserDefaults(suiteName:)`: every value here is written by one process
/// and read by another moments later, and a file written atomically is the one thing both sides
/// see identically. Images travel as files too, because a widget can't load a remote image.
///
/// The group identifier carries the team prefix on purpose: on macOS that is what lets a
/// Developer ID build use the container without a provisioning profile and without the system
/// asking the user whether the app may "access data from other apps".
nonisolated enum SharedStore {
    static let groupID = "JKMR84FU58.Altamirano.MacRadio"
    static let appBundleID = "Altamirano.MacRadio"
    /// Darwin notification the widget posts after queueing a command for the app.
    static let commandNotification = "Altamirano.MacRadio.command"

    static let log = Logger(subsystem: "com.macradio.shared", category: "store")

    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    private static var nowPlayingURL: URL? { container?.appendingPathComponent("nowplaying.json") }
    private static var stationsURL: URL? { container?.appendingPathComponent("stations.json") }
    static var commandsDirectory: URL? { directory("Commands") }
    static var imagesDirectory: URL? { directory("Images") }

    private static func directory(_ name: String) -> URL? {
        guard let url = container?.appendingPathComponent(name, isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Now playing

    static func loadNowPlaying() -> NowPlayingSnapshot? {
        read(NowPlayingSnapshot.self, from: nowPlayingURL)
    }

    static func saveNowPlaying(_ snapshot: NowPlayingSnapshot?) {
        guard let url = nowPlayingURL else { return }
        if let snapshot {
            write(snapshot, to: url)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
        reloadWidgets()
    }

    // MARK: Stations

    static func loadStations() -> [SharedStation] {
        read([SharedStation].self, from: stationsURL) ?? []
    }

    static func saveStations(_ stations: [SharedStation]) {
        guard let url = stationsURL else { return }
        write(stations, to: url)
        reloadWidgets()
    }

    // MARK: Images

    /// Stable file name for an image source, so the same logo or cover is stored once.
    static func imageName(for source: String) -> String {
        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined() + ".png"
    }

    static func imageURL(named name: String?) -> URL? {
        guard let name, let dir = imagesDirectory else { return nil }
        let url = dir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Stores `image` scaled down to `maxPixels` on its longest side. Widgets are archived
    /// with a tight memory budget, and a 3000px cover would blow it.
    @discardableResult
    static func storeImage(_ image: NSImage, named name: String, maxPixels: CGFloat = 400) -> Bool {
        guard let dir = imagesDirectory, let data = pngData(image, maxPixels: maxPixels) else { return false }
        do {
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
            return true
        } catch {
            log.error("could not store image: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Deletes stored images nobody refers to any more — covers of past songs, mostly.
    static func pruneImages(keeping names: Set<String>) {
        guard let dir = imagesDirectory,
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for file in files where !names.contains(file) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
        }
    }

    private static func pngData(_ image: NSImage, maxPixels: CGFloat) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(1, maxPixels / max(w, h))
        let size = CGSize(width: max(1, (w * scale).rounded()), height: max(1, (h * scale).rounded()))
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(origin: .zero, size: size))
        guard let scaled = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:])
    }

    // MARK: Widgets

    static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    // MARK: Files

    private static func read<T: Decodable>(_ type: T.Type, from url: URL?) -> T? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            log.error("could not write \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }
}

// MARK: - Models

/// What's playing, as the widget needs it. Written by the app on every change.
nonisolated struct NowPlayingSnapshot: Codable, Sendable, Equatable {
    var stationName: String
    var streamURL: String
    var track: String?
    var artist: String?
    /// Image file in the group container: the album cover when there is one, else the logo.
    var artworkFile: String?
    /// Whether `artworkFile` is a real album cover (drawn full-bleed) or the station logo.
    var artworkIsCover: Bool
    var isPlaying: Bool
    var isLoading: Bool
    /// When the current song started, as the lyrics should count it (the app has already applied
    /// its lead and the user's per-station adjustment). `songStartIsExact` says whether it can
    /// drive the lyrics:
    /// the app saw the title change, or the station published it. Tuning in mid-song to a
    /// station that doesn't gives a start time that is merely "now".
    var songStartedAt: Date?
    var songStartIsExact: Bool
    var lyrics: SongLyrics?
    /// True while the lyrics for the current song are still being fetched.
    var lyricsPending: Bool
    /// The song is hearted in the app's history.
    var isFavorite: Bool
    /// ShazamKit is listening to find out what's playing.
    var isIdentifying: Bool
    /// The user's lyrics adjustment for this station, in seconds (already in `songStartedAt`;
    /// here only to be shown). Optional so snapshots written by an older build still decode.
    var lyricsOffset: Double? = nil

    var hasSong: Bool { !(track ?? "").isEmpty }
}

/// One of the user's stations, as the widget offers it.
nonisolated struct SharedStation: Codable, Sendable, Identifiable, Hashable {
    var name: String
    var streamURL: String
    var logoFile: String?
    var initials: String

    var id: String { streamURL }
}

nonisolated struct LyricLine: Codable, Sendable, Hashable {
    /// Seconds from the start of the song.
    var time: Double
    var text: String
}

nonisolated struct SongLyrics: Codable, Sendable, Equatable {
    /// Time-stamped lines; empty when the source only has plain text.
    var synced: [LyricLine]
    var plain: [String]
    var isInstrumental: Bool
    /// The song's length in seconds, when the source knows it.
    var duration: Double? = nil

    var isEmpty: Bool { synced.isEmpty && plain.isEmpty }

    /// Lines to display, whichever form we have.
    var lines: [String] {
        synced.isEmpty ? plain : synced.map(\.text)
    }

    /// Index of the line being sung `elapsed` seconds into the song, or nil before the first.
    func lineIndex(at elapsed: Double) -> Int? {
        guard !synced.isEmpty else { return nil }
        var found: Int?
        for (i, line) in synced.enumerated() {
            if line.time <= elapsed { found = i } else { break }
        }
        return found
    }
}
