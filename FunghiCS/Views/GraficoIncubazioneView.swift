import SwiftUI
import Charts

struct PuntoIncubazione: Identifiable {
    let id = UUID()
    let giorno: Int             // 0..14 giorni dall'evento piovoso
    let etichettaGiorno: String // "-6g", "-5g", "OGGI", "+1g", etc.
    let probabilita: Double    // Punteggio 0..100%
    let eOggi: Bool
}

struct GraficoIncubazioneView: View {
    let punto: PuntoInteresse
    let meteo: DatiMeteo
    let previsione: RisultatoPrevisione
    
    private var dataPoints: [PuntoIncubazione] {
        let tAttuale = meteo.giorniDaUltimaPioggiaSignificativa
        let tMax = 14
        
        let terrainInfo = DEMService.shared.getTerrainData(latitude: punto.latitude, longitude: punto.longitude)
        let soilType = terrainInfo.soilType
        
        let sigma: Double
        switch soilType {
        case "sandy_granite": sigma = 1.8
        case "clay_limestone": sigma = 3.0
        default: sigma = 2.4
        }
        
        let quotaPunto = punto.quota > 0 ? punto.quota : terrainInfo.quota
        let pendenzaPunto = punto.pendenza > 0 ? punto.pendenza : terrainInfo.pendenza
        let esposizionePunto = !punto.esposizione.isEmpty ? punto.esposizione : terrainInfo.esposizione
        let kVeg = quotaPunto >= 800.0 ? 1.00 : terrainInfo.kVeg
        
        let sogliaBase: Double = 60.0
        var fattoreCorrezione: Double = 1.0
        if quotaPunto > 1000.0 { fattoreCorrezione *= 0.90 }
        let espUpper = esposizionePunto.uppercased()
        if espUpper.contains("S") { fattoreCorrezione *= 1.15 }
        if pendenzaPunto > 20.0 { fattoreCorrezione *= 1.15 }
        else if pendenzaPunto < 5.0 { fattoreCorrezione *= 0.95 }
        
        let sogliaFinale = sogliaBase * fattoreCorrezione
        let rapportoPioggia = meteo.pioggiaCumulata15Giorni / max(1.0, sogliaFinale)
        var pMax = min(100.0, rapportoPioggia * 85.0)
        
        if !(meteo.temperaturaSuolo >= 8.0 && meteo.temperaturaSuolo <= 26.0) { pMax *= 0.4 }
        if meteo.deltaTSuolo >= 3.5 && meteo.pioggiaCumulata15Giorni >= 20.0 { pMax *= 1.20 }
        
        let ventoAlSuolo = meteo.velocitaVentoMax * 0.40
        let kVento = (ventoAlSuolo > 15.0 || meteo.evapotraspirazioneET0 > 5.5) ? 0.75 : 1.00
        let kUmiditaSuolo = meteo.umiditaSuoloMiceliare < 0.18 ? max(0.2, meteo.umiditaSuoloMiceliare / 0.18) : 1.0
        
        var points: [PuntoIncubazione] = []
        
        for g in 0...tMax {
            let offsetGiorno = g - tAttuale
            let label: String
            if offsetGiorno == 0 {
                label = "OGGI"
            } else if offsetGiorno > 0 {
                label = "+\(offsetGiorno)g"
            } else {
                label = "\(offsetGiorno)g"
            }
            
            let mu: Double = 6.5
            let gauss = exp(-pow(Double(g) - mu, 2) / (2.0 * pow(sigma, 2)))
            var probCalc = pMax * gauss * kVeg * kVento * kUmiditaSuolo
            
            if rapportoPioggia >= 0.50 && g <= 6 {
                probCalc = max(38.0, probCalc)
            }
            let finalProb = max(0.0, min(100.0, probCalc))
            
            points.append(PuntoIncubazione(
                giorno: g,
                etichettaGiorno: label,
                probabilita: finalProb,
                eOggi: (g == tAttuale)
            ))
        }
        
        return points
    }
    
    private var faseAttualeSintesi: (testo: String, colore: Color, icona: String) {
        let t = meteo.giorniDaUltimaPioggiaSignificativa
        if t <= 4 {
            return ("Incubazione Miceliare (Primordi nel terreno)", .orange, "leaf.arrow.triangle.circlepath")
        } else if t >= 5 && t <= 8 {
            return ("Picco della Buttata (Carpofori Pronti!)", .green, "checkmark.seal.fill")
        } else {
            return ("Fase di Discesa (Terreno in Asciugatura)", .secondary, "clock.arrow.circlepath")
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("📊 Curva di Incubazione Miceliare")
                        .font(.headline)
                    Text("Fase biologica del terreno (SoilGrids + Gauss)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            // Badge Sintesi Stato del Micelio ad Oggi
            HStack(spacing: 6) {
                Image(systemName: faseAttualeSintesi.icona)
                    .foregroundColor(faseAttualeSintesi.colore)
                Text(faseAttualeSintesi.testo)
                    .font(.caption)
                    .bold()
                    .foregroundColor(faseAttualeSintesi.colore)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(faseAttualeSintesi.colore.opacity(0.15))
            .cornerRadius(8)
            
            // Grafico Campana di Gauss Nativo SwiftUI Charts
            Chart {
                ForEach(dataPoints) { p in
                    AreaMark(
                        x: .value("Giorno", p.etichettaGiorno),
                        y: .value("Probabilità", p.probabilita)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.green.opacity(0.4), Color.green.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    
                    LineMark(
                        x: .value("Giorno", p.etichettaGiorno),
                        y: .value("Probabilità", p.probabilita)
                    )
                    .foregroundStyle(Color.green)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                    
                    if p.eOggi {
                        RuleMark(x: .value("Giorno", p.etichettaGiorno))
                            .foregroundStyle(Color.blue)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                            .annotation(position: .top, alignment: .center) {
                                Text("📍 OGGI (\(Int(p.probabilita))%)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue)
                                    .cornerRadius(6)
                            }
                    }
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel("\(value.as(Int.self) ?? 0)%")
                        .font(.caption2)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisGridLine()
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .frame(height: 180)
            .padding(.top, 10)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
