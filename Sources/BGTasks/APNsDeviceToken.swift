import SwiftUI

enum APNsDeviceToken {
    private static let key = "apnsDeviceToken"

    static var current: String {
        get {
            if let existing = UserDefaults.standard.string(forKey: key) {
                return existing
            }

            let emptyToken = ""
            UserDefaults.standard.set(emptyToken, forKey: key)
            return emptyToken
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
}
