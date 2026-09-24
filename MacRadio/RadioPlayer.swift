import AppKit
import AVFoundation
import Combine
import MediaPlayer
import Network
import os
import SwiftUI

/// Playback / reconnection tracing, visible in Console.app under subsystem `com.macradio.playback`.
/// A stream that won't start looks the same from the outside whatever the cause; these traces
/// are what tell the causes apart. `nonisolated` so the off-main helpers can use it too.
private nonisolated let playbackLog = Logger(subsystem: "com.macradio.playback", category: "stream")

/// Thread-safe holder bridging the audio render thread (stream tap) to ShazamKit. Set and
/// cleared on the main actor, called from the real-time audio thread.
nonisolated final class StreamSinkBox: Sendable {
    private let sink = OSAllocatedUnfairLock<(@Sendable (AVAudioPCMBuffer) -> Void)?>(initialState: nil)

    func set(_ sink: (@Sendable (AVAudioPCMBuffer) -> Void)?) {
        self.sink.withLock { $0 = sink }
    }

    func call(_ buffer: AVAudioPCMBuffer) {
        let sink = self.sink.withLock { $0 }
        sink?(buffer)
    }
}

/// The radio engine. Ported from RadioApp for iOS: the stream proxy, reconnection watchdog,
/// make-before-break standby, station-slogan filter and cover lookup are the same code. What
/// only exists on a phone — the audio session, route changes towards the built-in speaker,
/// call interruptions, CarPlay — is gone; sleep/wake, which only a Mac has, is new.
@MainActor
final class RadioPlayer: NSObject, ObservableObject {
    static let shared = RadioPlayer()

    @Published private(set) var currentStation: Station?
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var isReconnecting = false
    @Published private(set) var currentTrack: String?
    @Published private(set) var currentArtist: String?
    /// Album cover for the track on screen; nil means "show the station logo".
    @Published private(set) var currentArtworkURL: URL?
    /// Apple Music page for the current track, when the cover lookup found one.
    @Published private(set) var currentAppleMusicURL: URL?
    @Published private(set) var lyrics: SongLyrics?
    @Published private(set) var lyricsPending = false
    /// When the current song started, and whether that time can be trusted to follow the lyrics:
    /// we saw the title change, or ShazamKit said how far into the song we are.
    @Published private(set) var songStartedAt: Date?
    @Published private(set) var songStartIsExact = false
    /// How much earlier than `songStartedAt` suggests the lyrics should run, for this station.
    /// Stations change the title a little after the song really starts (crossfades, jingles),
    /// and by how much depends on the station — so it's the user's to adjust, and remembered.
    @Published private(set) var lyricsOffset: Double = 0
    /// Lines light up this much before they're sung, so reading keeps pace with singing.
    private static let lyricsLead: Double = 1

    /// The clock the lyrics run on: the song's start, moved by the lead and the user's offset.
    var lyricsStart: Date? {
        songStartedAt?.addingTimeInterval(-(Self.lyricsLead + lyricsOffset))
    }

    /// Moves the lyrics earlier (positive) or later (negative) for the current station.
    func nudgeLyrics(by seconds: Double) {
        guard let station = currentStation else { return }
        lyricsOffset = min(15, max(-15, lyricsOffset + seconds))
        UserDefaults.standard.set(lyricsOffset, forKey: "lyrics_offset." + station.streamURL)
        publishState()
    }

    /// Whether the lyrics can follow the song right now (and so be adjusted).
    var lyricsAreSynced: Bool {
        songStartIsExact && !(lyrics?.synced.isEmpty ?? true)
    }

    /// The user clicked the line being sung right now: the lyrics carry on from there.
    ///
    /// With the song's start already known, the correction is the station's — it changes titles
    /// late — so it goes into the station's offset and the next songs start right too. Tuned in
    /// mid-song, it's the missing start itself.
    func syncLyrics(toLine index: Int, clickedAt click: Date = Date()) {
        guard let station = currentStation, let lines = lyrics?.synced, lines.indices.contains(index) else { return }
        let wanted = click.addingTimeInterval(-lines[index].time - PlayerCommand.clickReaction)
        if songStartIsExact, let start = songStartedAt {
            lyricsOffset = min(15, max(-15, start.timeIntervalSince(wanted) - Self.lyricsLead))
            UserDefaults.standard.set(lyricsOffset, forKey: "lyrics_offset." + station.streamURL)
        } else {
            songStartedAt = wanted.addingTimeInterval(Self.lyricsLead + lyricsOffset)
            songStartIsExact = true
        }
        publishState()
    }

    func resetLyricsOffset() {
        zeroLyricsOffset()
        publishState()
    }

    /// Back to ±0 without redrawing the widget: callers that move to a new song publish anyway.
    private func zeroLyricsOffset() {
        guard let station = currentStation else { return }
        lyricsOffset = 0
        UserDefaults.standard.removeObject(forKey: "lyrics_offset." + station.streamURL)
    }

    /// ShazamKit has placed a song on this station since tuning in. From then on it places each
    /// song exactly (and learns the station's late titles), so a hand adjustment is only for
    /// the song it was made on: carried over, it would push the next song off.
    private var shazamSyncsLyrics = false

    /// The current song's entry in the history, if it was recorded (see `HistoryStore.record`).
    @Published private(set) var historyEntryID: UUID?
    private var historyObserver: AnyCancellable?
    private var shazamObserver: AnyCancellable?
    /// True while ShazamKit is listening, so the widget can say so.
    @Published private(set) var isIdentifying = false

    // MARK: Song recognition
    private let streamTap = AudioStreamTap()
    /// Receives decoded PCM from the live stream while a tap is attached (for ShazamKit).
    let streamSink = StreamSinkBox()
    private var streamTapActive = false
    /// Whether the station has named a song since tuning in. Stations that do never need
    /// ShazamKit; the ones that don't (Kiss FM) get it automatically.
    private var stationSendsTitles = false
    private var autoIdentifyTask: Task<Void, Never>?
    private var missedIdentifications = 0
    /// Whether the song on screen came from ShazamKit rather than from the stream.
    private var songIsFromShazam = false
    /// When the current song's title change was heard, if we heard it — kept to measure how
    /// late this station changes its title against ShazamKit's exact position.
    private var titleChangeHeardAt: Date?
    private var syncIdentifyTask: Task<Void, Never>?
    /// A title the station kept sending after its song was over (Cadena 100 went a whole song
    /// without renaming it). While set, a re-delivery of it is ignored and ShazamKit names what's
    /// on air, as on a station that sends no titles, until the station sends a new title.
    private var staleTitleKey: String?
    private var staleTitleTask: Task<Void, Never>?
    /// ShazamKit was asked because the song on screen should be over by now.
    private var checkingStaleTitle = false
    /// Past the song's length, plus this, the title is checked; songs without a known length
    /// are taken to be `assumedSongLength` long.
    private static let staleTitleGrace: Double = 20
    private static let assumedSongLength: Double = 300

