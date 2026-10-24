import SwiftUI
import Charts

struct TrendsView: View {
    @EnvironmentObject private var scale: ScaleManager
    @EnvironmentObject private var profile: UserProfile
    @State private var memberKey = MeasurementBackup.primaryID.uuidString
    @State private var days = 30
    @State private var metric = TrendMetric.weight
    @State private var useDailyMedian = true
    @State private var selectedDate: Date?

    private var memberOptions: [(key: String, name: String)] {
        var result = [(profile.primaryMember.id.uuidString, String(appLocalized: "本人"))]
        for member in profile.members { result.append((member.id.uuidString, member.name)) }
        for record in scale.history {
            let key = record.memberID?.uuidString ?? "unknown"
            if !result.contains(where: { $0.0 == key }) {
                result.append((key, record.memberName ?? String(appLocalized: "未归属")))
            }
        }
        return result
    }

    private var memberRecords: [BodyMeasurement] {
        scale.history.filter { ($0.memberID?.uuidString ?? "unknown") == memberKey }.sorted { $0.date < $1.date }
    }

    private var records: [BodyMeasurement] {
        let today = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: today)!
        return memberRecords.filter { (days == 0 || $0.date >= start) && $0.date <= Date() }
    }

    private var daily: [DailyWeightPoint] { MeasurementTrends.dailyWeights(records) }
    private var rolling: [DailyWeightPoint] {
        // Compute using history before the viewport so the first visible day has a full window.
        let points = MeasurementTrends.rollingWeights(MeasurementTrends.dailyWeights(memberRecords.filter { $0.date <= Date() }))
        guard let first = daily.first else { return [] }
        return points.filter { $0.date >= first.date && $0.date <= daily.last!.date }
    }

    private var selected: BodyMeasurement? {
        guard let selectedDate else { return nil }
        return records.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    private var events: [(record: BodyMeasurement, text: String)] {
        let ids = Set(records.map(\.id))
        return zip(memberRecords, memberRecords.dropFirst()).compactMap { before, after in
            let changes = MeasurementTrends.changes(before, after)
            guard ids.contains(after.id), !changes.isEmpty else { return nil }
            return (after, changes.joined(separator: " · "))
        }
    }

    private var segments: [UUID: Int] {
        var result: [UUID: Int] = [:]
        var previous: String?
        var index = 0
        for record in records {
            let key = MeasurementTrends.series(record, metric: metric)
            if key != previous { index += 1; previous = key }
            result[record.id] = index
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("成员", selection: $memberKey) {
                        ForEach(memberOptions, id: \.key) { option in Text(option.name).tag(option.key) }
                    }
                    Picker("时间范围", selection: $days) {
                        Text("30 天").tag(30); Text("90 天").tag(90); Text("全部").tag(0)
                    }.pickerStyle(.segmented)
                    Picker("指标", selection: $metric) {
                        ForEach(TrendMetric.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    if records.isEmpty {
                        EmptyStateView(title: "这个范围内还没有记录", icon: "chart.xyaxis.line", message: "换个时间范围，或先完成一次测量。")
                    } else {
                        summary
                        NavigationLink { MeasurementPlaybackView(records: records, metric: metric) } label: {
                            HStack {
                                Image(systemName: "play.circle.fill").font(.title)
                                VStack(alignment: .leading) {
                                    Text("播放这段时光").font(.headline)
                                    Text("让曲线带你重看每一次记录").font(.caption)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                            }.foregroundStyle(.teal).padding()
                                .background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                        }
                        chart
                        if metric == .weight {
                            Toggle("显示每日中位数", isOn: $useDailyMedian)
                            Text("圆点为原始测量。实线为每日中位数，虚线为最近 7 个日历日内有测量日期的日中位数平均；缺测日期不补值。趋势不会修改原始记录。")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("体脂为公式估算。不同 ADC、算法和资料快照使用分开的线段；不平均不同算法的体脂。旧记录可能缺少快照，无法识别全部变化。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let selected {
                            NavigationLink { MeasurementDetailView(measurement: selected) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(selected.date, format: .dateTime.year().month().day().hour().minute())
                                    Text("\(metric.value(selected), specifier: "%.2f") \(metric.unit)").font(.title3.bold())
                                    Text("查看这次测量与对照").font(.caption)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding()
                                    .background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                            }
                        } else {
                            Text("轻点或拖动图表查看附近的原始记录").font(.caption).foregroundStyle(.secondary)
                        }
                        if !events.isEmpty {
                            Text("计算条件变化").font(.headline)
                            ForEach(events, id: \.record.id) { event in
                                NavigationLink { MeasurementDetailView(measurement: event.record) } label: {
                                    HStack {
                                        Text(event.record.date, format: .dateTime.month().day())
                                        Text(event.text)
                                    }.font(.caption)
                                }
                            }
                            Text("这里标记的是相邻测量档案的差异，不代表设置修改的精确时刻，也不能推断是否更换了实体秤。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        NavigationLink("查看完整历史") { HistoryView() }
                    }
                }.padding().frame(maxWidth: 1000)
                    .frame(maxWidth: .infinity)
            }
            .navigationTitle("测量趋势")
            .onChange(of: memberKey) { _, _ in selectedDate = nil }
            .onChange(of: days) { _, _ in selectedDate = nil }
            .onChange(of: metric) { _, _ in selectedDate = nil }
        }
    }

    private var summary: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("范围内最新").font(.caption).foregroundStyle(.secondary)
                Text("\(metric.value(records.last!), specifier: "%.2f") \(metric.unit)").font(.title.bold())
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("\(records.count) 次 · \(daily.count) 天").font(.subheadline)
                if metric == .weight, let first = daily.first, let last = daily.last, daily.count >= 2 {
                    Text(String(format: "%+.2f kg", last.value - first.value)).font(.headline)
                    Text("首末日中位数差").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding().background(.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
    }

    private var chart: some View {
        let lineSegments = segments
        return Chart {
            ForEach(records) { record in
                PointMark(x: .value("日期", record.date), y: .value(metric.title, metric.value(record)))
                    .foregroundStyle(.teal.opacity(0.4)).symbolSize(24)
            }
            if metric == .weight {
                if useDailyMedian {
                    ForEach(daily) { day in
                        LineMark(x: .value("日期", day.date), y: .value("每日中位数", day.value), series: .value("series", "daily"))
                            .foregroundStyle(.teal).lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                ForEach(rolling) { day in
                    LineMark(x: .value("日期", day.date), y: .value("7 日趋势", day.value), series: .value("series", "rolling"))
                        .foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }
            } else {
                ForEach(records) { record in
                    LineMark(x: .value("日期", record.date), y: .value(metric.title, metric.value(record)),
                             series: .value("series", lineSegments[record.id] ?? 0))
                        .foregroundStyle(.teal).lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            ForEach(events, id: \.record.id) { event in
                RuleMark(x: .value("日期", event.record.date))
                    .foregroundStyle(.secondary.opacity(0.25)).lineStyle(StrokeStyle(dash: [2, 4]))
            }
            if let selected {
                RuleMark(x: .value("日期", selected.date)).foregroundStyle(.teal.opacity(0.6))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXSelection(value: $selectedDate)
        .chartYAxisLabel(metric.unit)
        .frame(height: 280)
        .accessibilityLabel(Text("测量趋势"))
    }
}
