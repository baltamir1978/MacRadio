import Foundation
import os

private nonisolated let introLog = Logger(subsystem: "com.macradio.playback", category: "intro")

/// Station intros: a fixed clip — usually ads — that some servers play to every listener who
/// connects, before the live programme. La Indie sends about 20 seconds of it, and again on
/// every reconnection.
///
/// An intro is a file, so it's the same bytes on every connection, while live audio never
/// repeats. Two connections opened a few seconds apart therefore agree exactly for the length
/// of the intro and not a byte further — that is how it's measured (`IntroLearner`). Once
/// known, the stream proxy recognises it by its first bytes and drops it (`IcyReframer`). The
/// server sends the intro at roughly twice real time, so skipping it costs a few seconds of
/// connecting instead of twenty seconds of ads.
nonisolated struct StreamIntro: Codable, Sendable {
    /// Audio bytes to drop; 0 records "this station has no intro".
    var length: Int
    /// The intro's first audio bytes, to recognise it before dropping anything.
    var prefix: Data
    var checkedAt: Date
}

/// What's known about each stream's intro, kept across launches.
nonisolated final class IntroRegistry: Sendable {
    static let shared = IntroRegistry()

    private let key = "stream_intros"
    private let intros: OSAllocatedUnfairLock<[String: StreamIntro]>
    /// A station found without an intro is looked at again after this long: stations add them.
    private let recheckAfter: TimeInterval = 3 * 24 * 3600

    private init() {
        let saved = UserDefaults.standard.data(forKey: "stream_intros")
            .flatMap { try? JSONDecoder().decode([String: StreamIntro].self, from: $0) } ?? [:]
        intros = OSAllocatedUnfairLock(initialState: saved)
    }

    /// The intro to skip for this stream, if one is known.
    func intro(for url: String) -> StreamIntro? {
        guard Self.skippingEnabled else { return nil }
        return intros.withLock { $0[url] }.flatMap { $0.length > 0 ? $0 : nil }
    }

    func needsLearning(_ url: String) -> Bool {
        guard let known = intros.withLock({ $0[url] }) else { return true }
        let age = Date().timeIntervalSince(known.checkedAt)
        // Intros are ads, and ads rotate: they all open with the same station jingle, so the
        // first bytes still match while the length changes. Measure again every hour.
        return known.length > 0 ? age > 3600 : age > recheckAfter
    }

    /// The user's choice in Settings.
    static var skippingEnabled: Bool {
        UserDefaults.standard.object(forKey: "skip_intros") as? Bool ?? true
    }

    func record(_ intro: StreamIntro, for url: String) {
        let all = intros.withLock { $0[url] = intro; return $0 }
        save(all)
    }

    /// The stream no longer starts the way we remembered: forget it and measure again.
    func forget(_ url: String) {
        let all = intros.withLock { $0[url] = nil; return $0 }
        save(all)
    }

    private func save(_ all: [String: StreamIntro]) {
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// Measures a stream's intro with two connections opened a few seconds apart.
nonisolated enum IntroLearner {
    private static let running = OSAllocatedUnfairLock<Set<String>>(initialState: [])
    /// Below this, two connections agreeing is just the frame header they both start with.
    private static let minimumIntro = 32 * 1024
    static let prefixLength = 8 * 1024

    /// Starts a measurement in the background unless one is known, recent or already running.
    static func learnIfNeeded(_ urlString: String) {
        guard IntroRegistry.shared.needsLearning(urlString), let url = URL(string: urlString),
              url.pathExtension.lowercased() != "m3u8",
              running.withLock({ $0.insert(urlString).inserted }) else { return }
        Task.detached(priority: .utility) {
            defer { _ = running.withLock { $0.remove(urlString) } }
            async let first = read(url, delay: 0)
            async let second = read(url, delay: 4)
            guard let a = await first, let b = await second else { return }
            let length = introLength(a, b)
            let intro = StreamIntro(length: length,
                                    prefix: length > 0 ? a.prefix(prefixLength) : Data(),
                                    checkedAt: Date())
            IntroRegistry.shared.record(intro, for: urlString)
            introLog.notice("\(urlString, privacy: .public): intro of \(length, privacy: .public) bytes")
        }
    }

    /// Where two captures of the same stream stop agreeing. The live audio right after an
    /// intro starts with the same frame-header bytes the intro's frames have, so the raw
    /// agreement runs a few bytes into the first live frame; the cut goes back to its sync word.
    static func introLength(_ a: Data, _ b: Data) -> Int {
        let a = [UInt8](a), b = [UInt8](b)
        var n = 0
        let limit = min(a.count, b.count)
        while n < limit && a[n] == b[n] { n += 1 }
        // Agreeing all the way to the end means one capture was cut short, not an intro.
        guard n >= minimumIntro, n < limit else { return 0 }
        for i in stride(from: n, through: max(0, n - 8), by: -1) where i + 1 < a.count {
            if a[i] == 0xFF && (a[i + 1] & 0xE0) == 0xE0 { return i }
        }
        return n
    }

    /// Up to 1.5 MB or 30 seconds of raw audio, without ICY metadata so the bytes compare.
    private static func read(_ url: URL, delay: UInt64) async -> Data? {
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        var request = URLRequest(url: url)
        request.setValue("MacRadio/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        guard let (bytes, response) = try? await URLSession.shared.bytes(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else { return nil }
        var data = Data()
        data.reserveCapacity(1_500_000)
        let deadline = Date().addingTimeInterval(30)
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count >= 1_500_000 || (data.count % 16_384 == 0 && Date() > deadline) { break }
            }
        } catch {
            return data.isEmpty ? nil : data
        }
        return data
    }
}

/// Drops a known intro from a stream on its way to the player.
///
/// ICY streams interleave a metadata block every `metaint` audio bytes, and the player counts
/// those bytes from the start of the connection. Cutting audio out of the front would put every
/// later block in the wrong place and lose the song titles, so the stream is taken apart and
/// framed again: audio and metadata are separated on the way in, the intro's audio is dropped,
/// and the rest goes out with fresh framing at the same interval, carrying the latest title.
///
/// Nothing is dropped until the stream's first bytes match the remembered intro; if they don't,
/// everything is passed on untouched and `mismatch` is set so the intro gets measured again.
nonisolated struct IcyReframer {
    private let metaint: Int
    private let intro: StreamIntro

    private var inAudioLeft: Int
    private var inMetaLeft = -1
    private var inMeta = Data()

    private var outAudioSinceMeta = 0
    private var pendingMeta: Data?

    private var checking = true
    private var held = Data()
    private var toSkip: Int
    private(set) var mismatch = false
    private(set) var skipped = false

    init(metaint: Int, intro: StreamIntro) {
        self.metaint = metaint
        self.intro = intro
        inAudioLeft = metaint
        toSkip = intro.length
    }

    mutating func feed(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        var out = Data()
        var i = 0
        while i < bytes.count {
            if metaint > 0 && inMetaLeft >= 0 {
                let n = min(inMetaLeft, bytes.count - i)
                inMeta.append(contentsOf: bytes[i..<i + n])
                inMetaLeft -= n
                i += n
                if inMetaLeft == 0 {
                    pendingMeta = inMeta
                    inMetaLeft = -1
                    inAudioLeft = metaint
                }
            } else if metaint > 0 && inAudioLeft == 0 {
                let length = Int(bytes[i]) * 16
                i += 1
                if length == 0 {
                    inAudioLeft = metaint
                } else {
                    inMeta = Data([bytes[i - 1]])
                    inMetaLeft = length
                }
            } else {
                let n = metaint > 0 ? min(inAudioLeft, bytes.count - i) : bytes.count - i
                audio(Data(bytes[i..<i + n]), into: &out)
                i += n
                if metaint > 0 { inAudioLeft -= n }
            }
        }
        return out
    }

    private mutating func audio(_ chunk: Data, into out: inout Data) {
        if checking {
            held.append(chunk)
            guard held.count >= intro.prefix.count else { return }
            checking = false
            let waiting = held
            held = Data()
            if waiting.prefix(intro.prefix.count) == intro.prefix {
                skipped = true
                drop(waiting, into: &out)
            } else {
                mismatch = true
                toSkip = 0
                emit(waiting, into: &out)
            }
            return
        }
        drop(chunk, into: &out)
    }

    private mutating func drop(_ chunk: Data, into out: inout Data) {
        guard toSkip > 0 else { return emit(chunk, into: &out) }
        let n = min(toSkip, chunk.count)
        toSkip -= n
        if n < chunk.count { emit(chunk.dropFirst(n), into: &out) }
    }

    private mutating func emit(_ audio: Data, into out: inout Data) {
        guard metaint > 0 else { return out.append(audio) }
        var rest = audio[...]
        while !rest.isEmpty {
            let n = min(metaint - outAudioSinceMeta, rest.count)
            out.append(rest.prefix(n))
            rest = rest.dropFirst(n)
            outAudioSinceMeta += n
            if outAudioSinceMeta == metaint {
                out.append(pendingMeta ?? Data([0]))
                pendingMeta = nil
                outAudioSinceMeta = 0
            }
        }
    }
}
