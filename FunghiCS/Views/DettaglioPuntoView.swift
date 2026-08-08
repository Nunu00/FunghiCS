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
                    
                    // Card Previsione Principale
                    if let prev = previsione {
                        VStack(spacing: 8) {
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
                                .font(.body)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    } else {
                        ProgressView("Calcolo previsione e meteo...")
                            .padding()
                    }
                    
                    // Dati Altimetrici, Satellitari Copernicus & Morfologia Terreno
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Terreno, Altimetria & Satellitare (Copernicus)")
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
                            }
                            GridRow {
                                Text("Bosco Satellite:").bold()
                                Text(tInfo.nomeVegetazione)
                                    .font(.caption).bold()
                                    .foregroundColor(.green)
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
                    
                    // Dati Meteo Recenti (Open-Meteo)
                    if let m = meteo, let prev = previsione {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Analisi Precipitazioni (15 gg)")
                                .font(.headline)
                            
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Pioggia Caduta")
                                        .font(.caption).foregroundColor(.secondary)
                                    Text("\(String(format: "%.1f", m.pioggiaCumulata15Giorni)) mm")
                                        .font(.title2).bold()
                                }
                                Spacer()
                                VStack(alignment: .leading) {
                                    Text("Soglia Calcolata")
                                        .font(.caption).foregroundColor(.secondary)
                                    Text("\(String(format: "%.1f", prev.sogliaRichiesta)) mm")
                                        .font(.title2).bold()
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
                            Button {
                                mostrandoAggiungiObs = true
                            } label: {
                                Label("Aggiungi", systemImage: "plus")
                                    .font(.caption)
                            }
                        }
                        
                        if punto.osservazioni.isEmpty {
                            Text("Nessuna osservazione registrata in questo punto. Aggiungine una per calibrare l'algoritmo.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(punto.osservazioni.sorted(by: { $0.data > $1.data })) { obs in
                                HStack {
                                    Image(systemName: obs.trovato ? "checkmark.circle.fill" : "xmark.circle")
                                        .foregroundColor(obs.trovato ? .green : .red)
                                    VStack(alignment: .leading) {
                                        Text(obs.data.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption).bold()
                                        if obs.trovato {
                                            Text("\(obs.specie) — \(String(format: "%.1f", obs.quantitaKg ?? 0.0)) kg")
                                                .font(.caption2)
                                        } else {
                                            Text("Uscita a vuoto")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 4)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .sheet(isPresented: $mostrandoAggiungiObs) {
                AggiungiOsservazioneView(punto: punto)
            }
            .task {
                let fetchedMeteo = await MeteoService.shared.fetchMeteo(latitude: punto.latitude, longitude: punto.longitude)
                self.meteo = fetchedMeteo
                self.previsione = PrevisioneEngine.calcolaProbabilitaFruttificazione(punto: punto, meteo: fetchedMeteo)
            }
        }
    }
}
