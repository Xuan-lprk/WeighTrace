import SwiftUI

struct ScreenshotDemoView: View {
    var onExit: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system.rawValue
    @StateObject private var demo = ScreenshotDemo()
    @StateObject private var health = HealthKitManager(isDemo: true)

    var body: some View {
        ContentView()
            .id(language)
            .environmentObject(demo.scale)
            .environmentObject(demo.profile)
            .environmentObject(demo.comparisons)
            .environmentObject(health)
            .defaultAppStorage(demo.defaults)
            .environment(\.locale, AppLanguage.selected.locale)
            .safeAreaInset(edge: .top) {
                HStack {
                    Label("演示数据", systemImage: "photo.on.rectangle")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("退出演示") {
                        if let onExit { onExit() } else { dismiss() }
                    }
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal).padding(.vertical, 8)
                .background(.regularMaterial)
            }
            .onDisappear { demo.clearStorage() }
    }
}

#Preview("截图演示") {
    ScreenshotDemoView()
}
