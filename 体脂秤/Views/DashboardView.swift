import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var scale: ScaleManager
    @EnvironmentObject private var profile: UserProfile
    @AppStorage("afu.dashboard.metrics") private var selectedMetrics = "bodyFat,bmi,water"
    private var displayedMeasurement: BodyMeasurement? { scale.currentMeasurement ?? scale.history.first }

    var body: some View {
        NavigationStack {
            ScrollView { VStack(spacing: 12) {
                weightCard
                if scale.assistedCapture != nil {
                    NavigationLink("抱物称重进行中，点击继续") { AssistedWeighingView() }
                        .padding().background(.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                }
                if scale.repeatCapture != nil {
                    NavigationLink("三次检查进行中，点击查看进度") { RepeatabilityView() }
                        .padding().background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                }
                
                if let measurement = displayedMeasurement, !scale.isMeasuring {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(measurement.memberName ?? String(appLocalized: "本人")).font(.headline)
                        if let previous = scale.history.filter({ $0.memberID == measurement.memberID && $0.date < measurement.date }).max(by: { $0.date < $1.date }) {
                            Text(String(format: String(appLocalized: "较上次体重 %+.2f kg"), measurement.weight - previous.weight))
                                .font(.subheadline)
                        }
                        Text(measurement.adcIndex.map { String(format: String(appLocalized: "本次采用 ADC %lld，双路数据按实际接收保存"), $0 + 1) } ?? String(appLocalized: "这条记录未保存 ADC 选择"))
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    metricGrid(measurement)
                    NavigationLink("查看完整测量详情") { MeasurementDetailView(measurement: measurement) }
                } else {
                    measuringHint
                }
                NavigationLink("三次测量检查") { RepeatabilityView() }
                NavigationLink { AssistedWeighingView() } label: {
                    Label("抱猫、行李或包裹称重", systemImage: "pawprint.fill")
                        .frame(maxWidth: .infinity).padding()
                        .background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .padding()
            }
            .onAppear {
                scale.startScan()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { DashboardSettingsView() } label: { Label("自定义首页", systemImage: "slider.horizontal.3") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { scale.startScan() } label: {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                }
            }
        }
    }

    private var weightCard: some View {
        VStack(spacing: 12) {
            // Status bar inside card
            HStack {
                Label(scale.connectionState.title, systemImage: scale.connectionState.icon)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(scale.connectionState.color)
                Spacer()
                if scale.isMeasuring {
                    ProgressView().tint(.teal)
                } else if scale.normalizedImpedances.count >= 2 {
                    Text(verbatim: String(
                        format: "ADC 1 %.0f Ω · ADC 2 %.0f Ω",
                        scale.normalizedImpedances[0],
                        scale.normalizedImpedances[1]
                    ))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.teal)
                } else if scale.impedance > 0 {
                    Label(
                        scale.selectedADCIndex.map { "ADC \($0 + 1) · \(Int(scale.impedance)) Ω" }
                            ?? "\(Int(scale.impedance)) Ω",
                        systemImage: "bolt.heart"
                    )
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.teal)
                }
            }
            .padding(.bottom, 2)
            
            Divider()
            
            // Weight display
            VStack(spacing: 4) {
                    Text(scale.liveWeight <= 0 && displayedMeasurement != nil ? String(appLocalized: "最近记录") : (scale.isStable ? String(appLocalized: "测量完成") : (scale.liveWeight > 0 ? String(appLocalized: "正在测量...") : String(appLocalized: "请赤脚站上体脂秤"))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.2f", scale.liveWeight > 0 ? scale.liveWeight : (displayedMeasurement?.weight ?? 0)))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("kg").font(.title3).fontWeight(.semibold)
                }
            }
            .padding(.vertical, 4)
        }
        .padding()
        .background(LinearGradient(colors: [.teal.opacity(0.18), .mint.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
    }

    private func metricGrid(_ m: BodyMeasurement) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(selectedMetrics.split(separator: ",").compactMap { DashboardMetric(rawValue: String($0)) }) { metric in
                VStack(alignment: .leading, spacing: 6) {
                    Text(metric.title).font(.caption)
                    Text(metric.value(m)).font(.title2.bold())
                    Text(metric.source).font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding()
                    .background(.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var measuringHint: some View {
        EmptyStateView(title: "等待测量数据", icon: "figure.walk", message: "连接体脂秤后，赤脚站稳即可自动计算身体指标。")
            .frame(maxHeight: .infinity)
    }
}
