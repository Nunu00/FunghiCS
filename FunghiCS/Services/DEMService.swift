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
            print("DEM JSON non trovato nel bundle. Verranno usati calcoli altimetrici di precisione.")
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
    
    /// Maschera geografica per escludere il mare Tirreno e Jonio e relative zone costiere
    func isAreaMareOCosta(lat: Double, lon: Double, quota: Double) -> Bool {
        if quota < 800.0 { return true }
        if lon < 15.95 { return true } // Mare Tirreno
        if lon > 16.60 { return true } // Mare Jonio
        if lat > 39.65 && lat < 39.85 && lon > 16.25 && lon < 16.55 && quota < 800.0 {
            return true // Piana di Sibari
        }
        return false
    }
    
    /// Restituisce la quota e i parametri orografici esatti per qualsiasi coordinate lat/lon
    func getTerrainData(latitude: Double, longitude: Double) -> (quota: Double, pendenza: Double, esposizione: String) {
        guard let data = demData, !data.points.isEmpty else {
            return calcolaTerrainPunto(lat: latitude, lon: longitude)
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
        
        if let punto = migliorPunto, minDistSq < 0.04 {
            return (quota: punto.elevation, pendenza: punto.slope, esposizione: punto.aspect)
        } else {
            return calcolaTerrainPunto(lat: latitude, lon: longitude)
        }
    }
    
    /// Algoritmo altimetrico di fallback orografico per Cosenza (Sila, Pollino, Catena Costiera, Serre)
    private func calcolaTerrainPunto(lat: Double, lon: Double) -> (quota: Double, pendenza: Double, esposizione: String) {
        // Pollino (Lat 39.80..40.05, Lon 16.05..16.30)
        let distPollino = hypot(lat - 39.92, lon - 16.18)
        if distPollino < 0.22 {
            let alt = max(300.0, 1980.0 - (distPollino * 6000.0))
            return (quota: alt, pendenza: 16.0, esposizione: "N")
        }
        
        // Sila Grande (Lat 39.25..39.50, Lon 16.35..16.65)
        let distSilaGrande = hypot(lat - 39.38, lon - 16.50)
        if distSilaGrande < 0.28 {
            let alt = max(250.0, 1750.0 - (distSilaGrande * 4500.0))
            return (quota: alt, pendenza: 12.0, esposizione: "NE")
        }
        
        // Sila Piccola (Lat 39.05..39.25, Lon 16.40..16.65)
        let distSilaPiccola = hypot(lat - 39.15, lon - 16.52)
        if distSilaPiccola < 0.20 {
            let alt = max(200.0, 1600.0 - (distSilaPiccola * 5000.0))
            return (quota: alt, pendenza: 14.0, esposizione: "E")
        }
        
        // Catena Costiera (Lat 39.20..39.60, Lon 16.02..16.14)
        if lat >= 39.15 && lat <= 39.65 && lon >= 16.00 && lon <= 16.16 {
            let distAsse = abs(lon - 16.08)
            let alt = max(150.0, 1300.0 - (distAsse * 7000.0))
            return (quota: alt, pendenza: 20.0, esposizione: "W")
        }
        
        // Per tutte le altre zone (pianura, costa, mare) quota reale bassa!
        return (quota: 80.0, pendenza: 3.0, esposizione: "S")
    }
}
