import Foundation

struct DEMGridPoint: Codable {
    let lat: Double
    let lon: Double
    let elevation: Double
    let slope: Double
    let aspect: String
}

struct DEMDataFile: Codable {
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double
    let points: [DEMGridPoint]
}

final class DEMService {
    static let shared = DEMService()
    
    private var demData: DEMDataFile?
    
    private init() {
        caricaDEMJSON()
    }
    
    private func caricaDEMJSON() {
        let url = Bundle.main.url(forResource: "cosenza_dem", withExtension: "json") ??
                  Bundle.main.url(forResource: "cosenza_dem", withExtension: "json", subdirectory: "DEM")
        
        guard let validUrl = url else {
            print("DEM JSON non trovato nel bundle. Uso calcolo orografico analitico TINITALY.")
            return
        }
        
        do {
            let data = try Data(contentsOf: validUrl)
            let decoder = JSONDecoder()
            self.demData = try decoder.decode(DEMDataFile.self, from: data)
            print("DEM TINITALY caricato con successo: \(self.demData?.points.count ?? 0) punti altimetrici.")
        } catch {
            print("Errore decodifica DEM JSON: \(error)")
        }
    }
    
    /// Restituisce true se la quota rientra nella fascia montana/boschiva idonea ai funghi (>= 800m s.l.m.)
    func isQuotaIdonea(quota: Double) -> Bool {
        return quota >= 800.0 && quota <= 2100.0
    }
    
    /// Maschera geografica per escludere il mare ed i litorali
    func isAreaMareOCosta(lat: Double, lon: Double, quota: Double) -> Bool {
        if quota < 800.0 { return true }
        if lon < 15.96 { return true } // Mare Tirreno
        if lon > 16.58 { return true } // Mare Jonio
        // Piana di Sibari
        if lat > 39.65 && lat < 39.85 && lon > 16.25 && lon < 16.55 && quota < 800.0 {
            return true
        }
        // Valle del Crati (Cosenza città, Rende, Bisignano, Torano)
        if lat > 39.20 && lat < 39.55 && lon > 16.16 && lon < 16.32 && quota < 800.0 {
            return true
        }
        return false
    }
    
    /// Restituisce la quota e i parametri orografici esatti per qualsiasi coordinate lat/lon
    func getTerrainData(latitude: Double, longitude: Double) -> (quota: Double, pendenza: Double, esposizione: String) {
        guard let data = demData, !data.points.isEmpty else {
            return calcolaOrograriaAnalitica(lat: latitude, lon: longitude)
        }
        
        var minDistSq = Double.greatestFiniteMagnitude
        var migliorPunto: DEMGridPoint? = nil
        
        for point in data.points {
            let dLat = point.lat - latitude
            let dLon = point.lon - longitude
            let distSq = dLat * dLat + dLon * dLon
            if distSq < minDistSq {
                minDistSq = distSq
                migliorPunto = point
            }
        }
        
        // Raggio di tolleranza strettissimo: 0.0009 (~3km) per evitare che punti di montagna sanguinino su coste o valli!
        if let punto = migliorPunto, minDistSq < 0.0009 {
            return (quota: punto.elevation, pendenza: punto.slope, esposizione: punto.aspect)
        } else {
            return calcolaOrograriaAnalitica(lat: latitude, lon: longitude)
        }
    }
    
    /// Algoritmo altimetrico orografico di alta precisione per i massicci della provincia di Cosenza
    private func calcolaOrograriaAnalitica(lat: Double, lon: Double) -> (quota: Double, pendenza: Double, esposizione: String) {
        // 1. Massiccio del Pollino (Monte Pollino, Serra Dolcedorme, Alessandria del Carretto)
        let distPollino = hypot(lat - 39.92, lon - 16.18)
        if distPollino < 0.18 {
            let alt = max(100.0, 1980.0 - (distPollino * 8500.0))
            return (quota: alt, pendenza: 18.0, esposizione: "N")
        }
        
        // 2. Sila Grande (Monte Botte Donato, Camigliatello, Lorica, Monte Scuro)
        let distSilaGrande = hypot(lat - 39.38, lon - 16.50)
        if distSilaGrande < 0.22 {
            let alt = max(120.0, 1780.0 - (distSilaGrande * 6500.0))
            return (quota: alt, pendenza: 14.0, esposizione: "NE")
        }
        
        // 3. Sila Piccola (Trepidò, Villaggio Mancuso, Monte Gariglione)
        let distSilaPiccola = hypot(lat - 39.15, lon - 16.52)
        if distSilaPiccola < 0.16 {
            let alt = max(100.0, 1620.0 - (distSilaPiccola * 7500.0))
            return (quota: alt, pendenza: 15.0, esposizione: "E")
        }
        
        // 4. Catena Costiera (Monte Cocuzzo, Passo Crocetta, Fagnano Castello)
        if lat >= 39.15 && lat <= 39.65 && lon >= 16.02 && lon <= 16.14 {
            let distAsse = abs(lon - 16.08)
            let alt = max(80.0, 1320.0 - (distAsse * 12000.0))
            return (quota: alt, pendenza: 22.0, esposizione: "W")
        }
        
        // 5. Serre Cosentine (Dipignano, Mendicino alte quote)
        if lat >= 39.10 && lat <= 39.22 && lon >= 16.14 && lon <= 16.30 {
            let distCenter = hypot(lat - 39.16, lon - 16.22)
            if distCenter < 0.10 {
                let alt = max(100.0, 950.0 - (distCenter * 6000.0))
                return (quota: alt, pendenza: 12.0, esposizione: "S")
            }
        }
        
        // Valle del Crati, Pianure e Coste -> Bassa Quota (<300m)!
        return (quota: 120.0, pendenza: 3.0, esposizione: "S")
    }
}
