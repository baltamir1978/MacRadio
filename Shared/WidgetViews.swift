import AppIntents
import AppKit
import SwiftUI
import WidgetKit

// The widget's views live here, compiled into the app as well as the extension, so the app can
// render them offscreen (`--render-widgets`) and the layout can be checked without placing a
// widget on the desktop by hand.

nonisolated struct RadioEntry: TimelineEntry {
    let date: Date
    let snapshot: NowPlayingSnapshot?
    /// Stations offered as buttons, already filtered by the widget's configuration.
    let stations: [SharedStation]
    /// Line of the synced lyrics being sung at `date`, if known.
    let lyricIndex: Int?
}

extension RadioEntry {
    /// What the widget gallery shows before the app has ever run.
    static var sample: RadioEntry {
        let stations = ["Cadena 100", "Kiss FM", "La Indie", "Cassette FM", "Los 40 Classic"].map {
            SharedStation(name: $0, streamURL: "sample://\($0)", logoFile: nil, initials: initials(of: $0))
        }
        let lyrics = SongLyrics(synced: [
            LyricLine(time: 0, text: "♪"),
            LyricLine(time: 4, text: String(localized: "Aquí va la letra de la canción")),
            LyricLine(time: 8, text: String(localized: "que suena en la radio,")),
            LyricLine(time: 12, text: String(localized: "línea a línea, a su ritmo")),
        ], plain: [], isInstrumental: false)
        let snapshot = NowPlayingSnapshot(stationName: "Cadena 100", streamURL: "sample://Cadena 100",
                                          track: String(localized: "Canción en directo"),
                                          artist: String(localized: "Artista"),
                                          artworkFile: nil, artworkIsCover: false,
                                          isPlaying: true, isLoading: false,
                                          songStartedAt: nil, songStartIsExact: false,
                                          lyrics: lyrics, lyricsPending: false, isFavorite: false, isIdentifying: false)
        return RadioEntry(date: Date(), snapshot: snapshot, stations: stations, lyricIndex: 1)
    }
}

struct RadioWidgetView: View {
    let entry: RadioEntry
    let family: WidgetFamily

    var body: some View {
        Group {
            switch family {
            case .systemSmall: SmallLayout(entry: entry)
            case .systemMedium: MediumLayout(entry: entry)
            case .systemExtraLarge: ExtraLargeLayout(entry: entry)
            default: LargeLayout(entry: entry)
            }
        }
        .containerBackground(for: .widget) { Color.appBackground }
        .widgetURL(URL(string: "macradio://open"))
    }
}

// MARK: - Layouts

private struct SmallLayout: View {
    let entry: RadioEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                ArtworkView(snapshot: entry.snapshot, size: 64)
                Spacer(minLength: 4)
                PlayPauseButton(isPlaying: entry.snapshot?.isPlaying ?? false, size: 30)
            }
            Spacer(minLength: 0)
            SongText(snapshot: entry.snapshot, titleFont: .system(size: 13, weight: .semibold), titleLines: 2,
                     saysPaused: true)
        }
    }
}

