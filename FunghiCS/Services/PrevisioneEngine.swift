import Foundation
import CoreGraphics

struct PrevisioneEngine {
    
    /// Calcola la probabilità di fruttificazione fungina combinando dati meteo avanzati, altimetrici,
    /// copertura forestale Copernicus (K_veg), trama del suolo SoilGrids, shock termico e penalizzazione vento secco.
    static func calcolaProbabilitaFruttificazione(punto: PuntoInteresse, meteo: DatiMeteo) -> RisultatoPrevisione {
        let terrainInfo = DEMService.shared.getTerrainData(latitude: punto.latitude, longitude: punto.longitude)
        
        let quotaPunto = punto.quota > 0 ? punto.quota : terrainInfo.quota
        let pendenzaPunto = punto.pendenza > 0 ? punto.pendenza : terrainInfo.pendenza
        let esposizionePunto = !punto.esposizione.isEmpty ? punto.esposizione : terrainInfo.esposizione
        
        let kVeg = quotaPunto >= 800.0 ? 1.00 : terrainInfo.kVeg
        let soilType = terrainInfo.soilType
        
        if kVeg <= 0.0 {
            return RisultatoPrevisione(
                stato: .nonFavorevole,
                probabilitaPercentuale: 0,
                pioggiaCumulata15gg: meteo.pioggiaCumulata15Giorni,
                sogliaRichiesta: 60.0,
                messaggioDettagliato: "Quota o superficie non idonea alla fruttificazione.",
                ritardoGiorniQuota: 0
            )
        }
        
        let sogliaBase: Double = 60.0
        var fattoreCorrezione: Double = 1.0
        var ritardoGiorniQuota: Int = 0
        
        // 1. Correzione Quota (>1000m)
        if quotaPunto > 1000.0 {
            fattoreCorrezione *= 0.90
            ritardoGiorniQuota = 14
        }
        
        // 2. Correzione Esposizione
        let espUpper = esposizionePunto.uppercased()
        if espUpper.contains("S") {
            fattoreCorrezione *= 1.15
        } else if espUpper.contains("N") {
            fattoreCorrezione *= 1.0
        }
        
        // 3. Correzione Pendenza
        if pendenzaPunto > 20.0 {
            fattoreCorrezione *= 1.15
        } else if pendenzaPunto < 5.0 {
            fattoreCorrezione *= 0.95
        }
        
        // 4. Calibrazione personalizzata dell'utente
        fattoreCorrezione *= max(0.5, min(2.0, punto.moltiplicatoreSoglia))
        
        let sogliaFinaleCalcolata = sogliaBase * fattoreCorrezione
        let pioggia = meteo.pioggiaCumulata15Giorni
        
        // 5. Temperatura Suolo (Range ideale miceliare: 10.0°C - 22.0°C)
        let tempSuolo = meteo.temperaturaSuolo
        let tempFavorevole = (tempSuolo >= 8.0 && tempSuolo <= 26.0)
        
        // Ampiezza Potenziale Massima (P_max)
        let rapportoPioggia = pioggia / max(1.0, sogliaFinaleCalcolata)
        var pMax = min(100.0, rapportoPioggia * 85.0)
        
        if !tempFavorevole {
            pMax *= 0.4
        }
        
        // 6. Bonus Shock Termico del Terreno (Delta T >= 3.5°C)
        if meteo.deltaTSuolo >= 3.5 && pioggia >= 20.0 {
            pMax *= 1.20
        }
        
        // 7. Penalizzazione Vento Secco sotto Chioma Forestale (Vento al suolo = 0.40 * Vento 10m Open-Meteo)
        let ventoAlSuolo = meteo.velocitaVentoMax * 0.40
        let kVento = (ventoAlSuolo > 15.0 || meteo.evapotraspirazioneET0 > 5.5) ? 0.75 : 1.00
        
        // 8. Modello ad Incubazione con Curva a Campana di Gauss e Trama del Suolo (SoilGrids)
        let sigma: Double
        switch soilType {
        case "sandy_granite": sigma = 1.8
        case "clay_limestone": sigma = 3.0
        default: sigma = 2.4
        }
        
        let t = Double(meteo.giorniDaUltimaPioggiaSignificativa)
        let mu: Double = 6.5
        let fattoreCampanaGauss = exp(-pow(t - mu, 2) / (2.0 * pow(sigma, 2)))
        
        // 9. Check Umidità dello Strato Miceliare a 3-9 cm
        let kUmiditaSuolo = meteo.umiditaSuoloMiceliare < 0.18 ? max(0.2, meteo.umiditaSuoloMiceliare / 0.18) : 1.0
        
        var probCalc = pMax * fattoreCampanaGauss * kVeg * kVento * kUmiditaSuolo
        
        if rapportoPioggia >= 1.0 && t <= 6 {
            probCalc = max(48.0, probCalc)
        }
        
        let probFinale = Int(max(0.0, min(100.0, probCalc)))
        
        // 10. Determinazione dello Stato e del Messaggio di Sintesi ALLINEATO 100% ALLA LEGENDA COLORE
        let stato: StatoFruttificazione
        let messaggio: String
        
        if probFinale >= 65 {
            // VERDE (>65%)
            stato = .buttataProbabile
            messaggio = "Suolo idratato. Probabile fruttificazione in corso."
        } else if probFinale >= 48 {
            // ARANCIONE (48-64%) -> SEMPRE "IN PREPARAZIONE / INCUBAZIONE"
            stato = .inPreparazione
            messaggio = "Suolo idratato. Inizio fase di incubazione."
        } else if probFinale >= 30 {
            // GIALLO (30-47%) -> SEMPRE "IN ESAURIMENTO / CALANTE"
            stato = .inEsaurimento
            messaggio = "Suolo in corso di asciugatura. Fase calante della fruttificazione."
        } else {
            // GRIGIO (<30%)
            stato = .nonFavorevole
            messaggio = "Suolo non idratato. Condizioni non favorevoli alla fruttificazione."
        }
        
        return RisultatoPrevisione(
            stato: stato,
            probabilitaPercentuale: probFinale,
            pioggiaCumulata15gg: pioggia,
            sogliaRichiesta: sogliaFinaleCalcolata,
            messaggioDettagliato: messaggio,
            ritardoGiorniQuota: ritardoGiorniQuota
        )
    }
    
