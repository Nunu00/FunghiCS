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
            self.demData = try decoder.decode(DEMDataFile.self, from: data)
            print("✅ DEM TINITALY con Copernicus CLC 2018 e Suoli caricato con successo: \(self.demData?.points.count ?? 0) punti orografici reali.")
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
    
    /// Restituisce la quota e i parametri orografici/satellitari/suolo reali per qualsiasi coordinate lat/lon
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
        guard let data = demData, !data.points.isEmpty else {
            return (0.0, 0.0, "N", 0.0, "farmland_urban", "CLC_211", "Zona non boschiva", "Terreno Agricolo/Urbano")
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
        
        if let punto = migliorPunto, minDistSq < 0.008 {
            let clc = punto.clcClass ?? "CLC_311"
            let kv = punto.kVeg ?? (punto.elevation >= 800.0 ? 1.0 : 0.0)
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
            default: nomeSuolo = "Terreno Standard"
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
