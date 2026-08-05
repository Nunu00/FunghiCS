import SwiftUI
import SwiftData

struct ListaPuntiView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PuntoInteresse.nome) private var punti: [PuntoInteresse]
    
    @State private var puntoSelezionato: PuntoInteresse? = nil
    @State private var mostrandoNuovoPuntoSheet = false
    @State private var nomeInput = ""
    @State private var latInput = "39.30"
    @State private var lonInput = "16.25"
    
    var body: some View {
        NavigationStack {
            List {
                if punti.isEmpty {
                    ContentUnavailableView(
                        "Nessun Punto Salvato",
                        systemImage: "location.slash",
                        description: Text("Tocca la mappa o premi '+' per aggiungere un punto di raccolta in Sila o Pollino.")
                    )
                } else {
                    ForEach(punti) { punto in
                        Button {
                            puntoSelezionato = punto
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(punto.nome)
                                        .font(.headline)
                                    Text("Quota: \(Int(punto.quota))m | Esposizione: \(punto.esposizione)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: eliminaPunti)
                }
            }
            .navigationTitle("I Miei Punti Funghi")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        mostrandoNuovoPuntoSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $puntoSelezionato) { punto in
                DettaglioPuntoView(punto: punto)
            }
            .sheet(isPresented: $mostrandoNuovoPuntoSheet) {
                NavigationStack {
                    Form {
                        Section("Dati Punto") {
                            TextField("Nome Punto (es. Camigliatello)", text: $nomeInput)
                            TextField("Latitudine", text: $latInput)
                                .keyboardType(.decimalPad)
                            TextField("Longitudine", text: $lonInput)
                                .keyboardType(.decimalPad)
                        }
                    }
                    .navigationTitle("Nuovo Punto")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Annulla") { mostrandoNuovoPuntoSheet = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Salva") {
                                if let lat = Double(latInput), let lon = Double(lonInput), !nomeInput.isEmpty {
                                    let terrain = DEMService.shared.getTerrainData(latitude: lat, longitude: lon)
                                    let p = PuntoInteresse(
                                        nome: nomeInput,
                                        latitude: lat,
                                        longitude: lon,
                                        quota: terrain.quota,
                                        pendenza: terrain.pendenza,
                                        esposizione: terrain.esposizione
                                    )
                                    modelContext.insert(p)
                                    mostrandoNuovoPuntoSheet = false
                                    nomeInput = ""
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func eliminaPunti(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(punti[index])
        }
    }
}
