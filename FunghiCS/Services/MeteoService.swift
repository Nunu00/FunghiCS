import Foundation

actor MeteoService {
    static let shared = MeteoService()
    
    private init() {}
    
    func fetchMeteo(latitude: Double, longitude: Double) async -> DatiMeteo {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&daily=precipitation_sum,temperature_2m_max,temperature_2m_min&hourly=relative_humidity_2m,soil_moisture_0_to_1cm&past_days=16&forecast_days=7&timezone=Europe/Rome"
        
        guard let url = URL(string: urlString) else {
            print("URL Open-Meteo non valido.")
            return DatiMeteo(pioggiaCumulata15Giorni: 55.0, temperaturaMedia: 16.0)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("Risposta HTTP Open-Meteo non valida")
                return DatiMeteo(pioggiaCumulata15Giorni: 55.0, temperaturaMedia: 16.0)
            }
            
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            return DatiMeteo.daOpenMeteo(decoded)
            
        } catch {
            print("Errore durante la chiamata Open-Meteo: \(error.localizedDescription)")
            // Fallback con dati stimati per permettere il funzionamento offline
            return DatiMeteo(pioggiaCumulata15Giorni: 58.0, temperaturaMedia: 17.5, umiditaMedia: 68.0, umiditaSuolo: 0.28, giorniDaUltimaPioggiaSignificativa: 4)
        }
    }
}
