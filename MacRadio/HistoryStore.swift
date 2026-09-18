import Combine
import Foundation

/// A song heard on a station, captured from the stream's title as it plays.
struct ListenedSong: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var artist: String?
    var stationName: String
    var listenedAt: Date
    var artworkURL: String?
    var appleMusicURL: String?
    /// Kept by the user (heart). Survives "delete for good" and clearing the non-favorites.
    var favorite = false
}

/// A station-specific title the user chose to keep out of the history — the slogans and
/// jingles some stations send as if they were songs.
struct IgnoredTitle: Identifiable, Codable, Hashable {
    var stationName: String
    var title: String

    var key: String { Self.key(station: stationName, title: title) }
    var id: String { key }

    static func key(station: String, title: String) -> String {
        normalize(station) + "\n" + normalize(title)
    }

    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}

/// The log of songs heard, with favorites and the ignore list — the same model as RadioApp
/// for iOS. Fed by `RadioPlayer` rather than by a view, so it keeps recording with the window
/// closed and the radio driven from the widget or the menu bar.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var songs: [ListenedSong] = []
    @Published private(set) var ignored: [IgnoredTitle] = []

    private let maxEntries = 1000

    private static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacRadio", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()
    private let songsURL = folder.appendingPathComponent("history.json")
    private let ignoredURL = folder.appendingPathComponent("ignored_titles.json")

    private init() {
        songs = Self.read([ListenedSong].self, from: songsURL) ?? []
        ignored = Self.read([IgnoredTitle].self, from: ignoredURL) ?? []
    }

    // MARK: Capture

    /// Records a song as it starts. Returns its entry's id, so the player can fill in the cover
    /// and fix the order of title and artist once it knows them; nil when the title is on the
    /// ignore list or the same song is already the latest entry (a reconnect re-sends it).
    func record(title: String, artist: String?, stationName: String) -> UUID? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isIgnored(title: title, stationName: stationName) else { return nil }
        if let last = songs.first, last.stationName == stationName, last.title == title {
            return last.id
        }
        let song = ListenedSong(title: title, artist: artist, stationName: stationName, listenedAt: Date())
        songs.insert(song, at: 0)
        trim()
        save()
        return song.id
    }

    func update(_ id: UUID, _ change: (inout ListenedSong) -> Void) {
        guard let index = songs.firstIndex(where: { $0.id == id }) else { return }
        change(&songs[index])
        save()
    }

    // MARK: Favorites

    func isFavorite(_ id: UUID?) -> Bool {
        guard let id else { return false }
        return songs.first { $0.id == id }?.favorite ?? false
    }

    func toggleFavorite(_ id: UUID) {
        update(id) { $0.favorite.toggle() }
    }

    // MARK: Editing

    func delete(_ ids: Set<UUID>) {
        songs.removeAll { ids.contains($0.id) }
        save()
    }

    /// Clears the history but keeps the favorites — losing those by accident would hurt.
    func clearNonFavorites() {
        songs.removeAll { !$0.favorite }
        save()
    }

    // MARK: Ignore list

    func isIgnored(title: String, stationName: String) -> Bool {
        let key = IgnoredTitle.key(station: stationName, title: title)
        return ignored.contains { $0.key == key }
    }

    /// "Delete for good": this title on this station is never recorded again, and the copies
    /// already in the history go too — except the ones the user kept as favorites.
    func ignoreAndPurge(_ song: ListenedSong) {
        let entry = IgnoredTitle(stationName: song.stationName, title: song.title)
        if !ignored.contains(where: { $0.key == entry.key }) {
            ignored.insert(entry, at: 0)
            Self.write(ignored, to: ignoredURL)
        }
        songs.removeAll { !$0.favorite && IgnoredTitle.key(station: $0.stationName, title: $0.title) == entry.key }
        save()
    }

    func unignore(_ entry: IgnoredTitle) {
        ignored.removeAll { $0.id == entry.id }
        Self.write(ignored, to: ignoredURL)
    }

    // MARK: Files

    /// Drops the oldest non-favorites beyond the cap; favorites never age out.
    private func trim() {
        guard songs.count > maxEntries else { return }
        var excess = songs.count - maxEntries
        for index in songs.indices.reversed() where excess > 0 && !songs[index].favorite {
            songs.remove(at: index)
            excess -= 1
        }
    }

    private func save() { Self.write(songs, to: songsURL) }

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(value).write(to: url, options: .atomic)
    }
}
