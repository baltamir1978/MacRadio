import AVFoundation
import Combine
import Foundation
import os
import ShazamKit

private nonisolated let shazamLog = Logger(subsystem: "com.macradio.playback", category: "shazam")

/// A song recognised by ShazamKit.
struct ShazamMatch: Sendable {
    let title: String
    let artist: String?
    let artworkURL: URL?
    let appleMusicURL: URL?
    /// How far into the song the audio we heard was, at `matchedAt` — what lets the lyrics
    /// follow a song on a station that never says what it's playing.
    let offset: TimeInterval?
    let matchedAt: Date
}

/// Feeds decoded PCM to a ShazamKit session. Called from the audio render thread (tap) or the
/// decoder's queue, hence off the main actor. Buffers go through untouched: ShazamKit
/// resamples by itself, and converting per buffer here would break the fingerprint.
nonisolated final class StreamMatcher: @unchecked Sendable {
    // `@unchecked`: SHSession isn't Sendable, but it's only touched here and ShazamKit
    // documents `matchStreamingBuffer` as callable from any thread.
    let session: SHSession
    private let count = OSAllocatedUnfairLock(initialState: 0)

    /// PCM buffers fed so far — tells a starved tap from a genuine "no match".
    var bufferCount: Int { count.withLock { $0 } }

    init(delegate: SHSessionDelegate) {
        session = SHSession()
        session.delegate = delegate
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        count.withLock { $0 += 1 }
        session.matchStreamingBuffer(buffer, at: nil)
    }
}

/// Identifies the song on air from the stream itself — no microphone, so it works whatever
/// the output (speakers, headphones, AirPlay). Same two paths as RadioApp for iOS:
///
/// 1. A passive tap on the player's own item: the audio being heard, exactly.
/// 2. When a station's delivery starves the tap (redirect chains, tokenised URLs — Kiss FM),
///    a second connection decoded by `StreamDecoder`.
@MainActor
final class ShazamService: NSObject, ObservableObject, SHSessionDelegate {
    static let shared = ShazamService()

    @Published private(set) var isListening = false
    /// Why the last attempt found nothing, for the UI. Cleared by the next attempt.
    @Published private(set) var failure: String?
    /// Apple's Shazam service refused this app (error 202): ShazamKit isn't enabled for its
    /// App ID. Nothing to retry until it is, so identification stops asking.
    @Published private(set) var unavailable = false

    /// Where results go (the player). Set once at start-up.
    var onMatch: ((ShazamMatch, _ viaDecoder: Bool) -> Void)?
    var onNoMatch: (() -> Void)?

    private let listenWindow: TimeInterval = 12
    private static let minTapBuffers = 10

    private var matcher: StreamMatcher?
    private var usingTap = false
    private var decoder: StreamDecoder?
    private var timeoutTask: Task<Void, Never>?

    func identify() {
        guard !isListening, !unavailable else { return }
        let player = RadioPlayer.shared
        guard player.isPlaying, player.currentStation != nil else { return }
        failure = nil
        isListening = true
        shazamLog.notice("identifying via stream tap")
        let matcher = StreamMatcher(delegate: self)
        self.matcher = matcher
        usingTap = true
        player.beginStreamTap()
        player.streamSink.set { matcher.append($0) }
        startTimeout(listenWindow) { [weak self] in self?.tapTimedOut() }
    }

    func cancel() {
        guard isListening else { return }
        finish()
    }

    private func finish() {
        timeoutTask?.cancel()
        timeoutTask = nil
        if usingTap {
            RadioPlayer.shared.endStreamTap()
            usingTap = false
        }
        decoder?.stop()
        decoder = nil
        matcher = nil
        isListening = false
    }

    private func startTimeout(_ seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    /// No match within the window. If the tap got audio, the song just isn't known (or it's
    /// talk, or an ad); if it got next to nothing, try again over our own connection.
    private func tapTimedOut() {
        guard isListening, usingTap else { return }
        let delivered = matcher?.bufferCount ?? 0
        RadioPlayer.shared.endStreamTap()
        usingTap = false
        matcher = nil
        guard delivered < Self.minTapBuffers,
              let raw = RadioPlayer.shared.currentStation?.streamURL, let url = URL(string: raw) else {
            noMatch()
            return
        }
        shazamLog.notice("tap starved (\(delivered, privacy: .public) buffers) — decoding a second connection")
        let matcher = StreamMatcher(delegate: self)
        self.matcher = matcher
        let decoder = StreamDecoder(url: url) { matcher.append($0) }
        self.decoder = decoder
        decoder.start()
        // A little longer: the second connection has to buffer first.
        startTimeout(listenWindow + 4) { [weak self] in self?.noMatch() }
    }

    private func noMatch() {
        guard isListening else { return }
        shazamLog.notice("no match")
        failure = String(localized: "No se ha reconocido la canción")
        finish()
        onNoMatch?()
    }

    // MARK: SHSessionDelegate

    nonisolated func session(_ session: SHSession, didFind match: SHMatch) {
        guard let item = match.mediaItems.first else { return }
        let result = ShazamMatch(title: item.title ?? "", artist: item.artist,
                                 artworkURL: item.artworkURL, appleMusicURL: item.appleMusicURL,
                                 offset: item.predictedCurrentMatchOffset, matchedAt: Date())
        Task { @MainActor in
            guard self.isListening, !result.title.isEmpty else { return }
            let viaDecoder = self.decoder != nil
            shazamLog.notice("match: \(result.title, privacy: .public) at \(result.offset ?? -1, privacy: .public)s")
            if let decoder = self.decoder {
                shazamLog.notice("second connection: \(decoder.skippedBurst, privacy: .public)s of opening burst held back")
            }
            self.finish()
            self.onMatch?(result, viaDecoder)
        }
    }

    nonisolated func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: (any Error)?) {
        // A single unmatched signature is normal while streaming; the timeout decides. An
        // error, though, is worth seeing — it's how a missing ShazamKit service shows up.
        guard let error else { return }
        shazamLog.error("ShazamKit error: \(String(describing: error), privacy: .public)")
        if (error as NSError).domain == SHErrorDomain, (error as NSError).code == 202 {
            Task { @MainActor in
                guard !self.unavailable else { return }
                self.unavailable = true
                self.failure = String(localized: "Shazam no está disponible para MacRadio")
                self.finish()
            }
        }
    }
}
