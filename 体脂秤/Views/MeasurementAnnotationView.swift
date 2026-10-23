import SwiftUI

struct MeasurementAnnotationLink: View {
    @EnvironmentObject private var scale: ScaleManager
    let measurement: BodyMeasurement
    private var record: BodyMeasurement { scale.history.first { $0.id == measurement.id } ?? measurement }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink("标签与备注") { MeasurementAnnotationView(measurement: record) }
            if let tags = record.tags, !tags.isEmpty {
                Text(tags.map { MeasurementTag(rawValue: $0)?.title ?? $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.teal)
            }
            if let note = record.note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding()
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct MeasurementAnnotationView: View {
    @EnvironmentObject private var scale: ScaleManager
    @Environment(\.dismiss) private var dismiss
    let measurement: BodyMeasurement
    @State private var tags: [String] = []
    @State private var note = ""
    var body: some View {
        Form {
            Section("测量条件") {
                ForEach(MeasurementTag.allCases) { tag in
                    Toggle(tag.title, isOn: Binding(get: { tags.contains(tag.rawValue) }, set: { enabled in
                        tags.removeAll { $0 == tag.rawValue }
                        if enabled { tags.append(tag.rawValue) }
                    }))
                }
            }
            Section {
                TextField("备注（最多 500 字）", text: $note, axis: .vertical).lineLimit(3...8)
                    .onChange(of: note) { _, value in if value.count > 500 { note = String(value.prefix(500)) } }
            } header: { Text("备注") } footer: {
                Text("标签用于回看和筛选，不调整体脂算法。标签与备注只保存在本地及 JSON 备份，不更新已经写入的健康样本。")
            }
        }.navigationTitle("标签与备注")
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("保存") { scale.updateAnnotation(id: measurement.id, tags: tags, note: note); dismiss() }
            } }
            .onAppear {
                let current = scale.history.first { $0.id == measurement.id } ?? measurement
                tags = current.tags ?? []; note = current.note ?? ""
            }
    }
}

struct DashboardSettingsView: View {
    @AppStorage("afu.dashboard.metrics") private var selection = "bodyFat,bmi,water"
    private var selected: [String] { selection.split(separator: ",").map(String.init) }
    var body: some View {
        Form {
            Section {
                ForEach(DashboardMetric.allCases) { metric in
                    Toggle(metric.title, isOn: Binding(get: { selected.contains(metric.rawValue) }, set: { enabled in
                        var updated = selected.filter { $0 != metric.rawValue }
                        if enabled && updated.count < 3 { updated.append(metric.rawValue) }
                        selection = updated.joined(separator: ",")
                    })).disabled(!selected.contains(metric.rawValue) && selected.count >= 3)
                }
            } header: { Text("首页常看指标") } footer: {
                Text("最多选择 3 项；取消一项后可选择其他指标。完整指标仍可在测量详情查看。")
            }
        }.navigationTitle("自定义首页")
    }
}