    /// Whether ShazamKit, not the stream, names the songs right now.
    private var shazamNamesSongs: Bool { !stationSendsTitles || staleTitleKey != nil }

    @Published var volume: Double {
        didSet {
            player?.volume = Float(volume)
            UserDefaults.standard.set(volume, forKey: "volume")
        }
    }
    @Published var bufferDuration: Double {
        didSet { UserDefaults.standard.set(bufferDuration, forKey: "buffer_duration") }
    }

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var statusObserver: NSKeyValueObservation?
    private var metadataOutput: AVPlayerItemMetadataOutput?

    // MARK: Now Playing / widget artwork
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var artworkToken = 0
    /// Image file in the App Group for the widget, and whether it's a cover or the logo.
    private var widgetArtworkFile: String?
    private var widgetArtworkIsCover = false
    private var lastPublished: NowPlayingSnapshot?
    private var hasPublishedOnce = false

    // MARK: Cover and lyrics lookups
    /// "artist|title" of the song on screen, so repeated ICY frames don't re-fetch.
    private var lastSongKey: String?
    private var artworkCache: [String: ResolvedArtwork?] = [:]
    private var artworkLookupsInFlight: Set<String> = []
    private var lyricsCache: [String: SongLyrics?] = [:]
    private var lyricsLookupsInFlight: Set<String> = []
    /// Whether a song title has arrived since the user picked this station. The first one is a
    /// song already under way, so its start time is only "about now".
    private var sawTitleSinceTuning = false

    // MARK: Reconnection
    /// True while the user wants audio. Survives network drops so the watchdog keeps rebuilding
    /// the connection; distinct from `isPlaying`, which says whether audio is coming out now.
    private var intendsToPlay = false
    private var timeControlObserver: NSKeyValueObservation?
    private var itemObservers: [NSObjectProtocol] = []
    private var watchdogTask: Task<Void, Never>?
    /// Identifies the watchdog owning `watchdogTask`, so a cancelled one can't clear a newer timer.
    private var watchdogGeneration = 0
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var pauseRecoveryTask: Task<Void, Never>?
    private var pauseRecoveryGeneration = 0
    private let pathMonitor = NWPathMonitor()
    private var hasNetwork = true
    /// How long established playback may sit stalled before we rebuild the connection.
    private let stallGrace: TimeInterval = 5
    /// How long a fresh connection may buffer before we give up on it — far longer than
    /// `stallGrace`, because filling the forward buffer on a slow link takes a while.
    private let connectGrace: TimeInterval = 25
    private var hasPlayedSinceConnect = false
    private let maxReconnectDelay: TimeInterval = 15

    // MARK: Make-before-break
    private var bufferHealthObserver: NSKeyValueObservation?
    private var standbyItem: AVPlayerItem?
    /// An item that isn't attached to a player never loads, so the standby gets a muted one.
    private var standbyPlayer: AVPlayer?
    private var standbyStatusObserver: NSKeyValueObservation?
    private var standbyTimeoutTask: Task<Void, Never>?
    private var streamProxy: LocalStreamProxy?
    private var standbyProxy: LocalStreamProxy?
    private let standbyTimeout: TimeInterval = 20
    private var preflightTask: Task<Void, Never>?
    private let preflightGrace: TimeInterval = 1.5

