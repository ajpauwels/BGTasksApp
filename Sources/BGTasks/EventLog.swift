import SwiftUI

final class EventLog: ObservableObject, Sendable {
    private let name: String
    // private let deviceData: [String: String]
    private let queue: DispatchQueue

    init(name: String) {
        // Initialize queue and device-specific information
        self.name = name
        self.queue = DispatchQueue(label: "uk.ac.cam.cst.sn17.BGTasks.eventlog.\(name)")
    }

    func appendBeginIdle() {
        let data: [String: Any] = [
            "type": "begin-idle"
        ]
        return append(data: data)
    }

    func appendEndIdle() {
        let data: [String: Any] = [
            "type": "end-idle"
        ]
        return append(data: data)
    }

    func appendAppRefreshTaskStart(willExpire: Bool) {
        let data: [String: Any] = [
            "type": "refresh-start\(willExpire ? "-expire" : "")"
        ]
        return append(data: data)
    }

    func appendAppRefreshTaskExpired() {
        let data: [String: Any] = [
            "type": "refresh-expired"
        ]
        return append(data: data)
    }

    func appendProcessingTaskStart(willExpire: Bool, taskNum: Int) {
        let data: [String: Any] = [
            "type": "processing-\(taskNum)-start\(willExpire ? "-expire" : "")"
        ]
        return append(data: data)
    }

    func appendProcessingTaskExpired(taskNum: Int) {
        let data: [String: Any] = [
            "type": "processing-\(taskNum)-expired"
        ]
        return append(data: data)
    }

    func append(
        data: [String: Any]
    ) {
        let ts = ISO8601DateFormatter().string(from: Date())

        var data = data
        data["ts"] = ts

        guard let data = try? JSONSerialization.data(withJSONObject: data, options: []) else {
            return
        }
        guard var line = String(data: data, encoding: .utf8) else {
            return
        }
        line.append("\n")

        let url = fileURL()
        queue.sync {
            if FileManager.default.fileExists(atPath: url.path) {
                if let h = try? FileHandle(forWritingTo: url) {
                    defer { try? h.close() }
                    do { try h.seekToEnd() } catch { return }
                    if let d = line.data(using: .utf8) { h.write(d) }
                }
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    func loadEvents() -> [String] {
        let url = fileURL()
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        var rows: [String] = []
        for line in content.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            let ts = (obj["ts"] as? String) ?? ""
            let type = (obj["type"] as? String) ?? ""
            if !ts.isEmpty && !type.isEmpty {
                rows.append("\(ts) - \(type)")
            }
        }
        return rows
    }

    func deleteEvents() {
        let url = fileURL()
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
                NSLog("[BGTasks.Debug] File deleted successfully")
            } catch {
                NSLog("[BGTasks.Debug] Error deleting file: \(error)")
            }
        } else {
            return
        }
    }

    func fileURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("eventlog-\(name).json")
    }
}
