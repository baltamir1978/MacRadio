import Foundation

struct Station: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var streamURL: String
    var logoURL: String?
    var country: String?
    var genre: String?
    var stationuuid: String?

    var initials: String { MacRadio.initials(of: name) }

    /// Genre and country, for the secondary line under the name.
    var detail: String {
        [genre?.capitalized, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

extension Station {
    /// The same starting list as RadioApp for iOS.
    static let defaults: [Station] = [
        Station(name: "Vive Segovia",
                streamURL: "https://streaming.viveradio.es/vivesegovia",
                logoURL: "https://viveradio.es/dist/images/favicons/apple-touch-icon.webp",
                country: "ES", genre: "Regional"),
        Station(name: "Cassette FM",
                streamURL: "https://stream.costafm.es/listen/cassettefm_-_em/radio.mp3",
                logoURL: "https://media.emisorasmusicales.net/wp-content/uploads/2021/05/11022133/Cassette.png",
                country: "ES", genre: "Pop"),
        Station(name: "Cadena 100",
                streamURL: "https://cadena100-cope-rrcast.flumotion.com/cope/cadena100-low.mp3",
                logoURL: "https://www.cadena100.es/estaticos/apple-touch-icon-192x192.png",
                country: "ES", genre: "Pop"),
        Station(name: "Kiss FM",
                streamURL: "https://bbkissfm.kissfmradio.cires21.com/bbkissfm.mp3",
                logoURL: "https://www.kissfm.es/wp-content/uploads/2024/10/Logo-KISS-FM_Negativo-Color.png",
                country: "ES", genre: "Dance"),
        Station(name: "La Indie",
                streamURL: "https://stream.emisorasmusicales.net/listen/la_indie/laindie.mp3",
                logoURL: "https://media.emisorasmusicales.net/wp-content/uploads/2020/04/11023707/LA-INDIE.png",
                country: "ES", genre: "Indie"),
        Station(name: "Los 40 Classic",
                streamURL: "http://playerservices.streamtheworld.com/api/livestream-redirect/LOS40_CLASSIC.mp3",
                logoURL: "https://los40es00.epimg.net/iconos/v1.x/v1.0/promos/promo_og_los40.png",
                country: "ES", genre: "Pop"),
        Station(name: "SER Oriente",
                streamURL: "https://playerservices.streamtheworld.com/api/livestream-redirect/SER_ASO_ORIENTE.mp3",
                logoURL: "https://cadenaser00.epimg.net/favicon.png",
                country: "ES", genre: "Talk"),
        Station(name: "COPE Madrid",
                streamURL: "https://flucast09-h-cloud.flumotion.com/cope/madrid.mp3",
                logoURL: "https://www.cope.es/estaticos/apple-touch-icon-192x192.png",
                country: "ES", genre: "Talk"),
    ]
}
