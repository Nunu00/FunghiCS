import SwiftUI

struct SplashScreenView: View {
    @Binding var isAppReady: Bool
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var progresso: Double = 0.0
    @State private var messaggioStato: String = "Caricamento dataset orografico Cosenza..."
    
    var body: some View {
        ZStack {
            // Sfondo Gradiente Scuro Foresta
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.18, blue: 0.12), Color(red: 0.02, green: 0.06, blue: 0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 25) {
                Spacer()
                
                // Icona fungo animata con bagliore
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 140, height: 140)
                        .scaleEffect(pulseScale)
                    
                    Text("🍄")
                        .font(.system(size: 80))
                        .shadow(color: .green.opacity(0.5), radius: 10, x: 0, y: 5)
                }
                
                VStack(spacing: 8) {
                    Text("FunghiCS")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Previsione Fruttificazione Provincia Cosenza")
                        .font(.subheadline)
                        .foregroundColor(.green.opacity(0.9))
                }
                
                Spacer()
                
                // Barra di Caricamento
                VStack(spacing: 12) {
                    ProgressView(value: progresso, total: 1.0)
                        .tint(.green)
                        .frame(width: 240)
                    
                    Text(messaggioStato)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseScale = 1.15
            }
            inizializzaAppEInvia()
        }
    }
    
    private func inizializzaAppEInvia() {
        Task {
            // Step 1: Forzare caricamento DEM INGV in memoria (109.329 punti)
            await MainActor.run {
                messaggioStato = "Inizializzazione 109.329 punti INGV 10m..."
                progresso = 0.25
            }
            _ = DEMService.shared
            
            // Step 2: Download griglia radar/satellite 100 nodi montani
            await MainActor.run {
                messaggioStato = "Download mappe pioggia Radar/Satellite 100 nodi..."
                progresso = 0.65
            }
            _ = await MeteoService.shared.fetchGrigliaMeteoSpaziale()
            
            // Step 3: Pre-generazione asincrona bitmap della mappa di calore in memoria heap
            await MainActor.run {
                messaggioStato = "Generazione grafica mappa di calore..."
                progresso = 0.90
            }
            
            let heatmapImg = await PrevisioneEngine.generaHeatmapBitmap()
            let rainImg = await PrevisioneEngine.generaPrecipitazioniBitmap()
            
            await MainActor.run {
                CosenzaHeatmapOverlayRenderer.sharedFruttificazioneCGImage = heatmapImg
                CosenzaHeatmapOverlayRenderer.sharedPrecipitazioniCGImage = rainImg
                NotificationCenter.default.post(name: .heatmapDataUpdated, object: nil)
                progresso = 1.0
                messaggioStato = "Mappa pronta!"
            }
            
            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.5)) {
                    isAppReady = true
                }
            }
        }
    }
}
