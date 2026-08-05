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
        guard let url = Bundle.main.url(forResource: "cosenza_dem", withExtension: "json") else {
            print("DEM JSON non trovato nel bundle. Verranno usati valori di fallback.")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            self.demData = try decoder.decode(DEMDataFile.self, from: data)
            print("DEM TINITALY caricato con successo: \(self.demData?.points.count ?? 0) punti griglia.")
        } catch {
            print("Errore decodifica DEM JSON: \(error)")
        }
    }
    
    /// Restituisce (quota, pendenza, esposizione) per le coordinate specificate
    func getTerrainData(latitude: Double, longitude: Double) -> (quota: Double, pendenza: Double, esposizione: String) {
        guard let data = demData, !data.points.isEmpty else {
            // Fallback euristico basato su altimetria generica Cosenza
            return fallbackTerrain(lat: latitude, lon: longitude)
        }
        
        // Cerca il punto della griglia più vicino (Nearest Neighbor)
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
        
        if let punto = migliorPunto, minDistSq < 0.05 { // entro circa 5km
            return (quota: punto.elevation, pendenza: punto.slope, esposizione: punto.aspect)
        } else {
            return fallbackTerrain(lat: latitude, lon: longitude)
        }
    }
    
    private func fallbackTerrain(lat: Double, lon: Double) -> (quota: Double, pendenza: Double, esposizione: String) {
        // Stima euristica per la provincia di Cosenza (Sila vs Pollino vs Costa)
        var quota = 750.0
        if lat > 39.7 { // Pollino
            quota = 1100.0
        } else if lon > 16.3 { // Sila Grande / Sila Piccola
            quota = 1250.0
        } else if lon < 16.0 { // Catena Costiera
            quota = 650.0
        }
        
        return (quota: quota, pendenza: 12.0, esposizione: "N")
    }
}
