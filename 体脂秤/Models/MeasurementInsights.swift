import Foundation

/// Descriptive statistics only. Never changes measurements or infers causes of weight changes.
enum MeasurementInsights {
    static let minimumComparisonDays = 3

    static func eligible(_ records: [BodyMeasurement], memberID: UUID?, through end: Date) -> [BodyMeasurement] {
        // Unassigned records may belong to different people; never combine them.
        guard let memberID else { return [] }
        var seen = Set<UUID>()
        return records.filter {
            $0.memberID == memberID && $0.date <= end && $0.weight.isFinite && $0.weight > 0
                && seen.insert($0.id).inserted
        }.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
        }
    }

    struct Period {
        let records: [BodyMeasurement]
        let days: [DailyWeightPoint]
        init(records: [BodyMeasurement], calendar: Calendar) {
            self.records = records
            days = MeasurementTrends.dailyWeights(records, calendar: calendar)
        }
        var average: Double? {
            days.isEmpty ? nil : days.reduce(0) { $0 + $1.value } / Double(days.count)
        }
        var range: ClosedRange<Double>? {
            guard let low = records.map(\.weight).min(), let high = records.map(\.weight).max() else { return nil }
            return low...high
        }
        var untaggedCount: Int { records.filter { knownTags($0).isEmpty }.count }
        func count(tag: MeasurementTag) -> Int { records.filter { ($0.tags ?? []).contains(tag.rawValue) }.count }
        var missingImpedanceCount: Int { records.filter { !(100...1500).contains($0.impedance) }.count }
        var hasIncompleteMetadata: Bool {
            records.contains { $0.profileSnapshot == nil || $0.algorithmVersion == nil || $0.adcIndex == nil }
        }
    }

    static func difference(_ current: Period, _ previous: Period) -> Double? {
        guard current.days.count >= minimumComparisonDays, previous.days.count >= minimumComparisonDays,
              let a = current.average, let b = previous.average else { return nil }
        return a - b
    }

    static func knownTags(_ record: BodyMeasurement) -> Set<String> {
        Set((record.tags ?? []).filter { MeasurementTag(rawValue: $0) != nil })
    }

    struct Reading {
        let previous: BodyMeasurement?
        let recent: Period
        let earlier: Period
        let changes: [String]
        let tagsDiffer: Bool
        var trendDifference: Double? { MeasurementInsights.difference(recent, earlier) }

        init(measurement: BodyMeasurement, history: [BodyMeasurement], calendar: Calendar = .current) {
            let records = MeasurementInsights.eligible(history.filter { $0.id != measurement.id } + [measurement],
                                                       memberID: measurement.memberID, through: measurement.date)
            previous = records.last { $0.date < measurement.date }
            let today = calendar.startOfDay(for: measurement.date)
            let recentStart = calendar.date(byAdding: .day, value: -6, to: today)!
            let earlierStart = calendar.date(byAdding: .day, value: -7, to: recentStart)!
            recent = Period(records: records.filter { $0.date >= recentStart }, calendar: calendar)
            earlier = Period(records: records.filter { $0.date >= earlierStart && $0.date < recentStart }, calendar: calendar)
            changes = previous.map { MeasurementTrends.changes($0, measurement) } ?? []
            // An absent tag means unknown, not that a condition did not occur.
            tagsDiffer = previous.map {
                !knownTags($0).isEmpty && !knownTags(measurement).isEmpty && knownTags($0) != knownTags(measurement)
            } ?? false
        }
    }

    struct Week {
        let memberID: UUID?
        let start: Date
        let asOf: Date
        let previousStart: Date
        let current: Period
        let previous: Period
        let conditionChanges: [String]
        var difference: Double? { MeasurementInsights.difference(current, previous) }

        init(history: [BodyMeasurement], memberID: UUID?, now: Date = .now, calendar: Calendar = .current) {
            // Monday–Sunday in the device timezone, independent of interface language / locale week defaults.
            let today = calendar.startOfDay(for: now)
            let offset = (calendar.component(.weekday, from: today) + 5) % 7
            let start = calendar.date(byAdding: .day, value: -offset, to: today)!
            let previousStart = calendar.date(byAdding: .day, value: -7, to: start)!
            self.start = start
            self.previousStart = previousStart
            self.memberID = memberID
            asOf = now
            let records = MeasurementInsights.eligible(history, memberID: memberID, through: now)
            current = Period(records: records.filter { $0.date >= start }, calendar: calendar)
            previous = Period(records: records.filter { $0.date >= previousStart && $0.date < start }, calendar: calendar)
            // Include the preceding reading so a change on this week's first day is not missed.
            conditionChanges = Array(Set(zip(records, records.dropFirst()).flatMap { before, after in
                after.date >= start ? MeasurementTrends.changes(before, after) : []
            })).sorted()
        }
    }
}