    /// Pre-calcola la bitmap CGImage della mappa di calore della fruttificazione
    static func generaHeatmapBitmap() async -> CGImage? {
        return await Task.detached(priority: .userInitiated) { () -> CGImage? in
            let width = 300
            let height = 300
            let bytesPerRow = width * 4
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            
            guard let bitmapContext = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return nil
            }
            
            guard let rawPointer = bitmapContext.data else { return nil }
            let pixels = rawPointer.bindMemory(to: UInt8.self, capacity: width * height * 4)
            
            let minLat: Double = 38.80
            let maxLat: Double = 40.35
            let minLon: Double = 15.80
            let maxLon: Double = 17.25
            
            let nodi = MeteoService.nodiGrigliaSpaziale
            
            for y in 0..<height {
                let lat = maxLat - (Double(y) / Double(height)) * (maxLat - minLat)
                
                for x in 0..<width {
                    let lon = minLon + (Double(x) / Double(width)) * (maxLon - minLon)
                    
                    let terrain = DEMService.shared.getTerrainData(latitude: lat, longitude: lon)
                    let quota = terrain.quota
                    let isIdonea = DEMService.shared.isQuotaIdonea(quota: quota)
                    let eMare = DEMService.shared.isAreaMareOCosta(lat: lat, lon: lon, quota: quota)
                    
                    let idx = (y * width + x) * 4
                    
                    if eMare || quota == 0.0 || !isIdonea {
                        pixels[idx]     = 0
                        pixels[idx + 1] = 0
                        pixels[idx + 2] = 0
                        pixels[idx + 3] = 0
                    } else {
                        var pioggiaLocale = 38.0
                        var tempBase = 16.5
                        var giorniDaPioggia = 4
                        var umiditaSuolo = 0.25
                        var tempSuolo = 15.0
                        var deltaTSuolo = 0.0
                        var ventoMax = 10.0
                        var et0Val = 2.5
                        
                        if !nodi.isEmpty {
                            var pesoTotale = 0.0
                            var pioggiaPesata = 0.0
                            var tempPesata = 0.0
                            var giorniDaPioggiaPesati = 0.0
                            var smPesata = 0.0
                            var stPesata = 0.0
                            var dtPesato = 0.0
                            var ventoPesato = 0.0
                            var et0Pesata = 0.0
                            
                            for n in nodi {
                                let d2 = (n.lat - lat)*(n.lat - lat) + (n.lon - lon)*(n.lon - lon)
                                let w = 1.0 / max(0.0001, d2)
                                pesoTotale += w
                                pioggiaPesata += n.pioggia15gg * w
                                tempPesata += n.tempMedia * w
                                giorniDaPioggiaPesati += Double(n.giorniDaPioggia) * w
                                smPesata += n.umiditaSuoloMiceliare * w
                                stPesata += n.temperaturaSuolo * w
                                dtPesato += n.deltaTSuolo * w
                                ventoPesato += n.velocitaVentoMax * w
                                et0Pesata += n.evapotraspirazioneET0 * w
                            }
                            
                            if pesoTotale > 0 {
                                pioggiaLocale = pioggiaPesata / pesoTotale
                                tempBase = tempPesata / pesoTotale
                                giorniDaPioggia = Int(round(giorniDaPioggiaPesati / pesoTotale))
                                umiditaSuolo = smPesata / pesoTotale
                                tempSuolo = stPesata / pesoTotale
                                deltaTSuolo = dtPesato / pesoTotale
                                ventoMax = ventoPesato / pesoTotale
                                et0Val = et0Pesata / pesoTotale
                            }
                        }
                        
                        let tempQuota = max(8.0, tempBase - max(0.0, (quota - 800.0) / 160.0))
                        let meteoLocale = DatiMeteo(
                            pioggiaCumulata15Giorni: pioggiaLocale,
                            temperaturaMedia: tempQuota,
                            umiditaMedia: 65.0,
                            umiditaSuoloMiceliare: umiditaSuolo,
                            temperaturaSuolo: tempSuolo,
                            deltaTSuolo: deltaTSuolo,
                            velocitaVentoMax: ventoMax,
                            evapotraspirazioneET0: et0Val,
                            giorniDaUltimaPioggiaSignificativa: giorniDaPioggia
                        )
                        
                        let pTemp = PuntoInteresse(
                            nome: "Pixel",
                            latitude: lat,
                            longitude: lon,
                            quota: quota,
                            pendenza: terrain.pendenza,
                            esposizione: terrain.esposizione
                        )
                        let res = PrevisioneEngine.calcolaProbabilitaFruttificazione(punto: pTemp, meteo: meteoLocale)
                        let prob = res.probabilitaPercentuale
                        
                        if prob >= 65 {
                            // Verde Buttata Probabile (>65%)
                            pixels[idx]     = 34  // R
                            pixels[idx + 1] = 197 // G
                            pixels[idx + 2] = 94  // B
                            pixels[idx + 3] = 200 // Alpha
                        } else if prob >= 48 {
                            // Arancione In Preparazione (48-64%)
                            pixels[idx]     = 249 // R
                            pixels[idx + 1] = 115 // G
                            pixels[idx + 2] = 22  // B
                            pixels[idx + 3] = 200 // Alpha
                        } else if prob >= 30 {
                            // Giallo In Esaurimento (30-47%)
                            pixels[idx]     = 234 // R
                            pixels[idx + 1] = 179 // G
                            pixels[idx + 2] = 8   // B
                            pixels[idx + 3] = 190 // Alpha
                        } else {
                            // Grigio Non Favorevole (<30%)
                            pixels[idx]     = 156 // R
                            pixels[idx + 1] = 163 // G
                            pixels[idx + 2] = 175 // B
                            pixels[idx + 3] = 140 // Alpha
                        }
                    }
                }
            }
            
            print("✅ [DEBUG] Heatmap CGImage pre-calcolata con successo in memoria heap!")
            return bitmapContext.makeImage()
        }.value
    }
    
    /// Pre-calcola la bitmap CGImage della mappa Radar Precipitazioni 15 giorni (mm)
    static func generaPrecipitazioniBitmap() async -> CGImage? {
        return await Task.detached(priority: .userInitiated) { () -> CGImage? in
            let width = 300
            let height = 300
            let bytesPerRow = width * 4
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            
            guard let bitmapContext = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return nil
            }
            
            guard let rawPointer = bitmapContext.data else { return nil }
            let pixels = rawPointer.bindMemory(to: UInt8.self, capacity: width * height * 4)
            
            let minLat: Double = 38.80
            let maxLat: Double = 40.35
            let minLon: Double = 15.80
            let maxLon: Double = 17.25
            
            let nodi = MeteoService.nodiGrigliaSpaziale
            
            for y in 0..<height {
                let lat = maxLat - (Double(y) / Double(height)) * (maxLat - minLat)
                
                for x in 0..<width {
                    let lon = minLon + (Double(x) / Double(width)) * (maxLon - minLon)
                    
                    let terrain = DEMService.shared.getTerrainData(latitude: lat, longitude: lon)
                    let quota = terrain.quota
                    let isIdonea = DEMService.shared.isQuotaIdonea(quota: quota)
                    let eMare = DEMService.shared.isAreaMareOCosta(lat: lat, lon: lon, quota: quota)
                    
                    let idx = (y * width + x) * 4
                    
                    if eMare || quota == 0.0 || !isIdonea {
                        pixels[idx]     = 0
                        pixels[idx + 1] = 0
                        pixels[idx + 2] = 0
                        pixels[idx + 3] = 0
                    } else {
                        var pioggiaLocale = 38.0
                        
                        if !nodi.isEmpty {
                            var pesoTotale = 0.0
                            var pioggiaPesata = 0.0
                            for n in nodi {
                                let d2 = (n.lat - lat)*(n.lat - lat) + (n.lon - lon)*(n.lon - lon)
                                let w = 1.0 / max(0.0001, d2)
                                pesoTotale += w
                                pioggiaPesata += n.pioggia15gg * w
                            }
                            if pesoTotale > 0 {
                                pioggiaLocale = pioggiaPesata / pesoTotale
                            }
                        }
                        
                        if pioggiaLocale >= 70.0 {
                            // Blu Scuro Elettrico (Abbondante >= 70mm)
                            pixels[idx]     = 30
                            pixels[idx + 1] = 64
                            pixels[idx + 2] = 175
                            pixels[idx + 3] = 210
                        } else if pioggiaLocale >= 45.0 {
                            // Azzurro Ciano Intenso (Ottima 45-69mm)
                            pixels[idx]     = 6
                            pixels[idx + 1] = 182
                            pixels[idx + 2] = 212
                            pixels[idx + 3] = 200
                        } else if pioggiaLocale >= 25.0 {
                            // Verde Acqua Smeraldo (Moderata 25-44mm)
                            pixels[idx]     = 16
                            pixels[idx + 1] = 185
                            pixels[idx + 2] = 129
                            pixels[idx + 3] = 190
                        } else if pioggiaLocale >= 10.0 {
                            // Giallo Sabbia (Scarsa 10-24mm)
                            pixels[idx]     = 234
                            pixels[idx + 1] = 179
                            pixels[idx + 2] = 8
                            pixels[idx + 3] = 170
                        } else {
                            // Grigio Trasparente (<10mm)
                            pixels[idx]     = 156
                            pixels[idx + 1] = 163
                            pixels[idx + 2] = 175
                            pixels[idx + 3] = 120
                        }
                    }
                }
            }
            
            print("✅ [DEBUG] Heatmap Precipitazioni 15gg CGImage pre-calcolata con successo!")
            return bitmapContext.makeImage()
        }.value
    }
    
    /// Calibra il moltiplicatore di soglia del punto in base alle osservazioni storiche dell'utente
    static func ricalibraMoltiplicatore(punto: PuntoInteresse) {
        let osservazioni = punto.osservazioni
        guard !osservazioni.isEmpty else { return }
        
        var adeguamento: Double = 0.0
        for obs in osservazioni {
            if obs.trovato {
                adeguamento -= 0.05
            } else {
                adeguamento += 0.05
            }
        }
        let nuovoMoltiplicatore = max(0.5, min(2.0, punto.moltiplicatoreSoglia + adeguamento))
        punto.moltiplicatoreSoglia = nuovoMoltiplicatore
    }
}
