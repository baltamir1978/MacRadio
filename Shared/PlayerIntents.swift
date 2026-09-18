import AppIntents
import Foundation

// Compiled into both the app and the widget extension. The widget's buttons need the intent
// types in their own module; the app needs them so the system can run an `AudioPlaybackIntent`
// right where the player lives. `PlayerCommand.dispatch()` works out which of the two it's in.

// MARK: - Station entity

/// One of the user's stations. Identified by stream URL, the one thing that survives edits of
/// the name or logo and is the same in the app and the widget.
nonisolated struct StationEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Emisora")
    static let defaultQuery = StationQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

nonisolated struct StationQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [StationEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [StationEntity] { all() }

    private func all() -> [StationEntity] {
        SharedStore.loadStations().map { StationEntity(id: $0.streamURL, name: $0.name) }
    }
}

// MARK: - Playback intents

struct PlayStationIntent: AudioPlaybackIntent {
    nonisolated static var title: LocalizedStringResource { "Escuchar emisora" }
    nonisolated static var description: IntentDescription { IntentDescription("Pone una de tus emisoras en MacRadio.") }

    @Parameter(title: "Emisora") var station: StationEntity

    init() {}

    init(station: StationEntity) {
        self.station = station
    }

    func perform() async throws -> some IntentResult {
        await PlayerCommand.play(streamURL: station.id).dispatch()
        return .result()
    }
}

struct TogglePlaybackIntent: AudioPlaybackIntent {
    nonisolated static var title: LocalizedStringResource { "Reproducir o pausar la radio" }

    func perform() async throws -> some IntentResult {
        await PlayerCommand.togglePlayPause.dispatch()
        return .result()
    }
}

struct NextStationIntent: AudioPlaybackIntent {
    nonisolated static var title: LocalizedStringResource { "Emisora siguiente" }

    func perform() async throws -> some IntentResult {
        await PlayerCommand.next.dispatch()
        return .result()
    }
}

struct PreviousStationIntent: AudioPlaybackIntent {
    nonisolated static var title: LocalizedStringResource { "Emisora anterior" }

    func perform() async throws -> some IntentResult {
        await PlayerCommand.previous.dispatch()
        return .result()
    }
}

struct ToggleFavoriteIntent: AppIntent {
    nonisolated static var title: LocalizedStringResource { "Marcar la canción como favorita" }
    nonisolated static var description: IntentDescription {
        IntentDescription("Guarda la canción que suena entre tus favoritas de MacRadio, o la quita.")
    }

    func perform() async throws -> some IntentResult {
        await PlayerCommand.toggleFavorite.dispatch()
        return .result()
    }
}

struct IdentifySongIntent: AudioPlaybackIntent {
    nonisolated static var title: LocalizedStringResource { "Identificar la canción" }
    nonisolated static var description: IntentDescription {
        IntentDescription("Averigua con Shazam qué canción suena en la emisora.")
    }

    func perform() async throws -> some IntentResult {
        await PlayerCommand.identify.dispatch()
        return .result()
    }
}
