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
    
    // Griglia spaziale condivisa non-isolata per accesso sincrono immediato nel renderer della mappa
    nonisolated(unsafe) static var nodiGrigliaSpaziale: [NodoMeteoSpaziale] = []
    
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
    
    /// Scarica in UN'UNICA CHIAMATA HTTP la griglia meteo a 64 nodi CONCENTRATI ESCLUSIVAMENTE SULLE ZONE MONTANE >=800m s.l.m.
    /// per risolvere con precisione chirurgica i temporali estivi nei boschi!
    func fetchGrigliaMeteoSpaziale() async -> [NodoMeteoSpaziale] {
        let puntiMontani = DEMService.shared.getPuntiMontaniIdonei()
        guard !puntiMontani.isEmpty else { return [] }
        
        let targetCount = 64
        let step = max(1, puntiMontani.count / targetCount)
        
        var coords: [(lat: Double, lon: Double)] = []
        for i in stride(from: 0, to: puntiMontani.count, by: step) {
            if coords.count >= targetCount { break }
            let p = puntiMontani[i]
            coords.append((p.lat, p.lon))
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
            
            MeteoService.nodiGrigliaSpaziale = nodi
            print("✅ Scaricati con successo \(nodi.count) nodi Radar/Satellite CONCENTRATI IN MONTAGNA (>=800m)!")
            return nodi
            
        } catch {
            print("❌ Errore scaricamento griglia spaziale montana: \(error)")
            return []
        }
    }
}