    private override init() {
        let savedBuffer = UserDefaults.standard.double(forKey: "buffer_duration")
        bufferDuration = savedBuffer > 0 ? savedBuffer : 10
        volume = UserDefaults.standard.object(forKey: "volume") as? Double ?? 0.8
        super.init()
        setupRemoteControls()
        setupPathMonitor()
        setupSleepWakeHandling()
        // A heart toggled in the history window has to reach the widget as well.
        historyObserver = HistoryStore.shared.$songs.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.publishState() }
        }
        let shazam = ShazamService.shared
        shazam.onMatch = { [weak self] match, viaDecoder in self?.applyShazamMatch(match, viaDecoder: viaDecoder) }
        shazam.onNoMatch = { [weak self] in self?.handleNoMatch() }
        shazamObserver = shazam.$isListening.dropFirst().sink { [weak self] listening in
            Task { @MainActor in
                self?.isIdentifying = listening
                self?.publishState()
            }
        }
    }

    /// Whether stations without song titles get identified by ShazamKit on their own.
    var autoIdentify: Bool {
        get { UserDefaults.standard.object(forKey: "auto_identify") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "auto_identify")
            objectWillChange.send()
            if newValue { scheduleAutoIdentify(in: 2) } else { autoIdentifyTask?.cancel() }
        }
    }

    /// Identifies the song on air with ShazamKit (the button, the menu, the widget).
    func identifySong() {
        guard isPlaying, !isIdentifying else { return }
        ShazamService.shared.identify()
    }

    var isFavorite: Bool { HistoryStore.shared.isFavorite(historyEntryID) }

    /// Hearts the song on air (or takes the heart back).
    func toggleFavorite() {
        guard let id = historyEntryID else { return }
        HistoryStore.shared.toggleFavorite(id)
    }

    // MARK: - Transport

    func play(_ station: Station) {
        if currentStation?.streamURL == station.streamURL, isPlaying { return }
        // Not `stop()`: that would publish a paused state to the widget a moment before the
        // new station, and every widget reload counts against its budget.
        cancelReconnect()
        teardownStream()
        currentStation = station
        clearSong()
        sawTitleSinceTuning = false
        stationSendsTitles = false
        missedIdentifications = 0
        shazamSyncsLyrics = false
        staleTitleKey = nil
        checkingStaleTitle = false
        lyricsOffset = UserDefaults.standard.double(forKey: "lyrics_offset." + station.streamURL)
        ShazamService.shared.cancel()
        autoIdentifyTask?.cancel()
        isLoading = true
        intendsToPlay = true
        reconnectAttempt = 0

        guard startStream() else {
            isLoading = false
            intendsToPlay = false
            publishState()
            return
        }
        UserDefaults.standard.set(station.streamURL, forKey: "last_station")
        // Measures the station's intro (ads on connect) in the background, once, so the next
        // connection — including any reconnection — can skip it.
        IntroLearner.learnIfNeeded(station.streamURL)
        showStationLogo()
        updateNowPlayingInfo()
    }

    /// Switches to the next station in the user's list, wrapping around.
    func playNext() { step(1) }

    func playPrevious() { step(-1) }

    private func step(_ offset: Int) {
        let stations = StationsStore.shared.stations
        guard !stations.isEmpty else { return }
        let current = currentStation.flatMap { c in stations.firstIndex { $0.streamURL == c.streamURL } }
        let start = current ?? (offset > 0 ? -1 : 0)
        play(stations[((start + offset) % stations.count + stations.count) % stations.count])
    }

    func togglePlayPause() {
        if isPlaying || isReconnecting {
            pause()
        } else if let station = currentStation ?? lastStation() {
            // Radio resumes on air, not from where it stopped: `play` opens a fresh connection.
            play(station)
        }
    }

    /// Stops the audio but keeps the station and song on screen. The connection is closed
    /// too — a paused live stream would otherwise keep downloading into its buffer.
    func pause() {
        intendsToPlay = false
        ShazamService.shared.cancel()
        autoIdentifyTask?.cancel()
        staleTitleTask?.cancel()
        checkingStaleTitle = false
        cancelReconnect()
        teardownStream()
        isPlaying = false
        isLoading = false
        updateNowPlayingInfo()
    }

    func stop() { pause() }

    /// The station played last time, so play/pause works from a cold start.
    private func lastStation() -> Station? {
        let stations = StationsStore.shared.stations
        let saved = UserDefaults.standard.string(forKey: "last_station")
        return saved.flatMap { url in stations.first { $0.streamURL == url } } ?? stations.first
    }

    private func clearSong() {
        currentTrack = nil
        currentArtist = nil
        currentArtworkURL = nil
        currentAppleMusicURL = nil
        lyrics = nil
        lyricsPending = false
        songStartedAt = nil
        songStartIsExact = false
        lastSongKey = nil
        historyEntryID = nil
        songIsFromShazam = false
        titleChangeHeardAt = nil
        syncIdentifyTask?.cancel()
        staleTitleTask?.cancel()
    }

    // MARK: - Stream

    /// Builds a fresh player item from `currentStation` and starts it. Shared by `play(_:)` and
    /// every reconnect attempt. Returns false only if the URL is unusable.
    @discardableResult
    private func startStream() -> Bool {
        guard let station = currentStation, let url = URL(string: station.streamURL) else { return false }

        let (item, proxy) = makeItem(for: url)
        playerItem = item
        streamProxy?.stop()
        streamProxy = proxy
        hasPlayedSinceConnect = false

        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        metadataOutput = output
        output.setDelegate(self, queue: .main)
        item.add(output)

        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor [weak self] in self?.handleItemStatus(status) }
        }
        attachStallObservers(to: item)
        observeBufferHealth(of: item)

        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        player.volume = Float(volume)
        self.player = player
        observeTimeControl(of: player)
        player.play()
        isPlaying = true
        return true
    }

    /// Continuous live audio goes through `LocalStreamProxy`, which relays it without byte-range
    /// requests (see that class for why). HLS keeps AVFoundation's own stack, which genuinely
    /// needs range access; if the proxy can't start we play the URL directly.
    private func makeItem(for url: URL) -> (AVPlayerItem, LocalStreamProxy?) {
        let item: AVPlayerItem
        var proxy: LocalStreamProxy?
        if url.pathExtension.lowercased() != "m3u8", let live = LocalStreamProxy(originURL: url) {
            item = AVPlayerItem(url: live.localURL)
            proxy = live
        } else {
            item = AVPlayerItem(url: url)
        }
        // After a skipped intro the server has no head start to give: live audio arrives in real
        // time, so a long buffer would just be a long silence before the first note.
        let skipsIntro = proxy != nil && IntroRegistry.shared.intro(for: url.absoluteString) != nil
        item.preferredForwardBufferDuration = skipsIntro ? min(bufferDuration, 3) : bufferDuration
        return (item, proxy)
    }

    private func handleItemStatus(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            isLoading = false
            publishState()
        case .failed:
            playbackLog.error("item failed: \(String(describing: self.playerItem?.error), privacy: .public)")
            if intendsToPlay {
                scheduleReconnect()
            } else {
                isLoading = false
                isPlaying = false
                publishState()
            }
        default:
            break
        }
    }

    /// Disposes the AVPlayer and its observers without touching the chosen station, the intent
    /// to play or the reconnect schedule — used between reconnect attempts and by `stop`.
    private func teardownStream() {
        cancelPreflight()
        endStreamTap()
        bufferHealthObserver = nil
        timeControlObserver = nil
        statusObserver = nil
        for token in itemObservers { NotificationCenter.default.removeObserver(token) }
        itemObservers = []
        player?.pause()
        player = nil
        playerItem = nil
        metadataOutput = nil
        streamProxy?.stop()
        streamProxy = nil
    }

    // MARK: - Reconnection

    private func attachStallObservers(to item: AVPlayerItem) {
        let center = NotificationCenter.default
        let stalled = center.addObserver(forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.armWatchdog() }
        }
        let failed = center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] note in
            let err = String(describing: note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey])
            Task { @MainActor [weak self] in
                playbackLog.error("failed-to-play-to-end: \(err, privacy: .public)")
                self?.scheduleReconnect()
            }
        }
        itemObservers = [stalled, failed]
    }

    private func observeTimeControl(of player: AVPlayer) {
        timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in self?.handleTimeControl(status) }
        }
    }

    private func handleTimeControl(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            if !hasPlayedSinceConnect {
                playbackLog.notice("playing — audio started")
                // Give the station a moment to name the song before asking ShazamKit.
                if !stationSendsTitles && lastSongKey == nil { scheduleAutoIdentify(in: 8) }
            }
            isLoading = false
            isReconnecting = false
            reconnectAttempt = 0
            hasPlayedSinceConnect = true
            disarmWatchdog()
            publishState()
        case .waitingToPlayAtSpecifiedRate:
            if intendsToPlay { armWatchdog() }
        case .paused:
            disarmWatchdog()
            // A pause nobody asked for: the item quietly gave up. Nudge it back.
            if intendsToPlay { scheduleUnexpectedPauseRecovery() }
        @unknown default:
            break
        }
    }

    /// Resumes a self-paused player, rebuilding the stream if resuming doesn't take. Delayed on
    /// purpose: swapping in the standby item passes through `.paused` for an instant.
    private func scheduleUnexpectedPauseRecovery() {
        guard pauseRecoveryTask == nil else { return }
        pauseRecoveryGeneration += 1
        let generation = pauseRecoveryGeneration
        pauseRecoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            if let self, !Task.isCancelled, self.intendsToPlay, self.player?.timeControlStatus == .paused {
                playbackLog.notice("player paused itself — resuming")
                self.player?.play()
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled, self.intendsToPlay, self.player?.timeControlStatus != .playing {
                    playbackLog.notice("resume didn't take — rebuilding the stream")
                    self.scheduleReconnect()
                }
            }
            guard let self, self.pauseRecoveryGeneration == generation else { return }
            self.pauseRecoveryTask = nil
        }
    }

    /// One-shot timer: if the stream still isn't playing after the applicable grace, reconnect.
    private func armWatchdog() {
        guard intendsToPlay, watchdogTask == nil else { return }
        let grace = hasPlayedSinceConnect ? stallGrace : connectGrace
        watchdogGeneration += 1
        let generation = watchdogGeneration
        watchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(grace))
            guard let self else { return }
            // Only clear the slot if it still holds *this* timer; a cancelled task resumes one
            // hop later and would otherwise orphan a watchdog armed in between.
            if self.watchdogGeneration == generation { self.watchdogTask = nil }
            guard !Task.isCancelled, self.intendsToPlay else { return }
            if self.player?.timeControlStatus != .playing {
                playbackLog.notice("watchdog fired after \(grace, privacy: .public)s (hasPlayed=\(self.hasPlayedSinceConnect, privacy: .public)) → reconnect")
                self.scheduleReconnect()
            }
        }
    }

    private func disarmWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = nil
    }

    /// Tears down the stalled player and rebuilds it after an exponential backoff.
    private func scheduleReconnect(after fixedDelay: TimeInterval? = nil) {
        guard intendsToPlay else { return }
        disarmWatchdog()
        reconnectTask?.cancel()
        isReconnecting = true
        publishState()

        let delay = fixedDelay ?? min(pow(2, Double(reconnectAttempt)), maxReconnectDelay)
        reconnectAttempt += 1

        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.reconnectTask = nil
            guard self.intendsToPlay else { return }
            // No point rebuilding while offline; the path monitor kicks us when the network returns.
            guard self.hasNetwork else { return }
            playbackLog.notice("rebuilding connection (attempt \(self.reconnectAttempt, privacy: .public))")
            self.teardownStream()
            self.startStream()
        }
    }

    private func cancelReconnect() {
        disarmWatchdog()
        cancelPreflight()
        pauseRecoveryTask?.cancel()
        pauseRecoveryTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        isReconnecting = false
        reconnectAttempt = 0
    }

    private func setupPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in self?.handleNetworkChange(satisfied: satisfied) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "radio.path.monitor"))
    }

    /// Recovers the moment connectivity returns instead of waiting out the backoff.
    private func handleNetworkChange(satisfied: Bool) {
        hasNetwork = satisfied
        guard satisfied, intendsToPlay, isReconnecting else { return }
        reconnectAttempt = 0
        scheduleReconnect()
    }

    /// A Mac that wakes from sleep holds a connection the server dropped long ago. Rebuilding
    /// straight away beats waiting for the watchdog to notice the silence.
    private func setupSleepWakeHandling() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.intendsToPlay else { return }
                playbackLog.notice("woke from sleep — reconnecting")
                self.reconnectAttempt = 0
                self.scheduleReconnect(after: 1)
            }
        }
    }

    // MARK: Make-before-break

    /// `isPlaybackLikelyToKeepUp` flips false the instant fresh data stops arriving, while audio
    /// still plays from the buffer. That head start lets us reconnect with no audible gap.
    private func observeBufferHealth(of item: AVPlayerItem) {
        bufferHealthObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            let likely = item.isPlaybackLikelyToKeepUp
            Task { @MainActor [weak self] in
                if likely { self?.cancelPreflight() } else { self?.startPreflight() }
            }
        }
    }

    private func startPreflight() {
        guard intendsToPlay, hasNetwork, !isReconnecting,
              standbyItem == nil, preflightTask == nil,
              player?.timeControlStatus == .playing else { return }
        preflightTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.preflightGrace))
            self.preflightTask = nil
            guard !Task.isCancelled, self.intendsToPlay, self.hasNetwork, !self.isReconnecting,
                  self.standbyItem == nil,
                  self.player?.currentItem?.isPlaybackLikelyToKeepUp == false else { return }
            self.buildStandby()
        }
    }

    private func cancelPreflight() {
        preflightTask?.cancel()
        preflightTask = nil
        discardStandby()
    }

    private func buildStandby() {
        guard let station = currentStation, let url = URL(string: station.streamURL) else { return }
        let (item, proxy) = makeItem(for: url)
        standbyItem = item
        standbyProxy = proxy
        standbyStatusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor [weak self] in
                switch status {
                case .readyToPlay: self?.promoteStandby()
                case .failed: self?.discardStandby()
                default: break
                }
            }
        }
        let warmup = AVPlayer(playerItem: item)
        warmup.isMuted = true
        warmup.automaticallyWaitsToMinimizeStalling = true
        standbyPlayer = warmup

        standbyTimeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.standbyTimeout))
            guard !Task.isCancelled, self.standbyItem === item else { return }
            self.discardStandby()
        }
    }

    /// Swaps the ready standby in for the struggling primary. The old buffer covers playback up
    /// to the swap, so there's no silent stall — at most a small jump to the live edge.
    private func promoteStandby() {
        guard intendsToPlay, let player, let standby = standbyItem else { discardStandby(); return }

        bufferHealthObserver = nil
        statusObserver = nil
        for token in itemObservers { NotificationCenter.default.removeObserver(token) }
        itemObservers = []
        // An identification in progress falls back to its own connection (see ShazamService).
        endStreamTap()

        standbyStatusObserver = nil
        standbyTimeoutTask?.cancel()
        standbyTimeoutTask = nil
        standbyItem = nil
        standbyPlayer?.replaceCurrentItem(with: nil)
        standbyPlayer = nil
        streamProxy?.stop()
        streamProxy = standbyProxy
        standbyProxy = nil

        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        metadataOutput = output
        output.setDelegate(self, queue: .main)
        standby.add(output)
        playerItem = standby
        statusObserver = standby.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor [weak self] in self?.handleItemStatus(status) }
        }
        attachStallObservers(to: standby)
        observeBufferHealth(of: standby)

        player.replaceCurrentItem(with: standby)
        player.play()
        isPlaying = true
        isReconnecting = false
        reconnectAttempt = 0
        hasPlayedSinceConnect = true
    }

    private func discardStandby() {
        standbyStatusObserver = nil
        standbyTimeoutTask?.cancel()
        standbyTimeoutTask = nil
        standbyPlayer?.replaceCurrentItem(with: nil)
        standbyPlayer = nil
        standbyItem = nil
        standbyProxy?.stop()
        standbyProxy = nil
    }

    // MARK: - Stream metadata

    /// `sounding` is when the title's place in the audio is (or was) heard: the metadata group's
    /// own timestamp against the item's clock, rather than the moment the callback happens to
    /// run — the two can be seconds apart, and the lyrics count from this.
    fileprivate func handleMetadata(_ metadata: [AVMetadataItem], sounding: Date) async {
        for item in metadata {
            guard let raw = try? await item.load(.value), let title = raw as? String else { continue }
            let cleaned = Self.repairingLatin1(title).trimmingCharacters(in: .whitespacesAndNewlines)
            // Some stations (Los 40 Classic) send a bare numeric rotation code instead of a song.
            guard Self.isMeaningfulTitle(cleaned) else { continue }
            // Split on " - " first: a bare "-" would cut band names like "M-Clan" in two.
            let separator = cleaned.contains(" - ") ? " - " : "-"
            let parts = cleaned.components(separatedBy: separator)
            let pair = parts.count >= 2
                ? [parts[0], parts.dropFirst().joined(separator: separator)].map { $0.trimmingCharacters(in: .whitespaces) }
                : [cleaned]
            let track: String
            let artist: String?
            if pair.count == 2, !pair[0].isEmpty, !pair[1].isEmpty {
                artist = pair[0]
                track = pair[1]
            } else {
                track = cleaned
                artist = nil
            }
            // A station announcing itself is not a song — keep it off the screen.
            guard !Self.announcesStation(track: track, artist: artist, station: currentStation?.name ?? "") else {
                clearStreamMetadata()
                return
            }
            let key = "\(artist ?? "")|\(track)".lowercased()
            // The title that outlived its song, sent again (a reconnect): ShazamKit carries on.
            guard key != staleTitleKey else { return }
            stationSendsTitles = true
            autoIdentifyTask?.cancel()
            guard key != lastSongKey else { return }
            if staleTitleKey != nil {
                staleTitleKey = nil
                checkingStaleTitle = false
                // The station catching up with the song ShazamKit already put on screen.
                if songIsFromShazam, let shown = currentTrack, Self.sameSong(shown, track) {
                    songIsFromShazam = false
                    lastSongKey = key
                    scheduleStaleTitleCheck()
                    return
                }
            }
            songIsFromShazam = false
            lastSongKey = key
            if shazamSyncsLyrics { zeroLyricsOffset() }

            // The first title after tuning in belongs to a song already under way; only a title
            // that *changes* while we listen marks the real start of a song. A reconnect
            // re-delivers the same title and is caught by the key check above.
            // Stations change the title a little after the song really starts — crossfades,
            // encoder delay — by an amount that belongs to the station, not to the connection.
            // ShazamKit measures it (see `applyShazamMatch`) and it's taken off from then on.
            titleChangeHeardAt = sawTitleSinceTuning ? sounding : nil
            songStartedAt = sounding.addingTimeInterval(-titleLag)
            songStartIsExact = sawTitleSinceTuning
            sawTitleSinceTuning = true

            currentArtist = artist
            currentTrack = track
            currentAppleMusicURL = nil
            historyEntryID = currentStation.flatMap {
                HistoryStore.shared.record(title: track, artist: artist, stationName: $0.name)
            }
            resolveArtwork(key: key, track: track, artist: artist)
            resolveLyrics(key: key, track: track, artist: artist)
            scheduleStaleTitleCheck()
            updateNowPlayingInfo()
            return
        }
    }

    /// Asks ShazamKit what's on air once the song on screen should be over: the station may
    /// have stopped renaming its songs. With no `delay`, that's the song's length past its start.
    private func scheduleStaleTitleCheck(after delay: TimeInterval? = nil) {
        staleTitleTask?.cancel()
        guard !shazamNamesSongs, let key = lastSongKey, let start = songStartedAt else { return }
        let length = lyrics?.duration ?? Self.assumedSongLength
        let wait = delay ?? start.addingTimeInterval(length + Self.staleTitleGrace).timeIntervalSinceNow
        staleTitleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(5, wait)))
            guard let self, !Task.isCancelled, key == self.lastSongKey, self.isPlaying,
                  !self.shazamNamesSongs else { return }
            // Busy with the in-song check: its result wouldn't say whether the song is over.
            guard !ShazamService.shared.isListening else {
                self.scheduleStaleTitleCheck(after: 15)
                return
            }
            playbackLog.notice("title unchanged past the song's end — asking ShazamKit")
            self.checkingStaleTitle = true
            ShazamService.shared.identify()
        }
    }

    /// A station sending Latin-1 ("El Último" with a lone 0xDA byte) can have its title guessed
    /// as Windows-1256 by AVFoundation, which turns "Ú" into "ع". Arabic in a title is taken for
    /// that mistake: back to the original bytes and read them as Windows-1252.
    static func repairingLatin1(_ title: String) -> String {
        guard title.unicodeScalars.contains(where: { (0x0600...0x06FF).contains($0.value) }) else { return title }
        let arabic = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.windowsArabic.rawValue)))
        guard let bytes = title.data(using: arabic),
              let latin = String(data: bytes, encoding: .windowsCP1252) else { return title }
        return latin
    }

    private static func isMeaningfulTitle(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    /// Stations broadcast their own name or a slogan between songs — Cadena 100 sends
    /// "La Mejor Variedad Musical - CADENA 100" permanently. Either side matching the station's
    /// name gives it away.
    private static func announcesStation(track: String, artist: String?, station: String) -> Bool {
        let stationKey = compact(station)
        guard !stationKey.isEmpty else { return false }
        return [track, artist].compactMap { $0 }.contains { compact($0) == stationKey }
    }

    /// `compact` for artist names, blind to how a band's "and" is spelt: iTunes has
    /// "Fito y Fitipaldis" where the station sends "Fito & Fitipaldis".
    private static func artistKey(_ s: String) -> String {
        LyricsService.artistNames(s).map(compact).joined()
    }

    private static func compact(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    /// Returns the screen to the station when the stream stops naming a song.
    private func clearStreamMetadata() {
        guard currentTrack != nil, !songIsFromShazam else { return }
        clearSong()
        showStationLogo()
        updateNowPlayingInfo()
    }

    // MARK: - Song recognition

    /// Starts routing the stream's PCM to `streamSink`. Only while identifying: a tap left on
    /// a live item for good was what made audio cut out in the background on iOS.
    func beginStreamTap() { activateStreamTap() }

    func endStreamTap() {
        streamTap.remove()
        streamSink.set(nil)
        streamTapActive = false
    }

    /// Stream tracks load late, so this retries for a few seconds.
    private func activateStreamTap(retriesLeft: Int = 8) {
        guard let item = playerItem, !streamTapActive else { return }
        let box = streamSink
        if streamTap.install(on: item, handler: { buffer, _ in box.call(buffer) }) {
            streamTapActive = true
        } else if retriesLeft > 0 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, self.playerItem === item else { return }
                self.activateStreamTap(retriesLeft: retriesLeft - 1)
            }
        }
    }

    /// Puts a ShazamKit result on screen, in the history and in the widget. Its offset is the
    /// exact position in the song, so the lyrics follow along even on a station that never
    /// says what it's playing. Audio decoded over the second connection runs ahead of what's
    /// heard by roughly what the player holds in its buffer, so that path corrects for it.
    private func applyShazamMatch(_ match: ShazamMatch, viaDecoder: Bool) {
        guard let station = currentStation, isPlaying else { return }
        missedIdentifications = 0
        // On a station that names its songs, ShazamKit was only asked for the position in the
        // song (see `finishLyrics`), or whether the song is over (`scheduleStaleTitleCheck`).
        // Take the offset if it heard the same song; leave the station's title, cover and
        // history entry alone — unless the song is over and the title stayed.
        let stillOnStationSong = !songIsFromShazam && currentTrack.map { Self.sameSong($0, match.title) } == true
        if stationSendsTitles, staleTitleKey == nil, !(checkingStaleTitle && !stillOnStationSong) {
            let wasChecking = checkingStaleTitle
            checkingStaleTitle = false
            guard stillOnStationSong, let offset = match.offset else {
                if wasChecking { scheduleStaleTitleCheck(after: 60) }
                return
            }
            let ahead = viaDecoder ? bufferedAhead() : 0
            if viaDecoder { playbackLog.notice("player is \(ahead, privacy: .public)s behind the air") }
            let start = match.matchedAt.addingTimeInterval(-offset + ahead)
            if let heard = titleChangeHeardAt {
                let lag = heard.timeIntervalSince(start)
                // A plausible lag only: a match on the previous song's tail would give nonsense.
                if (-5...30).contains(lag) { learnTitleLag(lag) }
            }
            songStartedAt = start
            songStartIsExact = true
            shazamSyncsLyrics = true
            zeroLyricsOffset()
            playbackLog.notice("lyrics synced by ShazamKit at \(offset, privacy: .public)s")
            // Still on it past its expected end (a longer version): look again in a minute.
            scheduleStaleTitleCheck(after: wasChecking ? 60 : nil)
            updateNowPlayingInfo()
            return
        }
        if checkingStaleTitle {
            // Another song on air while the station still names the last one.
            checkingStaleTitle = false
            staleTitleKey = lastSongKey
            playbackLog.notice("station title is stale — ShazamKit names the songs until it changes")
        }
        let key = "\(match.artist ?? "")|\(match.title)".lowercased()
        let isNewSong = key != lastSongKey
        if isNewSong {
            lastSongKey = key
            songIsFromShazam = true
            currentTrack = match.title
            currentArtist = match.artist
            currentAppleMusicURL = match.appleMusicURL
            historyEntryID = HistoryStore.shared.record(title: match.title, artist: match.artist,
                                                        stationName: station.name)
            if let artwork = match.artworkURL {
                applyResolved(ResolvedArtwork(artwork: artwork, appleMusic: match.appleMusicURL,
                                              track: match.title, artist: match.artist))
            } else {
                resolveArtwork(key: key, track: match.title, artist: match.artist)
            }
            resolveLyrics(key: key, track: match.title, artist: match.artist)
        }
        if let offset = match.offset {
            let lag = viaDecoder ? bufferedAhead() : 0
            songStartedAt = match.matchedAt.addingTimeInterval(-offset + lag)
            songStartIsExact = true
            // Matched again every minute on the same song: only a new one starts from ±0.
            if isNewSong || !shazamSyncsLyrics { zeroLyricsOffset() }
            shazamSyncsLyrics = true
        }
        updateNowPlayingInfo()
        // Check again in a while: the song will have changed, and the station won't say so.
        if shazamNamesSongs { scheduleAutoIdentify(in: 60) }
    }

    /// How many seconds after the real start of a song this station changes its title.
    private var titleLag: Double {
        guard let station = currentStation else { return 0 }
        return UserDefaults.standard.double(forKey: "title_lag." + station.streamURL)
    }

    /// Averaged with what was known, so one odd measurement can't throw the lyrics off.
    private func learnTitleLag(_ measured: Double) {
        guard let station = currentStation else { return }
        let key = "title_lag." + station.streamURL
        let known = UserDefaults.standard.object(forKey: key) as? Double
        let lag = known.map { ($0 + measured) / 2 } ?? measured
        UserDefaults.standard.set(lag, forKey: key)
        playbackLog.notice("\(station.name, privacy: .public) changes its titles \(measured, privacy: .public)s late (now using \(lag, privacy: .public)s)")
    }

    /// Loose title comparison: "Miedo (Directo)" from the station is ShazamKit's "Miedo".
    private static func sameSong(_ a: String, _ b: String) -> Bool {
        let x = compact(a), y = compact(b)
        return !x.isEmpty && !y.isEmpty && (x.contains(y) || y.contains(x))
    }

    /// Nothing recognised: talk, an ad, or a song ShazamKit doesn't know. One miss may be a
    /// jingle over the end of the song; two in a row and the song on screen is surely over.
    private func handleNoMatch() {
        if checkingStaleTitle {
            // Talk or ads under a title whose song is over: back to the station until
            // ShazamKit hears a song or the station names one.
            checkingStaleTitle = false
            staleTitleKey = lastSongKey
            playbackLog.notice("station title is stale and nothing recognised — showing the station")
            clearSong()
            showStationLogo()
            updateNowPlayingInfo()
            scheduleAutoIdentify(in: 45)
            return
        }
        guard shazamNamesSongs else { return }
        missedIdentifications += 1
        if missedIdentifications >= 2, songIsFromShazam {
            clearSong()
            showStationLogo()
            updateNowPlayingInfo()
        }
        scheduleAutoIdentify(in: 45)
    }

    private func scheduleAutoIdentify(in seconds: TimeInterval) {
        autoIdentifyTask?.cancel()
        guard autoIdentify, shazamNamesSongs else { return }
        autoIdentifyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled, self.intendsToPlay, self.isPlaying,
                  self.shazamNamesSongs else { return }
            self.identifySong()
        }
    }

    // MARK: - Buffer

    /// Seconds of audio downloaded but not yet played — the part of the delay that's ours.
    private func bufferedAhead() -> Double {
        guard let item = playerItem, let range = item.loadedTimeRanges.last?.timeRangeValue else { return 0 }
        return max(0, (range.start + range.duration).seconds - item.currentTime().seconds)
    }

    // MARK: - Cover art

    /// Stations only broadcast a title, so the cover comes from the iTunes Search API (free,
    /// keyless), cached per song and retried when the *network* fails rather than the lookup.
    private func resolveArtwork(key: String, track: String, artist: String?) {
        currentArtworkURL = nil
        showStationLogo()
        if let cached = artworkCache[key] {
            if let cached { applyResolved(cached) }
            return
        }
        guard !artworkLookupsInFlight.contains(key) else { return }
        artworkLookupsInFlight.insert(key)
        Task { @MainActor [weak self] in
            for wait in [2, 5, 12, 0] {
                let outcome = await Self.lookupCoverArt(track: track, artist: artist)
                guard let self else { return }
                switch outcome {
                case .found(let resolved):
                    self.remember(resolved, for: key)
                    if key == self.lastSongKey { self.applyResolved(resolved) }
                    self.artworkLookupsInFlight.remove(key)
                    return
                case .notFound:
                    playbackLog.notice("no cover found for \(track, privacy: .public)")
                    self.remember(nil, for: key)
                    self.artworkLookupsInFlight.remove(key)
                    return
                case .failed:
                    guard wait > 0, key == self.lastSongKey else {
                        self.artworkLookupsInFlight.remove(key)
                        return
                    }
                    playbackLog.notice("cover lookup failed for \(track, privacy: .public) — retrying")
                    try? await Task.sleep(for: .seconds(wait))
                }
            }
        }
    }

    /// Some stations (Cassette FM) send "Title - Artist" instead of the usual "Artist - Title".
    /// Nothing in the title itself tells the two apart, but the iTunes match does: when its
    /// artist is what we took for the song, the pair was the wrong way round.
    private func correctSwappedOrder(using resolved: ResolvedArtwork) {
        guard let track = currentTrack, let artist = currentArtist,
              let itunesArtist = resolved.artist.map(Self.artistKey), !itunesArtist.isEmpty else { return }
        let asTrack = Self.artistKey(track), asArtist = Self.artistKey(artist)
        guard asTrack == itunesArtist || (asTrack.contains(itunesArtist) && !asArtist.contains(itunesArtist)) else { return }
        playbackLog.notice("station sends title and artist swapped — correcting \(track, privacy: .public)")
        currentTrack = artist
        currentArtist = track
        if let id = historyEntryID {
            HistoryStore.shared.update(id) { $0.title = artist; $0.artist = track }
        }
        updateNowPlayingInfo()
    }

    private func remember(_ resolved: ResolvedArtwork?, for key: String) {
        if artworkCache.count >= 60 { artworkCache.removeAll() }
        artworkCache[key] = .some(resolved)
    }

    private func applyResolved(_ resolved: ResolvedArtwork) {
        correctSwappedOrder(using: resolved)
        currentArtworkURL = resolved.artwork
        currentAppleMusicURL = resolved.appleMusic
        if let id = historyEntryID {
            HistoryStore.shared.update(id) {
                $0.artworkURL = resolved.artwork.absoluteString
                $0.appleMusicURL = resolved.appleMusic?.absoluteString
            }
        }
        loadArtwork(source: resolved.artwork.absoluteString, isCover: true)
    }

    private func showStationLogo() {
        loadArtwork(source: currentStation?.logoURL, isCover: false)
    }

    private nonisolated static func lookupCoverArt(track: String, artist: String?) async -> ArtworkLookup {
        let term = [artist, track].compactMap { $0 }.joined(separator: " ")
        guard !term.isEmpty, var comps = URLComponents(string: "https://itunes.apple.com/search") else { return .notFound }
        comps.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = comps.url else { return .notFound }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return .failed }
        // iTunes Search throttles bursts with a 403: transient, not a miss.
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            playbackLog.error("iTunes search returned \(http.statusCode, privacy: .public)")
            return .failed
        }
        guard let root = try? JSONDecoder().decode(ITunesSearchResponse.self, from: data) else { return .failed }
        guard let hit = root.results.first, let art = hit.artworkUrl100 else { return .notFound }
        let big = art.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        guard let artworkURL = URL(string: big) else { return .notFound }
        return .found(ResolvedArtwork(artwork: artworkURL, appleMusic: hit.trackViewUrl.flatMap { URL(string: $0) },
                                      track: hit.trackName, artist: hit.artistName))
    }

    private enum ArtworkLookup {
        case found(ResolvedArtwork)
        case notFound
        case failed
    }

    private nonisolated struct ResolvedArtwork: Sendable {
        let artwork: URL
        let appleMusic: URL?
        /// How iTunes names the song and artist — used to spot stations that send them swapped.
        let track: String?
        let artist: String?
    }

    private nonisolated struct ITunesSearchResponse: Decodable {
        let results: [Item]
        nonisolated struct Item: Decodable {
            let artworkUrl100: String?
            let trackViewUrl: String?
            let trackName: String?
            let artistName: String?
        }
    }

    /// Loads the image for Now Playing and the widget: the cover, the logo, or drawn initials.
    /// Token-guarded so a slow download never paints over a newer song.
    private func loadArtwork(source: String?, isCover: Bool) {
        artworkToken += 1
        let token = artworkToken
        let initials = currentStation?.initials ?? "♪"
        let seed = currentStation?.name ?? ""
        Task.detached(priority: .utility) {
            var image: NSImage?
            if let source { image = await ImageLoader.image(from: source) }
            let final = image ?? Self.drawInitialsImage(initials, seed: seed)
            let fileName = SharedStore.imageName(for: "art:" + (source ?? "initials:\(seed)"))
            let stored = SharedStore.storeImage(final, named: fileName)
            // Built here, off the main actor, on purpose: MediaPlayer calls this handler on its
            // own queue, and built on the main actor it would inherit that isolation and trap
            // under Swift 6 (the crash RadioApp hit on iOS).
            let artwork = MPMediaItemArtwork(boundsSize: final.size) { _ in final }
            await MainActor.run { [weak self] in
                guard let self, token == self.artworkToken else { return }
                self.nowPlayingArtwork = artwork
                self.widgetArtworkFile = stored ? fileName : nil
                self.widgetArtworkIsCover = isCover && image != nil
                self.updateNowPlayingInfo()
                SharedStore.pruneImages(keeping: StationsStore.shared.logoFiles.union([fileName]))
            }
        }
    }

    private nonisolated static func drawInitialsImage(_ initials: String, seed: String) -> NSImage {
        let size = NSSize(width: 512, height: 512)
        return NSImage(size: size, flipped: false) { rect in
            NSColor(Color.tile(for: seed)).setFill()
            rect.fill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 200, weight: .bold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph,
            ]
            let text = initials as NSString
            let height = text.size(withAttributes: attrs).height
            text.draw(in: NSRect(x: 0, y: (rect.height - height) / 2, width: rect.width, height: height),
                      withAttributes: attrs)
            return true
        }
    }

    // MARK: - Lyrics

    private func resolveLyrics(key: String, track: String, artist: String?) {
        lyrics = nil
        if let cached = lyricsCache[key] {
            lyrics = cached
            lyricsPending = false
            return
        }
        lyricsPending = true
        guard !lyricsLookupsInFlight.contains(key) else { return }
        lyricsLookupsInFlight.insert(key)
        Task { @MainActor [weak self] in
            // LRCLIB answers 503 for a while when it's overloaded: keep trying through the song.
            for wait in [3, 10, 30, 60, 90, 0] {
                let outcome = await LyricsService.lookup(track: track, artist: artist)
                guard let self else { return }
                switch outcome {
                case .found(let found):
                    self.rememberLyrics(found, for: key)
                    self.finishLyrics(key: key, lyrics: found)
                    return
                case .notFound:
                    self.rememberLyrics(nil, for: key)
                    self.finishLyrics(key: key, lyrics: nil)
                    return
                case .failed:
                    guard wait > 0, key == self.lastSongKey else {
                        self.finishLyrics(key: key, lyrics: nil)
                        return
                    }
                    try? await Task.sleep(for: .seconds(wait))
                }
            }
        }
    }

    private func finishLyrics(key: String, lyrics found: SongLyrics?) {
        lyricsLookupsInFlight.remove(key)
        guard key == lastSongKey else { return }
        lyrics = found
        lyricsPending = false
        publishState()
        // ShazamKit says exactly where in the song we are: the only way to follow a song we
        // tuned into halfway, and the check on a station's late title changes. Asked ~20 s in,
        // past the crossfade, where it would still hear the previous song.
        scheduleStaleTitleCheck()
        if found?.synced.isEmpty == false, !shazamNamesSongs, isPlaying {
            let elapsed = songStartIsExact ? songStartedAt.map { Date().timeIntervalSince($0) } ?? 0 : 20
            syncIdentifyTask?.cancel()
            syncIdentifyTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(max(0, 20 - elapsed)))
                guard let self, !Task.isCancelled, key == self.lastSongKey, self.isPlaying else { return }
                ShazamService.shared.identify()
            }
        }
    }

    private func rememberLyrics(_ lyrics: SongLyrics?, for key: String) {
        if lyricsCache.count >= 60 { lyricsCache.removeAll() }
        lyricsCache[key] = .some(lyrics)
    }

    // MARK: - Now Playing, media keys, widget

    private func setupRemoteControls() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == false { self?.togglePlayPause() } }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPrevious() }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        let center = MPNowPlayingInfoCenter.default()
        guard let station = currentStation else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            publishState()
            return
        }
        var info: [String: Any] = [:]
        let track = (currentTrack ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = (currentArtist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Each line only says what the lines above don't: filling every empty field with the
        // station name printed it three times over between songs.
        let hasSong = !track.isEmpty
        info[MPMediaItemPropertyTitle] = hasSong ? track : station.name
        if hasSong, !artist.isEmpty { info[MPMediaItemPropertyArtist] = artist }
        if hasSong { info[MPMediaItemPropertyAlbumTitle] = station.name }
        info[MPNowPlayingInfoPropertyIsLiveStream] = true
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        if let nowPlayingArtwork { info[MPMediaItemPropertyArtwork] = nowPlayingArtwork }
        center.nowPlayingInfo = info
        // macOS, unlike iOS, takes the play state from here rather than from the audio session.
        center.playbackState = isPlaying ? .playing : .paused
        publishState()
    }

    /// Mirrors the state into the App Group for the widget. Only when something the widget
    /// shows has changed: every write reloads its timeline, and those reloads are budgeted.
    private func publishState() {
        let snapshot = currentStation.map { station in
            NowPlayingSnapshot(stationName: station.name, streamURL: station.streamURL,
                               track: currentTrack, artist: currentArtist,
                               artworkFile: widgetArtworkFile, artworkIsCover: widgetArtworkIsCover,
                               isPlaying: isPlaying || isReconnecting,
                               isLoading: isLoading || isReconnecting,
                               songStartedAt: lyricsStart, songStartIsExact: songStartIsExact,
                               lyrics: lyrics, lyricsPending: lyricsPending,
                               isFavorite: isFavorite, isIdentifying: isIdentifying,
                               lyricsOffset: lyricsOffset)
        }
        guard !hasPublishedOnce || snapshot != lastPublished else { return }
        hasPublishedOnce = true
        lastPublished = snapshot
        SharedStore.saveNowPlaying(snapshot)
    }
}

// The output is set up with `setDelegate(self, queue: .main)`, so the callback already runs on
// the main actor; `@preconcurrency` lets it be main-actor isolated and checks that at run time.
extension RadioPlayer: @preconcurrency AVPlayerItemMetadataOutputPushDelegate {
    func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                        from track: AVPlayerItemTrack?) {
        let items = groups.flatMap(\.items)
        // Where in the item's timeline these titles sit, versus where playback is right now.
        var sounding = Date()
        if let start = groups.first?.timeRange.start, start.isNumeric,
           let now = playerItem?.currentTime(), now.isNumeric {
            let ahead = (start - now).seconds
            // Guard against a bogus timestamp: a title can't sit minutes away from playback.
            if abs(ahead) < 60 {
                sounding = Date().addingTimeInterval(ahead)
                playbackLog.notice("title timestamp is \(ahead, privacy: .public)s from playback")
            }
        }
        Task { await handleMetadata(items, sounding: sounding) }
    }
}
