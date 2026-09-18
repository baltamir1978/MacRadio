import Foundation

/// Asks the station itself when the current song started, for the servers that publish it.
///
/// A stream's title says *what* is playing but not *since when*, so a song that was already
/// under way when the user tuned in can't have its lyrics followed line by line. AzuraCast —
/// the software behind Cassette FM, La Indie and many small stations — has a public
/// now-playing API with the moment each song went on air. Its streams live at
/// `https://host/listen/<station>/…`, and the API at `https://host/api/nowplaying/<station>`.
nonisolated enum StationClock {
    struct Song: Sendable {
        let playedAt: Date
        let title: String
        let artist: String

        /// Whether this is the song we took from the stream. Either order counts: some stations
        /// have title and artist swapped, and they are swapped the same way in both places.
        func matches(track: String, artist ours: String?) -> Bool {
            let mine = [track, ours].compactMap { $0 }.map(compact).filter { !$0.isEmpty }
            let theirs = [title, artist].map(compact).filter { !$0.isEmpty }
            return !mine.isEmpty && mine.allSatisfy { m in theirs.contains { $0 == m || $0.contains(m) || m.contains($0) } }
        }
    }

    static func apiURL(for streamURL: String) -> URL? {
        guard let url = URL(string: streamURL), let host = url.host else { return nil }
        let parts = url.pathComponents
        guard let i = parts.firstIndex(of: "listen"), parts.indices.contains(i + 1) else { return nil }
        var comps = URLComponents()
        comps.scheme = url.scheme
        comps.host = host
        comps.port = url.port
        comps.path = "/api/nowplaying/\(parts[i + 1])"
        return comps.url
    }

    static func currentSong(from api: URL) async -> Song? {
        var request = URLRequest(url: api)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONDecoder().decode(Response.self, from: data),
              let playedAt = root.now_playing.played_at else { return nil }
        return Song(playedAt: Date(timeIntervalSince1970: playedAt),
                    title: root.now_playing.song.title ?? "",
                    artist: root.now_playing.song.artist ?? "")
    }

    private static func compact(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private struct Response: Decodable {
        let now_playing: NowPlaying
        struct NowPlaying: Decodable {
            let played_at: Double?
            let song: SongInfo
        }
        struct SongInfo: Decodable {
            let title: String?
            let artist: String?
        }
    }
}
