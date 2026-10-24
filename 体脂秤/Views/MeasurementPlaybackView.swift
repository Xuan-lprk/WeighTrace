import SwiftUI
import Charts

struct MeasurementPlaybackView: View {
    let records: [BodyMeasurement]
    let metric: TrendMetric
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var progress = 0.0
    @State private var playing = false
    @State private var speed = 1.0

    init(records: [BodyMeasurement], metric: TrendMetric) {
        self.records = records.sorted { $0.date < $1.date }
        self.metric = metric
    }
    private var ordered: [BodyMeasurement] { records }
    private var index: Int? { MeasurementPlayback.index(progress: progress, count: ordered.count) }
    private var current: BodyMeasurement? { index.map { ordered[$0] } }
    private var yDomain: ClosedRange<Double> {
        let values = ordered.map { metric.value($0) }
        let low = values.min() ?? 0, high = values.max() ?? 1
        let padding = max(0.5, (high - low) * 0.18)
        return (low - padding)...(high + padding)
    }
    private var xDomain: ClosedRange<Date> {
        let start = ordered.first?.date ?? Date()
        let end = ordered.last?.date ?? start
        return start...max(end, start.addingTimeInterval(3600))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if let current, let index {
                    stage(current: current, index: index)
                    HStack {
                        Button {
                            if progress >= 1 { progress = 0 }
                            playing.toggle()
                        } label: {
                            Label(playing ? String(localized: "暂停回放") : String(localized: "播放回忆"), systemImage: playing ? "pause.fill" : "play.fill")
                                .font(.headline).padding(.horizontal, 8).padding(.vertical, 5)
                        }.buttonStyle(.borderedProminent).tint(.teal).disabled(ordered.count < 2)
                        Spacer()
                        Picker("播放速度", selection: $speed) {
                            Text("0.5×").tag(0.5); Text("1×").tag(1.0); Text("2×").tag(2.0)
                        }.pickerStyle(.segmented).frame(maxWidth: 220)
                    }
                    Slider(value: $progress, in: 0...1) { editing in if editing { playing = false } }
                        .tint(.teal).disabled(ordered.count < 2).accessibilityLabel(Text("回放进度"))
                    HStack {
                        Text(ordered.first!.date, format: .dateTime.year().month().day())
                        Spacer()
                        Text(ordered.last!.date, format: .dateTime.year().month().day())
                    }.font(.caption).foregroundStyle(.secondary)
                    eventCard(current: current, index: index)
                    Text("回放沿用当前趋势的成员、时间范围和指标。只播放已有记录，不补齐缺测日期，也不改写数据。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("还没有测量记录", systemImage: "play.rectangle")
                }
            }.padding().frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }
        .navigationTitle("数据回放")
        .task(id: playing) {
            guard playing else { return }
            // Discrete record steps, one cancellable task. No timer per stroke/point or 60 Hz rebuild.
            while !Task.isCancelled && playing && progress < 1 {
                do { try await Task.sleep(for: .seconds(max(0.06, min(0.8, 20 / Double(max(1, ordered.count - 1)))) / speed)) }
                catch { return }
                guard playing, !Task.isCancelled else { return }
                let next = min(1, progress + 1 / Double(max(1, ordered.count - 1)))
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { progress = next }
            }
            if !Task.isCancelled { playing = false }
        }
        .onDisappear { playing = false }
        .onChange(of: scenePhase) { _, phase in if phase != .active { playing = false } }
        .onChange(of: records.map(\.id)) { _, _ in playing = false; progress = 0 }
    }

    private func stage(current: BodyMeasurement, index: Int) -> some View {
        // Keep at most 300 plotted samples while the scrubber still visits every original record.
        let strideSize = max(1, (index + 300) / 300)
        let points = Array(ordered.prefix(index + 1).enumerated().filter { $0.offset % strideSize == 0 || $0.offset == index }.map(\.element))
        var segment = 0
        var segments: [UUID: Int] = [:]
        for (offset, record) in ordered.prefix(index + 1).enumerated() {
            if offset > 0 && MeasurementTrends.series(ordered[offset - 1], metric: metric) != MeasurementTrends.series(record, metric: metric) { segment += 1 }
            segments[record.id] = segment
        }
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("时光轨迹", systemImage: "sparkles").font(.caption.weight(.semibold)).tracking(2)
                Spacer()
                Text("\(index + 1) / \(ordered.count)").font(.caption.monospacedDigit())
            }.foregroundStyle(.mint)
            Text(current.date, format: .dateTime.year().month().day()).font(.title3.weight(.medium)).foregroundStyle(.white.opacity(0.8))
            HStack(alignment: .firstTextBaseline) {
                Text(metric.value(current), format: .number.precision(.fractionLength(2)))
                    .font(.system(size: 56, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                Text(metric.unit).font(.title3).foregroundStyle(.mint)
            }.foregroundStyle(.white)
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("日期", point.date), y: .value(metric.title, metric.value(point)), series: .value("段", segments[point.id] ?? 0))
                        .foregroundStyle(LinearGradient(colors: [.cyan, .mint], startPoint: .leading, endPoint: .trailing))
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
                RuleMark(x: .value("日期", current.date)).foregroundStyle(.white.opacity(0.25)).lineStyle(StrokeStyle(dash: [3, 5]))
                PointMark(x: .value("日期", current.date), y: .value(metric.title, metric.value(current)))
                    .symbolSize(180).foregroundStyle(.mint.opacity(0.18))
                PointMark(x: .value("日期", current.date), y: .value(metric.title, metric.value(current)))
                    .symbolSize(45).foregroundStyle(.white)
            }.chartXScale(domain: xDomain).chartYScale(domain: yDomain)
                .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 200)
                .accessibilityLabel(Text("数据回放曲线"))
        }.padding(24)
            .background {
                ZStack(alignment: .topTrailing) {
                    LinearGradient(colors: [Color(red: 0.04, green: 0.09, blue: 0.15), Color(red: 0.06, green: 0.19, blue: 0.23)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle().fill(.cyan.opacity(0.16)).frame(width: 180, height: 180).blur(radius: 55).offset(x: 35, y: -70)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(.mint.opacity(0.18), lineWidth: 1))
    }

    private func eventCard(current: BodyMeasurement, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(current.memberName ?? String(localized: "本人")).font(.headline)
            if index > 0 {
                let changes = MeasurementTrends.changes(ordered[index - 1], current)
                if !changes.isEmpty { Label(changes.joined(separator: " · "), systemImage: "flag.fill").font(.caption).foregroundStyle(.orange) }
            }
            if let tags = current.tags, !tags.isEmpty {
                Label(tags.map { MeasurementTag(rawValue: $0)?.title ?? $0 }.joined(separator: " · "), systemImage: "tag")
                    .font(.subheadline).foregroundStyle(.teal)
            }
            if let note = current.note, !note.isEmpty { Text(note).font(.callout) }
            NavigationLink("打开这次测量") { MeasurementDetailView(measurement: current) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}
