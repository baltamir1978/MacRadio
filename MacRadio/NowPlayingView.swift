import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var player: RadioPlayer

    var body: some View {
        if let station = player.currentStation {
            HStack(alignment: .top, spacing: 32) {
                PlayerColumn(station: station).frame(width: 280)
                LyricsPanel().frame(minWidth: 240)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ContentUnavailableView {
                Label("Elige una emisora", systemImage: "radio")
            } description: {
                Text("Selecciona una emisora en la barra lateral para empezar a escucharla.")
            }
        }
    }
}

private struct PlayerColumn: View {
    let station: Station
    @EnvironmentObject private var player: RadioPlayer

    var body: some View {
        VStack(spacing: 18) {
            CoverView(station: station, coverURL: player.currentArtworkURL)
                .frame(width: 240, height: 240)

            VStack(spacing: 4) {
                Text(station.name.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brand)
                    .accessibilityLabel(Text(station.name))
                Text(player.currentTrack ?? station.name)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .textSelection(.enabled)
                if let artist = player.currentArtist, !artist.isEmpty {
                    Text(artist)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                }
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .accessibilityElement(children: .combine)

            TransportBar(size: .large)

            VolumeSlider()

            if let url = player.currentAppleMusicURL {
                Link("Abrir en Apple Music", destination: url)
                    .font(.callout)
            }
        }
    }

    private var statusText: LocalizedStringKey {
        if player.isReconnecting { return "Reconectando…" }
        if player.isLoading { return "Conectando…" }
        if !player.isPlaying { return "En pausa" }
        return player.currentTrack == nil ? "En directo · la emisora no dice qué suena" : "En directo"
    }
}

/// The album cover when there is one, else the station logo.
struct CoverView: View {
    let station: Station
    let coverURL: URL?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let coverURL {
                    AsyncImage(url: coverURL) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            StationLogo(station: station, size: geo.size.width)
                        }
                    }
                } else {
                    StationLogo(station: station, size: geo.size.width)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: geo.size.width * 0.06, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct TransportBar: View {
    enum Size { case large, compact }
    let size: Size
    @EnvironmentObject private var player: RadioPlayer
    /// Watched so the heart follows changes made in the history window.
    @ObservedObject private var history = HistoryStore.shared

    var body: some View {
        HStack(spacing: size == .large ? 28 : 18) {
            Button { player.playPrevious() } label: {
                Image(systemName: "backward.fill")
            }
            .help("Emisora anterior")
            .accessibilityLabel(Text("Emisora anterior"))

            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: size == .large ? 22 : 15, weight: .bold))
                    .foregroundStyle(Color.appBackground)
                    .frame(width: size == .large ? 56 : 36, height: size == .large ? 56 : 36)
                    .background(Circle().fill(Color.brand))
                    .contentShape(Circle())
            }
            .help(player.isPlaying ? Text("Pausar") : Text("Reproducir"))
            .accessibilityLabel(player.isPlaying ? Text("Pausar") : Text("Reproducir"))

            Button { player.playNext() } label: {
                Image(systemName: "forward.fill")
            }
            .help("Emisora siguiente")
            .accessibilityLabel(Text("Emisora siguiente"))
        }
        .overlay(alignment: .trailing) {
            // Beside the controls rather than among them, so play/pause stays centred.
            if player.historyEntryID != nil {
                let favorite = history.isFavorite(player.historyEntryID)
                Button { player.toggleFavorite() } label: {
                    Image(systemName: favorite ? "heart.fill" : "heart")
                }
                .help(favorite ? Text("Quitar de favoritas") : Text("Marcar como favorita"))
                .accessibilityLabel(favorite ? Text("Quitar de favoritas") : Text("Marcar como favorita"))
                .offset(x: size == .large ? 52 : 40)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: size == .large ? 20 : 14, weight: .semibold))
        .foregroundStyle(Color.brand)
    }
}

struct VolumeSlider: View {
    @EnvironmentObject private var player: RadioPlayer

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill").foregroundStyle(.secondary).accessibilityHidden(true)
            Slider(value: $player.volume, in: 0...1)
                .accessibilityLabel(Text("Volumen"))
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary).accessibilityHidden(true)
        }
        .font(.caption)
    }
}

// MARK: - Lyrics

private struct LyricsPanel: View {
    @EnvironmentObject private var player: RadioPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Letra")
                .font(.headline)
                .foregroundStyle(Color.brand)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        if player.currentTrack == nil {
            note("La letra aparece cuando la emisora dice qué canción suena.")
        } else if let lyrics = player.lyrics, lyrics.isInstrumental {
            note("Instrumental ♪")
        } else if let lyrics = player.lyrics, !lyrics.isEmpty {
            if !lyrics.synced.isEmpty, player.songStartIsExact, let start = player.songStartedAt {
                SyncedLyrics(lyrics: lyrics, start: start, reduceMotion: reduceMotion)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if !lyrics.synced.isEmpty {
                        Text("Has sintonizado a mitad de canción: la letra irá sincronizada desde la siguiente.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ScrollView {
                        Text(lyrics.lines.joined(separator: "\n"))
                            .font(.title3)
                            .lineSpacing(6)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        } else if player.lyricsPending {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Buscando la letra…").foregroundStyle(.secondary)
            }
        } else {
            note("No hay letra para esta canción.")
        }
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.title3).foregroundStyle(.secondary)
    }
}

/// Lyrics that follow the song: the line being sung is highlighted and kept in view.
private struct SyncedLyrics: View {
    let lyrics: SongLyrics
    let start: Date
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let current = lyrics.lineIndex(at: context.date.timeIntervalSince(start))
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(lyrics.synced.enumerated()), id: \.offset) { index, line in
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.title3.weight(index == current ? .bold : .regular))
                                .foregroundStyle(index == current ? AnyShapeStyle(.primary)
                                                 : (current.map { index < $0 } ?? false)
                                                    ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                                .id(index)
                                .accessibilityAddTraits(index == current ? .isSelected : [])
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 40)
                }
                .onChange(of: current) { _, index in
                    guard let index else { return }
                    if reduceMotion {
                        proxy.scrollTo(index, anchor: .center)
                    } else {
                        withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(index, anchor: .center) }
                    }
                }
            }
        }
    }
}
