import Foundation
import SwiftUI

enum StatoFruttificazione: String, Codable, CaseIterable {
    case nonFavorevole = "Non Favorevole"
    case inPreparazione = "In Preparazione (0-3 gg)"
    case buttataProbabile = "Buttata Probabile (4-10 gg)"
    case inEsaurimento = "In Esaurimento (11-15 gg)"
    
    var icona: String {
        switch self {
        case .nonFavorevole: return "xmark.circle.fill"
        case .inPreparazione: return "clock.fill"
        case .buttataProbabile: return "leaf.fill"
        case .inEsaurimento: return "exclamationmark.triangle.fill"
        }
    }
    
    var colore: Color {
        switch self {
        case .nonFavorevole: return .gray
        case .inPreparazione: return .orange
        case .buttataProbabile: return .green
        case .inEsaurimento: return .yellow
        }
    }
}

struct RisultatoPrevisione {
    let stato: StatoFruttificazione
    let probabilitaPercentuale: Int       // 0 - 100%
    let pioggiaCumulata15gg: Double
    let sogliaRichiesta: Double          // mm necessari calcolati per questo specifico punto
    let messaggioDettagliato: String
    let ritardoGiorniQuota: Int
}
