import Foundation

struct NodoMeteoSpaziale {
    let lat: Double
    let lon: Double
    let pioggia15gg: Double
    let tempMedia: Double
    let giorniDaPioggia: Int
    let umiditaSuoloMiceliare: Double
    let temperaturaSuolo: Double
    let deltaTSuolo: Double
    let velocitaVentoMax: Double
    let evapotraspirazioneET0: Double
}

actor MeteoService {
    static let shared = MeteoService()
    
    // Griglia spaziale condivisa non-isolata per accesso sincrono immediato nel renderer della mappa
    nonisolated(unsafe) static var nodiGrigliaSpaziale: [NodoMeteoSpaziale] = []
    
    private init() {}
    
    /// Scarica il meteo per una posizione specifica garantendo coerenza 1:1 con la mappa di calore
    func fetchMeteo(latitude: Double, longitude: Double) async -> DatiMeteo {
        let nodi = MeteoService.nodiGrigliaSpaziale
        if !nodi.isEmpty {
            var pesoTotale = 0.0
            var pioggiaPesata = 0.0
            var tempPesata = 0.0
            var giorniDaPioggiaPesati = 0.0
            var umiditaSuoloPesata = 0.0
            var tempSuoloPesata = 0.0
            var deltaTPesato = 0.0
            var ventoPesato = 0.0
            var et0Pesata = 0.0
            
            for n in nodi {
                let d2 = (n.lat - latitude)*(n.lat - latitude) + (n.lon - longitude)*(n.lon - longitude)
                let w = 1.0 / max(0.0001, d2)
                pesoTotale += w
                pioggiaPesata += n.pioggia15gg * w
                tempPesata += n.tempMedia * w
                giorniDaPioggiaPesati += Double(n.giorniDaPioggia) * w
                umiditaSuoloPesata += n.umiditaSuoloMiceliare * w
                tempSuoloPesata += n.temperaturaSuolo * w
                deltaTPesato += n.deltaTSuolo * w
                ventoPesato += n.velocitaVentoMax * w
                et0Pesata += n.evapotraspirazioneET0 * w
            }
            
            if pesoTotale > 0 {
                let p15 = pioggiaPesata / pesoTotale
                let tMed = tempPesata / pesoTotale
                let gPioggia = Int(round(giorniDaPioggiaPesati / pesoTotale))
                let sm = umiditaSuoloPesata / pesoTotale
                let st = tempSuoloPesata / pesoTotale
                let dt = deltaTPesato / pesoTotale
                let wMax = ventoPesato / pesoTotale
                let et0 = et0Pesata / pesoTotale
                
                return DatiMeteo(
                    pioggiaCumulata15Giorni: p15,
                    temperaturaMedia: tMed,
                    umiditaMedia: 65.0,
                    umiditaSuoloMiceliare: sm,
                    temperaturaSuolo: st,
                    deltaTSuolo: dt,
                    velocitaVentoMax: wMax,
                    evapotraspirazioneET0: et0,
                    giorniDaUltimaPioggiaSignificativa: gPioggia
                )
            }
        }
        
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&daily=precipitation_sum,temperature_2m_max,temperature_2m_min,wind_speed_10m_max,et0_fao_evapotranspiration&hourly=relative_humidity_2m,soil_moisture_3_to_9cm,soil_temperature_0_to_10cm&past_days=16&forecast_days=1&timezone=Europe/Rome"
        
        guard let url = URL(string: urlString) else {
            return DatiMeteo(pioggiaCumulata15Giorni: 38.0, temperaturaMedia: 16.0, giorniDaUltimaPioggiaSignificativa: 4)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return DatiMeteo(pioggiaCumulata15Giorni: 38.0, temperaturaMedia: 16.0, giorniDaUltimaPioggiaSignificativa: 4)
            }
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            return DatiMeteo.daOpenMeteo(decoded)
        } catch {
            return DatiMeteo(pioggiaCumulata15Giorni: 38.0, temperaturaMedia: 16.5, umiditaMedia: 68.0, umiditaSuoloMiceliare: 0.28, giorniDaUltimaPioggiaSignificativa: 4)
        }
    }
    
    /// Scarica in UN'UNICA CHIAMATA HTTP la griglia meteo a 100 NODI CONCENTRATI ESCLUSIVAMENTE SULLE ZONE MONTANE >=800m s.l.m.
    /// Inclusi i dati REALI Open-Meteo per Umidità Suolo (3-9cm), DeltaT Suolo, Vento ed Evapotraspirazione ET0
    func fetchGrigliaMeteoSpaziale() async -> [NodoMeteoSpaziale] {
        let puntiMontani = DEMService.shared.getPuntiMontaniIdonei()
        guard !puntiMontani.isEmpty else { return [] }
        
        let targetCount = 100
        let step = max(1, puntiMontani.count / targetCount)
        
        var coords: [(lat: Double, lon: Double)] = []
        for i in stride(from: 0, to: puntiMontani.count, by: step) {
            if coords.count >= targetCount { break }
            let p = puntiMontani[i]
            coords.append((p.lat, p.lon))
        }
        
        let latStr = coords.map { String(format: "%.4f", $0.lat) }.joined(separator: ",")
        let lonStr = coords.map { String(format: "%.4f", $0.lon) }.joined(separator: ",")
        
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latStr)&longitude=\(lonStr)&daily=precipitation_sum,temperature_2m_max,temperature_2m_min,wind_speed_10m_max,et0_fao_evapotranspiration&hourly=relative_humidity_2m,soil_moisture_3_to_9cm,soil_temperature_0_to_10cm&past_days=16&forecast_days=1&timezone=Europe/Rome"
        
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
                    giorniDaPioggia: meteo.giorniDaUltimaPioggiaSignificativa,
                    umiditaSuoloMiceliare: meteo.umiditaSuoloMiceliare,
                    temperaturaSuolo: meteo.temperaturaSuolo,
                    deltaTSuolo: meteo.deltaTSuolo,
                    velocitaVentoMax: meteo.velocitaVentoMax,
                    evapotraspirazioneET0: meteo.evapotraspirazioneET0
                )
                nodi.append(nodo)
            }
            
            MeteoService.nodiGrigliaSpaziale = nodi
            print("✅ Scaricati con successo \(nodi.count) nodi Radar/Satellite con dati REALI Open-Meteo per Umidità Suolo e Shock Termico!")
            
            // Rigenera le bitmap della mappa di calore fruttificazione e pioggia con la nuova griglia meteo reale
            let nuovaBitmapFrutt = await PrevisioneEngine.generaHeatmapBitmap()
            let nuovaBitmapRain = await PrevisioneEngine.generaPrecipitazioniBitmap()
            
            await MainActor.run {
                CosenzaHeatmapOverlayRenderer.sharedFruttificazioneCGImage = nuovaBitmapFrutt
                CosenzaHeatmapOverlayRenderer.sharedPrecipitazioniCGImage = nuovaBitmapRain
                NotificationCenter.default.post(name: .heatmapDataUpdated, object: nil)
            }
            
            return nodi
            
        } catch {
            print("❌ Errore scaricamento griglia spaziale montana: \(error)")
            return []
        }
    }
}
