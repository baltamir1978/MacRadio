import AppKit
import SwiftUI

/// The songs heard, day by day, with the favorites a click away. Double-click (or Return)
/// tunes back into the station a song was heard on.
struct HistoryView: View {
    @ObservedObject private var history = HistoryStore.shared
    @EnvironmentObject private var player: RadioPlayer
    @EnvironmentObject private var store: StationsStore

    private enum Filter: Hashable { case all, favorites }

    @State private var filter = Filter.all
    @State private var query = ""
    @State private var selection = Set<UUID>()
    @State private var confirmingClear = false
    @State private var showingIgnored = false

    private var visible: [ListenedSong] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return history.songs.filter { song in
            (filter == .all || song.favorite) &&
            (q.isEmpty || [song.title, song.artist ?? "", song.stationName]
                .contains { $0.localizedStandardContains(q) })
        }
    }

    private var days: [(day: Date, songs: [ListenedSong])] {
        let calendar = Calendar.current
        var result: [(day: Date, songs: [ListenedSong])] = []
        for song in visible {
            let day = calendar.startOfDay(for: song.listenedAt)
            if result.last?.day == day {
                result[result.count - 1].songs.append(song)
            } else {
                result.append((day, [song]))
            }
        }
        return result
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(days, id: \.day) { group in
                Section {
                    ForEach(group.songs) { song in
                        HistoryRow(song: song).tag(song.id)
                    }
                } header: {
                    Text(group.day, format: .dateTime.weekday(.wide).day().month(.wide))
                }
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            menu(for: ids)
        } primaryAction: { ids in
            if let song = songs(ids).first { play(stationOf: song) }
        }
        .onDeleteCommand { history.delete(selection) }
        .searchable(text: $query, placement: .toolbar, prompt: Text("Buscar en el historial"))
        .overlay { emptyState }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mostrar", selection: $filter) {
                    Text("Todas").tag(Filter.all)
                    Text("Favoritas").tag(Filter.favorites)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItem {
                Menu {
                    Button("Títulos ignorados…") { showingIgnored = true }
                    Divider()
                    Button("Vaciar historial…", role: .destructive) { confirmingClear = true }
                        .disabled(history.songs.allSatisfy(\.favorite))
                } label: {
                    Label("Más", systemImage: "ellipsis")
                }
                .help("Más opciones")
            }
        }
        .confirmationDialog("¿Vaciar el historial?", isPresented: $confirmingClear) {
            Button("Vaciar", role: .destructive) { history.clearNonFavorites() }
        } message: {
            Text("Se borran todas las canciones menos las favoritas.")
        }
        .sheet(isPresented: $showingIgnored) { IgnoredTitlesView() }
        .frame(minWidth: 460, minHeight: 360)
    }

    @ViewBuilder
    private var emptyState: some View {
        if visible.isEmpty {
            if !query.isEmpty {
                ContentUnavailableView.search(text: query)
            } else if filter == .favorites {
                ContentUnavailableView("Sin favoritas", systemImage: "heart",
                                       description: Text("Pulsa el corazón mientras suena una canción para guardarla aquí."))
            } else {
                ContentUnavailableView("El historial está vacío", systemImage: "music.note.list",
                                       description: Text("Las canciones que suenen en tus emisoras irán apareciendo aquí."))
            }
        }
    }

    /// Menu items without icons, as macOS 27 asks of context menus.
    @ViewBuilder
    private func menu(for ids: Set<UUID>) -> some View {
        let picked = songs(ids)
        if picked.count == 1, let song = picked.first {
            Button(song.favorite ? "Quitar de favoritas" : "Marcar como favorita") {
                history.toggleFavorite(song.id)
            }
            if store.stations.contains(where: { $0.name == song.stationName }) {
                Button("Escuchar \(song.stationName)") { play(stationOf: song) }
            }
            if let raw = song.appleMusicURL, let url = URL(string: raw) {
                Button("Abrir en Apple Music") { NSWorkspace.shared.open(url) }
            }
            Button("Copiar título y artista") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString([song.title, song.artist].compactMap { $0 }.joined(separator: " — "),
                                               forType: .string)
            }
            Divider()
        }
        if !picked.isEmpty {
            Button("Eliminar", role: .destructive) { history.delete(ids) }
        }
        if picked.count == 1, let song = picked.first, !song.favorite {
            Button("No volver a guardar este título en \(song.stationName)", role: .destructive) {
                history.ignoreAndPurge(song)
            }
        }
    }

    private func songs(_ ids: Set<UUID>) -> [ListenedSong] {
        history.songs.filter { ids.contains($0.id) }
    }

    private func play(stationOf song: ListenedSong) {
        if let station = store.stations.first(where: { $0.name == song.stationName }) {
            player.play(station)
        }
    }
}

// MARK: - Row

private struct HistoryRow: View {
    let song: ListenedSong

    var body: some View {
        HStack(spacing: 12) {
            artwork
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).fontWeight(.semibold).lineLimit(1)
                if let artist = song.artist, !artist.isEmpty {
                    Text(artist).foregroundStyle(.secondary).lineLimit(1)
                }
                Text("\(song.stationName) · \(song.listenedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            Button {
                HistoryStore.shared.toggleFavorite(song.id)
            } label: {
                Image(systemName: song.favorite ? "heart.fill" : "heart")
                    .foregroundStyle(song.favorite ? AnyShapeStyle(Color.brand) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)
            .help(song.favorite ? Text("Quitar de favoritas") : Text("Marcar como favorita"))
            .accessibilityLabel(song.favorite ? Text("Quitar de favoritas") : Text("Marcar como favorita"))
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var artwork: some View {
        if let raw = song.artworkURL, let url = URL(string: raw) {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() } else { placeholder }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.mintSurface
            Image(systemName: "music.note").foregroundStyle(Color.brand)
        }
    }
}

// MARK: - Ignored titles

/// The titles kept out of the history, with a way back for each.
private struct IgnoredTitlesView: View {
    @ObservedObject private var history = HistoryStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Títulos ignorados").font(.title2.weight(.semibold))
            Text("Las emisoras mandan a veces su eslogan como si fuera una canción. Estos títulos no se guardan en el historial.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach(history.ignored) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.title).lineLimit(1)
                            Text(entry.stationName).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Volver a guardar") { history.unignore(entry) }
                    }
                }
            }
            .overlay {
                if history.ignored.isEmpty {
                    ContentUnavailableView("Ningún título ignorado", systemImage: "nosign")
                }
            }
            .frame(minHeight: 200)

            HStack {
                Spacer()
                Button("Listo") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 420)
    }
}
