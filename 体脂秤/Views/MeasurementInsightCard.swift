import SwiftUI

struct MeasurementInsightCard: View {
    @EnvironmentObject private var scale: ScaleManager
    let measurement: BodyMeasurement
    private var record: BodyMeasurement { scale.history.first { $0.id == measurement.id } ?? measurement }

    var body: some View {
        let record = record
        let reading = MeasurementInsights.Reading(measurement: record, history: scale.history)
        VStack(alignment: .leading, spacing: 16) {
            InsightHeading(title: "读懂这次测量", subtitle: "根据本地记录整理", icon: "sparkle.magnifyingglass")
            if let previous = reading.previous {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(InsightFormat.delta(record.weight - previous.weight))
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .foregroundStyle(.teal)
                    Text("较上次 · kg").font(.subheadline).foregroundStyle(.secondary)
                }
                Text("单次涨跌不代表长期趋势，也不等于脂肪增减。")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text(record.memberID == nil ? LocalizedStringKey("请先确认记录归属，再进行个人趋势比较。") : LocalizedStringKey("这是一个新的起点，积累记录后就能看到变化。"))
                    .font(.callout)
            }
            if let delta = reading.trendDifference {
                InsightFact(icon: "chart.line.uptrend.xyaxis", title: "近 7 日与前 7 日") {
                    Text("日中位数均值变化：\(InsightFormat.delta(delta)) kg")
                }
            } else {
                InsightFact(icon: "calendar", title: "趋势还在积累") {
                    Text("两个时段各有至少 3 个记录日后，再比较趋势；缺测日期不补值。")
                }
            }
            if !(100...1500).contains(record.impedance) {
                InsightFact(icon: "exclamationmark.circle", title: "缺少有效阻抗", warning: true) {
                    Text("这条记录未保存有效阻抗，已有体脂可能来自回退估算，不能视为有效 BIA 结果。")
                }
            } else {
                InsightFact(icon: "waveform.path", title: record.hasDualADC ? "双路阻抗已记录" : "有效阻抗已记录") {
                    if let index = record.adcIndex, (0...1).contains(index) {
                        Text("本次采用 ADC \(index + 1)；体脂为公式估算，水分和肌肉等为粗略推算。")
                    } else {
                        Text("旧记录未标明采用哪一路 ADC；身体成分为估算值。")
                    }
                }
            }
            if !reading.changes.isEmpty {
                InsightFact(icon: "slider.horizontal.3", title: "估算条件有变化", warning: true) {
                    Text(reading.changes.joined(separator: " · "))
                    Text("体脂差异可能包含计算条件的影响，不宜直接解释为身体变化。")
                }
            }
            if reading.tagsDiffer {
                InsightFact(icon: "tag", title: "两次测量标签不同") {
                    Text("优先比较相似条件的测量；标签只描述记录，不证明变化原因。")
                }
            }
            Divider()
            Label(scale.history.contains { $0.id == record.id } ? LocalizedStringKey("本地档案中已有此记录") : LocalizedStringKey("未在本地档案中找到此记录"),
                  systemImage: "internaldrive")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("查看解读依据") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("仅比较同一成员、截至这次测量的本地记录；Apple 健康读取的数据不混入统计。")
                    if let previous = reading.previous {
                        NavigationLink { MeasurementDetailView(measurement: previous) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("上次记录")
                                Text(previous.date, format: .dateTime.year().month().day().hour().minute())
                                Text("\(previous.weight, specifier: "%.2f") kg")
                            }
                        }
                    }
                    Text("近 7 日：\(reading.recent.days.count) 个记录日；前 7 日：\(reading.earlier.days.count) 个记录日。")
                    Text("每天先取体重中位数，再按天等权平均；多次称重不会增加某一天的权重。")
                    if record.profileSnapshot == nil || record.algorithmVersion == nil {
                        Text("部分旧记录缺少算法或资料快照，无法识别全部计算条件变化。")
                    }
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }.font(.subheadline).tint(.teal)
        }.insightSurface()
    }
}

enum InsightFormat {
    static func delta(_ value: Double) -> String {
        // Avoid presenting a floating-point rounding residue as “−0.00”.
        String(format: "%+.2f", locale: AppLanguage.selected.locale, abs(value) < 0.005 ? 0 : value)
    }
}

struct InsightHeading: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let icon: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(.teal)
                .frame(width: 44, height: 44)
                .background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct InsightFact<Content: View>: View {
    let icon: String
    let title: LocalizedStringKey
    var warning = false
    @ViewBuilder let content: Content
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(warning ? .orange : .teal)
                .frame(width: 22).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                content.font(.callout).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func insightSurface() -> some View {
        self.appCard(padding: 20)
    }
}
