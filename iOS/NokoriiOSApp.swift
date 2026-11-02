import SwiftUI

@main struct NokoriiOSApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ContentView(model: .shared)
                .preferredColorScheme(appearance == "system" ? nil : (appearance == "dark" ? .dark : .light))
                .onChange(of: phase, initial: true) {
                    if phase == .active { Task { await UsageModel.shared.pull() } }
                    else if phase == .background { UsageModel.scheduleRefresh() }
                }
        }.backgroundTask(.appRefresh(UsageModel.refreshID)) {
            await UsageModel.shared.pull()
            await UsageModel.scheduleRefresh()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        Task { await UsageModel.shared.subscribe() }
        return true
    }
    /// The silent push CloudKit sends when the Mac writes a new snapshot.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await UsageModel.shared.pull() ? .newData : .failed
    }
}
