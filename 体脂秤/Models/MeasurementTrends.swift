import Foundation

enum TrendMetric: String, CaseIterable, Identifiable {
    case weight, bodyFat, bmi
    var id: String { rawValue }
    var title: String {
        switch self {
        case .weight: String(appLocalized: "体重")
        case .bodyFat: String(appLocalized: "体脂率")
        case .bmi: "BMI"
        }
    }
    var unit: String { self == .weight ? "kg" : (self == .bodyFat ? "%" : "BMI") }
    func value(_ record: BodyMeasurement) -> Double {
        switch self { case .weight: record.weight; case .bodyFat: record.bodyFat; case .bmi: record.bmi }
    }
}

struct DailyWeightPoint: Identifiable {
    let date: Date
    let value: Double
    let sampleCount: Int
    var id: Date { date }
}

enum MeasurementTrends {
    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    static func dailyWeights(_ records: [BodyMeasurement], calendar: Calendar = .current) -> [DailyWeightPoint] {
        Dictionary(grouping: records, by: { calendar.startOfDay(for: $0.date) }).map { date, records in
            DailyWeightPoint(date: date, value: median(records.map(\.weight)), sampleCount: records.count)
        }.sorted { $0.date < $1.date }
    }

    /// Seven calendar days, equal weight per measured day, no interpolation of missing dates.
    static func rollingWeights(_ days: [DailyWeightPoint], calendar: Calendar = .current) -> [DailyWeightPoint] {
        var first = 0
        var sum = 0.0
        return days.enumerated().map { index, day in
            let start = calendar.date(byAdding: .day, value: -6, to: day.date)!
            sum += day.value
            while first < index && days[first].date < start { sum -= days[first].value; first += 1 }
            return DailyWeightPoint(date: day.date, value: sum / Double(index - first + 1),
                                    sampleCount: index - first + 1)
        }
    }

    static func changes(_ before: BodyMeasurement, _ after: BodyMeasurement) -> [String] {
        var result: [String] = []
        if before.adcIndex != after.adcIndex { result.append(String(appLocalized: "ADC 改变")) }
        if before.algorithmVersion != after.algorithmVersion { result.append(String(appLocalized: "算法改变")) }
        if let old = before.profileSnapshot, let new = after.profileSnapshot, old != new {
            result.append(String(appLocalized: "资料改变"))
        }
        return result
    }

    static func series(_ record: BodyMeasurement, metric: TrendMetric) -> String {
        // Never connect body estimates across different algorithm / ADC / profile snapshots.
        guard metric != .weight else { return "weight" }
        let p = record.profileSnapshot
        return "\(record.algorithmVersion ?? "legacy")|\(record.adcIndex ?? -1)|\(p?.height ?? 0)|\(p?.sex.rawValue ?? "unknown")|\(p?.birthDate.timeIntervalSince1970 ?? 0)"
    }
}
