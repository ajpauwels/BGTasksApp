import SwiftUI

enum ExpectedRunTimes {
    private static let key = "expectedRunTimes"

    static func get(identifier: String) -> Date? {
        if let existing = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] {
            guard let timestamp = existing[identifier] else {
                return Optional.none
            }
            return Date(timeIntervalSince1970: timestamp)
        }

        let newDictionary = [String: Double]()
        UserDefaults.standard.set(newDictionary, forKey: key)
        return Optional.none
    }

    static func set(identifier: String, expectedRunTime: Date) {
        if var existing = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] {
            existing[identifier] = expectedRunTime.timeIntervalSince1970
        } else {
            var newDictionary = [String: Double]()
            newDictionary[identifier] = expectedRunTime.timeIntervalSince1970
            UserDefaults.standard.set(newDictionary, forKey: key)
        }
    }
}
