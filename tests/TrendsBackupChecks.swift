import Foundation

@main
struct TrendsBackupChecks {
    @MainActor static func main() throws {
        let primary = FamilyMember(id: MeasurementBackup.primaryID, name: "本人", sex: .male,
                                   height: 170, birthDate: Date(timeIntervalSince1970: 946684800), referenceWeight: 60)
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
        var shifting = RepeatabilityCapture(member: primary)
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
    }
}
