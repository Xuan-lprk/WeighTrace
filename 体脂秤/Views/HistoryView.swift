import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var scale: ScaleManager
    @EnvironmentObject private var comparisonStore: ComparisonStore
    @EnvironmentObject private var profile: UserProfile
    @State private var deletionError: String?
    @State private var selectedTag = "all"
    @State private var selectedMember = "all"
    private var filteredHistory: [BodyMeasurement] {
        scale.history.filter {
            (selectedTag == "all" || ($0.tags ?? []).contains(selectedTag)) &&
            (selectedMember == "all" || ($0.memberID?.uuidString ?? "unknown") == selectedMember)
        }.sorted { $0.date > $1.date }
    }
    private var groups: [(date: Date, records: [BodyMeasurement])] {
        Dictionary(grouping: filteredHistory, by: { Calendar.current.startOfDay(for: $0.date) })
            .map { (date: $0.key, records: $0.value) }.sorted { $0.date > $1.date }
    }
    private var members: [(key: String, name: String)] {
        var options = [(key: profile.primaryMember.id.uuidString, name: String(appLocalized: "本人"))]
        options += profile.members.map { (key: $0.id.uuidString, name: $0.name) }
        for record in scale.history {
            let key = record.memberID?.uuidString ?? "unknown"
            if !options.contains(where: { $0.key == key }) {
                options.append((key, record.memberName ?? String(appLocalized: "未归属")))
            }
        }
        return options
    }

    var body: some View {
        NavigationStack {
            List {
                AppPageHeader(title: "你的测量档案", subtitle: "按日期整理，每一笔都能追溯。")
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(filteredHistory.count) 条记录").font(.headline)
                    Picker("成员", selection: $selectedMember) {
                        Text("全部").tag("all")
                        ForEach(members, id: \.key) { Text($0.name).tag($0.key) }
                    }
                    Picker("测量条件", selection: $selectedTag) {
                        Text("全部").tag("all")
                        ForEach(MeasurementTag.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                }.appCard().listRowBackground(Color.clear).listRowSeparator(.hidden)
                if filteredHistory.isEmpty {
                    EmptyStateView(title: "还没有测量记录", icon: "calendar.badge.clock", message: "换个筛选条件，或完成一次测量。")
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                ForEach(groups, id: \.date) { group in
                    Section {
                        ForEach(group.records) { item in
                            NavigationLink { MeasurementDetailView(measurement: item) } label: { historyCard(item) }
                                .contextMenu { Button("删除", role: .destructive) { delete([item]) } }
                                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                        }.onDelete { offsets in delete(offsets.map { group.records[$0] }) }
                    } header: {
                        Text(group.date, format: .dateTime.year().month().day()).font(.subheadline.weight(.semibold))
                    }
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .appContentWidth(1000)
            .navigationBarTitleDisplayMode(.inline)
            .appScreenBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ADCComparisonView()
                    } label: {
                        Label("ADC 对比", systemImage: "arrow.left.arrow.right")
                    }
                }
            }
            .alert(
                "删除失败",
                isPresented: Binding(
                    get: { deletionError != nil },
                    set: { if !$0 { deletionError = nil } }
                )
            ) {
                Button("知道了", role: .cancel) {
                    deletionError = nil
                }
            } message: {
                Text(deletionError ?? "")
            }
        }
    }

    private func delete(_ records: [BodyMeasurement]) {
        Task {
            for record in records {
                if let error = await scale.deleteMeasurement(record) { deletionError = error; break }
            }
        }
    }

    private func historyCard(_ item: BodyMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.memberName ?? String(appLocalized: "本人")).font(.headline)
                    Text(item.date, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(item.weight, specifier: "%.2f") kg")
                    .font(.system(.title, design: .rounded, weight: .semibold))
            }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack { compositionLabel(item); Spacer(); recordBadges(item) }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 8) { compositionLabel(item); recordBadges(item) }
            }
        }.appCard(padding: 20)
    }

    private func compositionLabel(_ item: BodyMeasurement) -> some View {
        Text("BMI \(item.bmi, specifier: "%.2f") · 体脂 \(item.bodyFat, specifier: "%.1f")%")
            .font(.caption).foregroundStyle(.secondary)
    }

    private func recordBadges(_ item: BodyMeasurement) -> some View {
        HStack(spacing: 8) {
            if item.hasDualADC { Label("双 ADC", systemImage: "waveform.path") }
            if comparisonStore.reference(for: item.id) != nil { Label("已对照阿福", systemImage: "checkmark.seal") }
        }.font(.caption2.weight(.medium)).foregroundStyle(AppTheme.accent)
    }
}

struct MeasurementDetailView: View {
    @EnvironmentObject private var scale: ScaleManager
    @EnvironmentObject private var profile: UserProfile
    @EnvironmentObject private var comparisonStore: ComparisonStore
    let measurement: BodyMeasurement

