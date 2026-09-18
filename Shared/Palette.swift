import AppKit
import SwiftUI

/// The mint vintage-radio palette of RadioApp for iOS, with its dark variants. One file for the
/// app and the widget (compiled into both), so the two can't drift apart as they did on iOS.
///
/// Contrast is the one inherited from iOS: the accent reaches 4.9:1 on the surfaces in light
/// mode, and white on the dark-mode accent would only reach 1.8:1 — glyphs on the accent use
/// `Color.appBackground`, which inverts with it.
extension Color {
    static let brand = Color(light: 0x1F6F64, dark: 0x5FD3C2)
    static let appBackground = Color(light: 0xEAF7F3, dark: 0x0E1B19)
    static let mintSurface = Color(light: 0xD6EFE8, dark: 0x16302C)

    nonisolated init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    nonisolated init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
    }

    /// Deterministic tile colour for a station without a logo. Every entry clears 3:1 against
    /// the white initials drawn on it. Hashed by hand: `hashValue` changes on every launch, and
    /// the app and the widget would paint the same station differently.
    nonisolated static func tile(for name: String) -> Color {
        let palette: [UInt32] = [0xD9541F, 0xE8445A, 0x7C5CBF, 0x2D9CDB, 0x1E8A72,
                                 0x219653, 0xC97A22, 0xEB5757, 0x1B8FBF, 0x9B51E0]
        let sum = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Color(hex: palette[sum % palette.count])
    }
}

nonisolated func initials(of name: String) -> String {
    name.split(separator: " ")
        .prefix(2)
        .compactMap(\.first)
        .map(String.init)
        .joined()
        .uppercased()
}
