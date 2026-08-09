import Foundation

struct DEMGridPoint: Codable {
    let lat: Double
    let lon: Double
    let elevation: Double
    let slope: Double
    let aspect: String
    let clcClass: String?
    let kVeg: Double?
    let soilType: String?
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
    private var spatialGrid: [[DEMGridPoint?]] = []
    private let gridRows = 350
    private let gridCols = 350
    
    private init() {
        caricaDEMJSON()
    }
    
    private func caricaDEMJSON() {
        let url = Bundle.main.url(forResource: "cosenza_dem", withExtension: "json") ??
                  Bundle.main.url(forResource: "cosenza_dem", withExtension: "json", subdirectory: "DEM")
        
        guard let validUrl = url else {
            print("❌ ERRORE CRITICO: cosenza_dem.json non trovato nel bundle!")
            return
        }
        
        do {
            let data = try Data(contentsOf: validUrl)
            let decoder = JSONDecoder()
            let loaded = try decoder.decode(DEMDataFile.self, from: data)
            self.demData = loaded
            
            // Costruzione della Griglia Spaziale O(1) in memoria (350x350 bucket)
            var grid = Array(repeating: Array<DEMGridPoint?>(repeating: nil, count: gridCols), count: gridRows)
            let minLat = loaded.minLat
            let maxLat = loaded.maxLat
            let minLon = loaded.minLon
            let maxLon = loaded.maxLon
            
            let dLat = maxLat - minLat
            let dLon = maxLon - minLon
            
            if dLat > 0 && dLon > 0 {
                for p in loaded.points {
                    let r = min(gridRows - 1, max(0, Int(((maxLat - p.lat) / dLat) * Double(gridRows - 1))))
                    let c = min(gridCols - 1, max(0, Int(((p.lon - minLon) / dLon) * Double(gridCols - 1))))
                    grid[r][c] = p
                }
            }
            
            self.spatialGrid = grid
            print("✅ DEM TINITALY O(1) con Copernicus CLC 2018 e Suoli caricato con successo: \(loaded.points.count) punti orografici reali.")
        } catch {
            print("❌ Errore decodifica DEM JSON: \(error)")
        }
    }
    
    /// Restituisce true se la quota rientra nella fascia montana/boschiva idonea ai funghi (>= 800m s.l.m.)
    func isQuotaIdonea(quota: Double) -> Bool {
        return quota >= 800.0 && quota <= 2500.0
    }
    
    /// Restituisce true se la posizione si trova sul mare o sulla costa (quota <= 20m)
    func isAreaMareOCosta(lat: Double, lon: Double, quota: Double) -> Bool {
        return quota <= 20.0
    }
    
    /// Restituisce la quota e i parametri orografici/satellitari/suolo reali in O(1) sub-millisecondo
    func getTerrainData(latitude: Double, longitude: Double) -> (
        quota: Double,
        pendenza: Double,
        esposizione: String,
        kVeg: Double,
        soilType: String,
        clcClass: String,
        nomeVegetazione: String,
        nomeSuolo: String
    ) {
        guard let data = demData, !spatialGrid.isEmpty else {
            return (0.0, 0.0, "N", 0.0, "farmland_urban", "CLC_211", "Zona non boschiva", "Terreno Agricolo/Urbano")
        }
        
        let minLat = data.minLat
        let maxLat = data.maxLat
        let minLon = data.minLon
        let maxLon = data.maxLon
        
        let dLat = maxLat - minLat
        let dLon = maxLon - minLon
        
        var migliorPunto: DEMGridPoint? = nil
        
        if dLat > 0 && dLon > 0 {
            let r = min(gridRows - 1, max(0, Int(((maxLat - latitude) / dLat) * Double(gridRows - 1))))
            let c = min(gridCols - 1, max(0, Int(((longitude - minLon) / dLon) * Double(gridCols - 1))))
            
            migliorPunto = spatialGrid[r][c]
            
            // Se la cella esatta è vuota, cerca nelle 8 celle adiacenti
            if migliorPunto == nil {
                outerLoop: for dr in -1...1 {
                    for dc in -1...1 {
                        let nr = r + dr
                        let nc = c + dc
                        if nr >= 0 && nr < gridRows && nc >= 0 && nc < gridCols {
                            if let candidate = spatialGrid[nr][nc] {
                                migliorPunto = candidate
                                break outerLoop
                            }
                        }
                    }
                }
            }
        }
        
        if let punto = migliorPunto {
            let clc = punto.clcClass ?? (punto.elevation >= 800.0 ? "CLC_312_Coniferous_Pine_Forest" : "CLC_211")
            let kv = punto.elevation >= 800.0 ? 1.0 : (punto.kVeg ?? 0.0)
            let soil = punto.soilType ?? "sandy_granite"
            
            let nomeVeg: String
            switch clc {
            case "CLC_312_Coniferous_Pine_Forest": nomeVeg = "Pineta di Pino Laricio (Sila)"
            case "CLC_311_Broadleaved_Forest": nomeVeg = "Bosco di Latifoglie (Castagno/Quercia)"
            case "CLC_311_Broadleaved_Beech_Forest": nomeVeg = "Fagjeta Alta Quota"
            case "CLC_313_Mixed_Forest": nomeVeg = "Bosco Misto (Faggio/Abete/Pino)"
            case "CLC_324_Transitional_Woodland": nomeVeg = "Macchia Pedemontana / Arbusteto"
            case "CLC_512_Water_Bodies": nomeVeg = "Superficie Lacustre / Lago"
            case "CLC_332_Bare_Rock_Screes": nomeVeg = "Roccia Nuda / Ghiaione Sommitale"
            default: nomeVeg = kv > 0 ? "Bosco Montano Naturale" : "Zona Non Boschiva"
            }
            
            let nomeSuolo: String
            switch soil {
            case "sandy_granite": nomeSuolo = "Granitico-Sabbioso (Drenaggio Rapido)"
            case "clay_limestone": nomeSuolo = "Calcareo-Argilloso (Ritenzione Prolungata)"
            case "loam_metamorphic": nomeSuolo = "Limoso-Metamorfico (Drenaggio Bilanciato)"
            default: nomeSuolo = "Terreno Montano"
            }
            
            return (
                quota: punto.elevation,
                pendenza: punto.slope,
                esposizione: punto.aspect,
                kVeg: kv,
                soilType: soil,
                clcClass: clc,
                nomeVegetazione: nomeVeg,
                nomeSuolo: nomeSuolo
            )
        } else {
            return (0.0, 0.0, "N", 0.0, "farmland_urban", "CLC_211", "Zona non boschiva", "Terreno Agricolo/Urbano")
        }
    }
    
    /// Restituisce tutti i punti altimetrici INGV 10m presenti nelle zone montane boschive idonee
    func getPuntiMontaniIdonei() -> [DEMGridPoint] {
        guard let data = demData else { return [] }
        return data.points.filter { ($0.kVeg ?? 1.0) > 0.0 && $0.elevation >= 600.0 }
    }
}
