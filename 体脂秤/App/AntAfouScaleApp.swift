import SwiftUI

@main struct AntAfouScaleApp: App {
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system.rawValue
    @State private var launchDemo = ProcessInfo.processInfo.arguments.contains("--screenshot-demo")

    var body: some Scene {
        WindowGroup {
            Group {
                if launchDemo {
                    ScreenshotDemoView(onExit: { launchDemo = false })
                } else {
                    MainAppContent(language: language)
                }
            }
                .environment(\.locale, AppLanguage.selected.locale)
        }
    }
}

private struct MainAppContent: View {
    let language: String
    @StateObject private var scale = ScaleManager()
    @StateObject private var profile = UserProfile()
    @StateObject private var healthKit = HealthKitManager()
    @StateObject private var comparisonStore = ComparisonStore()

    var body: some View {
        ContentView()
            .id(language)
            .environmentObject(scale)
            .environmentObject(profile)
            .environmentObject(healthKit)
            .environmentObject(comparisonStore)
    }
}
