import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var scale: ScaleManager
    @EnvironmentObject private var profile: UserProfile
    @AppStorage("afu.dashboard.metrics") private var selectedMetrics = "bodyFat,bmi,water"
    @State private var showingConnection = false
    @ScaledMetric(relativeTo: .largeTitle) private var weightSize = 78
    private var displayedMeasurement: BodyMeasurement? { scale.currentMeasurement ?? scale.history.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    AppPageHeader(title: "今天，从一次称重开始", subtitle: "直接连接你的秤，留下自己的记录。")
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 18) {
                            weightCard.frame(minWidth: 420)
                            captureGuide.frame(width: 270)
                        }
                        VStack(spacing: 16) { weightCard; captureGuide }
                    }

                    if let capture = scale.assistedCapture {
                        DashboardActionCard(
                            title: "抱物称重进行中",
                            subtitle: String(format: String(appLocalized: "当前步骤：%@"), capture.phaseTitle),
                            systemImage: "pawprint.fill",
                            tint: AppTheme.accent
                        ) { AssistedWeighingView() }
                    }
                    if let capture = scale.repeatCapture {
                        DashboardActionCard(
                            title: "三次测量检查进行中",
                            subtitle: String(format: String(appLocalized: "已完成 %lld / 3 次"), capture.measurements.count),
                            systemImage: "repeat.circle.fill",
                            tint: AppTheme.warning
                        ) { RepeatabilityView() }
                    }

                    if let measurement = displayedMeasurement, !scale.isMeasuring,
                       scale.liveWeight <= 0 || (100...1500).contains(scale.impedance) {
                        latestSummary(measurement)
                        metricGrid(measurement)
                    } else if scale.isStable && scale.liveWeight > 0 {
                        EmptyStateView(title: "等待有效阻抗", icon: "waveform.path",
                                       message: "本次体重已稳定，尚未取得有效阻抗；暂不展示上次的身体成分。")
                            .appCard()
                    } else {
                        EmptyStateView(title: "等待测量数据", icon: "figure.walk", message: "连接体脂秤后，赤脚站稳即可自动计算身体指标。")
                            .appCard()
                    }
                    quickActions
                }
                .padding(24)
                .appContentWidth(1100)
            }
            .appScreenBackground()
            .onAppear { scale.startScan() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { DashboardSettingsView() } label: {
                        Label("自定义首页", systemImage: "slider.horizontal.3")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingConnection = true } label: {
                        Label("体脂秤连接", systemImage: "antenna.radiowaves.left.and.right")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .sheet(isPresented: $showingConnection) {
                NavigationStack {
                    List {
                        Section("连接状态") {
                            Label(scale.connectionState.title, systemImage: scale.connectionState.icon)
                            if let name = scale.deviceName { Text(name) }
                            if scale.connectionState == .connected || scale.connectionState == .measuring {
                                Text("体脂秤已连接，可以直接上秤测量。")
                            } else {
                                Button("重新搜索") { scale.startScan() }
                                ForEach(scale.discoveredDevices) { device in
                                    Button { scale.connect(device) } label: {
                                        Text("\(device.name) · \(device.rssi) dBm")
                                    }
                                }
                            }
                        }
                        Section {
                            Text("若连接不上，请关闭手机上的其他体脂秤 App，并轻踩秤面唤醒设备。")
                        }
                    }
                    .navigationTitle("体脂秤连接")
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showingConnection = false }
                    } }
                }
            }
        }
    }

    private var weightCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Label("测量体重", systemImage: "scalemass").font(.subheadline.weight(.semibold))
                Spacer()
                Circle().fill(scale.liveWeight > 0 ? Color.mint : Color.white.opacity(0.3)).frame(width: 8, height: 8)
            }.foregroundStyle(.white.opacity(0.75))
            VStack(alignment: .leading, spacing: 10) {
                Text(weightStatusText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.2f", scale.liveWeight > 0 ? scale.liveWeight : (displayedMeasurement?.weight ?? 0)))
                        .font(.system(size: weightSize, weight: .medium, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.5).monospacedDigit()
                        .contentTransition(.numericText())
                    Text("kg").font(.title3.weight(.medium)).foregroundStyle(.white.opacity(0.65))
                }
            }
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<35) { tick in
                    Rectangle().fill(.white.opacity(tick.isMultiple(of: 5) ? 0.45 : 0.17))
                        .frame(width: 1, height: tick.isMultiple(of: 5) ? 16 : 8)
                        .frame(maxWidth: .infinity)
                }
            }.accessibilityHidden(true)
            Text(scale.deviceName ?? String(appLocalized: "AFU Welland 体脂秤"))
                .font(.caption).foregroundStyle(.white.opacity(0.55))
        }
        .padding(28).frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white).background(AppTheme.hero, in: RoundedRectangle(cornerRadius: 30))
    }

    private var captureGuide: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("测量进度").font(.headline)
            stage("1", title: "连接体脂秤", done: scale.connectionState == .connected || scale.connectionState == .measuring)
            stage("2", title: "体重稳定", done: scale.isStable && scale.liveWeight > 0)
            stage("3", title: "取得有效阻抗", done: (100...1500).contains(scale.impedance))
            Divider()
            connectionLabel
            impedanceStatus
            Button { showingConnection = true } label: {
                Label("管理连接", systemImage: "arrow.up.right").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered).tint(AppTheme.accent)
        }.appCard(padding: 22)
    }

    private func stage(_ number: String, title: LocalizedStringKey, done: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(done ? AppTheme.accent : Color.secondary.opacity(0.10)).frame(width: 28, height: 28)
                if done { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(AppTheme.surface) }
                else { Text(number).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
            }
            Text(title).font(.subheadline).foregroundStyle(done ? .primary : .secondary)
        }
    }

    private var connectionLabel: some View {
        Label(scale.connectionState.title, systemImage: scale.connectionState.icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(scale.connectionState.color)
    }

    @ViewBuilder private var impedanceStatus: some View {
        if scale.isMeasuring {
            ProgressView().tint(AppTheme.accent)
        } else if scale.normalizedImpedances.count >= 2 {
            AppBadge(title: String(format: "ADC 1 %.0f Ω · ADC 2 %.0f Ω",
                                   scale.normalizedImpedances[0], scale.normalizedImpedances[1]),
                     systemImage: "bolt.heart")
        } else if scale.impedance > 0 {
            AppBadge(title: scale.selectedADCIndex.map { "ADC \($0 + 1) · \(Int(scale.impedance)) Ω" }
                        ?? "\(Int(scale.impedance)) Ω", systemImage: "bolt.heart")
        }
    }

    private var weightStatusText: String {
        if scale.liveWeight <= 0 && displayedMeasurement != nil { return String(appLocalized: "最近记录") }
        if scale.isStable {
            return scale.impedance > 0
                ? String(appLocalized: "测量完成")
                : String(appLocalized: "体重已稳定，等待有效阻抗")
        }
        return scale.liveWeight > 0
            ? String(appLocalized: "正在测量...")
            : String(appLocalized: "请赤脚站上体脂秤")
    }

    private func latestSummary(_ measurement: BodyMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(measurement.memberName ?? String(appLocalized: "本人")).font(.headline)
                Spacer()
                if let previous = scale.history
                    .filter({ measurement.memberID != nil && $0.memberID == measurement.memberID && $0.date < measurement.date })
                    .max(by: { $0.date < $1.date }) {
                    AppBadge(title: String(format: String(appLocalized: "较上次 %+.2f kg"), measurement.weight - previous.weight),
                             systemImage: "arrow.up.arrow.down")
                }
            }
            Text(measurement.adcIndex.map {
                String(format: String(appLocalized: "本次采用 ADC %lld，双路数据按实际接收保存"), $0 + 1)
            } ?? String(appLocalized: "这条记录未保存 ADC 选择"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .appCard()
    }

    private func metricGrid(_ m: BodyMeasurement) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ForEach(selectedMetrics.split(separator: ",").compactMap { DashboardMetric(rawValue: String($0)) }) { metric in
                VStack(alignment: .leading, spacing: 6) {
                    Text(metric.title).font(.caption).foregroundStyle(.secondary)
                    Text(metric.value(m)).font(.system(.title3, design: .rounded, weight: .bold))
                    Text(metric.source).font(.caption2).foregroundStyle(.secondary)
                }
                .appTile()
            }
        }
    }

    private var quickActions: some View {
        VStack(spacing: 10) {
            if let measurement = displayedMeasurement {
                NavigationLink { MeasurementDetailView(measurement: measurement) } label: {
                    Label("查看最近记录详情", systemImage: "doc.text.magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.accent)
            }
            Text("测量工具箱").font(.title3.bold()).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                AppRouteCard(title: "三次测量检查", subtitle: "看看同样条件下有多稳定", icon: "repeat") { RepeatabilityView() }
                AppRouteCard(title: "抱物称重", subtitle: "给宠物、行李和包裹留个档案", icon: "pawprint") { AssistedWeighingView() }
                AppRouteCard(title: "ADC 对比", subtitle: "导入阿福结果，比较两路估算", icon: "arrow.left.arrow.right") { ADCComparisonView() }
            }
        }
    }
}

private struct DashboardActionCard<Destination: View>: View {
    let title: LocalizedStringKey
    let subtitle: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let destination: Destination

    var body: some View {
        NavigationLink { destination } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .appCard(padding: 14)
        }
    }
}
