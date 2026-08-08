import SwiftUI

@main
struct ApexGaugeWatchApp: App {
    @StateObject private var connectivityManager = WatchConnectivityManager()

    var body: some Scene {
        WindowGroup {
            ContentView(connectivityManager: connectivityManager)
                .task {
                    connectivityManager.activate()
                }
        }
    }
}
