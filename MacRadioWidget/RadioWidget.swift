import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Configuration

/// The widget's edit screen: which stations get a button, in order. Left empty, the widget
/// offers the top of the station list, so it works the moment it is placed.
struct SelectStationsIntent: WidgetConfigurationIntent {
    nonisolated static var title: LocalizedStringResource { "Emisoras del widget" }
    nonisolated static var description: IntentDescription {
        IntentDescription("Elige qué emisoras aparecen como botones en el widget.")
    }

    @Parameter(title: "Emisoras", size: 8) var stations: [StationEntity]?

    var chosenIDs: [String] { (stations ?? []).map(\.id) }
}

// MARK: - Timeline

struct RadioProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RadioEntry {
        RadioEntry.sample
    }

    func snapshot(for configuration: SelectStationsIntent, in context: Context) async -> RadioEntry {
        context.isPreview && SharedStore.loadNowPlaying() == nil ? .sample : entries(for: configuration).first!
    }

    func timeline(for configuration: SelectStationsIntent, in context: Context) async -> Timeline<RadioEntry> {
        // No refresh policy of our own: the app reloads the widget whenever the song, station
        // or play state changes. Only the lyrics move by the clock, and those are in the entries.
        Timeline(entries: entries(for: configuration), policy: .never)
    }

    /// One entry for right now, plus one per synced lyric line still to come, so the lyrics
    /// window steps along with the song without the app having to wake the widget.
    private func entries(for configuration: SelectStationsIntent) -> [RadioEntry] {
        let snapshot = SharedStore.loadNowPlaying()
        let stations = resolve(configuration)
        let now = Date()

        guard let snapshot, snapshot.isPlaying,
              let start = snapshot.songStartedAt, snapshot.songStartIsExact,
              let synced = snapshot.lyrics?.synced, !synced.isEmpty else {
            return [RadioEntry(date: now, snapshot: snapshot, stations: stations, lyricIndex: nil)]
        }

        var entries = [RadioEntry(date: now, snapshot: snapshot, stations: stations,
                                  lyricIndex: snapshot.lyrics?.lineIndex(at: now.timeIntervalSince(start)))]
        for (index, line) in synced.enumerated() {
            let date = start.addingTimeInterval(line.time)
            guard date > now else { continue }
            entries.append(RadioEntry(date: date, snapshot: snapshot, stations: stations, lyricIndex: index))
            // A song has well under this many lines; the cap only guards against a broken file.
            if entries.count >= 150 { break }
        }
        return entries
    }

    /// Chosen stations win; stations deleted in the app since the widget was set up drop out.
    private func resolve(_ configuration: SelectStationsIntent) -> [SharedStation] {
        let all = SharedStore.loadStations()
        let ids = configuration.chosenIDs
        guard !ids.isEmpty else { return all }
        return ids.compactMap { id in all.first { $0.streamURL == id } }
    }
}

// MARK: - Widget

struct RadioWidget: Widget {
    let kind = "MacRadioWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectStationsIntent.self, provider: RadioProvider()) { entry in
            RadioWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("MacRadio")
        .description("Lo que suena, con carátula, y tus emisoras a un clic. En el tamaño grande, también la letra.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

private struct RadioWidgetEntryView: View {
    let entry: RadioEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        RadioWidgetView(entry: entry, family: family)
    }
}

@main
struct MacRadioWidgetBundle: WidgetBundle {
    var body: some Widget {
        RadioWidget()
    }
}
