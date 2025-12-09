import SwiftUI

struct ContentView: View {
    @State private var events: [String] = []
    @State private var showingShare = false
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var eventLog: EventLog

    var body: some View {
        VStack {
            Button("Begin Idle") {
                eventLog.appendBeginIdle()
                loadEvents()
            }
            .padding()

            Button("End Idle") {
                eventLog.appendEndIdle()
                loadEvents()
            }
            .padding()

            Button("Clear Events") {
                eventLog.deleteEvents()
                loadEvents()
            }
            .padding()

            ShareLink(
                item: eventLog.fileURL(),
            ) {
                Label("Share Logs", systemImage: "square.and.arrow.up")
            }

            List(events, id: \.self) { ts in
                Text(ts)
            }
        }
        .onAppear(perform: loadEvents)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                loadEvents()
            default: break
            }
        }
    }

    func loadEvents() {
        NSLog("[BGTasks.Debug] Loading events")
        events = eventLog.loadEvents()
    }
}
