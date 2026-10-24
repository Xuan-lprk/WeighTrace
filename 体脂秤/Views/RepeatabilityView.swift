import SwiftUI

struct RepeatabilityView: View {
    @EnvironmentObject private var scale: ScaleManager
    @EnvironmentObject private var profile: UserProfile
    @State private var memberID = MeasurementBackup.primaryID
    private var member: FamilyMember { ([profile.primaryMember] + profile.members).first { $0.id == memberID } ?? profile.primaryMember }

    var body: some View {
        List {
            Section {
                Text("连续三次检查体重、两路阻抗和体脂估算的重复性；结果不代表真实准确度。实验不进入日常历史或 Apple 健康。请保持相同站位与测量条件。")
                if let capture = scale.repeatCapture {
                    ProgressView(value: Double(capture.measurements.count), total: 3)
                    Text("已完成 \(capture.measurements.count) / 3 次")
                    if capture.measurements.count == 3 {
                        Label("检查完成，报告已保存", systemImage: "checkmark.circle")
                    } else {
                        Text(capture.waitingForStepOff ? String(appLocalized: "请先离秤，等秤发送低于 1 kg 的读数后再上秤。") : String(appLocalized: "请重新上秤，等待稳定体重和两路有效阻抗。"))
                    }
                    Button(capture.measurements.count == 3 ? "退出检查模式" : "结束本次检查", role: .cancel) { scale.endRepeatCheck() }
                } else {
                    Picker("成员", selection: $memberID) {
                        ForEach([profile.primaryMember] + profile.members) { Text($0.name).tag($0.id) }
                    }
                    Button("开始三次测量检查") { scale.startRepeatCheck(member: member) }
                        .disabled(scale.connectionState != .connected || scale.reviewMeasurement != nil || scale.assistedCapture != nil)
                    Text("先连接体脂秤。每次必须观察到离秤事件；断线后也需要先离秤再继续。退出后请离秤，再开始日常称重。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("已保存的检查报告") {
                ForEach(scale.repeatReports) { report in
                    NavigationLink { RepeatabilityReportView(report: report) } label: {
                        VStack(alignment: .leading) {
                            Text(report.date, format: .dateTime.year().month().day().hour().minute())
                            Text(report.measurements.first?.memberName ?? "")
                            Text(report.hasLargeVariation ? String(appLocalized: "本次波动较大") : String(appLocalized: "本次重复性较稳定"))
                                .font(.caption).foregroundStyle(report.hasLargeVariation ? .orange : .teal)
                        }
                    }.swipeActions {
                        Button("删除", role: .destructive) { scale.removeRepeatReport(id: report.id) }
                    }
                }
            }
        }.navigationTitle("三次测量检查")
    }
}

struct RepeatabilityReportView: View {
    let report: RepeatabilityReport
    private func spreadRow(_ title: String, values: [Double], unit: String) -> some View {
        let spread = Spread(values)
        return VStack(alignment: .leading) {
            Text(title).font(.headline)
            Text(String(format: String(appLocalized: "中位数 %.2f · 范围 %.2f–%.2f · 波动 %.2f %@"), spread.median, spread.minimum, spread.maximum, spread.range, unit))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    var body: some View {
        List {
            Section {
                Text(report.hasLargeVariation ? String(appLocalized: "本次波动较大") : String(appLocalized: "本次重复性较稳定"))
                spreadRow(String(appLocalized: "体重"), values: report.measurements.map(\.weight), unit: "kg")
                ForEach(0..<2) { index in
                    spreadRow("ADC \(index + 1) Ω", values: report.measurements.compactMap { $0.normalizedImpedances?[index] }, unit: "Ω")
                    spreadRow("ADC \(index + 1) " + String(appLocalized: "体脂率"), values: estimates(index).map(\.bodyFat), unit: "%")
                }
                Text("体重范围超过 0.2 kg，或任一路阻抗范围超过其中位数 5% 时标记波动较大。这是重复性提示，不是医学准确性判断。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("三次原始档案") {
                ForEach(report.measurements) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.date, format: .dateTime.hour().minute().second())
                        Text("\(record.weight, specifier: "%.2f") kg")
                        Text(verbatim: "ADC raw: \(record.rawADCs ?? []) · Ω: \(record.normalizedImpedances ?? [])")
                            .font(.caption).textSelection(.enabled)
                    }
                }
            }
        }.navigationTitle("重复性报告")
    }
    private func estimates(_ index: Int) -> [BodyMeasurement] {
        report.measurements.compactMap { record in
            guard let snapshot = record.profileSnapshot, let values = record.normalizedImpedances, values.indices.contains(index) else { return nil }
            return BodyAlgorithm.measure(date: record.date, weight: record.weight, impedance: values[index],
                member: snapshot.member(id: record.memberID, name: record.memberName, referenceWeight: record.weight), adcIndex: index)
        }
    }
}
