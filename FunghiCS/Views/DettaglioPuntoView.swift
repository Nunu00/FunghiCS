import SwiftUI
import SwiftData

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
                    
                    // Card Previsione Principale (Sintesi Pulita)
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
                    
                    // Card 2: Terreno, Altimetria & Satellitare (Copernicus)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Terreno & Copertura Satellitare Copernicus")
                            .font(.headline)
                        
                        let tInfo = DEMService.shared.getTerrainData(latitude: punto.latitude, longitude: punto.longitude)
                        
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
                                    .foregroundColor(tInfo.kVeg > 0 ? .green : .red)
                                    .bold()
                            }
                            GridRow {
                                Text("Bosco Satellite:").bold()
                                Text(tInfo.nomeVegetazione)
                                    .font(.caption).bold()
                                    .foregroundColor(tInfo.kVeg > 0 ? .green : .orange)
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
                    
                    // Card 3: Analisi Meteo, Idratazione Micelio & Shock Termico
                    if let m = meteo, let prev = previsione {
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
                                    Text("\(String(format: "%.2f", m.umiditaSuoloMiceliare)) m³/m³")
                                    Text("Temp. Terreno:").bold()
                                    Text("\(String(format: "%.1f", m.temperaturaSuolo)) °C")
                                }
                                GridRow {
                                    Text("Shock Termico DeltaT:").bold()
                                    Text(m.deltaTSuolo >= 3.5 ? "+\(String(format: "%.1f", m.deltaTSuolo))°C (Bonus +20%)" : "Assente")
                                        .font(.caption).bold()
                                        .foregroundColor(m.deltaTSuolo >= 3.5 ? .blue : .secondary)
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
                    
                    // Storico Osservazioni Utente
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
                                            Text("Trovato: \(String(format: "%.1f", obs.quantitaKg)) kg (\(obs.specie))")
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
}
