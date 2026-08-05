import SwiftUI
import MapKit
import SwiftData

struct PrevisioneCella {
    let cella: CellaGrigliaTerritorio
    let previsione: RisultatoPrevisione
}

struct MappaView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var punti: [PuntoInteresse]
    
    // Centrato sulla provincia di Cosenza (Sila, Pollino, Catena Costiera)
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.35, longitude: 16.30),
            span: MKCoordinateSpan(latitudeDelta: 0.95, longitudeDelta: 0.95)
        )
    )
    
    @State private var puntoSelezionato: PuntoInteresse? = nil
    @State private var mostrandoFormNuovoPunto = false
    @State private var nomeNuovoPunto = ""
    @State private var latNuovoPunto = "39.33"
    @State private var lonNuovoPunto = "16.44"
    
    // Dizionario risultati previsioni sui punti salvati
    @State private var risultatiMeteoPunti: [UUID: RisultatoPrevisione] = [:]
    
    // Griglia della Mappa di Calore Continua
    @State private var cellePrevisioni: [PrevisioneCella] = []
    
    // Toggle Layer
    @State private var mostraMappaDiCalore = true
    @State private var filtraSoloZoneIdonee = true // Quota >= 800m
    
    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $position) {
                    
                    // 1. MAPPA DI CALORE OVERLAY FLUIDA E CONTINUA (Senza bordi a scacchiera)
                    if mostraMappaDiCalore {
                        ForEach(cellePrevisioni, id: \.cella.id) { item in
                            if !filtraSoloZoneIdonee || item.cella.idonea {
                                MapPolygon(coordinates: [
                                    CLLocationCoordinate2D(latitude: item.cella.minLat, longitude: item.cella.minLon),
                                    CLLocationCoordinate2D(latitude: item.cella.maxLat, longitude: item.cella.minLon),
                                    CLLocationCoordinate2D(latitude: item.cella.maxLat, longitude: item.cella.maxLon),
                                    CLLocationCoordinate2D(latitude: item.cella.minLat, longitude: item.cella.maxLon)
                                ])
                                .foregroundStyle(colorePerStato(item.previsione.stato).opacity(0.42))
                            }
                        }
                    }
                    
                    // 2. SEGNALINI PUNTI UTENTE
                    ForEach(punti) { punto in
                        Annotation(punto.nome, coordinate: CLLocationCoordinate2D(latitude: punto.latitude, longitude: punto.longitude)) {
                            Button {
                                puntoSelezionato = punto
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(colorePerPunto(punto))
                                        .shadow(radius: 3)
                                    
                                    let prob = risultatiMeteoPunti[punto.id]?.probabilitaPercentuale ?? calcolaProbabilitaImmediataFallback(punto: punto)
                                    Text("\(prob)%")
                                        .font(.caption2)
                                        .bold()
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(colorePerPunto(punto))
                                        .cornerRadius(6)
                                }
                            }
                        }
                    }
                }
                
                // Overlay Legenda e Controlli
                VStack {
                    HStack {
                        // Controlli Filtri
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: $mostraMappaDiCalore) {
                                Label("Mappa Calore", systemImage: "square.grid.3x3.fill")
                                    .font(.caption).bold()
                            }
                            .tint(.green)
                            
                            Toggle(isOn: $filtraSoloZoneIdonee) {
                                Label("Filtro Quota >800m", systemImage: "mountain.2.fill")
                                    .font(.caption).bold()
                            }
                            .tint(.green)
                        }
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                        .padding(.leading, 10)
                        .padding(.top, 10)
                        
                        Spacer()
                        
                        // Legenda
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Legenda Fruttificazione")
                                .font(.caption2)
                                .bold()
                            HStack { Circle().fill(.green).frame(width: 8, height: 8); Text("Buttata (>65%)").font(.caption2) }
                            HStack { Circle().fill(.orange).frame(width: 8, height: 8); Text("Preparazione").font(.caption2) }
                            HStack { Circle().fill(.yellow).frame(width: 8, height: 8); Text("Esaurimento").font(.caption2) }
                            HStack { Circle().fill(.gray).frame(width: 8, height: 8); Text("Non fav. (<30%)").font(.caption2) }
                        }
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                        .padding(.trailing, 10)
                        .padding(.top, 10)
                    }
                    
                    Spacer()
                }
            }
            .navigationTitle("FunghiCS — Previsione Cosenza")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        mostrandoFormNuovoPunto = true
                    } label: {
                        Label("Aggiungi Punto", systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                }
            }
            .sheet(item: $puntoSelezionato) { punto in
                DettaglioPuntoView(punto: punto)
            }
            .sheet(isPresented: $mostrandoFormNuovoPunto) {
                NavigationStack {
                    Form {
                        Section("Dati Nuovo Punto Funghi") {
                            TextField("Nome Punto (es. Monte Botte Donato)", text: $nomeNuovoPunto)
                            TextField("Latitudine", text: $latNuovoPunto)
                                .keyboardType(.decimalPad)
                            TextField("Longitudine", text: $lonNuovoPunto)
                                .keyboardType(.decimalPad)
                        }
                    }
                    .navigationTitle("Nuovo Punto")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Annulla") { mostrandoFormNuovoPunto = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Salva") {
                                if let lat = Double(latNuovoPunto), let lon = Double(lonNuovoPunto), !nomeNuovoPunto.isEmpty {
                                    creaEPopolaPunto(nome: nomeNuovoPunto, lat: lat, lon: lon)
                                    mostrandoFormNuovoPunto = false
                                }
                            }
                        }
                    }
                }
            }
            .task {
                await calcolaMappaDiCaloreEPunti()
            }
        }
    }
    
    private func colorePerPunto(_ punto: PuntoInteresse) -> Color {
        if let res = risultatiMeteoPunti[punto.id] {
            return res.stato.colore
        }
        let meteoIniziale = DatiMeteo(pioggiaCumulata15Giorni: 62.0, temperaturaMedia: 16.5)
        let resIniziale = PrevisioneEngine.calcolaProbabilitaFruttificazione(punto: punto, meteo: meteoIniziale)
        return resIniziale.stato.colore
    }
    
    private func calcolaProbabilitaImmediataFallback(punto: PuntoInteresse) -> Int {
        let meteoIniziale = DatiMeteo(pioggiaCumulata15Giorni: 62.0, temperaturaMedia: 16.5)
        let resIniziale = PrevisioneEngine.calcolaProbabilitaFruttificazione(punto: punto, meteo: meteoIniziale)
        return resIniziale.probabilitaPercentuale
    }
    
    private func colorePerStato(_ stato: StatoFruttificazione) -> Color {
        return stato.colore
    }
    
    private func calcolaMappaDiCaloreEPunti() async {
        for punto in punti {
            let meteo = await MeteoService.shared.fetchMeteo(latitude: punto.latitude, longitude: punto.longitude)
            let res = PrevisioneEngine.calcolaProbabilitaFruttificazione(punto: punto, meteo: meteo)
            risultatiMeteoPunti[punto.id] = res
        }
        
        let celle = DEMService.shared.generaGrigliaTerritorio(stepGradiente: 0.018)
        var tempCellePrevisioni: [PrevisioneCella] = []
        let meteoGenerale = await MeteoService.shared.fetchMeteo(latitude: 39.30, longitude: 16.40)
        
        for cella in celle {
            if cella.idonea {
                let pTemp = PuntoInteresse(
                    nome: "Cella",
                    latitude: cella.centerLat,
                    longitude: cella.centerLon,
                    quota: cella.quota,
                    pendenza: cella.pendenza,
                    esposizione: cella.esposizione
                )
                let res = PrevisioneEngine.calcolaProbabilitaFruttificazione(punto: pTemp, meteo: meteoGenerale)
                tempCellePrevisioni.append(PrevisioneCella(cella: cella, previsione: res))
            }
        }
        
        await MainActor.run {
            self.cellePrevisioni = tempCellePrevisioni
        }
    }
    
    private func creaEPopolaPunto(nome: String, lat: Double, lon: Double) {
        let terrain = DEMService.shared.getTerrainData(latitude: lat, longitude: lon)
        let nuovoPunto = PuntoInteresse(
            nome: nome,
            latitude: lat,
            longitude: lon,
            quota: terrain.quota,
            pendenza: terrain.pendenza,
            esposizione: terrain.esposizione
        )
        modelContext.insert(nuovoPunto)
        
        Task {
            let meteo = await MeteoService.shared.fetchMeteo(latitude: lat, longitude: lon)
            let res = PrevisioneEngine.calcolaProbabilitaFruttificazione(punto: nuovoPunto, meteo: meteo)
            risultatiMeteoPunti[nuovoPunto.id] = res
        }
    }
}
