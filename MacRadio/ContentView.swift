import SwiftUI

/// Main window: stations in the sidebar, what's playing (and its lyrics) in the detail.
/// Standard split view, list and toolbar only — on macOS 27 the system draws the edge-to-edge
/// sidebar, the toolbar and its scroll edge; custom backgrounds there would fight it.
struct ContentView: View {
    @EnvironmentObject private var player: RadioPlayer
    @EnvironmentObject private var store: StationsStore

    @State private var selection: String?
    @State private var editing: Station?
    @State private var addingStation = false
    @State private var searching = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            NowPlayingView()
                .frame(minWidth: 620, minHeight: 540)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { openWindow(id: "history") } label: {
                    Label("Historial", systemImage: "clock.arrow.circlepath")
                }
                .help("Historial de canciones (⌘Y)")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Buscar emisoras…") { searching = true }
                    Button("Añadir una emisora a mano…") { addingStation = true }
                } label: {
                    Label("Añadir emisora", systemImage: "plus")
                }
                .help("Añadir emisora")
            }
        }
        .sheet(isPresented: $searching) { StationSearchView() }
        .sheet(isPresented: $addingStation) { StationEditor(station: nil) }
        .sheet(item: $editing) { StationEditor(station: $0) }
        .onKeyPress(.space) {
            player.togglePlayPause()
            return .handled
        }
        .onOpenURL(perform: handleURL)
        .onAppear { selection = player.currentStation?.streamURL }
        .onChange(of: player.currentStation?.streamURL) { _, url in
            if selection != url { selection = url }
        }
        .onChange(of: selection) { _, url in
            guard let url, url != player.currentStation?.streamURL,
                  let station = store.station(streamURL: url) else { return }
            player.play(station)
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Mis emisoras") {
                ForEach(store.stations) { station in
                    StationRow(station: station)
                        .tag(station.streamURL)
                        .contextMenu {
                            Button("Reproducir") { player.play(station) }
                            Button("Editar…") { editing = station }
                            Divider()
                            Button("Eliminar", role: .destructive) { store.remove(station) }
                        }
                }
                .onMove { store.move(from: $0, to: $1) }
            }
        }
        .onDeleteCommand {
            if let url = selection, let station = store.station(streamURL: url) { store.remove(station) }
        }
        .overlay {
            if store.stations.isEmpty {
                ContentUnavailableView {
                    Label("Sin emisoras", systemImage: "radio")
                } description: {
                    Text("Busca emisoras o añade una con su dirección de stream.")
                } actions: {
                    Button("Buscar emisoras…") { searching = true }
                }
            }
        }
    }

    /// `macradio://play?u=<stream URL>` plays that station; anything else just opens the window.
    private func handleURL(_ url: URL) {
        guard url.scheme == "macradio", url.host == "play",
              let stream = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "u" })?.value,
              let station = store.station(streamURL: stream) else { return }
        player.play(station)
    }
}

private struct StationRow: View {
    let station: Station
    @EnvironmentObject private var player: RadioPlayer

    private var isCurrent: Bool { player.currentStation?.streamURL == station.streamURL }

    var body: some View {
        HStack(spacing: 10) {
            StationLogo(station: station, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(station.name).lineLimit(1)
                if !station.detail.isEmpty {
                    Text(station.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if isCurrent && player.isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(Color.brand)
                    .symbolEffect(.variableColor.iterative, isActive: !player.isLoading)
                    .accessibilityLabel(Text("Sonando"))
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// A station's logo on white, or its initials on a colour tile when there's no logo.
struct StationLogo: View {
    let station: Station
    let size: CGFloat

    var body: some View {
        Group {
            if let logo = station.logoURL, let url = URL(string: logo) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        ZStack {
                            Color.white
                            image.resizable().aspectRatio(contentMode: .fit).padding(size * 0.06)
                        }
                    } else {
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        // Decorative: the station's name always sits right next to it.
        .accessibilityHidden(true)
    }

    private var initials: some View {
        ZStack {
            Color.tile(for: station.name)
            Text(station.initials)
                .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
        }
    }
}
