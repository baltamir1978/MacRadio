import AppKit
import Foundation
import os

/// Something the user asked for from outside the app window: a widget button, Shortcuts.
nonisolated enum PlayerCommand: Codable, Sendable, Equatable {
    case play(streamURL: String)
    case togglePlayPause
    case next
    case previous
    case toggleFavorite
    case identify
    /// Lyrics earlier (positive) or later (negative) for the current station.
    case nudgeLyrics(seconds: Double)
    /// The user clicked lyric line `line` as it was being sung, at `at`. The time travels with
    /// the command: the app may take a moment to receive it, or even to launch.
    case syncLyrics(line: Int, at: Date)
}

extension PlayerCommand {
    /// A click on the line being sung comes this long after the line is heard.
    static let clickReaction: TimeInterval = 0.3
}

// MARK: - Delivery

extension PlayerCommand {
    /// Hands the command to the player, wherever this code happens to be running.
    ///
    /// Inside the app (the system may run an `AudioPlaybackIntent` there) it acts directly.
    /// Inside the widget extension it can't touch the player, so it queues the command in the
    /// App Group, rings the app with a Darwin notification, and launches the app in the
    /// background if it isn't running. It also writes the state the command is about to
    /// produce, because WidgetKit redraws the widget as soon as `perform()` returns — long
    /// before the app has actually switched stations.
    nonisolated func dispatch() async {
        #if MACRADIO_APP
        await MainActor.run { CommandHandler.handle(self) }
        #else
        SharedStore.applyOptimistically(self)
        CommandChannel.post(self)
        await AppLauncher.ensureRunning()
        #endif
    }
}

/// The queue of commands waiting for the app: one small file each, named so they sort in the
/// order they were sent. Files rather than a single slot so two quick taps are both honoured.
nonisolated enum CommandChannel {
    static func post(_ command: PlayerCommand) {
        guard let dir = SharedStore.commandsDirectory,
              let data = try? SharedStore.encoder.encode(command) else { return }
        let stamp = String(format: "%.0f", Date().timeIntervalSince1970 * 1000)
        let file = dir.appendingPathComponent("\(stamp)-\(UUID().uuidString).json")
        try? data.write(to: file, options: .atomic)
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(SharedStore.commandNotification as CFString),
                                             nil, nil, true)
    }

    /// Removes and returns every pending command, oldest first. Stale ones (a tap from before
    /// the Mac slept, say) are dropped: acting on them now would be a surprise.
    static func drain(maxAge: TimeInterval = 60) -> [PlayerCommand] {
        guard let dir = SharedStore.commandsDirectory,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var commands: [PlayerCommand] = []
        let now = Date().timeIntervalSince1970 * 1000
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            defer { try? FileManager.default.removeItem(at: file) }
            let stamp = Double(file.lastPathComponent.split(separator: "-").first ?? "") ?? 0
            guard now - stamp < maxAge * 1000,
                  let data = try? Data(contentsOf: file),
                  let command = try? SharedStore.decoder.decode(PlayerCommand.self, from: data) else { continue }
            commands.append(command)
        }
        return commands
    }
}

#if !MACRADIO_APP
/// Starts the app, without bringing it to the front, when a widget button needs it.
nonisolated enum AppLauncher {
    static func ensureRunning() async {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: SharedStore.appBundleID).isEmpty else { return }
        // The extension lives at MacRadio.app/Contents/PlugIns/MacRadioWidget.appex.
        let appURL = Bundle.main.bundleURL
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard appURL.pathExtension == "app" else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        do {
            try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        } catch {
            SharedStore.log.error("could not launch the app: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension SharedStore {
    /// Writes the state `command` is about to produce, so the widget's immediate redraw shows it.
    static func applyOptimistically(_ command: PlayerCommand) {
        let stations = loadStations()
        var snapshot = loadNowPlaying()

        func tune(_ station: SharedStation) {
            snapshot = NowPlayingSnapshot(stationName: station.name, streamURL: station.streamURL,
                                          track: nil, artist: nil,
                                          artworkFile: station.logoFile, artworkIsCover: false,
                                          isPlaying: true, isLoading: true,
                                          songStartedAt: nil, songStartIsExact: false,
                                          lyrics: nil, lyricsPending: false, isFavorite: false, isIdentifying: false)
        }

        func neighbour(_ step: Int) -> SharedStation? {
            guard !stations.isEmpty else { return nil }
            let current = snapshot.flatMap { s in stations.firstIndex { $0.streamURL == s.streamURL } }
            let start = current ?? (step > 0 ? -1 : 0)
            return stations[((start + step) % stations.count + stations.count) % stations.count]
        }

        switch command {
        case .play(let url):
            if let station = stations.first(where: { $0.streamURL == url }) { tune(station) }
        case .togglePlayPause:
            if snapshot != nil {
                snapshot?.isPlaying.toggle()
            } else if let first = stations.first {
                tune(first)
            }
        case .next:
            if let station = neighbour(1) { tune(station) }
        case .previous:
            if let station = neighbour(-1) { tune(station) }
        case .toggleFavorite:
            if snapshot?.hasSong == true { snapshot?.isFavorite.toggle() }
        case .identify:
            if snapshot?.isPlaying == true { snapshot?.isIdentifying = true }
        case .nudgeLyrics(let seconds):
            // The snapshot carries the lyrics' clock, offset already applied: earlier lyrics
            // mean an earlier start. The app clamps the offset; close enough until it answers.
            if var s = snapshot, let start = s.songStartedAt, s.songStartIsExact {
                s.songStartedAt = start.addingTimeInterval(-seconds)
                s.lyricsOffset = (s.lyricsOffset ?? 0) + seconds
                snapshot = s
            }
        case .syncLyrics(let line, let date):
            if let lines = snapshot?.lyrics?.synced, lines.indices.contains(line) {
                snapshot?.songStartedAt = date.addingTimeInterval(-lines[line].time - PlayerCommand.clickReaction)
                snapshot?.songStartIsExact = true
            }
        }

        // Written without asking WidgetKit to reload: finishing the intent already does that.
        if let snapshot, let url = container?.appendingPathComponent("nowplaying.json"),
           let data = try? encoder.encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
#endif
