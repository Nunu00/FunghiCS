import SwiftUI

struct SplashScreenView: View {
    @Binding var isAppReady: Bool
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var opacity: Double = 0.3
    @State private var messaggioStato = "Inizializzazione terreno TINITALY..."
    @State private var progresso: Double = 0.15
    
    var body: some View {
        ZStack {
            // Fondo Sfumato Foresta
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.15, blue: 0.08), Color(red: 0.10, green: 0.25, blue: 0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                // Emblema Fungo Animato
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 140, height: 140)
                        .scaleEffect(pulseScale)
                    
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                        .shadow(color: .green.opacity(0.6), radius: 10)
                }
                
                VStack(spacing: 8) {
                    Text("FunghiCS")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Provincia di Cosenza — Sila & Pollino")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
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
            avviaSimulazioneCaricamento()
        }
    }
    
    private func avviaSimulazioneCaricamento() {
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            await MainActor.run {
                messaggioStato = "Analisi altimetrica e boschiva (>400m)..."
                progresso = 0.45
            }
            
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                messaggioStato = "Download bollettini Open-Meteo..."
                progresso = 0.80
            }
            
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                messaggioStato = "Generazione mappa di calore..."
                progresso = 1.0
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
