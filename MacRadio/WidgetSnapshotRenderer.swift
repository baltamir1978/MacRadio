import AppKit
import SwiftUI
import WidgetKit

/// Renders the widget's views to PNG files: `MacRadio --render-widgets <folder>`.
///
/// A desktop widget can only be seen by placing it by hand, so this is how its layout gets
/// checked after a change — every size, light and dark, with the live state from the App Group
/// and with the gallery sample. It draws what the views draw; the system's own treatment on the
/// desktop (glass, the dimmed look when the desktop isn't in focus) isn't reproduced.
@MainActor
enum WidgetSnapshotRenderer {
    private static let sizes: [(WidgetFamily, String, CGSize)] = [
        (.systemSmall, "small", CGSize(width: 170, height: 170)),
        (.systemMedium, "medium", CGSize(width: 364, height: 170)),
        (.systemLarge, "large", CGSize(width: 364, height: 382)),
        (.systemExtraLarge, "extralarge", CGSize(width: 764, height: 382)),
    ]

    static func render(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var entries: [(String, RadioEntry)] = [("sample", .sample)]
        if let live = SharedStore.loadNowPlaying() {
            let index = live.songStartedAt.flatMap { live.lyrics?.lineIndex(at: Date().timeIntervalSince($0)) }
            entries.append(("live", RadioEntry(date: Date(), snapshot: live,
                                               stations: SharedStore.loadStations(), lyricIndex: index)))
        }
        entries.append(("empty", RadioEntry(date: Date(), snapshot: nil,
                                            stations: SharedStore.loadStations(), lyricIndex: nil)))

        for (name, entry) in entries {
            for (family, familyName, size) in sizes {
                for scheme in [ColorScheme.light, .dark] {
                    let view = RadioWidgetView(entry: entry, family: family)
                        .padding(16)
                        .frame(width: size.width, height: size.height)
                        .background(Color.appBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .environment(\.colorScheme, scheme)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    guard let image = renderer.nsImage,
                          let tiff = image.tiffRepresentation,
                          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
                    let file = folder.appendingPathComponent("\(name)-\(familyName)-\(scheme == .dark ? "dark" : "light").png")
                    try? png.write(to: file)
                }
            }
        }
    }

    /// Saves every visible window of the app as `<folder>/window-<n>.png`.
    static func snapshotWindows(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (n, window) in NSApp.windows.filter(\.isVisible).enumerated() {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: folder.appendingPathComponent("window-\(n).png"))
        }
    }
}
