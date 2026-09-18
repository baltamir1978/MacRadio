import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class StationsStore: ObservableObject {
    static let shared = StationsStore()

    @Published private(set) var stations: [Station] = []

    private let saveKey = "saved_stations"
    /// Logos already fetched for the widget this session, successful or not, so a dead logo URL
    /// isn't retried every time the list changes.
    private var logoAttempts: Set<String> = []

    private init() {
        load()
        if stations.isEmpty { stations = Station.defaults }
        publish()
    }

    func add(_ station: Station) {
        guard !contains(station) else { return }
        stations.append(station)
        save()
    }

    func update(_ station: Station) {
        guard let index = stations.firstIndex(where: { $0.id == station.id }) else { return }
        stations[index] = station
        save()
    }

    func remove(_ station: Station) {
        stations.removeAll { $0.id == station.id }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        stations.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func contains(_ station: Station) -> Bool {
        stations.contains { $0.streamURL == station.streamURL }
    }

    func station(streamURL: String) -> Station? {
        stations.first { $0.streamURL == streamURL }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(stations) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
        publish()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let decoded = try? JSONDecoder().decode([Station].self, from: data) else { return }
        stations = decoded
    }

    // MARK: Widget

    /// Shares the list with the widget, then fetches any logo it doesn't have yet and shares
    /// the list again once they're in. The widget can't download them itself.
    private func publish() {
        SharedStore.saveStations(sharedStations())
        let missing = stations.compactMap(\.logoURL).filter {
            SharedStore.imageURL(named: SharedStore.imageName(for: $0)) == nil && !logoAttempts.contains($0)
        }
        guard !missing.isEmpty else { return }
        logoAttempts.formUnion(missing)
        Task { [weak self] in
            var fetchedAny = false
            for url in Set(missing) {
                if let image = await ImageLoader.image(from: url) {
                    SharedStore.storeImage(image, named: SharedStore.imageName(for: url), maxPixels: 160)
                    fetchedAny = true
                }
            }
            guard fetchedAny, let self else { return }
            SharedStore.saveStations(self.sharedStations())
        }
    }

    private func sharedStations() -> [SharedStation] {
        stations.map { station in
            let file = station.logoURL.map(SharedStore.imageName(for:))
            return SharedStation(name: station.name, streamURL: station.streamURL,
                                 logoFile: SharedStore.imageURL(named: file) != nil ? file : nil,
                                 initials: station.initials)
        }
    }

    /// Image files the widget may still need: every station logo.
    var logoFiles: Set<String> {
        Set(stations.compactMap(\.logoURL).map(SharedStore.imageName(for:)))
    }
}

/// Downloads an image, off the main actor. Nil on any failure: callers fall back to initials.
nonisolated enum ImageLoader {
    static func image(from urlString: String) async -> NSImage? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("MacRadio/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { return nil }
        return NSImage(data: data)
    }
}
