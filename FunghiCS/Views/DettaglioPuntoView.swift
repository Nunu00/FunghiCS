import SwiftUI
import SwiftData
import Charts

struct DettaglioPuntoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let punto: PuntoInteresse
    
    @State private var meteo: DatiMeteo? = nil
    @State private var previsione: RisultatoPrevisione? = nil
    @State private var mostrandoAggiungiObs = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    cardPrevisione
                    if let m = meteo, let prev = previsione {
                        GraficoIncubazioneView(punto: punto, meteo: m, previsione: prev)
                    }
                    cardTerrenoCopernicus
                    cardMeteo
                    cardOsservazioni
                }
                .padding()
            }
            .navigationTitle(punto.nome)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .sheet(isPresented: $mostrandoAggiungiObs) {
                AggiungiOsservazioneView(punto: punto)
            }
            .task {
                let m = await MeteoService.shared.fetchMeteo(latitude: punto.latitude, longitude: punto.longitude)
                self.meteo = m
                self.previsione = PrevisioneEngine.calcolaProbabilitaFruttificazione(punto: punto, meteo: m)
            }
        }
    }
    
    @ViewBuilder
    private var cardPrevisione: some View {
        if let prev = previsione {
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: prev.stato.icona)
                        .font(.system(size: 36))
                        .foregroundColor(prev.stato.colore)
                    VStack(alignment: .leading) {
                        Text("\(prev.probabilitaPercentuale)% Probabilità")
                            .font(.title).bold()
                        Text(prev.stato.rawValue)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                Divider()
                
                Text(prev.messaggioDettagliato)
                    .font(.body).bold()
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        } else {
            ProgressView("Calcolo previsione e meteo...")
                .padding()
        }
    }
    
    @ViewBuilder
    private var cardTerrenoCopernicus: some View {
        let tInfo = DEMService.shared.getTerrainData(latitude: punto.latitude, longitude: punto.longitude)
        let isBosco = tInfo.kVeg > 0
        let colorVeg: Color = isBosco ? .green : .red
        
        VStack(alignment: .leading, spacing: 10) {
            Text("Terreno & Copertura Satellitare Copernicus")
                .font(.headline)
            
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Quota:").bold()
                    Text("\(Int(punto.quota)) m s.l.m.")
                    Text("Pendenza:").bold()
                    Text("\(String(format: "%.1f", punto.pendenza))°")
                }
                GridRow {
                    Text("Esposizione:").bold()
                    Text(punto.esposizione)
                    Text("Idoneità K_veg:").bold()
                    Text("\(String(format: "%.2f", tInfo.kVeg))x")
                        .foregroundColor(colorVeg)
                        .bold()
                }
                GridRow {
                    Text("Bosco Satellite:").bold()
                    Text(tInfo.nomeVegetazione)
                        .font(.caption).bold()
                        .foregroundColor(isBosco ? .green : .orange)
                }
                GridRow {
                    Text("Trama Suolo:").bold()
                    Text(tInfo.nomeSuolo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private var cardMeteo: some View {
        if let m = meteo, let prev = previsione {
            let isShock = m.deltaTSuolo >= 3.5
            let shockText = isShock ? "+\(String(format: "%.1f", m.deltaTSuolo))°C (Bonus +20%)" : "Assente"
            let shockColor: Color = isShock ? .blue : .secondary
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Dati Meteo & Idratazione Suolo (Open-Meteo)")
                    .font(.headline)
                
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Pioggia Caduta:").bold()
                        Text("\(String(format: "%.1f", m.pioggiaCumulata15Giorni)) mm")
                        Text("Soglia Richiesta:").bold()
                        Text("\(String(format: "%.1f", prev.sogliaRichiesta)) mm")
                    }
                    GridRow {
                        Text("Umidità Suolo (3-9cm):").bold()
                        Text("\(Int(round(m.umiditaSuoloMiceliare * 100)))%")
                        Text("Temp. Terreno:").bold()
                        Text("\(String(format: "%.1f", m.temperaturaSuolo)) °C")
                    }
                    GridRow {
                        Text("Shock Termico DeltaT:").bold()
                        Text(shockText)
                            .font(.caption).bold()
                            .foregroundColor(shockColor)
                        Text("Vento Max:").bold()
                        Text("\(String(format: "%.1f", m.velocitaVentoMax)) km/h")
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
    }
    
    @ViewBuilder
    private var cardOsservazioni: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Le tue Osservazioni sul Campo")
                    .font(.headline)
                Spacer()
                Button(action: { mostrandoAggiungiObs = true }) {
                    Label("Aggiungi", systemImage: "plus.circle.fill")
                        .font(.subheadline)
                }
            }
            
            if punto.osservazioni.isEmpty {
                Text("Nessuna osservazione registrata in questo punto. Aggiungi la tua prima uscita per calibrare automaticamente la soglia!")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(punto.osservazioni.sorted(by: { $0.data > $1.data })) { obs in
                    HStack {
                        Image(systemName: obs.trovato ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(obs.trovato ? .green : .red)
                        
                        VStack(alignment: .leading) {
                            Text(obs.data.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).bold()
                            if obs.trovato {
                                Text("Trovato: \(String(format: "%.1f", obs.quantitaKg ?? 0.0)) kg (\(obs.specie))")
                                    .font(.caption)
                            } else {
                                Text("Nessun fungo trovato")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Componente Grafico Incubazione Miceliare (Campana di Gauss Charts)

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
            return ("Incubazione Miceliare (Formazione primi funghi)", .orange, "leaf.arrow.triangle.circlepath")
        } else if t >= 5 && t <= 8 {
            return ("Picco della Buttata (Carpofori Pronti!)", .green, "checkmark.seal.fill")
        } else {
            return ("Fase di Discesa (Terreno in Asciugatura)", .secondary, "clock.arrow.circlepath")
        }
    }
    
    private var etichetteXVisibili: [String] {
        let points = dataPoints
        let t = meteo.giorniDaUltimaPioggiaSignificativa
        // Mostriamo etichette distanziate a passo 3 per evitare sovrapposizioni visive
        return points.compactMap { p -> String? in
            let diff = abs(p.giorno - t)
            if p.eOggi || diff % 3 == 0 {
                return p.etichettaGiorno
            }
            return nil
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
                AxisMarks(values: etichetteXVisibili) { value in
                    AxisGridLine()
                    AxisValueLabel()
                        .font(.system(size: 10, weight: .bold))
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
