import SwiftUI
import Charts

private struct ADCDifferencePoint: Identifiable {
    let id: String
    let date: Date
    let value: Double
    let source: String
    let segment: String
}

struct ADCDifferenceView: View {
    let comparisons: [ADCComparison]
    @State private var includeRejected = false
    @State private var selectedDate: Date?
    private var visible: [ADCComparison] {
        comparisons.filter { includeRejected || $0.isQualified }.sorted { $0.measurement.date < $1.measurement.date }
    }
    private var selected: ADCComparison? {
        guard let selectedDate else { return nil }
        return visible.min { abs($0.measurement.date.timeIntervalSince(selectedDate)) < abs($1.measurement.date.timeIntervalSince(selectedDate)) }
    }
    private var segments: [UUID: Int] {
        var result: [UUID: Int] = [:]
        var segment = 0
        for (index, item) in visible.enumerated() {
            if index > 0 && !MeasurementTrends.changes(visible[index - 1].measurement, item.measurement).isEmpty { segment += 1 }
            result[item.id] = segment
        }
        return result
    }
    private func chartPoints(errors: Bool) -> [ADCDifferencePoint] {
        let groups = segments
        return visible.flatMap { item -> [ADCDifferencePoint] in
            let sources = errors ? ["ADC 1", "ADC 2"] : [String(appLocalized: "阿福参考"), "ADC 1", "ADC 2"]
            let values = errors ? [item.adc1Error, item.adc2Error] :
                [item.reference.bodyFat, item.adc1Measurement.bodyFat, item.adc2Measurement.bodyFat]
            return sources.enumerated().map { index, source in
                ADCDifferencePoint(id: "\(item.id)-\(index)", date: item.measurement.date,
                    value: values[index], source: source, segment: "\(source)-\(groups[item.id] ?? 0)")
            }
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Toggle("同时显示不合格对照", isOn: $includeRejected)
                Text("图表使用当前本地公式及测量时资料快照分别重算 ADC 1/2，不改写原始历史。阿福只是厂商参考；更接近不代表医学上更准确。")
                    .font(.caption).foregroundStyle(.secondary)
                if visible.isEmpty {
                    ContentUnavailableView("还没有可用对照", systemImage: "chart.xyaxis.line")
                } else {
                    Text("体脂时间线").font(.headline)
                    Chart {
                        ForEach(chartPoints(errors: false)) { point in
                            LineMark(x: .value("日期", point.date), y: .value("体脂率", point.value), series: .value("段", point.segment))
                                .foregroundStyle(by: .value("来源", point.source)).symbol(by: .value("来源", point.source))
                        }
                        if let selected { RuleMark(x: .value("日期", selected.measurement.date)).foregroundStyle(.secondary) }
                    }.chartForegroundStyleScale(domain: [String(appLocalized: "阿福参考"), "ADC 1", "ADC 2"], range: [Color.gray, Color.teal, Color.orange])
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartXSelection(value: $selectedDate).frame(height: 250)
                    Text("与阿福差值（百分点）").font(.headline)
                    Chart {
                        RuleMark(y: .value("零差值", 0)).foregroundStyle(.secondary)
                        ForEach(chartPoints(errors: true)) { point in
                            LineMark(x: .value("日期", point.date), y: .value("差值", point.value), series: .value("段", point.segment))
                                .foregroundStyle(by: .value("来源", point.source)).symbol(by: .value("来源", point.source))
                        }
                        if let selected { RuleMark(x: .value("日期", selected.measurement.date)).foregroundStyle(.secondary) }
                    }.chartForegroundStyleScale(domain: ["ADC 1", "ADC 2"], range: [Color.teal, Color.orange])
                        .chartXSelection(value: $selectedDate).frame(height: 230)
                    Text("正数表示本地估算更高，负数表示更低。点击或拖动任一图表可查看那次对照。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let selected {
                        NavigationLink { ADCComparisonDetailView(comparison: selected) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(selected.measurement.date, format: .dateTime.year().month().day().hour().minute())
                                Text(selected.qualityReason)
                                Text("查看双 ADC、资料快照与对照条件")
                            }.font(.callout)
                        }
                    }
                    Text("计算条件变化").font(.headline)
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            let changes = MeasurementTrends.changes(visible[index - 1].measurement, item.measurement)
                            if !changes.isEmpty {
                                HStack {
                                    Text(item.measurement.date, format: .dateTime.month().day())
                                    Text(changes.joined(separator: " · "))
                                }.font(.caption)
                            }
                        }
                    }
                    Text("旧记录没有资料快照时采用当前本人资料，结果仅供查看；不合格记录不会加入 ADC 推荐统计。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding().frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }.navigationTitle("ADC 差异地图")
            .onChange(of: includeRejected) { _, _ in selectedDate = nil }
    }
}
