import SwiftUI
import MapKit
import SwiftData

struct MappaView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var punti: [PuntoInteresse]
    
    // Centrato su Cosenza (Sila, Pollino, Catena Costiera)
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.30, longitude: 16.25),
            span: MKCoordinateSpan(latitudeDelta: 0.95, longitudeDelta: 0.95)
        )
    )
    
    @State private var puntoSelezionato: PuntoInteresse? = nil
    @State private var mostrandoFormNuovoPunto = false
    @State private var coordinataToccata: CLLocationCoordinate2D? = nil
    @State private var nomeNuovoPunto = ""
    @State private var risultatiMeteo: [UUID: RisultatoPrevisione] = [:]
    
    var body: some View {
        NavigationStack {
            ZStack {
                MapReader { proxy in
                    Map(position: $position) {
                        ForEach(punti) { punto in
                            Annotation(punto.nome, coordinate: CLLocationCoordinate2D(latitude: punto.latitude, longitude: punto.longitude)) {
                                Button {
                                    puntoSelezionato = punto
                                } label: {
                                    VStack(spacing: 2) {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.title)
                                            .foregroundColor(colorePerPunto(punto))
                                        
                                        if let res = risultatiMeteo[punto.id] {
                                            Text("\(res.probabilitaPercentuale)%")
                                                .font(.caption2)
                                                .bold()
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 2)
                                                .background(.thinMaterial)
                                                .cornerRadius(4)
                                        }
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
                
                // Legenda sovrapposta
                VStack {
                    HStack {
                        Spacer()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Legenda Previsioni")
                                .font(.caption)
                                .bold()
                            HStack { Circle().fill(.green).frame(width: 8, height: 8); Text("Buttata").font(.caption2) }
                            HStack { Circle().fill(.orange).frame(width: 8, height: 8); Text("Preparazione").font(.caption2) }
                            HStack { Circle().fill(.yellow).frame(width: 8, height: 8); Text("Esaurimento").font(.caption2) }
                            HStack { Circle().fill(.gray).frame(width: 8, height: 8); Text("Non fav.").font(.caption2) }
                        }
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .padding(.trailing, 10)
                        .padding(.top, 10)
                    }
                    Spacer()
                }
            }
            .navigationTitle("FunghiCS — Cosenza")
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
                await aggiornaPrevisioniTuttiPunti()
            }
        }
    }
    
    private func colorePerPunto(_ punto: PuntoInteresse) -> Color {
        guard let res = risultatiMeteo[punto.id] else { return .blue }
        return res.stato.colore
    }
    
    private func aggiornaPrevisioniTuttiPunti() async {
        for punto in punti {
            let meteo = await MeteoService.shared.fetchMeteo(latitude: punto.latitude, longitude: punto.longitude)
            let res = PrevisioneEngine.calcolaProbabilitaFruttificazione(punto: punto, meteo: meteo)
            risultatiMeteo[punto.id] = res
            
            if res.probabilitaPercentuale >= 70 {
                NotificheService.shared.inviaNotificaIncrocioSoglia(nomePunto: punto.nome, probabilita: res.probabilitaPercentuale)
            }
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
            risultatiMeteo[nuovoPunto.id] = res
        }
    }
}
