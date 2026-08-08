import Foundation

actor MeteoService {
    static let shared = MeteoService()
    
    // Cache per il meteo regionale di Cosenza (Sila e Pollino)
    private(set) var meteoRegionale: DatiMeteo? = nil
    
    private init() {}
    
    /// Scarica il meteo live per una posizione specifica
    func fetchMeteo(latitude: Double, longitude: Double) async -> DatiMeteo {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&daily=precipitation_sum,temperature_2m_max,temperature_2m_min&hourly=relative_humidity_2m,soil_moisture_0_to_1cm&past_days=16&forecast_days=7&timezone=Europe/Rome"
        
        guard let url = URL(string: urlString) else {
            print("URL Open-Meteo non valido.")
            return DatiMeteo(pioggiaCumulata15Giorni: 28.0, temperaturaMedia: 16.0, giorniDaUltimaPioggiaSignificativa: 5)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("Risposta HTTP Open-Meteo non valida")
                return DatiMeteo(pioggiaCumulata15Giorni: 28.0, temperaturaMedia: 16.0, giorniDaUltimaPioggiaSignificativa: 5)
            }
            
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            let meteo = DatiMeteo.daOpenMeteo(decoded)
            
            // Aggiorna cache meteo regionale se vuota o per posizioni centrali (Sila)
            if self.meteoRegionale == nil || (latitude >= 39.20 && latitude <= 39.50) {
                self.meteoRegionale = meteo
            }
            
            return meteo
            
        } catch {
            print("Errore durante la chiamata Open-Meteo: \(error.localizedDescription)")
            return DatiMeteo(pioggiaCumulata15Giorni: 28.0, temperaturaMedia: 16.5, umiditaMedia: 68.0, umiditaSuolo: 0.28, giorniDaUltimaPioggiaSignificativa: 5)
        }
    }
    
    /// Scarica il meteo regionale di riferimento per la Provincia di Cosenza (Sila Grande)
    func caricaMeteoRegionaleIniziale() async -> DatiMeteo {
        let m = await fetchMeteo(latitude: 39.33, longitude: 16.44) // Camigliatello Silano
        self.meteoRegionale = m
        return m
    }
}
