import BackgroundTasks
import Connectivity
import OSLog
import SwiftUI

// Logger
let log = Logger()

// Task IDs
let refreshTaskID = "uk.ac.cam.cst.sn17.BGTasks.refresh"
let processingTaskID = "uk.ac.cam.cst.sn17.BGTasks.processing"
let maxProcessingTasks = 3
let schedulingInterval = ceil(30.0 + (30.0 / Double(maxProcessingTasks)))

// Backend URLs
let registerDeviceMetadataURL = "https://bgtasks.pauwelslabs.com/device/{device_id}/metadata"
let registerDeviceTokenURL = "https://bgtasks.pauwelslabs.com/device/{device_id}/token"
let registerDeviceNotificationStatusURL =
    "https://bgtasks.pauwelslabs.com/device/{device_id}/notification/status"
let recordDeviceBGTaskProcessingURL =
    "https://bgtasks.pauwelslabs.com/device/{device_id}/bgtask/processing"
let recordDeviceBGTaskAppRefreshURL =
    "https://bgtasks.pauwelslabs.com/device/{device_id}/bgtask/apprefresh"
let waitURL = "https://bgtasks.pauwelslabs.com/wait"

// HTTP request and response bodies
struct RecordBGTaskBody: Codable {
    var unixTSMillis: UInt64
    var batteryLevel: Float
    var batteryState: String
    var taskNum: Int
    var connectivity: String

    enum CodingKeys: String, CodingKey {
        case unixTSMillis = "unix_ts_millis"
        case batteryLevel = "battery_level"
        case batteryState = "battery_state"
        case taskNum = "task_num"
        case connectivity
    }
}

struct RecordBGTaskResponse: Codable {}

struct RegisterDeviceMetadataBody: Codable {
    var systemName: String
    var systemVersion: String
    var model: String

    enum CodingKeys: String, CodingKey {
        case systemName = "system_name"
        case systemVersion = "system_version"
        case model
    }
}

struct RegisterDeviceMetadataResponse: Codable {}

struct RegisterDeviceNotificationStatusBody: Codable {
    var authorized: Bool
}

struct RegisterDeviceNotificationStatusResponse: Codable {}

struct RegisterDeviceTokenBody: Codable {
    var token: String
}

struct RegisterDeviceTokenResponse: Codable {}

@main
struct bgtasksApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.eventLog)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            // case .background:
            //     scheduleAppRefreshTask()
            //     scheduleProcessingTask()
            case .active:
                UIApplication.shared.registerForRemoteNotifications()
                UNUserNotificationCenter.current().getNotificationSettings { settings in
                    switch settings.authorizationStatus {
                    case .authorized:
                        if NotificationsAuthorizationStatus.current != .authorized {
                            NotificationsAuthorizationStatus.current = .authorized
                            Task {
                                await backendRegisterDeviceNotificationStatus(authorized: true)
                            }
                        }
                    case .notDetermined:
                        UNUserNotificationCenter.current().requestAuthorization(options: [
                            .alert, .sound, .badge,
                        ]) { granted, _ in
                            if granted {
                                log.info("[BGTasks.Debug] Notifications permission granted")
                                NotificationsAuthorizationStatus.current = .authorized
                                Task {
                                    await backendRegisterDeviceNotificationStatus(authorized: true)
                                }
                            } else {
                                log.info("[BGTasks.Debug] Notifications permission denied")
                                NotificationsAuthorizationStatus.current = .denied
                                Task {
                                    await backendRegisterDeviceNotificationStatus(authorized: false)
                                }
                            }
                        }
                    case .denied, .provisional, .ephemeral:
                        if NotificationsAuthorizationStatus.current != .denied {
                            NotificationsAuthorizationStatus.current = .denied
                            Task {
                                await backendRegisterDeviceNotificationStatus(authorized: false)
                            }
                        }
                    @unknown default:
                        if NotificationsAuthorizationStatus.current != .denied {
                            NotificationsAuthorizationStatus.current = .denied
                            Task {
                                await backendRegisterDeviceNotificationStatus(authorized: false)
                            }
                        }
                    }
                }
            default: break
            }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    let eventLog = EventLog(name: "bgtasks")
    var processingTaskRan: [Bool] = Array(repeating: false, count: maxProcessingTasks)
    private let connectivity = Connectivity(
        configuration: .init()
            .configureFramework(.network)
    )

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Enable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true

        // Enable internet connection status monitoring
        let connectivityChanged: (Connectivity) -> Void = { connectivity in
            ConnectivityStatusInternal.current = connectivity.status
        }
        connectivity.whenConnected = connectivityChanged
        connectivity.whenDisconnected = connectivityChanged
        connectivity.startNotifier()

        // Register app refresh task handler
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) {
            task in
            self.handleAppRefreshTask(task: task as! BGAppRefreshTask)
        }

        // Register processing task handlers
        for i in 0..<maxProcessingTasks {
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: processingTaskID + ".\(i)", using: nil
            ) {
                task in
                log.info("Running task \"\(task.identifier)\" with index \(i)")
                self.handleProcessingTask(task: task as! BGProcessingTask, taskNum: i)
            }
        }

        // Schedule first processing task
        if let runTime = ExpectedRunTimes.get(identifier: processingTaskID + ".0"), runTime < Date()
        {
            scheduleProcessingTask(taskNum: 0, scheduleNextTask: false)
        }

        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken tokenData: Data
    ) {
        // Register the token and device metadata with our backend
        // each time it changes
        let token = tokenData.map { data in String(format: "%02.2hhx", data) }.joined()
        if APNsDeviceToken.current != token {
            Task {
                await backendRegisterDeviceToken(token: token)
                await backendRegisterDeviceMetadata()
            }
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Indicate that we failed to get an APNs token
        log.info("[BGTasks.Debug] Failed to register for APNs: \(error)")
    }

    func handleAppRefreshTask(task: BGAppRefreshTask) {
        log.info("[BGTasks.Debug] Executing app refresh task")

        scheduleAppRefreshTask()

        let t = Task {
            self.eventLog.appendAppRefreshTaskStart(willExpire: false)
            await backendRecordDeviceBGTaskAppRefresh()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            log.info("[BGTasks.Debug] Executing expiration handler for expired app refresh task")
            t.cancel()
            self.eventLog.appendAppRefreshTaskExpired()
            task.setTaskCompleted(success: false)
        }
    }

    func handleProcessingTask(task: BGProcessingTask, taskNum: Int) {
        log.info("[BGTasks.Debug] Executing processing task (num = \(taskNum))")

        scheduleProcessingTask(taskNum: taskNum, scheduleNextTask: !processingTaskRan[taskNum])
        processingTaskRan[taskNum] = true

        let t = Task {
            self.eventLog.appendProcessingTaskStart(willExpire: false, taskNum: taskNum)
            await backendRecordDeviceBGTaskProcessing(taskNum: taskNum)
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            log.info(
                "[BGTasks.Debug] Executing expiration handler for expired processing task (num = \(taskNum))"
            )
            t.cancel()
            self.eventLog.appendProcessingTaskExpired(taskNum: taskNum)
            task.setTaskCompleted(success: false)
        }
    }
}

