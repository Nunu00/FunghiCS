import SwiftUI
import SwiftData

struct AggiungiOsservazioneView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let punto: PuntoInteresse
    
    @State private var trovato: Bool = true
    @State private var quantitaKgText: String = "0.5"
    @State private var specie: String = "Porcino (Boletus edulis)"
    @State private var note: String = ""
    @State private var dataOsservazione: Date = Date()
    
    let specieComuni = [
        "Porcino (Boletus edulis)",
        "Porcino Nero (Boletus aereus)",
        "Porcino Pinicola (Boletus pinophilus)",
        "Ovolo Buono (Amanita caesarea)",
        "Gallinaccio (Cantharellus cibarius)",
        "Mazza di Tamburo (Macrolepiota procera)",
        "Rosito / Sanguinello (Lactarius deliciosus)",
        "Altro"
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Esito Uscita") {
                    Toggle("Funghi Trovati", isOn: $trovato)
                        .tint(.green)
                    
                    DatePicker("Data Uscita", selection: $dataOsservazione, displayedComponents: [.date])
                }
                
                if trovato {
                    Section("Dettagli Ritrovamento") {
                        Picker("Specie Prevalente", selection: $specie) {
                            ForEach(specieComuni, id: \.self) { s in
                                Text(s).tag(s)
                            }
                        }
                        
                        HStack {
                            Text("Quantità stimata (kg):")
                            Spacer()
                            TextField("Kg", text: $quantitaKgText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }
                }
                
                Section("Note & Condizioni") {
                    TextField("Note personali (es. terreno umido, bosco di castagno)", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Nuova Osservazione")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        let kg = Double(quantitaKgText.replacingOccurrences(of: ",", with: "."))
                        let obs = Osservazione(
                            data: dataOsservazione,
                            trovato: trovato,
                            quantitaKg: trovato ? kg : 0.0,
                            specie: trovato ? specie : "Nessuna",
                            note: note,
                            punto: punto
                        )
                        modelContext.insert(obs)
                        punto.osservazioni.append(obs)
                        
                        // Recalibrate target point threshold using observations
                        PrevisioneEngine.ricalibraMoltiplicatore(punto: punto)
                        
                        dismiss()
                    }
                }
            }
        }
    }
}
