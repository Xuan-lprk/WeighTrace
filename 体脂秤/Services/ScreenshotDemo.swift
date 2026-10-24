import Foundation
import Combine

/// An isolated sandbox of synthetic records, never the user's real data store.
@MainActor final class ScreenshotDemo: ObservableObject {
    let defaults: UserDefaults
    let scale: ScaleManager
    let profile: UserProfile
    let comparisons: ComparisonStore
    private let suiteName: String

    init() {
        let name = "afu.screenshot-demo.\(UUID().uuidString)"
        suiteName = name
        let store = UserDefaults(suiteName: name)!
        defaults = store
        store.set(false, forKey: HealthKitManager.enabledKey)
        store.set(true, forKey: "afu.hasPairedScale")
        store.set(true, forKey: "afu.family.hasPromptedInitial")
        profile = UserProfile(defaults: store)
        scale = ScaleManager(defaults: store, isDemo: true)
        comparisons = ComparisonStore(defaults: store)
        profile.completeProfile(
            sex: .male, height: 175,
            birthDate: Calendar.current.date(from: DateComponents(year: 1996, month: 5, day: 12))!
        )
        profile.addMember(FamilyMember(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: String(appLocalized: "演示成员"), sex: .female, height: 164,
            birthDate: Calendar.current.date(from: DateComponents(year: 1998, month: 8, day: 20))!,
            referenceWeight: 56
        ))
        let today = Calendar.current.startOfDay(for: .now)
        var records: [BodyMeasurement] = []
        for day in 0..<35 {
            let date = Calendar.current.date(byAdding: .day, value: day - 34, to: today)!
                .addingTimeInterval(7 * 3600 + 30 * 60)
            // Today must never be in the future when taking screenshots early in the morning.
            let measuredAt = min(date, Date().addingTimeInterval(-60))
            let weight = (71.8 - Double(day) * 0.042 + sin(Double(day) * 1.8) * 0.18)
            let adc1 = 545 + cos(Double(day) * 0.6) * 12
            let adc2 = adc1 - 32
            var measurement = BodyAlgorithm.measure(
                id: Self.id(day + 1), date: measuredAt, weight: weight, impedance: adc1,
                member: profile.primaryMember, adcIndex: 0,
                rawADCs: [adc1, adc2], normalizedImpedances: [adc1, adc2]
            )
            measurement.note = String(appLocalized: "虚构的截图演示数据")
            records.append(measurement)
            if day % 2 == 0 {
                comparisons.upsert(OfficialReferenceRecord(
                    id: Self.id(day + 100), measurementID: measurement.id,
                    measuredAt: measuredAt.addingTimeInterval(-180), importedAt: measuredAt,
                    referenceType: .officialApp, importMethod: .manual,
                    weight: weight, bodyFat: measurement.bodyFat - 0.7 + sin(Double(day)) * 0.25,
                    waterPercent: nil, musclePercent: nil, proteinPercent: nil,
                    boneMass: nil, skeletalMusclePercent: nil, subcutaneousFatPercent: nil,
                    visceralFat: nil, note: String(appLocalized: "虚构参考值，并非真实阿福测量")
                ))
            }
            if day % 3 == 0, let member = profile.members.first {
                records.append(BodyAlgorithm.measure(
                    id: Self.id(day + 200), date: measuredAt.addingTimeInterval(-600),
                    weight: 56 + sin(Double(day)) * 0.3, impedance: 610,
                    member: member, adcIndex: 0, rawADCs: [610, 582],
                    normalizedImpedances: [610, 582]
                ))
            }
        }
        scale.loadDemoMeasurements(records)
    }

    func clearStorage() { defaults.removePersistentDomain(forName: suiteName) }

    private static func id(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }
}
