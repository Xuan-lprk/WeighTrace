import SwiftUI

@main struct AntAfouScaleApp: App {
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system.rawValue
    @StateObject private var scale = ScaleManager()
    @StateObject private var profile = UserProfile()
    @StateObject private var healthKit = HealthKitManager()
    @StateObject private var comparisonStore = ComparisonStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .id(language)
                .environment(\.locale, AppLanguage.selected.locale)
                .environmentObject(scale)
                .environmentObject(profile)
                .environmentObject(healthKit)
                .environmentObject(comparisonStore)
        }
    }
}
