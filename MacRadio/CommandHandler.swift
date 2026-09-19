import Foundation

/// Carries out commands from the widget and Shortcuts. They reach the app either directly (the
/// system ran the intent in the app's process) or through the App Group queue that the widget
/// extension fills and announces with a Darwin notification.
@MainActor
enum CommandHandler {
    static func handle(_ command: PlayerCommand) {
        let player = RadioPlayer.shared
        switch command {
        case .play(let streamURL):
            if let station = StationsStore.shared.station(streamURL: streamURL) { player.play(station) }
        case .togglePlayPause:
            player.togglePlayPause()
        case .next:
            player.playNext()
        case .previous:
            player.playPrevious()
        case .toggleFavorite:
            player.toggleFavorite()
        case .identify:
            player.identifySong()
        case .nudgeLyrics(let seconds):
            player.nudgeLyrics(by: seconds)
        case .resetLyrics:
            player.resetLyricsOffset()
        case .syncLyrics(let line, let date):
            player.syncLyrics(toLine: line, clickedAt: date)
        }
    }

    /// Starts listening for the widget, and runs whatever it queued before the app was up —
    /// which is why the app was launched in the first place.
    static func startListening() {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, commandCallback,
                                        SharedStore.commandNotification as CFString, nil, .deliverImmediately)
        drainPending()
    }

    static func drainPending() {
        for command in CommandChannel.drain() { handle(command) }
    }

    static var hasPendingCommands: Bool {
        guard let dir = SharedStore.commandsDirectory,
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return false }
        return !files.isEmpty
    }
}

/// A C callback can't capture context, so it just hops to the main actor and drains the queue.
private let commandCallback: CFNotificationCallback = { _, _, _, _, _ in
    Task { @MainActor in CommandHandler.drainPending() }
}
