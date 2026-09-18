import SwiftUI

/// Finds stations in the public Radio Browser directory and adds them to the list.
struct StationSearchView: View {
    @EnvironmentObject private var store: StationsStore
    @EnvironmentObject private var player: RadioPlayer
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var country = Locale.current.region?.identifier ?? "ES"
    @State private var results: [RadioBrowserStation] = []
    @State private var isSearching = false
    @State private var failed = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("Nombre de la emisora", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(search)
                TextField("País", text: $country, prompt: Text(verbatim: "ES"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .help("Código de país de dos letras. Déjalo vacío para buscar en todo el mundo.")
                Button("Buscar", action: search)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            Group {
                if isSearching {
                    ProgressView("Buscando…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if failed {
                    ContentUnavailableView("No se pudo buscar", systemImage: "wifi.exclamationmark",
                                           description: Text("Comprueba la conexión y vuelve a intentarlo."))
                } else if results.isEmpty {
                    ContentUnavailableView("Busca emisoras", systemImage: "magnifyingglass",
                                           description: Text("Más de 50.000 emisoras de todo el mundo, del directorio Radio Browser."))
                } else {
                    List(results) { result in
                        ResultRow(result: result)
                    }
                }
            }
            .frame(minHeight: 320)

            Divider()
            HStack {
                Spacer()
                Button("Listo") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 560, height: 480)
        .task { await load(top: true) }
    }

    private func search() {
        searchTask?.cancel()
        searchTask = Task { await load(top: query.trimmingCharacters(in: .whitespaces).isEmpty) }
    }

    private func load(top: Bool) async {
        isSearching = true
        failed = false
        defer { isSearching = false }
        let code = country.trimmingCharacters(in: .whitespaces).uppercased()
        do {
            results = top
                ? try await RadioBrowserService.shared.topStations(country: code)
                : try await RadioBrowserService.shared.search(name: query, country: code)
        } catch is CancellationError {
        } catch {
            failed = true
        }
    }
}

private struct ResultRow: View {
    let result: RadioBrowserStation
    @EnvironmentObject private var store: StationsStore
    @EnvironmentObject private var player: RadioPlayer

    var body: some View {
        let station = result.toStation
        let added = store.contains(station)
        HStack(spacing: 10) {
            StationLogo(station: station, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(station.name).lineLimit(1)
                if !station.detail.isEmpty {
                    Text(station.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Button("Probar") { player.play(station) }
                .help("Escúchala sin añadirla")
            Button(added ? LocalizedStringKey("Añadida") : "Añadir") { store.add(station) }
                .disabled(added)
        }
        .padding(.vertical, 2)
    }
}
