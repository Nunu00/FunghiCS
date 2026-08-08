import SwiftUI
import SwiftData

@main
struct FunghiCSApp: App {
    @State private var isAppReady = false
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PuntoInteresse.self,
            Osservazione.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            return container
        } catch {
            fatalError("Impossibile creare ModelContainer SwiftData: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ZStack {
                TabView {
                    MappaView()
                        .tabItem {
                            Label("Mappa Calore", systemImage: "map.fill")
                        }
                    
                    ListaPuntiView()
                        .tabItem {
                            Label("I miei Punti", systemImage: "mappin.and.ellipse")
                        }
                }
                
                // SplashScreen Overlay
                if !isAppReady {
                    SplashScreenView(isAppReady: $isAppReady)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onAppear {
                NotificheService.shared.richiediAutorizzazione()
            }
        }
        .modelContainer(sharedModelContainer)
    }
}

@MainActor
private func puntiInizialiEsempio() -> [PuntoInteresse] {
    return [
        PuntoInteresse(
            nome: "Camigliatello Silano",
            latitude: 39.3385,
            longitude: 16.4439,
            quota: 1270.0,
            pendenza: 12.0,
            esposizione: "N",
            note: "Boschi di faggeta e pino laricio."
        ),
        PuntoInteresse(
            nome: "Lorica (Lago Arvo)",
            latitude: 39.2514,
            longitude: 16.5147,
            quota: 1315.0,
            pendenza: 8.0,
            esposizione: "NW",
            note: "Pianori vicino al lago, terreno sabbioso acido."
        ),
        PuntoInteresse(
            nome: "Fagnano Castello (Catena Costiera)",
            latitude: 39.5667,
            longitude: 16.0500,
            quota: 750.0,
            pendenza: 18.0,
            esposizione: "E",
            note: "Castagneti e cerrete."
        ),
        PuntoInteresse(
            nome: "Morano Calabro (Pollino)",
            latitude: 39.8500,
            longitude: 16.1333,
            quota: 1100.0,
            pendenza: 22.0,
            esposizione: "NE",
            note: "Faggete di quota sul versante sud del Pollino."
        )
    ]
}
