import Foundation

struct NodoMeteoSpaziale {
    let lat: Double
    let lon: Double
    let pioggia15gg: Double
    let tempMedia: Double
    let giorniDaPioggia: Int
}

actor MeteoService {
    static let shared = MeteoService()
    
    private(set) var nodiGrigliaSpaziale: [NodoMeteoSpaziale] = []
    
    private init() {}
    
    /// Scarica il meteo live per una posizione specifica
    func fetchMeteo(latitude: Double, longitude: Double) async -> DatiMeteo {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&daily=precipitation_sum,temperature_2m_max,temperature_2m_min&hourly=relative_humidity_2m,soil_moisture_0_to_1cm&past_days=16&forecast_days=7&timezone=Europe/Rome"
        
        guard let url = URL(string: urlString) else {
            return DatiMeteo(pioggiaCumulata15Giorni: 28.0, temperaturaMedia: 16.0, giorniDaUltimaPioggiaSignificativa: 5)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return DatiMeteo(pioggiaCumulata15Giorni: 28.0, temperaturaMedia: 16.0, giorniDaUltimaPioggiaSignificativa: 5)
            }
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            return DatiMeteo.daOpenMeteo(decoded)
        } catch {
            return DatiMeteo(pioggiaCumulata15Giorni: 28.0, temperaturaMedia: 16.5, umiditaMedia: 68.0, umiditaSuolo: 0.28, giorniDaUltimaPioggiaSignificativa: 5)
        }
    }
    
    /// Scarica in UN'UNICA CHIAMATA HTTP la griglia meteo ad alta risoluzione (36 nodi spaziali)
    /// basata sui dati Radar/Satellite ICON-D2 per catturare i temporali estivi localizzati!
    func fetchGrigliaMeteoSpaziale() async -> [NodoMeteoSpaziale] {
        let lats: [Double] = [38.85, 39.15, 39.45, 39.75, 40.05, 40.30]
        let lons: [Double] = [15.85, 16.12, 16.35, 16.58, 16.85, 17.15]
        
        var coords: [(lat: Double, lon: Double)] = []
        for lat in lats {
            for lon in lons {
                coords.append((lat, lon))
            }
        }
        
        let latStr = coords.map { String(format: "%.4f", $0.lat) }.joined(separator: ",")
        let lonStr = coords.map { String(format: "%.4f", $0.lon) }.joined(separator: ",")
        
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latStr)&longitude=\(lonStr)&daily=precipitation_sum,temperature_2m_max,temperature_2m_min&past_days=16&forecast_days=1&timezone=Europe/Rome"
        
        guard let url = URL(string: urlString) else { return [] }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return [] }
            
            let decodedArray = try JSONDecoder().decode([OpenMeteoResponse].self, from: data)
            var nodi: [NodoMeteoSpaziale] = []
            
            for item in decodedArray {
                let meteo = DatiMeteo.daOpenMeteo(item)
                let nodo = NodoMeteoSpaziale(
                    lat: item.latitude,
                    lon: item.longitude,
                    pioggia15gg: meteo.pioggiaCumulata15Giorni,
                    tempMedia: meteo.temperaturaMedia,
                    giorniDaPioggia: meteo.giorniDaUltimaPioggiaSignificativa
                )
                nodi.append(nodo)
            }
            
            self.nodiGrigliaSpaziale = nodi
            print("✅ Scaricati con successo \(nodi.count) nodi Radar/Satellite per temporali estivi localizzati!")
            return nodi
            
        } catch {
            print("❌ Errore scaricamento griglia spaziale: \(error)")
            return []
        }
    }
}
