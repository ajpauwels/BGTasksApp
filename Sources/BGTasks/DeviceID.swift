import SwiftUI

enum DeviceID {
    private static let key = "deviceID"

    static var current: String {
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }

        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: key)
        return newID
    }
}