func scheduleAppRefreshTask() {
    log.info("[BGTasks.Debug] Scheduling BGAppRefreshTask")
    let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
    try? BGTaskScheduler.shared.submit(request)
    log.info("[BGTasks.Debug] App refresh task is scheduled")
}

func scheduleProcessingTask(taskNum: Int, scheduleNextTask: Bool) {
    log.info("[BGTasks.Debug] Scheduling BGProcessingTask (num = \(taskNum))")

    let request = BGProcessingTaskRequest(identifier: processingTaskID + ".\(taskNum)")
    request.requiresNetworkConnectivity = true
    request.requiresExternalPower = true
    try? BGTaskScheduler.shared.submit(request)
    log.info("[BGTasks.Debug] Processing task \(taskNum) is scheduled")

    if scheduleNextTask && taskNum < maxProcessingTasks - 1 {
        let request = BGProcessingTaskRequest(identifier: processingTaskID + ".\(taskNum + 1)")
        request.earliestBeginDate = Date(timeIntervalSinceNow: schedulingInterval * 60)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = true
        try? BGTaskScheduler.shared.submit(request)
        log.info("[BGTasks.Debug] Processing task \(taskNum + 1) is scheduled for the first time")
    }
}

@MainActor
func backendRegisterDeviceMetadata() async {
    guard
        let url = URL(
            string: registerDeviceMetadataURL.replacingOccurrences(
                of: "{device_id}", with: DeviceID.current))
    else {
        return
    }
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    request.httpMethod = "POST"
    let body = RegisterDeviceMetadataBody(
        systemName: UIDevice.current.systemName,
        systemVersion: UIDevice.current.systemVersion,
        model: UIDevice.current.model,
    )
    guard let bodyJSON = try? JSONEncoder().encode(body) else { return }
    request.httpBody = bodyJSON
    do {
        log.info("[BGTasks.Debug] Sending device metadata to backend")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            log.info(
                "[BGTasks.Debug] Sent device metadata to backend but received no response"
            )
            return
        }
        if (200...299).contains(httpResponse.statusCode) {
            log.info("[BGTasks.Debug] Successfully sent device metadata to backend")
        } else {
            log.info(
                "[BGTasks.Debug] Failed to send device metadata to backend: \(httpResponse.statusCode)"
            )
        }
    } catch {
        log.info(
            "[BGTasks.Debug] Failed to send device metadata to backend: \(error)")
    }
    return
}

