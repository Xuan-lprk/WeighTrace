import Foundation

@main
struct TrendsBackupChecks {
    @MainActor static func main() throws {
        let realProfileBefore = UserDefaults.standard.data(forKey: "afu.primary.profile")
        let realReferencesBefore = UserDefaults.standard.data(forKey: "afu.official.references")
        let suiteName = "afu.tests.demo.\(UUID().uuidString)"
        let demoDefaults = UserDefaults(suiteName: suiteName)!
        defer { demoDefaults.removePersistentDomain(forName: suiteName) }
        let demoProfile = UserProfile(defaults: demoDefaults)
        assert(!demoProfile.isComplete)
        assert(demoDefaults.data(forKey: "afu.primary.profile") == nil)
        demoProfile.height = 182
        assert(!UserProfile(defaults: demoDefaults).isComplete, "partial edits must not complete onboarding")
        let birthday = Date(timeIntervalSince1970: 946684800)
        assert(!demoProfile.completeProfile(sex: .male, height: .nan, birthDate: birthday))
        assert(!demoProfile.completeProfile(sex: .male, height: 182, birthDate: Date().addingTimeInterval(86400)))
        assert(demoDefaults.data(forKey: "afu.primary.profile") == nil)
        assert(demoProfile.completeProfile(sex: .male, height: 182, birthDate: birthday))
        let reloadedProfile = UserProfile(defaults: demoDefaults)
        assert(reloadedProfile.isComplete && reloadedProfile.height == 182 && reloadedProfile.sex == .male)
        assert(reloadedProfile.birthDate == birthday)
        assert(UserDefaults.standard.data(forKey: "afu.primary.profile") == realProfileBefore)
        assert(AppLanguage(rawValue: "en") == .english)
        assert(AppLanguage.simplifiedChinese.locale.identifier == "zh-Hans")
        let primary = FamilyMember(id: MeasurementBackup.primaryID, name: "本人", sex: .male,
                                   height: 170, birthDate: Date(timeIntervalSince1970: 946684800), referenceWeight: 60)
        let command = AFUPacket.profileCommand(member: primary, date: Date(timeIntervalSince1970: 1700000000), timeZone: TimeZone(secondsFromGMT: 0)!)
        assert(command.map { String(format: "%02x", $0) }.joined() == "ac276553f100000001aa0000170100000300d03f", "D0 must match the CLI encoder byte for byte")
        // Wrapped protocol fixtures need the opcode at byte 18, as on the wire.
        let wrappedADC = AFUPacket(data: Data([0xAC,0x29,0x02,0x00,0x02,0x05,0x01,0xD8,0x01,0x80,0x68,0xE2,0xC2,0,0,0,0,0x29,0xD6,0x0E]))!
        assert(wrappedADC.adcs == [517, 472] && abs(wrappedADC.adcWeight - 58.05) < 0.001)
        let zeroWeight = AFUPacket(data: Data([0xAC,0x29,0,0x68,0,0,2,0,5,0x40,0,0x64,0,0,0,0,0,0x29,0xD5,0x11]))!
        assert(zeroWeight.weight == 0 && !zeroWeight.stable, "reported zero D5 packet is not a completed on-scale measurement")
        let oldRelease = try JSONDecoder().decode(MacRelease.self, from: Data(#"{"tag_name":"V1.6.9","html_url":"https://github.com/Xuan-lprk/WeighTrace/releases/tag/V1.6.9","draft":false,"prerelease":false,"assets":[{"name":"WeighTrace1.6-9.dmg"}]}"#.utf8))
        assert(oldRelease.packageVersion == MacRelease.Version(number: "1.6", build: 9))
        assert(!oldRelease.packageVersion!.isNewer(than: .init(number: "1.6.1", build: 10)), "old build tag must not masquerade as a newer marketing version")
        assert(MacRelease.Version(number: "1.6.2", build: 12).isNewer(than: .init(number: "1.6.2", build: 11)))
        print("PASS: CLI D0 initialization, ADC/zero-weight packets and legacy release naming")
        // The original profile schema had these same fields, but no completion flag.
        demoDefaults.set(try JSONEncoder().encode(primary), forKey: "afu.primary.profile")
        assert(UserProfile(defaults: demoDefaults).isComplete, "valid existing profiles skip onboarding")
        let restored = UserProfile(defaults: UserDefaults(suiteName: suiteName + ".restore")!)
        defer { UserDefaults(suiteName: suiteName + ".restore")!.removePersistentDomain(forName: suiteName + ".restore") }
        assert(!restored.isComplete)
        restored.restoreBackup(primary: primary, family: [])
        assert(restored.isComplete && restored.height == primary.height)
        print("PASS: blank onboarding, partial/invalid rejection, completion persistence, legacy profile and backup restoration")
        let start = Date(timeIntervalSince1970: 1_760_000_000.123456)
        func measurement(_ day: Int, _ weight: Double, id: UUID = UUID()) -> BodyMeasurement {
            BodyAlgorithm.measure(id: id, date: start.addingTimeInterval(Double(day) * 86400), weight: weight,
                                  impedance: 500, member: primary, adcIndex: 0,
                                  rawADCs: [500, 510], normalizedImpedances: [500, 510])
        }
        let a = measurement(0, 60)
        let b = measurement(0, 64)
        let c = measurement(1, 63)
        let reference = OfficialReferenceRecord(id: UUID(), measurementID: a.id, measuredAt: start, importedAt: start,
            referenceType: .officialApp, importMethod: .manual, weight: 60, bodyFat: 15,
            waterPercent: nil, musclePercent: nil, proteinPercent: nil, boneMass: nil,
            skeletalMusclePercent: nil, subcutaneousFatPercent: nil, visceralFat: nil, note: "comma, quote\"\nline")
        let demoComparisons = ComparisonStore(defaults: demoDefaults)
        demoComparisons.upsert(reference)
        assert(ComparisonStore(defaults: demoDefaults).references == [reference])
        assert(UserDefaults.standard.data(forKey: "afu.official.references") == realReferencesBefore)
        print("PASS: injected demo profile/reference stores do not modify real defaults; language choices")
        let backup = MeasurementBackup(primary: primary, members: [], measurements: [a, b, c], references: [reference])
        let decoded = try MeasurementBackup.decode(backup.encoded())
        assert(decoded.measurements == backup.measurements, "dates, snapshots and ADCs round-trip exactly")
        assert(decoded.references == backup.references)
        let alternateReference = OfficialReferenceRecord(id: UUID(), measurementID: a.id, measuredAt: start,
            importedAt: start, referenceType: .officialApp, importMethod: .manual, weight: 60, bodyFat: 16,
            waterPercent: nil, musclePercent: nil, proteinPercent: nil, boneMass: nil,
            skeletalMusclePercent: nil, subcutaneousFatPercent: nil, visceralFat: nil, note: nil)
        let alternate = MeasurementBackup(primary: primary, members: [], measurements: [a], references: [alternateReference])
        assert(backup.merged(with: alternate, replaceConflicts: false).references == [reference])
        assert(backup.merged(with: alternate, replaceConflicts: true).references == [alternateReference])
        let repeatImport = backup.merged(with: decoded, replaceConflicts: false)
        assert(repeatImport.measurements.count == 3 && repeatImport.references.count == 1)
        assert(decoded.preview(against: backup).allSatisfy { $0.added == 0 && $0.conflicts == 0 })
        let changed = measurement(0, 65, id: a.id)
        let incoming = MeasurementBackup(primary: primary, members: [], measurements: [changed], references: [])
        assert(incoming.preview(against: backup).first { $0.title == String(localized: "测量记录") }?.conflicts == 1)
        assert(backup.merged(with: incoming, replaceConflicts: false).measurements.first { $0.id == a.id } == a)
        assert(backup.merged(with: incoming, replaceConflicts: true).measurements.first { $0.id == a.id } == changed)
        let daily = MeasurementTrends.dailyWeights([a, b, c])
        assert(daily.count == 2 && daily[0].value == 62 && daily[0].sampleCount == 2)
        let rolling = MeasurementTrends.rollingWeights(daily)
        assert(rolling.last?.value == 62.5, "equal weight per day, not per measurement")
        let gap = DailyWeightPoint(date: daily[0].date.addingTimeInterval(10 * 86400), value: 70, sampleCount: 1)
        assert(MeasurementTrends.rollingWeights([daily[0], gap]).last?.value == 70, "missing days aren't fabricated")
        assert(MeasurementTrends.median([1, 3, 2]) == 2)
        var changedADC = a
        changedADC.adcIndex = 1
        assert(MeasurementTrends.changes(a, changedADC).count == 1)
        assert(MeasurementTrends.series(a, metric: .bodyFat) != MeasurementTrends.series(changedADC, metric: .bodyFat))
        let newerProfile = FamilyMember(id: primary.id, name: primary.name, sex: primary.sex, height: 180,
                                       birthDate: primary.birthDate, referenceWeight: 60)
        var changedProfile = a
        changedProfile.profileSnapshot = MeasurementProfileSnapshot(member: newerProfile)
        assert(MeasurementTrends.changes(a, changedProfile) == [String(localized: "资料改变")])
        var invalid = backup
        invalid.schemaVersion = 999
        do { _ = try MeasurementBackup.decode(invalid.encoded()); assertionFailure("newer schema rejected") } catch {}
        let duplicates = MeasurementBackup(primary: primary, members: [], measurements: [a, a], references: [])
        do { try duplicates.validate(); assertionFailure("duplicate UUID rejected") } catch {}
        let orphan = MeasurementBackup(primary: primary, members: [], measurements: [], references: [reference])
        do { try orphan.validate(); assertionFailure("orphan reference rejected") } catch {}
        assert(backup.csv().contains("\"comma, quote\"\"\nline\""))
        var dangerousName = primary
        dangerousName.name = "=SUM(1,2)"
        let dangerousRecord = BodyMeasurement(id: UUID(), date: start, weight: 60, impedance: 0, bmi: 20,
            bodyFat: 15, muscle: 40, water: 60, protein: 20, boneMass: 2,
            memberID: primary.id, memberName: dangerousName.name)
        let escaped = MeasurementBackup(primary: primary, members: [], measurements: [dangerousRecord], references: []).csv()
        assert(escaped.contains("\"'=SUM(1,2)\""))
        var capture = RepeatabilityCapture(member: primary)
        capture.receiveWeight(60, stable: true)
        capture.receiveADCs(raw: [500, 510], impedances: [500, 510], packetWeight: 60)
        assert(!capture.captureIfReady(), "must observe step off before first sample")
        for _ in 0..<3 {
            capture.receiveWeight(0, stable: true)
            capture.receiveADCs(raw: [500, 510], impedances: [500, 510], packetWeight: 60)
            assert(!capture.captureIfReady(), "ADC without on-scale weight cannot capture")
            capture.receiveWeight(60, stable: false)
            capture.receiveADCs(raw: [500, 510], impedances: [500, 510], packetWeight: 70)
            capture.receiveWeight(60, stable: true)
            assert(!capture.captureIfReady(), "inconsistent packet weight rejected")
            capture.receiveADCs(raw: [500, 510], impedances: [500, 510], packetWeight: 60)
            assert(capture.captureIfReady())
            assert(!capture.captureIfReady(), "duplicate stable packets cannot add a repeat")
        }
        let report = RepeatabilityReport(id: UUID(), date: start, measurements: capture.measurements)
        assert(!report.hasLargeVariation)
        let varied = RepeatabilityReport(id: UUID(), date: start,
            measurements: [measurement(0, 60), measurement(0, 60), measurement(0, 60.3)])
        assert(varied.hasLargeVariation, "weight spread over 0.2 kg is flagged")
        var variedADC = a
        variedADC.normalizedImpedances = [540, 510]
        assert(RepeatabilityReport(id: UUID(), date: start, measurements: [a, a, variedADC]).hasLargeVariation)
        var experimentalBackup = backup
        experimentalBackup.repeatChecks = [report]
        let restoredExperiment = try MeasurementBackup.decode(experimentalBackup.encoded())
        assert(restoredExperiment.repeatChecks == [report])
        assert(experimentalBackup.merged(with: experimentalBackup, replaceConflicts: false).repeatChecks?.count == 1)
        var reconnect = RepeatabilityCapture(member: primary)
        reconnect.receiveWeight(0, stable: true)
        reconnect.receiveWeight(60, stable: true)
        reconnect.disconnect()
        reconnect.receiveADCs(raw: [500, 510], impedances: [500, 510], packetWeight: 60)
        assert(!reconnect.captureIfReady(), "disconnect invalidates pending cycle")
        var manual = RepeatabilityCapture(member: primary)
        for _ in 0..<3 {
            manual.confirmStepOff()
            manual.receiveADCs(raw: [500, 510], impedances: [500, 510], packetWeight: 60)
            manual.receiveWeight(60, stable: true)
            assert(!manual.captureIfReady(), "manual boundary must not reuse ADC without a fresh weight")
            manual.receiveADCs(raw: [500, 510], impedances: [500, 510], packetWeight: 60)
            assert(manual.captureIfReady(), "manual step-off supports scales without zero notifications")
            manual.receiveWeight(60, stable: true)
            manual.receiveADCs(raw: [500, 510], impedances: [500, 510], packetWeight: 60)
            assert(!manual.captureIfReady(), "must confirm a new boundary before another capture")
        }
        assert(manual.measurements.count == 3)
        manual.confirmStepOff()
        assert(manual.waitingForStepOff, "completed experiment cannot be rearmed")
        reconnect.confirmStepOff()
        reconnect.receiveWeight(60, stable: true)
        assert(!reconnect.captureIfReady(), "manual reconnect boundary clears stale ADCs")
        var shifting = RepeatabilityCapture(member: primary)
        var automatic = RepeatabilityCapture(member: primary)
        automatic.receiveWeight(50, stable: true)
        automatic.receiveWeight(20.01, stable: false)
        assert(automatic.waitingForStepOff, "a drop below 30 kg does not rearm")
        automatic.receiveWeight(.nan, stable: false)
        assert(automatic.waitingForStepOff)
        automatic.receiveWeight(20, stable: false)
        assert(!automatic.waitingForStepOff && automatic.weight == 0, "exact 30 kg drop rearms before the first capture")
        for index in 0..<3 {
            automatic.receiveWeight(20, stable: true)
            automatic.receiveADCs(raw: [500, 510], impedances: [500, 510], packetWeight: 20)
            assert(!automatic.captureIfReady(), "low step-off readings cannot become the next measurement")
            automatic.receiveWeight(50, stable: true)
            assert(!automatic.captureIfReady(), "fresh ADC is required after rearming")
            automatic.receiveADCs(raw: [500, 510], impedances: [500, 510], packetWeight: 50)
            assert(automatic.captureIfReady())
            automatic.receiveWeight(49, stable: false)
            assert(automatic.waitingForStepOff, "ordinary fluctuations do not rearm")
            if index < 2 {
                automatic.receiveWeight(19.5, stable: false)
                assert(!automatic.waitingForStepOff)
            }
        }
        automatic.receiveWeight(0, stable: true)
        assert(automatic.waitingForStepOff && automatic.measurements.count == 3, "completed reports stay completed")
        print("PASS: automatic 30 kg step-off, threshold boundary, low-reading and stale ADC rejection")
        shifting.receiveWeight(0, stable: true)
        shifting.receiveWeight(60, stable: false)
        shifting.receiveADCs(raw: [500, 510], impedances: [500, 510], packetWeight: 60)
        shifting.receiveWeight(61, stable: true)
        assert(!shifting.captureIfReady(), "weight shift invalidates previously received ADCs")
        var tagged = a
        tagged.tags = [MeasurementTag.morning.rawValue]
        tagged.note = "test note"
        let annotatedBackup = MeasurementBackup(primary: primary, members: [], measurements: [tagged], references: [])
        let restoredAnnotation = try MeasurementBackup.decode(annotatedBackup.encoded())
        assert(restoredAnnotation.measurements.first?.note == "test note")
        var oldVersionData = backup
        oldVersionData.repeatChecks = nil
        let decodedOld = try MeasurementBackup.decode(oldVersionData.encoded())
        assert(decodedOld.repeatChecks == nil, "older backup files remain readable")
        print("PASS: JSON round-trip, repeat/merge/conflict import, schema and UUID validation, reference integrity, CSV escaping, daily median, seven-day trend and ADC separation")
        print("PASS: three-cycle gating, duplicate packets, stale ADC rejection, disconnect invalidation, report backup and annotations")
        let cat = WeighedSubject(id: UUID(), name: "Cat", kind: .pet)
        var assisted = AssistedWeighingCapture(subject: cat)
        assert(assisted.receiveWeight(60, stable: true, at: start) == nil && assisted.baselineWeight == nil)
        _ = assisted.receiveWeight(0, stable: true, at: start)
        _ = assisted.receiveWeight(60, stable: false, at: start)
        assert(assisted.baselineWeight == nil)
        _ = assisted.receiveWeight(60, stable: true, at: start)
        assert(assisted.baselineWeight == 60)
        assert(assisted.receiveWeight(64.15, stable: true, at: start) == nil, "must step off between phases")
        _ = assisted.receiveWeight(0, stable: true, at: start)
        let assistedResult = assisted.receiveWeight(64.15, stable: true, at: start.addingTimeInterval(30))!
        assert(abs(assistedResult.weight - 4.15) < 1e-9)
        assert(assisted.receiveWeight(64.15, stable: true, at: start) == nil, "completed result saved only once")
        var expired = AssistedWeighingCapture(subject: cat)
        _ = expired.receiveWeight(0, stable: true, at: start)
        _ = expired.receiveWeight(60, stable: true, at: start)
        _ = expired.receiveWeight(0, stable: true, at: start)
        assert(expired.receiveWeight(64, stable: true, at: start.addingTimeInterval(601)) == nil)
        assert(expired.baselineWeight == nil)
        var reconnectAssisted = AssistedWeighingCapture(subject: cat)
        _ = reconnectAssisted.receiveWeight(0, stable: true, at: start)
        _ = reconnectAssisted.receiveWeight(60, stable: true, at: start)
        reconnectAssisted.disconnect()
        assert(reconnectAssisted.baselineWeight == nil && reconnectAssisted.waitingForStepOff)
        var invalidAssisted = AssistedWeighingCapture(subject: cat)
        _ = invalidAssisted.receiveWeight(0, stable: true, at: start)
        _ = invalidAssisted.receiveWeight(60, stable: true, at: start)
        _ = invalidAssisted.receiveWeight(0, stable: true, at: start)
        assert(invalidAssisted.receiveWeight(59, stable: true, at: start) == nil)
        assert(invalidAssisted.result == nil && invalidAssisted.baselineWeight == 60)
        _ = invalidAssisted.receiveWeight(0, stable: true, at: start)
        assert(invalidAssisted.receiveWeight(64, stable: true, at: start.addingTimeInterval(20)) != nil)
        var assistedBackup = backup
        assistedBackup.weighedSubjects = [cat]; assistedBackup.assistedRecords = [assistedResult]
        let restoredAssisted = try MeasurementBackup.decode(assistedBackup.encoded())
        assert(restoredAssisted.assistedRecords == [assistedResult] && restoredAssisted.weighedSubjects == [cat])
        assert(backup.merged(with: restoredAssisted, replaceConflicts: false).assistedRecords?.count == 1)
        assert(restoredAssisted.merged(with: restoredAssisted, replaceConflicts: true).assistedRecords?.count == 1)
        assistedBackup.weighedSubjects = []
        do { try assistedBackup.validate(); assertionFailure("orphan assisted record rejected") } catch {}
        assert(MeasurementPlayback.index(progress: 0, count: 0) == nil)
        assert(MeasurementPlayback.index(progress: 1, count: 1) == 0)
        assert(MeasurementPlayback.index(progress: 0.5, count: 5) == 2)
        assert(MeasurementPlayback.index(progress: -1, count: 5) == 0)
        assert(MeasurementPlayback.index(progress: 10, count: 5) == 4)
        assert(MeasurementPlayback.index(progress: .nan, count: 5) == 0)
        print("PASS: assisted step-off gating, unstable/negative-result rejection, duplicate suppression, timeout, disconnect, JSON backup, and playback boundaries")
    }
}
