import Foundation

struct PrevisioneEngine {
    
    /// Calcola la probabilità di fruttificazione fungina combinando dati meteo e altimetrici/morfologici del punto
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
        
        // 5. Temperatura Check (Temperatura media ideale tra 10°C e 24°C)
        let tempCentigradi = meteo.temperaturaMedia
        let tempFavorevole = (tempCentigradi >= 9.0 && tempCentigradi <= 25.0)
        
        // Calcolo della percentuale base di probabilità (0 - 100%)
        let rapportoPioggia = pioggia / max(1.0, sogliaFinaleCalcolata)
        var probBase = min(100.0, rapportoPioggia * 75.0)
        
        if !tempFavorevole {
            probBase *= 0.4 // penalizzazione se temperatura troppo rigida o caldissima
        }
        
        let probFinale = Int(max(0.0, min(100.0, probBase)))
        
        // 6. Determinazione dello Stato Temporale
        let giorniDaPioggia = meteo.giorniDaUltimaPioggiaSignificativa
        let stato: StatoFruttificazione
        let messaggio: String
        
        if probFinale < 40 {
            stato = .nonFavorevole
            messaggio = "Precipitazioni insufficienti (\(String(format: "%.1f", pioggia))mm / \(String(format: "%.1f", sogliaFinaleCalcolata))mm richiesti)."
        } else {
            switch giorniDaPioggia {
            case 0...3:
                stato = .inPreparazione
                messaggio = "Terreno in fase di innesco miceliare. Inizio buttata previsto nei prossimi giorni."
            case 4...10:
                stato = .buttataProbabile
                messaggio = "Condizioni ottimali! Probabile presenza di fruttificazione sul campo."
            case 11...15:
                stato = .inEsaurimento
                messaggio = "Umidità in calo. La buttata sta giungendo a termine."
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
                // Trovato funghi -> facilità maggiore del previsto, abbassa leggermente la soglia richiesta
                adeguamento -= 0.05
            } else {
                // Uscita a vuoto -> alza leggermente la soglia richiesta
                adeguamento += 0.05
            }
        }
        
        // Applica l'adeguamento limitandolo a un range di sicurezza [0.6, 1.5]
        let nuovoMoltiplicatore = punto.moltiplicatoreSoglia + adeguamento
        punto.moltiplicatoreSoglia = max(0.6, min(1.5, nuovoMoltiplicatore))
    }
}
