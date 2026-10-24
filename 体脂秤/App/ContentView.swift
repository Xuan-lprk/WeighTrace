import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var scale: ScaleManager
    @EnvironmentObject private var profile: UserProfile
    @EnvironmentObject private var healthKit: HealthKitManager
    @EnvironmentObject private var comparisonStore: ComparisonStore
    @State private var tab = 0
    @AppStorage("afu.hasPairedScale") private var hasPairedScale = false
    @AppStorage("afu.family.hasPromptedInitial") private var hasPromptedInitial = false
    @State private var showingMemberSheet = false
    @State private var showingInitialPrompt = false
    @State private var showingUnknownMember = false
    @State private var suggestedWeight: Double?

    var body: some View {
        TabView(selection: $tab) {
            Group {
                if hasPairedScale || scale.isDemo { DashboardView() } else { PairingView() }
            }.tabItem { Label("测量", systemImage: "waveform.path.ecg") }.tag(0)
            TrendsView().tabItem { Label("趋势", systemImage: "chart.xyaxis.line") }.tag(3)
            HistoryView().tabItem { Label("历史", systemImage: "chart.line.uptrend.xyaxis") }.tag(1)
            ProfileView().tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(2)
        }
        .tint(.teal)
        .onAppear {
            scale.profile = profile
            scale.comparisonStore = comparisonStore
#if !targetEnvironment(macCatalyst)
            if !scale.isDemo {
                scale.healthKit = healthKit
                healthKit.onMeasurementsRecovered = { measurements in
                    scale.mergeRestoredHistory(measurements)
                }
            }
#else
            // macOS 没有 Apple 健康数据库；Catalyst 版只保留蓝牙测量与本地历史。
            scale.healthKit = nil
#endif
        }
        .onAppear { promptForInitialMemberIfNeeded() }
        .onChange(of: hasPairedScale) { _, _ in promptForInitialMemberIfNeeded() }
        .onChange(of: scale.unrecognizedWeight) { _, weight in
            guard let weight else { return }
            suggestedWeight = weight
            showingUnknownMember = true
        }
        .alert("添加家庭成员", isPresented: $showingInitialPrompt) {
            Button("暂不添加", role: .cancel) { hasPromptedInitial = true }
            Button("添加成员") { hasPromptedInitial = true; suggestedWeight = nil; showingMemberSheet = true }
        } message: {
            Text("首次使用时添加家庭成员，之后体脂秤会自动识别并归属测量记录。")
        }
        .alert("可能是新成员", isPresented: $showingUnknownMember) {
            Button("暂不添加", role: .cancel) { scale.clearUnrecognizedWeight() }
            Button("添加成员") { showingMemberSheet = true }
        } message: {
            Text("检测到 \(suggestedWeight ?? 0, specifier: "%.2f") kg 的体重与现有成员差异较大，是否添加新成员？")
        }
        .sheet(isPresented: $showingMemberSheet) {
            AddFamilyMemberView(referenceWeight: suggestedWeight) { member in
                profile.addMember(member)
                scale.assignUnrecognizedMeasurement(to: member)
                scale.clearUnrecognizedWeight()
                hasPromptedInitial = true
            }
        }
        .sheet(item: $scale.reviewMeasurement) { measurement in
            MeasurementReviewView(measurement: measurement)
        }
    }

    private func promptForInitialMemberIfNeeded() {
        if !scale.isDemo && hasPairedScale && !hasPromptedInitial { showingInitialPrompt = true }
    }
}

#Preview("主界面") {
    ContentView()
        .environmentObject(ScaleManager())
        .environmentObject(UserProfile())
        .environmentObject(HealthKitManager())
        .environmentObject(ComparisonStore())
}
