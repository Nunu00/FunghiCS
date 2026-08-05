import Foundation
import SwiftData

@Model
final class PuntoInteresse {
    var id: UUID
    var nome: String
    var latitude: Double
    var longitude: Double
    var quota: Double          // in metri slm
    var pendenza: Double       // in gradi (0 - 90°)
    var esposizione: String    // "N", "S", "E", "W", "NE", "NW", "SE", "SW"
    var note: String
    var dataCreazione: Date
    var moltiplicatoreSoglia: Double // Calibrabile dall'utente (default 1.0)
    
    @Relationship(deleteRule: .cascade, inverse: \Osservazione.punto)
    var osservazioni: [Osservazione]
    
    init(
        id: UUID = UUID(),
        nome: String,
        latitude: Double,
        longitude: Double,
        quota: Double = 800.0,
        pendenza: Double = 10.0,
        esposizione: String = "N",
        note: String = "",
        dataCreazione: Date = Date(),
        moltiplicatoreSoglia: Double = 1.0,
        osservazioni: [Osservazione] = []
    ) {
        self.id = id
        self.nome = nome
        self.latitude = latitude
        self.longitude = longitude
        self.quota = quota
        self.pendenza = pendenza
        self.esposizione = esposizione
        self.note = note
        self.dataCreazione = dataCreazione
        self.moltiplicatoreSoglia = moltiplicatoreSoglia
        self.osservazioni = osservazioni
    }
}