private struct MediumLayout: View {
    let entry: RadioEntry

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(snapshot: entry.snapshot, size: 132)
            VStack(alignment: .leading, spacing: 0) {
                StatusLine(snapshot: entry.snapshot)
                SongText(snapshot: entry.snapshot, titleFont: .system(size: 15, weight: .semibold), titleLines: 2)
                    .padding(.top, 3)
                Spacer(minLength: 6)
                HStack(spacing: 6) {
                    PlayPauseButton(isPlaying: entry.snapshot?.isPlaying ?? false, size: 30)
                    ForEach(entry.stations.prefix(4)) { station in
                        StationButton(station: station, current: entry.snapshot?.streamURL, size: 28)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LargeLayout: View {
    let entry: RadioEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ArtworkView(snapshot: entry.snapshot, size: 112)
                VStack(alignment: .leading, spacing: 0) {
                    StatusLine(snapshot: entry.snapshot)
                    SongText(snapshot: entry.snapshot, titleFont: .system(size: 15, weight: .semibold), titleLines: 2)
                        .padding(.top, 3)
                    Spacer(minLength: 4)
                    TransportControls(isPlaying: entry.snapshot?.isPlaying ?? false, favorite: favoriteState(entry.snapshot))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 112)

            LyricsBlock(entry: entry, maxLines: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            StationStrip(stations: Array(entry.stations.prefix(7)), current: entry.snapshot?.streamURL, size: 36)
        }
    }
}

private struct ExtraLargeLayout: View {
    let entry: RadioEntry

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    ArtworkView(snapshot: entry.snapshot, size: 128)
                    VStack(alignment: .leading, spacing: 0) {
                        StatusLine(snapshot: entry.snapshot)
                        SongText(snapshot: entry.snapshot, titleFont: .system(size: 17, weight: .semibold), titleLines: 3)
                            .padding(.top, 4)
                        Spacer(minLength: 4)
                        TransportControls(isPlaying: entry.snapshot?.isPlaying ?? false, favorite: favoriteState(entry.snapshot))
                    }
                }
                .frame(height: 128)
                Spacer(minLength: 0)
                StationGrid(stations: Array(entry.stations.prefix(8)), current: entry.snapshot?.streamURL)
            }
            .frame(width: 330)

            Divider()

            LyricsBlock(entry: entry, maxLines: 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Pieces

/// Album cover or station logo, filling the tile. With nothing playing — the app closed, or
/// paused — the app's own icon takes the place, so the last song doesn't linger.
struct ArtworkView: View {
    let snapshot: NowPlayingSnapshot?
    let size: CGFloat

    var body: some View {
        let image = SharedStore.imageURL(named: snapshot?.artworkFile).flatMap(NSImage.init(contentsOf:))
        ZStack {
            if let snapshot, snapshot.isPlaying {
                if let image {
                    LogoImage(image: image)
                } else {
                    InitialsTile(name: snapshot.stationName, size: size)
                }
            } else {
                Image("AppArtwork").resizable().widgetAccentedRenderingMode(.fullColor)
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A cover or logo edge to edge, as the station draws it. A square one fills the tile; a wide
/// or tall one is fitted whole rather than cropped, on white. A logo with a transparent
/// background has no edge of its own, so it gets a little air, and a dark backing when it is
/// drawn in light colours (Kiss FM's white lettering would vanish on white).
private struct LogoImage: View {
    let image: NSImage

    var body: some View {
        let ratio = image.size.height > 0 ? image.size.width / image.size.height : 1
        let look = LogoLook(image)
        let fills = !look.isTransparent && (0.8...1.25).contains(ratio)
        GeometryReader { proxy in
            ZStack {
                look.isLight ? Color(white: 0.1) : Color.white
                Image(nsImage: image).resizable().widgetAccentedRenderingMode(.fullColor)
                    .aspectRatio(contentMode: fills ? .fill : .fit)
                    .padding(look.isTransparent ? proxy.size.width * 0.08 : 0)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

/// What a logo looks like, from a 24×24 sample: whether much of it is see-through, and whether
/// what isn't is mostly near-white.
private struct LogoLook {
    var isTransparent = false
    var isLight = false

    init(_ image: NSImage) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let n = 24
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: n, height: n, bitsPerComponent: 8,
                                      bytesPerRow: n * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        guard drawn else { return }
        var clear = 0, opaque = 0, light = 0
        for i in 0..<(n * n) {
            let a = Double(pixels[i * 4 + 3]) / 255
            if a < 0.5 { clear += 1; continue }
            opaque += 1
            let r = Double(pixels[i * 4]) / 255 / a
            let g = Double(pixels[i * 4 + 1]) / 255 / a
            let b = Double(pixels[i * 4 + 2]) / 255 / a
            if 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.85 { light += 1 }
        }
        isTransparent = clear * 10 > n * n
        isLight = isTransparent && light * 4 > opaque
    }
}

private struct InitialsTile: View {
    let name: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Color.tile(for: name)
            Text(initials(of: name))
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
        }
    }
}

private struct StatusLine: View {
    let snapshot: NowPlayingSnapshot?

    var body: some View {
        HStack(spacing: 4) {
            if let snapshot, !snapshot.isPlaying {
                // The station's name is right below, where the song would be.
                Image(systemName: "pause.fill").font(.system(size: 9, weight: .bold))
                Text("En pausa").lineLimit(1)
            } else if let snapshot {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 9, weight: .bold))
                Text(snapshot.stationName).lineLimit(1)
                Text("·")
                Text(statusText(snapshot)).lineLimit(1).layoutPriority(-1)
            } else {
                Image(systemName: "radio").font(.system(size: 9, weight: .bold))
                Text("MacRadio")
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.brand)
    }

    private func statusText(_ s: NowPlayingSnapshot) -> LocalizedStringKey {
        s.isLoading ? "Conectando…" : "En directo"
    }
}

private struct SongText: View {
    let snapshot: NowPlayingSnapshot?
    let titleFont: Font
    let titleLines: Int
    /// Says «En pausa» under the station when paused; the sizes with a status line already do.
    var saysPaused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let snapshot, !snapshot.isPlaying {
                // Paused or the app closed: the station the ▶︎ button would bring back.
                Text(snapshot.stationName)
                    .font(titleFont)
                    .lineLimit(titleLines)
                if saysPaused {
                    Text("En pausa")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else if let snapshot, snapshot.hasSong {
                Text(snapshot.track ?? "")
                    .font(titleFont)
                    .lineLimit(titleLines)
                if let artist = snapshot.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else if let snapshot {
                Text(snapshot.stationName)
                    .font(titleFont)
                    .lineLimit(titleLines)
                Text(snapshot.isIdentifying ? "Identificando la canción…" : "Sin datos de la canción")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Elige una emisora")
                    .font(titleFont)
                    .lineLimit(titleLines)
            }
        }
    }
}

private struct PlayPauseButton: View {
    let isPlaying: Bool
    let size: CGFloat
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Button(intent: TogglePlaybackIntent()) {
            let glyph = Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .frame(width: size, height: size)
            if renderingMode == .fullColor {
                glyph
                    .foregroundStyle(Color.appBackground)
                    .background(Circle().fill(Color.brand))
            } else {
                // On the desktop out of focus (vibrant) or with a tinted or clear appearance
                // (accented), the system recolours everything alike: a glyph drawn on a filled
                // circle comes out white on white. A faint disc keeps the button's shape.
                glyph
                    .foregroundStyle(.primary)
                    .background(Circle().fill(.primary.opacity(0.18)))
                    .widgetAccentable()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? Text("Pausar") : Text("Reproducir"))
    }
}

/// The heart only means something while the station names a song.
private func favoriteState(_ snapshot: NowPlayingSnapshot?) -> Bool? {
    guard let snapshot, snapshot.isPlaying, snapshot.hasSong else { return nil }
    return snapshot.isFavorite
}

private struct TransportControls: View {
    let isPlaying: Bool
    /// nil hides the heart.
    let favorite: Bool?

    var body: some View {
        HStack(spacing: 14) {
            Button(intent: PreviousStationIntent()) {
                Image(systemName: "backward.fill").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.brand)
            .accessibilityLabel(Text("Emisora anterior"))

            PlayPauseButton(isPlaying: isPlaying, size: 32)

            Button(intent: NextStationIntent()) {
                Image(systemName: "forward.fill").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.brand)
            .accessibilityLabel(Text("Emisora siguiente"))

            if favorite == nil, isPlaying {
                Button(intent: IdentifySongIntent()) {
                    Image(systemName: "shazam.logo").font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.brand)
                .accessibilityLabel(Text("Identificar la canción"))
            }
            if let favorite {
                Button(intent: ToggleFavoriteIntent()) {
                    Image(systemName: favorite ? "heart.fill" : "heart").font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.brand)
                .accessibilityLabel(favorite ? Text("Quitar de favoritas") : Text("Marcar como favorita"))
            }
        }
    }
}

private struct StationButton: View {
    let station: SharedStation
    let current: String?
    let size: CGFloat

    private var isCurrent: Bool { station.streamURL == current }

    var body: some View {
        Button(intent: PlayStationIntent(station: StationEntity(id: station.streamURL, name: station.name))) {
            StationLogoTile(station: station, size: size)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .strokeBorder(Color.brand, lineWidth: isCurrent ? 2.5 : 0)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Escuchar \(station.name)"))
    }
}

private struct StationLogoTile: View {
    let station: SharedStation
    let size: CGFloat

    var body: some View {
        ZStack {
            if let image = SharedStore.imageURL(named: station.logoFile).flatMap(NSImage.init(contentsOf:)) {
                LogoImage(image: image)
            } else {
                InitialsTile(name: station.name, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

/// A row of station buttons that spreads out to the widget's width.
private struct StationStrip: View {
    let stations: [SharedStation]
    let current: String?
    let size: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                if index > 0 { Spacer(minLength: 4) }
                StationButton(station: station, current: current, size: size)
            }
            if stations.count < 2 { Spacer(minLength: 0) }
        }
    }
}

/// Two rows of four, with names — the extra-large widget has room for them.
private struct StationGrid: View {
    let stations: [SharedStation]
    let current: String?

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(stations) { station in
                VStack(spacing: 3) {
                    StationButton(station: station, current: current, size: 44)
                    Text(station.name)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(station.streamURL == current ? Color.brand : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Lyrics

/// The lyrics window: the line being sung, one before it and the ones coming up.
///
/// A widget can't scroll or animate, so the timeline carries one entry per synced line and
/// each entry is drawn with its own `lyricIndex` — the window steps along as the song plays.
struct LyricsBlock: View {
    let entry: RadioEntry
    let maxLines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 0) {
                Label("Letra", systemImage: "quote.bubble")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.brand)
                    .textCase(.uppercase)
                Spacer(minLength: 8)
                if let snapshot = entry.snapshot, snapshot.isPlaying, isFollowing(snapshot) {
                    LyricsAdjuster(offset: snapshot.lyricsOffset ?? 0)
                }
            }
            content
        }
    }

    /// Whether the lyrics run on the song's clock, so moving them makes sense (as in the app).
    private func isFollowing(_ snapshot: NowPlayingSnapshot) -> Bool {
        snapshot.hasSong && snapshot.songStartIsExact && !(snapshot.lyrics?.synced.isEmpty ?? true)
    }

    @ViewBuilder
    private var content: some View {
        if entry.snapshot?.isPlaying != true {
            // Nothing playing: blank, rather than the words of the last song.
            EmptyView()
        } else if let snapshot = entry.snapshot, snapshot.hasSong {
            if let lyrics = snapshot.lyrics, lyrics.isInstrumental {
                note("Instrumental ♪")
            } else if let lyrics = snapshot.lyrics, !lyrics.isEmpty {
                lines(lyrics)
            } else if snapshot.lyricsPending {
                note("Buscando la letra…")
            } else {
                note("No hay letra para esta canción.")
            }
        } else {
            note("La letra aparece cuando la emisora dice qué canción suena.")
        }
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func lines(_ lyrics: SongLyrics) -> some View {
        let all = lyrics.lines
        let current = entry.lyricIndex
        // Keep one sung line above the current one for context.
        let first = max(0, min((current ?? 0) - 1, all.count - maxLines))
        let window = Array(all.enumerated()).dropFirst(first).prefix(maxLines)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(window), id: \.offset) { index, text in
                let isCurrent = index == current
                let isPast = current.map { index < $0 } ?? false
                let line = Text(text.isEmpty ? "♪" : text)
                    .font(.system(size: isCurrent ? 14 : 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? AnyShapeStyle(Color.primary)
                                     : isPast ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                    .lineLimit(isCurrent ? 2 : 1)
                if lyrics.synced.isEmpty {
                    line
                } else {
                    // As in the app: clicking the line being sung puts the lyrics in step.
                    Button(intent: SyncLyricsIntent(line: index)) { line }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("Sincroniza la letra con esta línea"))
                }
            }
        }
    }
}

/// − / + for the lyrics of this station, half a second at a time, as next to «Letra» in the app.
private struct LyricsAdjuster: View {
    let offset: Double

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: NudgeLyricsIntent(seconds: -0.5)) {
                Image(systemName: "minus").frame(width: 18, height: 16).contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Retrasar la letra"))
            if offset == 0 {
                label
            } else {
                // Clicking the figure puts it back to ±0, as the ↺ button in the app does.
                Button(intent: ResetLyricsIntent()) { label }
                    .accessibilityHint(Text("Pone la letra a cero"))
            }
            Button(intent: NudgeLyricsIntent(seconds: 0.5)) {
                Image(systemName: "plus").frame(width: 18, height: 16).contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Adelantar la letra"))
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.brand)
    }

    private var label: some View {
        Text(offsetText)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("Ajuste de la letra: \(offsetText)"))
    }

    private var offsetText: String {
        offset == 0 ? "±0 s"
            : offset.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())) + " s"
    }
}
