import SwiftUI

/// Adds a station by hand, or edits one (`station` non-nil).
struct StationEditor: View {
    let station: Station?
    @EnvironmentObject private var store: StationsStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var streamURL = ""
    @State private var logoURL = ""
    @State private var genre = ""
    @State private var country = ""

    private var trimmedStream: String { streamURL.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var streamIsValid: Bool {
        guard let url = URL(string: trimmedStream), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https"].contains(scheme) && url.host != nil
    }

    private var isDuplicate: Bool {
        store.stations.contains { $0.streamURL == trimmedStream && $0.id != station?.id }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && streamIsValid && !isDuplicate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(station == nil ? LocalizedStringKey("Añadir emisora") : "Editar emisora")
                .font(.title2.weight(.semibold))

            Form {
                TextField("Nombre", text: $name)
                TextField("Dirección del stream", text: $streamURL, prompt: Text(verbatim: "https://…"))
                if !trimmedStream.isEmpty && !streamIsValid {
                    Text("Tiene que ser una dirección http o https.")
                        .font(.caption).foregroundStyle(.red)
                } else if isDuplicate {
                    Text("Ya tienes una emisora con esta dirección.")
                        .font(.caption).foregroundStyle(.red)
                }
                TextField("Logo (dirección de la imagen, opcional)", text: $logoURL)
                TextField("Género (opcional)", text: $genre)
                TextField("País (opcional)", text: $country, prompt: Text(verbatim: "ES"))
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Guardar") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear(perform: fill)
    }

    private func fill() {
        guard let station else { return }
        name = station.name
        streamURL = station.streamURL
        logoURL = station.logoURL ?? ""
        genre = station.genre ?? ""
        country = station.country ?? ""
    }

    private func save() {
        func optional(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        var edited = station ?? Station(name: "", streamURL: "")
        edited.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        edited.streamURL = trimmedStream
        edited.logoURL = optional(logoURL)
        edited.genre = optional(genre)
        edited.country = optional(country)?.uppercased()
        if station == nil { store.add(edited) } else { store.update(edited) }
        dismiss()
    }
}
