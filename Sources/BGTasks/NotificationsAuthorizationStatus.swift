import SwiftUI

enum NotificationsAuthorizationStatus {
    private static let key = "notificationsAuthorizationStatus"

    static var current: UNAuthorizationStatus {
        get {
            let raw = UserDefaults.standard.integer(forKey: key)
            return UNAuthorizationStatus(rawValue: raw) ?? .notDetermined
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}
