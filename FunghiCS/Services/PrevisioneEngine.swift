import Foundation

struct PrevisioneEngine {
    
    /// Calcola la probabilità di fruttificazione fungina combinando dati meteo, altimetrici/morfologici del punto
    /// ed applicando il Modello ad Incubazione Miceliare con Curva a Campana di Gauss (Gaussian Incubation Model)
    static func calcolaProbabilitaFruttificazione(punto: PuntoInteresse, meteo: DatiMeteo) -> RisultatoPrevisione {
        let sogliaBase: Double = 60.0 // 60 mm di pioggia base nei 15 giorni
        var fattoreCorrezione: Double = 1.0
        var ritardoGiorniQuota: Int = 0
        
        // 1. Correzione Quota (>1000m)
        if punto.quota > 1000.0 {
            // Sopra i 1000m: ritardo stagionale di innesco (14 giorni) e soglia pioggia -10%
            fattoreCorrezione *= 0.90
            ritardoGiorniQuota = 14
        }
        
        // 2. Correzione Esposizione
        let espUpper = punto.esposizione.uppercased()
        if espUpper.contains("S") {
            // Versanti Sud: +15% pioggia necessaria per maggiore evaporazione
            fattoreCorrezione *= 1.15
        } else if espUpper.contains("N") {
            // Versanti Nord: conserva umidità, fattore base
            fattoreCorrezione *= 1.0
        } else {
            // Est / Ovest: neutro
            fattoreCorrezione *= 1.0
        }
        
        // 3. Correzione Pendenza
        if punto.pendenza > 20.0 {
            // Pendenza ripida (>20°): +15% soglia per via del dilavamento/scorrimento acqua
            fattoreCorrezione *= 1.15
        } else if punto.pendenza < 5.0 {
            // Pianeggiante (<5°): -5% soglia per accumulo/ristagno umidità
            fattoreCorrezione *= 0.95
        }
        
        // 4. Calibrazione personalizzata dell'utente
        fattoreCorrezione *= max(0.5, min(2.0, punto.moltiplicatoreSoglia))
        
        let sogliaFinaleCalcolata = sogliaBase * fattoreCorrezione
        let pioggia = meteo.pioggiaCumulata15Giorni
        
        // 5. Temperatura Check (Range ideale boschi e pinete montane: 6.0°C - 26.0°C)
        let tempCentigradi = meteo.temperaturaMedia
        let tempFavorevole = (tempCentigradi >= 6.0 && tempCentigradi <= 26.0)
        
        // Calcolo dell'Ampiezza Potenziale Massima (P_max) basata sul volume d'acqua
        let rapportoPioggia = pioggia / max(1.0, sogliaFinaleCalcolata)
        var pMax = min(100.0, rapportoPioggia * 85.0)
        
        if !tempFavorevole {
            pMax *= 0.4 // Penalizzazione se temperatura fuori dal range miceliare
        }
        
        // 6. Modello ad Incubazione con Curva a Campana di Gauss
        // t = giorni trascorsi dall'evento piovoso significativo (>5mm)
        // mu = 6.5 giorni (picco di fruttificazione del carpoforo)
        // sigma = 2.5 giorni (ampiezza temporale della buttata)
        let t = Double(meteo.giorniDaUltimaPioggiaSignificativa)
        let mu: Double = 6.5
        let sigma: Double = 2.5
        
        let fattoreCampanaGauss = exp(-pow(t - mu, 2) / (2.0 * pow(sigma, 2)))
        var probCalc = pMax * fattoreCampanaGauss
        
        // Se la pioggia è abbondantissima (>soglia) ed il temporale è recentissimo (0-3 gg),
        // manteniamo una probabilità minima di innesco in preparazione (45-55%)
        if rapportoPioggia >= 1.0 && t <= 3 {
            probCalc = max(45.0, probCalc)
        }
        
        let probFinale = Int(max(0.0, min(100.0, probCalc)))
        
        // 7. Determinazione dello Stato Temporale
        let giorniDaPioggia = meteo.giorniDaUltimaPioggiaSignificativa
        let stato: StatoFruttificazione
        let messaggio: String
        
        if probFinale < 30 {
            stato = .nonFavorevole
            messaggio = "Condizioni non favorevoli (\(String(format: "%.1f", pioggia))mm / \(String(format: "%.1f", sogliaFinaleCalcolata))mm). Terreno troppo secco o tempo di incubazione scaduto."
        } else {
            switch giorniDaPioggia {
            case 0...3:
                stato = .inPreparazione
                messaggio = "Fase di Incubazione (Innesco Primordi). La pioggia ha bagnato il terreno, picco della buttata previsto tra 3-5 giorni."
            case 4...9:
                stato = .buttataProbabile
                messaggio = "Picco della Campana di Gauss! Condizioni ottimali sul campo, probabile fruttificazione in corso."
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
