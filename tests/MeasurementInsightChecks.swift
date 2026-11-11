import Foundation

enum MeasurementInsightChecks {
    @MainActor static func run() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        calendar.firstWeekday = 1 // The product's Monday boundary must not depend on locale.
        func date(_ day: Int, hour: Int = 8) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
        }
        let member = FamilyMember(id: UUID(), name: "Test", sex: .male, height: 175,
                                  birthDate: date(1).addingTimeInterval(-30 * 365 * 86400), referenceWeight: 70)
        let other = FamilyMember(id: UUID(), name: "Other", sex: .female, height: 160,
                                 birthDate: member.birthDate, referenceWeight: 55)
        func record(_ day: Int, _ weight: Double, hour: Int = 8, owner: FamilyMember? = nil) -> BodyMeasurement {
            BodyAlgorithm.measure(date: date(day, hour: hour), weight: weight, impedance: 500,
                                  member: owner ?? member, adcIndex: 0, rawADCs: [500, 520], normalizedImpedances: [500, 520])
        }
        let monday = record(2, 70)
        let mondayAgain = record(2, 74, hour: 9)
        let tuesday = record(3, 73)
        var wednesday = record(4, 71)
        wednesday.tags = [MeasurementTag.morning.rawValue]
        let prior = [record(-5, 73), record(-4, 74), record(-3, 75)]
        let history = prior + [monday, mondayAgain, tuesday, wednesday,
                               record(4, 200, owner: other), record(8, 150)]
        let week = MeasurementInsights.Week(history: history + [monday], memberID: member.id, now: date(4, hour: 12), calendar: calendar)
        assert(week.start == date(2, hour: 0))
        assert(week.current.days.count == 3 && week.current.records.count == 4)
        assert(week.current.average == 72, "equal weight per day: (72 + 73 + 71) / 3")
        assert(week.previous.days.count == 3 && week.previous.average == 74)
        assert(week.difference == -2)
        assert(week.current.range == 70...74)
        assert(week.current.count(tag: .morning) == 1 && week.current.untaggedCount == 3)
        let sparse = MeasurementInsights.Week(history: [monday, mondayAgain, tuesday] + prior, memberID: member.id,
                                             now: date(4), calendar: calendar)
        assert(sparse.difference == nil, "multiple readings on one day do not satisfy minimum dates")
        let empty = MeasurementInsights.Week(history: history, memberID: nil, now: date(4), calendar: calendar)
        assert(empty.current.records.isEmpty && empty.current.average == nil && empty.difference == nil)
        let reading = MeasurementInsights.Reading(measurement: wednesday, history: history, calendar: calendar)
        assert(reading.previous?.id == tuesday.id && reading.trendDifference == -2)
        assert(!reading.tagsDiffer, "missing tags are unknown, not contradictory")
        var changed = wednesday
        changed.adcIndex = 1
        changed.algorithmVersion = "test_v2"
        var taggedTuesday = tuesday
        taggedTuesday.tags = [MeasurementTag.afterMeal.rawValue]
        let changedReading = MeasurementInsights.Reading(measurement: changed, history: [taggedTuesday, changed], calendar: calendar)
        assert(changedReading.changes.count == 2 && changedReading.tagsDiffer)
        var precedingSunday = record(1, 70)
        precedingSunday.adcIndex = 1
        let boundary = MeasurementInsights.Week(history: [precedingSunday, monday], memberID: member.id,
                                               now: date(2, hour: 12), calendar: calendar)
        assert(boundary.conditionChanges == [String(appLocalized: "ADC 改变")], "first reading of week must detect change from preceding week")
        let past = MeasurementInsights.Reading(measurement: monday, history: history, calendar: calendar)
        assert(past.previous?.date ?? .distantFuture < monday.date, "historical interpretation cannot see future records")
        assert(past.recent.records.allSatisfy { $0.date <= monday.date })
        let invalid = BodyMeasurement(id: UUID(), date: date(4), weight: .nan, impedance: 0,
                                     bmi: 0, bodyFat: 0, muscle: 0, water: 0, protein: 0, boneMass: 0,
                                     memberID: member.id, memberName: member.name)
        assert(MeasurementInsights.eligible([invalid], memberID: member.id, through: date(5)).isEmpty)
        let missingADC = BodyMeasurement(id: UUID(), date: date(4), weight: 70, impedance: 0,
                                        bmi: 23, bodyFat: 20, muscle: 0, water: 0, protein: 0, boneMass: 0,
                                        memberID: member.id, memberName: member.name)
        let legacy = MeasurementInsights.Period(records: [missingADC], calendar: calendar)
        assert(legacy.missingImpedanceCount == 1 && legacy.hasIncompleteMetadata && legacy.average == 70)

        let yearBoundary = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 12))!
        let newYear = MeasurementInsights.Week(history: [], memberID: member.id, now: yearBoundary, calendar: calendar)
        assert(calendar.component(.year, from: newYear.start) == 2026 && calendar.component(.day, from: newYear.start) == 28)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let dstSunday = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let dstWeek = MeasurementInsights.Week(history: [], memberID: member.id, now: dstSunday, calendar: calendar)
        assert(calendar.component(.day, from: dstWeek.start) == 2 && calendar.component(.hour, from: dstWeek.start) == 0)
        print("PASS: insight member isolation, deduplication, equal-day weighting, thresholds, historical cutoff, metadata, Monday/year/DST boundaries")
    }
}
