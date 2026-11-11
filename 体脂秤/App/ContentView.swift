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
        GeometryReader { geometry in
            if geometry.size.width >= 900 {
                HStack(spacing: 0) {
                    sidebar.frame(width: 224)
                    Divider()
                    selectedScreen.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                compactNavigation
            }
        }
        .tint(AppTheme.accent)
        .onAppear {
            scale.profile = profile
            scale.comparisonStore = comparisonStore
#if !targetEnvironment(macCatalyst)
            if !scale.isDemo {
                scale.healthKit = healthKit
                healthKit.onMeasurementsRecovered = { measurements in scale.mergeRestoredHistory(measurements) }
            }
#else
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
        .sheet(item: $scale.reviewMeasurement) { measurement in MeasurementReviewView(measurement: measurement) }
    }

    private var compactNavigation: some View {
        TabView(selection: $tab) {
            Group {
                if hasPairedScale || scale.isDemo { DashboardView() } else { PairingView() }
            }.tabItem { Label("测量", systemImage: "scalemass") }.tag(0)
            TrendsView().tabItem { Label("趋势", systemImage: "chart.line.uptrend.xyaxis") }.tag(1)
            HistoryView().tabItem { Label("历史", systemImage: "clock.arrow.circlepath") }.tag(2)
            ProfileView().tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(3)
        }
    }

    @ViewBuilder private var selectedScreen: some View {
        switch tab {
        case 1: TrendsView()
        case 2: HistoryView()
        case 3: ProfileView()
        default:
            if hasPairedScale || scale.isDemo { DashboardView() } else { PairingView() }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "scalemass.fill").font(.largeTitle).foregroundStyle(AppTheme.accent)
                Text("WeighTrace").font(.title2.bold())
                Text("每一次变化，都有迹可循").font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 24)
            VStack(spacing: 8) {
                sidebarButton(0, title: "测量", icon: "scalemass")
                sidebarButton(1, title: "趋势", icon: "chart.xyaxis.line")
                sidebarButton(2, title: "历史", icon: "clock.arrow.circlepath")
                sidebarButton(3, title: "我的", icon: "slider.horizontal.3")
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Label(scale.connectionState.title, systemImage: scale.connectionState.icon)
                    .foregroundStyle(scale.connectionState.color)
                Text("本地优先 · 由你掌控").foregroundStyle(.secondary)
            }.font(.caption).padding(.bottom, 20)
        }.padding(.horizontal, 20).appScreenBackground()
    }

    private func sidebarButton(_ index: Int, title: LocalizedStringKey, icon: String) -> some View {
        Button { tab = index } label: {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .foregroundStyle(tab == index ? AppTheme.accent : .primary)
                .background(tab == index ? AppTheme.accent.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).accessibilityAddTraits(tab == index ? [.isSelected] : [])
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
