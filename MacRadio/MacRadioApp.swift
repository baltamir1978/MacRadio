import AppKit
import SwiftUI

@main
struct MacRadioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var player = RadioPlayer.shared
    @StateObject private var store = StationsStore.shared
    @AppStorage("show_menu_bar") private var showInMenuBar = true

    /// Launched by a widget button: do what was asked without putting a window on screen.
    private let launchedForWidget = CommandHandler.hasPendingCommands

    var body: some Scene {
        Window("MacRadio", id: "main") {
            ContentView()
                .environmentObject(player)
                .environmentObject(store)
        }
        .defaultSize(width: 940, height: 600)
        .defaultLaunchBehavior(launchedForWidget ? .suppressed : .automatic)
        .commands { PlaybackCommands(player: player) }

        Window("Historial", id: "history") {
            HistoryView()
                .environmentObject(player)
                .environmentObject(store)
        }
        .defaultSize(width: 560, height: 640)

        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarPanel()
                .environmentObject(player)
                .environmentObject(store)
        } label: {
            Image(systemName: player.isPlaying ? "radio.fill" : "radio")
                .accessibilityLabel(Text("MacRadio"))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(player)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        CommandHandler.startListening()
        // Command-line hook for checking the widget layout without placing it on the desktop.
        if let index = CommandLine.arguments.firstIndex(of: "--render-widgets"),
           CommandLine.arguments.indices.contains(index + 1) {
            WidgetSnapshotRenderer.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            NSApp.terminate(nil)
        }
        // Same idea for the main window: plays the last station, waits for the song and its
        // cover, and saves what the window shows. Needs no screen-recording permission.
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot-window"),
           CommandLine.arguments.indices.contains(index + 1) {
            let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            RadioPlayer.shared.togglePlayPause()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(15))
                WidgetSnapshotRenderer.snapshotWindows(to: url)
                NSApp.terminate(nil)
            }
        }
    }

    /// The radio keeps playing with the window closed: the menu bar, the widget and the media
    /// keys all still drive it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// The Controls menu. No shortcut on play/pause: a bare Space as a menu key equivalent would
/// swallow spaces typed in the search field; the window handles Space itself when it can.
struct PlaybackCommands: Commands {
    @ObservedObject var player: RadioPlayer
    @ObservedObject private var history = HistoryStore.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Controles") {
            Button(player.isPlaying ? LocalizedStringKey("Pausar") : "Reproducir") { player.togglePlayPause() }
            Button("Emisora siguiente") { player.playNext() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Emisora anterior") { player.playPrevious() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Divider()
            Button("Subir volumen") { player.volume = min(1, player.volume + 0.1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Bajar volumen") { player.volume = max(0, player.volume - 0.1) }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Divider()
            Button(player.isFavorite ? LocalizedStringKey("Quitar de favoritas") : "Marcar como favorita") {
                player.toggleFavorite()
            }
            .keyboardShortcut("d")
            .disabled(player.historyEntryID == nil)
            Button("Historial") { openWindow(id: "history") }
                .keyboardShortcut("y")
        }
    }
}
