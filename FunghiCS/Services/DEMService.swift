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
    
    /// Restituisce true se la quota rientra nella fascia boschiva/montana idonea ai funghi (>= 800m s.l.m.)
    func isQuotaIdonea(quota: Double) -> Bool {
        return quota >= 800.0 && quota <= 2100.0
    }
    
    /// Maschera geografica rigorosa per escludere il mare ed i litorali (Tirreno e Jonio)
    func isAreaMareOCosta(lat: Double, lon: Double, quota: Double) -> Bool {
        // Se la quota è sotto gli 800m è già non idonea
        if quota < 800.0 { return true }
        
        // Esclusione lato Tirreno (Costa di Scalea, Cetraro, Paola, Amantea)
        if lon < 15.95 { return true }
        
        // Esclusione lato Jonio (Costa di Roseto, Sibari, Rossano, Cariati)
        if lon > 16.60 { return true }
        
        // Piana di Sibari (bassa altitudine/pianura agricola)
        if lat > 39.65 && lat < 39.85 && lon > 16.25 && lon < 16.55 && quota < 800.0 {
            return true
        }
        
        return false
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
    
    /// Genera una griglia ad alta densità per una mappa di calore fluida e continua (senza bordi a scacchiera)
    func generaGrigliaTerritorio(stepGradiente: Double = 0.018) -> [CellaGrigliaTerritorio] {
        let minLat = 39.05
        let maxLat = 40.15
        let minLon = 15.85
        let maxLon = 16.75
        
        var celle: [CellaGrigliaTerritorio] = []
        var lat = minLat
        
        // Margine di sovrapposizione per eliminare linee di separazione tra celle
        let overlap = 0.003
        
        while lat < maxLat {
            var lon = minLon
            while lon < maxLon {
                let centerLat = lat + (stepGradiente / 2.0)
                let centerLon = lon + (stepGradiente / 2.0)
                let terrain = getTerrainData(latitude: centerLat, longitude: centerLon)
                
                let eMare = isAreaMareOCosta(lat: centerLat, lon: centerLon, quota: terrain.quota)
                let idonea = !eMare && isQuotaIdonea(quota: terrain.quota)
                
                let cella = CellaGrigliaTerritorio(
                    id: "cell_\(String(format: "%.4f", lat))_\(String(format: "%.4f", lon))",
                    minLat: lat - overlap,
                    maxLat: lat + stepGradiente + overlap,
                    minLon: lon - overlap,
                    maxLon: lon + stepGradiente + overlap,
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
        var quota = 200.0 // Bassa quota di default per escludere zone non montane
        
        // Massiccio del Pollino
        if lat >= 39.75 && lat <= 40.10 && lon >= 16.00 && lon <= 16.35 {
            quota = 1250.0
        }
        // Sila Grande e Piccola
        else if lat >= 39.15 && lat <= 39.55 && lon >= 16.25 && lon <= 16.70 {
            quota = 1350.0
        }
        // Catena Costiera alti passi (Fagnano, Monte Cocuzzo)
        else if lat >= 39.20 && lat <= 39.60 && lon >= 16.00 && lon <= 16.15 {
            quota = 920.0
        }
        // Serre Cosentine
        else if lat >= 39.05 && lat <= 39.20 && lon >= 16.15 && lon <= 16.40 {
            quota = 880.0
        }
        
        return (quota: quota, pendenza: 12.0, esposizione: "N")
    }
}