@MainActor
func backendRecordDeviceBGTaskAppRefresh() async {
    guard
        let url = URL(
            string: recordDeviceBGTaskAppRefreshURL.replacingOccurrences(
                of: "{device_id}", with: DeviceID.current))
    else {
        return
    }
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    request.httpMethod = "POST"
    let batteryLevel = UIDevice.current.batteryLevel
    let batteryState = batteryStateToString(state: UIDevice.current.batteryState)
    let body = RecordBGTaskBody(
        unixTSMillis: UInt64(Date.now.timeIntervalSince1970 * 1000),
        batteryLevel: batteryLevel,
        batteryState: batteryState,
        taskNum: 0,
        connectivity: "\(ConnectivityStatusInternal.current)",
    )
    guard let bodyJSON = try? JSONEncoder().encode(body) else { return }
    request.httpBody = bodyJSON
    do {
        log.info("[BGTasks.Debug] Sending background app refresh task record to backend")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            log.info(
                "[BGTasks.Debug] Sent background app refresh task record to backend but received no response"
            )
            return
        }
        if (200...299).contains(httpResponse.statusCode) {
            log.info(
                "[BGTasks.Debug] Successfully sent background app refresh task record to backend")
        } else {
            log.info(
                "[BGTasks.Debug] Failed to send background app refresh task record to backend: \(httpResponse.statusCode)"
            )
        }
    } catch {
        log.info(
            "[BGTasks.Debug] Failed to send background app refresh task record to backend: \(error)"
        )
    }
    return
}

@MainActor
func backendRecordDeviceBGTaskProcessing(taskNum: Int) async {
    guard
        let url = URL(
            string: recordDeviceBGTaskProcessingURL.replacingOccurrences(
                of: "{device_id}", with: DeviceID.current))
    else {
        return
    }
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    request.httpMethod = "POST"
    let body = RecordBGTaskBody(
        unixTSMillis: UInt64(Date.now.timeIntervalSince1970 * 1000),
        batteryLevel: UIDevice.current.batteryLevel,
        batteryState: batteryStateToString(state: UIDevice.current.batteryState),
        taskNum: taskNum,
        connectivity: "\(ConnectivityStatusInternal.current)",
    )
    guard let bodyJSON = try? JSONEncoder().encode(body) else { return }
    request.httpBody = bodyJSON
    do {
        log.info("[BGTasks.Debug] Sending background processing task record to backend")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            log.info(
                "[BGTasks.Debug] Sent background processing task record to backend but received no response"
            )
            return
        }
        if (200...299).contains(httpResponse.statusCode) {
            log.info(
                "[BGTasks.Debug] Successfully sent background processing task record to backend")
        } else {
            log.info(
                "[BGTasks.Debug] Failed to send background processing task record to backend: \(httpResponse.statusCode)"
            )
        }
    } catch {
        log.info(
            "[BGTasks.Debug] Failed to send background processing task record to backend: \(error)")
    }
    return
}

func backendRegisterDeviceNotificationStatus(authorized: Bool) async {
    guard
        let url = URL(
            string: registerDeviceNotificationStatusURL.replacingOccurrences(
                of: "{device_id}", with: DeviceID.current))
    else {
        return
    }
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    request.httpMethod = "POST"
    let body = RegisterDeviceNotificationStatusBody(
        authorized: authorized
    )
    guard let bodyJSON = try? JSONEncoder().encode(body) else { return }
    request.httpBody = bodyJSON
    do {
        log.info("[BGTasks.Debug] Sending device notification status to backend")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            log.info(
                "[BGTasks.Debug] Sent device notification status to backend but received no response"
            )
            return
        }
        if (200...299).contains(httpResponse.statusCode) {
            log.info("[BGTasks.Debug] Successfully sent device notification status to backend")
        } else {
            log.info(
                "[BGTasks.Debug] Failed to send device notification status to backend: \(httpResponse.statusCode)"
            )
        }
    } catch {
        log.info(
            "[BGTasks.Debug] Failed to send device notification status to backend: \(error)")
    }
    return
}

func backendRegisterDeviceToken(token: String) async {
    guard
        let url = URL(
            string: registerDeviceTokenURL.replacingOccurrences(
                of: "{device_id}", with: DeviceID.current))
    else {
        return
    }
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    request.httpMethod = "POST"
    let body = RegisterDeviceTokenBody(
        token: token
    )
    guard let bodyJSON = try? JSONEncoder().encode(body) else { return }
    request.httpBody = bodyJSON
    do {
        log.info("[BGTasks.Debug] Sending device token to backend")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            log.info(
                "[BGTasks.Debug] Sent device token to backend but received no response"
            )
            return
        }
        if (200...299).contains(httpResponse.statusCode) {
            log.info("[BGTasks.Debug] Successfully sent device token to backend")
            APNsDeviceToken.current = token
        } else {
            log.info(
                "[BGTasks.Debug] Failed to send device token to backend: \(httpResponse.statusCode)"
            )
        }
    } catch {
        log.info(
            "[BGTasks.Debug] Failed to send device token to backend: \(error)")
    }
    return
}

func batteryStateToString(state: UIDevice.BatteryState) -> String {
    switch state {
    case .unknown:
        return "unknown"
    case .unplugged:
        return "unplugged"
    case .charging:
        return "charging"
    case .full:
        return "full"
    @unknown default:
        return "unknown-default"
    }
}
