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

struct CellaGrigliaTerritorio: Identifiable {
    let id: String
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double
    let centerLat: Double
    let centerLon: Double
    let quota: Double
    let pendenza: Double
    let esposizione: String
    let idonea: Bool
}

final class DEMService {
    static let shared = DEMService()
    
    private var demData: DEMDataFile?
    
    private init() {
        caricaDEMJSON()
    }
    
    private func caricaDEMJSON() {
        // Cerca prima in Resources/cosenza_dem.json, poi in DEM/cosenza_dem.json
        let url = Bundle.main.url(forResource: "cosenza_dem", withExtension: "json") ??
                  Bundle.main.url(forResource: "cosenza_dem", withExtension: "json", subdirectory: "DEM")
        
        guard let validUrl = url else {
            print("DEM JSON non trovato nel bundle. Verranno usati valori di fallback.")
            return
        }
        
        do {
            let data = try Data(contentsOf: validUrl)
            let decoder = JSONDecoder()
            self.demData = try decoder.decode(DEMDataFile.self, from: data)
            print("DEM TINITALY caricato con successo: \(self.demData?.points.count ?? 0) punti griglia.")
        } catch {
            print("Errore decodifica DEM JSON: \(error)")
        }
    }
    
    /// Restituisce true se la quota rientra nella fascia boschiva/montana idonea ai funghi (>= 400m s.l.m.)
    func isQuotaIdonea(quota: Double) -> Bool {
        return quota >= 400.0 && quota <= 2100.0
    }
    
    /// Restituisce (quota, pendenza, esposizione) per le coordinate specificate
    func getTerrainData(latitude: Double, longitude: Double) -> (quota: Double, pendenza: Double, esposizione: String) {
        guard let data = demData, !data.points.isEmpty else {
            return fallbackTerrain(lat: latitude, lon: longitude)
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
        
        if let punto = migliorPunto, minDistSq < 0.05 {
            return (quota: punto.elevation, pendenza: punto.slope, esposizione: punto.aspect)
        } else {
            return fallbackTerrain(lat: latitude, lon: longitude)
        }
    }
    
    /// Genera la griglia spaziale del territorio per la Provincia di Cosenza
    func generaGrigliaTerritorio(stepGradiente: Double = 0.025) -> [CellaGrigliaTerritorio] {
        let minLat = 39.05
        let maxLat = 40.15
        let minLon = 15.75
        let maxLon = 16.85
        
        var celle: [CellaGrigliaTerritorio] = []
        var lat = minLat
        
        while lat < maxLat {
            var lon = minLon
            while lon < maxLon {
                let centerLat = lat + (stepGradiente / 2.0)
                let centerLon = lon + (stepGradiente / 2.0)
                let terrain = getTerrainData(latitude: centerLat, longitude: centerLon)
                let idonea = isQuotaIdonea(quota: terrain.quota)
                
                let cella = CellaGrigliaTerritorio(
                    id: "cell_\(String(format: "%.3f", lat))_\(String(format: "%.3f", lon))",
                    minLat: lat,
                    maxLat: lat + stepGradiente,
                    minLon: lon,
                    maxLon: lon + stepGradiente,
                    centerLat: centerLat,
                    centerLon: centerLon,
                    quota: terrain.quota,
                    pendenza: terrain.pendenza,
                    esposizione: terrain.esposizione,
                    idonea: idonea
                )
                celle.append(cella)
                lon += stepGradiente
            }
            lat += stepGradiente
        }
        
        return celle
    }
    
    private func fallbackTerrain(lat: Double, lon: Double) -> (quota: Double, pendenza: Double, esposizione: String) {
        var quota = 250.0 // Di base bassa quota (non idonea per la costa)
        if lat > 39.7 && lon < 16.3 { // Pollino
            quota = 1150.0
        } else if lon > 16.25 && lat > 39.15 && lat < 39.6 { // Sila Grande / Sila Greca
            quota = 1300.0
        } else if lon < 16.08 && lat > 39.2 && lat < 39.65 { // Catena Costiera alti passi
            quota = 780.0
        } else if lon > 16.2 && lat <= 39.15 { // Serre Cosentine
            quota = 850.0
        }
        
        return (quota: quota, pendenza: 12.0, esposizione: "N")
    }
}
