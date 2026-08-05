import Foundation
import UserNotifications

final class NotificheService {
    static let shared = NotificheService()
    
    private init() {}
    
    func richiediAutorizzazione() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { concessa, errore in
            if let errore = errore {
                print("Errore autorizzazione notifiche: \(errore.localizedDescription)")
            } else {
                print("Autorizzazione notifiche: \(concessa)")
            }
        }
    }
    
    func inviaNotificaIncrocioSoglia(nomePunto: String, probabilita: Int) {
        let content = UNMutableNotificationContent()
        content.title = "🍄 Allarme Buttata Funghi!"
        content.body = "Il tuo punto '\(nomePunto)' ha raggiunto una probabilità del \(probabilita)%! Condizioni meteo e di suolo favorevoli."
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(identifier: "buttata_\(nomePunto)_\(Date().timeIntervalSince1970)", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Errore invio notifica locale: \(error)")
            }
        }
    }
}