    private var comparison: ADCComparison? {
        guard let reference = comparisonStore.reference(for: measurement.id) else { return nil }
        return comparisonStore.comparison(
            for: reference,
            history: scale.history,
            fallbackMember: profile.primaryMember
        )
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
            MeasurementAnnotationLink(measurement: measurement)
            // Combined Header, Weight, BMI, and Impedance Card
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(measurement.memberName ?? String(appLocalized: "本人"))
                            .font(.title3)
                            .fontWeight(.bold)
                        Text(measurement.date, format: .dateTime.year().month().day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if measurement.impedance > 0 {
                        AppBadge(
                            title: measurement.adcIndex.map { "ADC \($0 + 1) · \(Int(measurement.impedance)) Ω" }
                                ?? "\(Int(measurement.impedance)) Ω",
                            systemImage: "bolt.heart"
                        )
                    }
                }
                
                Divider().padding(.vertical, 2)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("测量体重").font(.caption).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.2f", measurement.weight))
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                            Text("kg").font(.subheadline).fontWeight(.semibold)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("身体质量指数").font(.caption).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.2f", measurement.bmi))
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                            Text("BMI").font(.subheadline).fontWeight(.semibold)
                        }
                    }
                }
            }
            .appHeroCard(padding: 18)

            MeasurementInsightCard(measurement: measurement)

            if let impedances = measurement.normalizedImpedances, impedances.count >= 2 {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("双 ADC 原始档案")
                            .font(.headline)
                        Spacer()
                        Text(measurement.algorithmVersion ?? String(appLocalized: "旧算法"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        ADCValueTile(
                            title: "ADC 1",
                            raw: measurement.rawADCs?.first,
                            impedance: impedances[0],
                            selected: measurement.adcIndex == 0
                        )
                        ADCValueTile(
                            title: "ADC 2",
                            raw: measurement.rawADCs.flatMap { $0.count > 1 ? $0[1] : nil },
                            impedance: impedances[1],
                            selected: measurement.adcIndex == 1
                        )
                    }
                    if let comparison {
                        NavigationLink {
                            ADCComparisonDetailView(comparison: comparison)
                        } label: {
                            Label("查看这次与阿福的详细对比", systemImage: "chart.bar.xaxis")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)
                    } else {
                        Text("可在“ADC 对比”中导入同一次阿福结果。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .appCard()
            } else {
                Text("这是一条旧记录，只保存了当时选中的 ADC，无法还原另一条进行公平对比。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
            }
            
            // Grid of metrics (compact)
            if !(100...1500).contains(measurement.impedance) {
                Text("这条记录没有有效阻抗。体脂等指标可能来自 BMI 回退估算，不能视为成功的阻抗测量，也不能补回当时缺失的 ADC。")
                    .font(.callout).foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("身体指标详情").font(.headline).foregroundStyle(.secondary).padding(.leading, 4)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    MetricTile(title: "体脂率/量", valueString: String(format: "%.1f%% / %.1f kg", measurement.bodyFat, measurement.bodyFatMass), icon: "drop.fill")
                    MetricTile(title: "肌肉率/量", valueString: String(format: "%.1f%% / %.1f kg", measurement.musclePercent, measurement.muscle), icon: "figure.strengthtraining.traditional")
                    MetricTile(title: "骨骼肌率/量", valueString: String(format: "%.1f%% / %.1f kg", measurement.skeletalMusclePercent, measurement.skeletalMuscleMass), icon: "figure.core.training")
                    MetricTile(title: "体水分率/量", valueString: String(format: "%.1f%% / %.1f kg", measurement.water, measurement.waterMass), icon: "water.waves")
                    MetricTile(title: "蛋白质率/量", valueString: String(format: "%.1f%% / %.1f kg", measurement.protein, measurement.proteinMass), icon: "leaf.fill")
                    MetricTile(title: "骨量率/量", valueString: String(format: "%.1f%% / %.1f kg", measurement.boneMassPercent, measurement.boneMass), icon: "shield.fill")
                    MetricTile(title: "皮下脂肪率/量", valueString: String(format: "%.1f%% / %.1f kg", measurement.subcutaneousFatPercent, measurement.subcutaneousFatMass), icon: "drop.triangle.fill")
                }
            }
            }
        }
        .padding()
        .appContentWidth(800)
        .navigationTitle("测量详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ADCValueTile: View {
    let title: String
    let raw: Double?
    let impedance: Double
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).fontWeight(.semibold)
                if selected {
                    Text("当时采用")
                        .font(.caption2)
                        .foregroundStyle(.teal)
                }
            }
            Text("\(impedance, specifier: "%.0f") Ω")
                .font(.title3)
                .fontWeight(.bold)
            if let raw {
                Text("原始值 \(raw, specifier: "%.0f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            selected ? Color.teal.opacity(0.12) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }
}
