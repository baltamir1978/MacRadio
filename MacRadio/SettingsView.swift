import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var player: RadioPlayer
    @AppStorage("show_menu_bar") private var showInMenuBar = true
    @AppStorage("skip_intros") private var skipIntros = true
    @ObservedObject private var shazam = ShazamService.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Abrir al iniciar sesión", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Mostrar en la barra de menús", isOn: $showInMenuBar)
            } footer: {
                Text("Con la app abierta, los botones del widget responden al instante.")
            }

            Section {
                Toggle("Identificar canciones automáticamente", isOn: Binding(
                    get: { player.autoIdentify }, set: { player.autoIdentify = $0 }))
                if shazam.unavailable {
                    Label("Apple no ha autorizado a MacRadio a usar Shazam. Hay que activar ShazamKit para el identificador Altamirano.MacRadio en developer.apple.com.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } footer: {
                Text("En las emisoras que no dicen qué suena (como Kiss FM), MacRadio pregunta a Shazam cada minuto. Así aparecen la carátula, la letra sincronizada y el historial. Si sintonizas a mitad de canción, Shazam también dice por dónde va, para que la letra siga el ritmo.")
            }

            Section {
                Toggle("Saltar la cuña de entrada", isOn: $skipIntros)
            } footer: {
                Text("Algunas emisoras ponen anuncios a cada oyente que se conecta. MacRadio los reconoce y se los salta: a cambio, la emisora tarda unos segundos más en empezar a sonar.")
            }

            Section {
                Picker("Búfer", selection: $player.bufferDuration) {
                    Text("5 segundos").tag(5.0)
                    Text("10 segundos").tag(10.0)
                    Text("20 segundos").tag(20.0)
                    Text("30 segundos").tag(30.0)
                }
            } footer: {
                Text("Un búfer mayor aguanta mejor los cortes de red, pero tarda más en empezar a sonar. Se aplica al cambiar de emisora.")
            }

            Section("Widget") {
                Text("Haz clic con el botón derecho en el escritorio, elige «Editar widgets…» y busca MacRadio. Para elegir sus emisoras, haz clic con el botón derecho sobre el widget y elige «Editar “MacRadio”».")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
