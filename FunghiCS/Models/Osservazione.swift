import Foundation
import SwiftData

@Model
final class Osservazione {
    var id: UUID
    var data: Date
    var trovato: Bool         // true = trovati funghi, false = uscita a vuoto
    var quantitaKg: Double?   // Quantità approssimativa in kg
    var specie: String        // E.g. "Porcino (Boletus edulis)", "Amanita caesarea", ecc.
    var note: String
    var punto: PuntoInteresse?
    
    init(
        id: UUID = UUID(),
        data: Date = Date(),
        trovato: Bool,
        quantitaKg: Double? = nil,
        specie: String = "Porcino",
        note: String = "",
        punto: PuntoInteresse? = nil
    ) {
        self.id = id
        self.data = data
        self.trovato = trovato
        self.quantitaKg = quantitaKg
        self.specie = specie
        self.note = note
        self.punto = punto
    }
}
