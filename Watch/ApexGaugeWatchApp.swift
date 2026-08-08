import SwiftUI

@main
struct ApexGaugeWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var snapshotRequester = SnapshotRequester()

    var body: some Scene {
        WindowGroup {
            ContentView(snapshotRequester: snapshotRequester)
                .task {
                    snapshotRequester.activate()
                    await snapshotRequester.requestSnapshotIfStale()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await snapshotRequester.requestSnapshotIfStale()
                    }
                }
        }
    }
}
