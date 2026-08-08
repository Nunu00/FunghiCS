import Foundation

struct PrevisioneEngine {
    
    /// Calcola la probabilità di fruttificazione fungina combinando dati meteo avanzati, altimetrici,
    /// copertura forestale Copernicus (K_veg), trama del suolo SoilGrids, shock termico e penalizzazione vento secco.
    static func calcolaProbabilitaFruttificazione(punto: PuntoInteresse, meteo: DatiMeteo) -> RisultatoPrevisione {
        let terrainInfo = DEMService.shared.getTerrainData(latitude: punto.latitude, longitude: punto.longitude)
        
        let kVeg = terrainInfo.kVeg
        let soilType = terrainInfo.soilType
        
        // Se K_veg è 0.0 (roccia nuda, acqua o urbano), la probabilità è 0% (nessuna fruttificazione simbiotica possibile)
        if kVeg <= 0.0 {
            return RisultatoPrevisione(
                stato: .nonFavorevole,
                probabilitaPercentuale: 0,
                pioggiaCumulata15gg: meteo.pioggiaCumulata15Giorni,
                sogliaRichiesta: 60.0,
                messaggioDettagliato: "Superficie non boschiva (\(terrainInfo.nomeVegetazione)). I funghi micorrizici nascono solo in simbiosi con gli alberi.",
                ritardoGiorniQuota: 0
            )
        }
        
        let sogliaBase: Double = 60.0
        var fattoreCorrezione: Double = 1.0
        var ritardoGiorniQuota: Int = 0
        
        // 1. Correzione Quota (>1000m)
        if punto.quota > 1000.0 {
            fattoreCorrezione *= 0.90
            ritardoGiorniQuota = 14
        }
        
        // 2. Correzione Esposizione
        let espUpper = punto.esposizione.uppercased()
        if espUpper.contains("S") {
            fattoreCorrezione *= 1.15
        } else if espUpper.contains("N") {
            fattoreCorrezione *= 1.0
        }
        
        // 3. Correzione Pendenza
        if punto.pendenza > 20.0 {
            fattoreCorrezione *= 1.15
        } else if punto.pendenza < 5.0 {
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
            pMax *= 0.4 // Penalizzazione se terreno troppo freddo o troppo caldo
        }
        
        // 6. Bonus Shock Termico del Terreno (Delta T >= 3.5°C)
        if meteo.deltaTSuolo >= 3.5 && pioggia >= 20.0 {
            pMax *= 1.20 // +20% bonus innesco da shock termico
        }
        
        // 7. Penalizzazione Vento Secco (Vento > 22 km/h o alta evapotraspirazione)
        let kVento = (meteo.velocitaVentoMax > 22.0 || meteo.evapotraspirazioneET0 > 4.5) ? 0.70 : 1.00
        
        // 8. Modello ad Incubazione con Curva a Campana di Gauss e Trama del Suolo (SoilGrids)
        // Sila (sandy_granite): sigma = 1.8 (drenaggio rapido)
        // Pollino (clay_limestone): sigma = 3.0 (ritenzione prolungata)
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
        
        if rapportoPioggia >= 1.0 && t <= 3 {
            probCalc = max(45.0, probCalc)
        }
        
        let probFinale = Int(max(0.0, min(100.0, probCalc)))
        
        // 10. Determinazione dello Stato Temporale
        let giorniDaPioggia = meteo.giorniDaUltimaPioggiaSignificativa
        let stato: StatoFruttificazione
        let messaggio: String
        
        if probFinale < 30 {
            stato = .nonFavorevole
            messaggio = "Condizioni non favorevoli (\(String(format: "%.1f", pioggia))mm / \(String(format: "%.1f", sogliaFinaleCalcolata))mm). Suolo secco (\(String(format: "%.2f", meteo.umiditaSuoloMiceliare))m³/m³) o tempo incubazione scaduto."
        } else {
            switch giorniDaPioggia {
            case 0...3:
                stato = .inPreparazione
                messaggio = "Fase di Incubazione (Innesco Primordi). Pioggia penetrata nel suolo, picco della buttata previsto tra 3-5 giorni."
            case 4...9:
                stato = .buttataProbabile
                messaggio = "Picco della Campana di Gauss! Suolo idratato (\(terrainInfo.nomeSuolo)), probabile fruttificazione in corso."
            case 10...14:
                stato = .inEsaurimento
                messaggio = "Fase Calante della Campana. Umidità del suolo in esaurimento, buttata in fase di termine."
            default:
                stato = .nonFavorevole
                messaggio = "Troppi giorni trascorsi dall'ultimo evento piovoso significativo."
            }
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
