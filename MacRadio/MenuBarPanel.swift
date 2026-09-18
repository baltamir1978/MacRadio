import SwiftUI

/// The mini player behind the menu bar icon: what's playing, the controls and the stations.
struct MenuBarPanel: View {
    @EnvironmentObject private var player: RadioPlayer
    @EnvironmentObject private var store: StationsStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            TransportBar(size: .compact).frame(maxWidth: .infinity)
            VolumeSlider()

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(store.stations) { station in
                        StationButton(station: station)
                    }
                }
            }
            .frame(maxHeight: 260)

            Divider()

            HStack {
                Button("Abrir MacRadio") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                Button("Ajustes…") {
                    openSettings()
                    NSApp.activate()
                }
                Button("Salir") { NSApp.terminate(nil) }
            }
            .buttonStyle(.link)
            .font(.callout)
        }
        .padding(14)
        .frame(width: 320)
    }

    @ViewBuilder
    private var header: some View {
        if let station = player.currentStation {
            HStack(spacing: 12) {
                CoverView(station: station, coverURL: player.currentArtworkURL)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTrack ?? station.name)
                        .font(.headline).lineLimit(2)
                    if let artist = player.currentArtist, !artist.isEmpty {
                        Text(artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text(station.name).font(.caption).foregroundStyle(Color.brand).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("Elige una emisora").font(.headline)
        }
    }
}

private struct StationButton: View {
    let station: Station
    @EnvironmentObject private var player: RadioPlayer

    private var isCurrent: Bool { player.currentStation?.streamURL == station.streamURL }

    var body: some View {
        Button { player.play(station) } label: {
            HStack(spacing: 8) {
                StationLogo(station: station, size: 22)
                Text(station.name).lineLimit(1)
                Spacer()
                if isCurrent && player.isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(Color.brand)
                        .accessibilityLabel(Text("Sonando"))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 6).fill(isCurrent ? Color.brand.opacity(0.14) : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Escuchar \(station.name)"))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
