import Connectivity
import SwiftUI

enum ConnectivityStatusInternal {
    private static let key = "connectivityStatus"

    static var current: ConnectivityStatus {
        get {
            if let existing = UserDefaults.standard.object(forKey: key) as? Int {
                guard let status = ConnectivityStatus(rawValue: existing) else {
                    UserDefaults.standard.set(ConnectivityStatus.determining.rawValue, forKey: key)
                    return ConnectivityStatus.determining
                }
                return status
            } else {
                UserDefaults.standard.set(ConnectivityStatus.determining.rawValue, forKey: key)
                return ConnectivityStatus.determining
            }
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}
