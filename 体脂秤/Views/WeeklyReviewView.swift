import SwiftUI
import Charts

struct WeeklyReviewCard: View {
    let week: MeasurementInsights.Week
    let memberName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InsightHeading(title: "本周回顾", subtitle: "本周截至今天 · 本地体重记录", icon: "calendar.badge.clock")
            HStack {
                Text(memberName).font(.subheadline.weight(.medium))
                Spacer()
                Text(week.start, format: .dateTime.month().day())
                Text("–")
                Text(week.asOf, format: .dateTime.month().day())
            }.font(.caption).foregroundStyle(.secondary)
            if let average = week.current.average {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 14) {
                    stat("日中位数均值", value: String(format: "%.2f kg", locale: AppLanguage.selected.locale, average))
                    stat("记录天数", value: "\(week.current.days.count) / 7")
                }
                if let delta = week.difference {
                    Text("较上周整周：\(InsightFormat.delta(delta)) kg")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.teal)
                } else {
                    Text("两周各至少记录 3 天后显示变化。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if week.current.days.count > 1 {
                    Chart(week.current.days) { point in
                        LineMark(x: .value(String(appLocalized: "日期"), point.date), y: .value(String(appLocalized: "体重"), point.value))
                            .foregroundStyle(.teal).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        PointMark(x: .value(String(appLocalized: "日期"), point.date), y: .value(String(appLocalized: "体重"), point.value))
                            .foregroundStyle(.teal).symbolSize(28)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartYAxisLabel("kg").frame(height: 130)
                    .accessibilityLabel(Text("本周每日体重中位数"))
                }
            } else {
                Text("本周还没有本地记录，下次称重后这里会自动更新。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            NavigationLink { WeeklyReviewView(week: week, memberName: memberName) } label: {
                HStack {
                    Text("查看本周回顾与依据").font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }.foregroundStyle(.teal).padding(.top, 4)
            }
        }.insightSurface()
    }

    private func stat(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title2, design: .rounded, weight: .semibold))
        }
    }
}

struct WeeklyReviewView: View {
    @EnvironmentObject private var scale: ScaleManager
    private let referenceWeek: MeasurementInsights.Week
    let memberName: String

    init(week: MeasurementInsights.Week, memberName: String) {
        referenceWeek = week
        self.memberName = memberName
    }

    // Refresh edits/deletions while retaining the report's explicit cutoff time.
    private var week: MeasurementInsights.Week {
        MeasurementInsights.Week(history: scale.history, memberID: referenceWeek.memberID, now: referenceWeek.asOf)
    }

    var body: some View {
        let week = week
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    InsightHeading(title: "每一笔，都有迹可循", subtitle: "本周截至今天，对比上周整周", icon: "chart.bar.doc.horizontal")
                    Text(memberName).font(.title2.bold())
                    Text(week.start, format: .dateTime.year().month().day())
                    Text("截至 \(week.asOf.formatted(.dateTime.locale(AppLanguage.selected.locale).month().day().hour().minute()))")
                        .font(.caption).foregroundStyle(.secondary)
                    if let delta = week.difference {
                        Text("\(InsightFormat.delta(delta)) kg")
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold)).foregroundStyle(.teal)
                        Text("日中位数均值变化，不代表脂肪增减。")
                    } else {
                        Text("数据还不够，先安心记录。")
                        Text("两周各至少记录 3 天后显示变化。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }.insightSurface()

                VStack(alignment: .leading, spacing: 14) {
                    Text("两周的数据基础").font(.headline)
                    periodRow("本周截至今天", period: week.current)
                    Divider()
                    periodRow("上周整周", period: week.previous)
                    Text("按设备时区，以周一至周日为一周。本周尚未结束时，比较的是部分周与上周整周，不作减重或增重评价。")
                        .font(.caption).foregroundStyle(.secondary)
                }.insightSurface()

                VStack(alignment: .leading, spacing: 14) {
                    Text("测量条件与数据质量").font(.headline)
                    ForEach(MeasurementTag.allCases) { tag in
                        HStack { Text(tag.title); Spacer(); Text("\(week.current.count(tag: tag)) 次") }
                    }
                    HStack { Text("未标注条件"); Spacer(); Text("\(week.current.untaggedCount) 次") }
                    Text("标签由你填写，同一次测量可有多个标签；未标注不代表空腹或未运动。")
                        .font(.caption).foregroundStyle(.secondary)
                    if week.current.missingImpedanceCount > 0 {
                        Text("\(week.current.missingImpedanceCount) 条记录缺少有效阻抗；体重仍参与统计，体脂不作有效 BIA 结果解读。")
                            .font(.callout).foregroundStyle(.orange)
                    }
                    if !week.conditionChanges.isEmpty {
                        Text(week.conditionChanges.joined(separator: " · ")).font(.subheadline.bold())
                        Text("体脂差异可能包含计算条件的影响，不宜直接解释为身体变化。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if week.current.hasIncompleteMetadata {
                        Text("部分旧记录缺少算法或资料快照，无法识别全部计算条件变化。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.insightSurface()

                VStack(alignment: .leading, spacing: 12) {
                    Text("统计方法").font(.headline)
                    Text("每天先取体重中位数，再按天等权平均；多次称重不会增加某一天的权重。")
                    Text("仅统计此成员的本地体重记录，排除未来日期和无效体重，不混入 Apple 健康读取的数据。体重范围为本周原始记录的最小值至最大值。")
                    Text("这些是记录摘要，不判断变化原因，也不提供诊断或饮食处方。")
                }.font(.callout).foregroundStyle(.secondary).insightSurface()

                evidence("本周原始记录", records: week.current.records)
                evidence("上周原始记录", records: week.previous.records)
            }.padding().appContentWidth(800)
        }.navigationTitle("本周回顾").navigationBarTitleDisplayMode(.inline)
    }

    private func periodRow(_ title: LocalizedStringKey, period: MeasurementInsights.Period) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Text("\(period.records.count) 次测量 · \(period.days.count) 个记录日")
                .font(.callout).foregroundStyle(.secondary)
            if let average = period.average {
                Text("日中位数均值：\(average, specifier: "%.2f") kg")
            }
            if let range = period.range {
                Text("体重范围：\(range.lowerBound, specifier: "%.2f")–\(range.upperBound, specifier: "%.2f") kg")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func evidence(_ title: LocalizedStringKey, records: [BodyMeasurement]) -> some View {
        DisclosureGroup(title) {
            LazyVStack(alignment: .leading, spacing: 12) {
                if records.isEmpty { Text("暂无记录").font(.callout).foregroundStyle(.secondary) }
                ForEach(records.reversed()) { record in
                    NavigationLink { MeasurementDetailView(measurement: record) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.date, format: .dateTime.month().day().hour().minute())
                            Text("\(record.weight, specifier: "%.2f") kg").fontWeight(.semibold)
                        }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.padding(.top, 12)
        }.tint(.teal).insightSurface()
    }
}
