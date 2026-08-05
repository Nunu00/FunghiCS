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
    @State private var cellaSelezionata: PrevisioneCella? = nil
    
    @State private var mostrandoFormNuovoPunto = false
    @State private var coordinataToccata: CLLocationCoordinate2D? = nil
    @State private var nomeNuovoPunto = ""
    
    // Dizionario risultati previsioni sui punti salvati
    @State private var risultatiMeteoPunti: [UUID: RisultatoPrevisione] = [:]
    
    // Griglia della Mappa di Calore
    @State private var cellePrevisioni: [PrevisioneCella] = []
    
    // Toggle Layer
    @State private var mostraMappaDiCalore = true
    @State private var filtraSoloZoneIdonee = true // Quota >= 400m
    
    var body: some View {
        NavigationStack {
            ZStack {
                MapReader { proxy in
                    Map(position: $position) {
                        
                        // 1. MAPPA DI CALORE OVERLAY (MapPolygon Vettoriali)
                        if mostraMappaDiCalore {
                            ForEach(cellePrevisioni, id: \.cella.id) { item in
                                if !filtraSoloZoneIdonee || item.cella.idonea {
                                    MapPolygon(coordinates: [
                                        CLLocationCoordinate2D(latitude: item.cella.minLat, longitude: item.cella.minLon),
                                        CLLocationCoordinate2D(latitude: item.cella.maxLat, longitude: item.cella.minLon),
                                        CLLocationCoordinate2D(latitude: item.cella.maxLat, longitude: item.cella.maxLon),
                                        CLLocationCoordinate2D(latitude: item.cella.minLat, longitude: item.cella.maxLon)
                                    ])
                                    .foregroundStyle(colorePerStato(item.previsione.stato).opacity(0.40))
                                    .stroke(colorePerStato(item.previsione.stato).opacity(0.60), lineWidth: 0.8)
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
                    .onTapGesture { positionScreen in
                        if let coord = proxy.convert(positionScreen, from: .local) {
                            coordinataToccata = coord
                            nomeNuovoPunto = "Punto Funghi \(punti.count + 1)"
                            mostrandoFormNuovoPunto = true
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
                                Label("Filtro Quota >400m", systemImage: "mountain.2.fill")
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
            .navigationTitle("FunghiCS — Mappa Calore")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $puntoSelezionato) { punto in
                DettaglioPuntoView(punto: punto)
            }
            .alert("Aggiungi Nuovo Punto", isPresented: $mostrandoFormNuovoPunto) {
                TextField("Nome punto", text: $nomeNuovoPunto)
                Button("Annulla", role: .cancel) { }
                Button("Salva") {
                    if let coord = coordinataToccata {
                        creaEPopolaPunto(nome: nomeNuovoPunto, lat: coord.latitude, lon: coord.longitude)
                    }
                }
            } message: {
                Text("Vuoi salvare questo punto di ricerca funghi?")
            }
            .task {
                await calcolaMappaDiCaloreEPunti()
            }
        }
    }
    
    // Colore immediato per evitare il bug iniziale del blu
    private func colorePerPunto(_ punto: PuntoInteresse) -> Color {
        if let res = risultatiMeteoPunti[punto.id] {
            return res.stato.colore
        }
        // Fallback calcolato immediatamente sul punto per non mostrare mai il blu
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
        // 1. Calcola previsione per i punti dell'utente
        for punto in punti {
            let meteo = await MeteoService.shared.fetchMeteo(latitude: punto.latitude, longitude: punto.longitude)
            let res = PrevisioneEngine.calcolaProbabilitaFruttificazione(punto: punto, meteo: meteo)
            risultatiMeteoPunti[punto.id] = res
        }
        
        // 2. Genera griglia del territorio e calcola mappa di calore
        let celle = DEMService.shared.generaGrigliaTerritorio(stepGradiente: 0.03)
        var tempCellePrevisioni: [PrevisioneCella] = []
        
        // Meteo di riferimento provinciale
        let meteoGenerale = await MeteoService.shared.fetchMeteo(latitude: 39.30, longitude: 16.40)
        
        for cella in celle {
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
