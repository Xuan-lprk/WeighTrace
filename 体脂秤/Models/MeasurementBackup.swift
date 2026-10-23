import Foundation

struct MeasurementBackup: Codable {
    static let primaryID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    var format = "afu-scale-backup"
    var schemaVersion = 1
    var exportedAt = Date()
    let primary: FamilyMember
    let members: [FamilyMember]
    let measurements: [BodyMeasurement]
    let references: [OfficialReferenceRecord]

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 50_000_000 else { throw BackupError.invalid }
        let decoder = JSONDecoder()
        let backup = try decoder.decode(Self.self, from: data)
        try backup.validate()
        return backup
    }

    func validate() throws {
        guard format == "afu-scale-backup", schemaVersion == 1 else { throw BackupError.version }
        let allMembers = [primary] + members
        guard primary.id == Self.primaryID,
              Set(allMembers.map(\.id)).count == allMembers.count,
              Set(measurements.map(\.id)).count == measurements.count,
              Set(references.map(\.id)).count == references.count,
              Set(references.map(\.measurementID)).count == references.count else { throw BackupError.invalid }
        guard allMembers.allSatisfy({
            $0.height.isFinite && (50...300).contains($0.height) &&
            $0.referenceWeight.isFinite && (0...1000).contains($0.referenceWeight) &&
            $0.birthDate.timeIntervalSince1970.isFinite
        }) else { throw BackupError.invalid }
        for record in measurements {
            let values = [record.weight, record.impedance, record.bmi, record.bodyFat, record.muscle,
                          record.water, record.protein, record.boneMass] + (record.rawADCs ?? []) + (record.normalizedImpedances ?? [])
            guard values.allSatisfy({ $0.isFinite && $0 >= 0 }), record.weight > 0,
                  record.bodyFat <= 100, record.water <= 100, record.protein <= 100,
                  record.adcIndex == nil || record.adcIndex == 0 || record.adcIndex == 1,
                  record.date.timeIntervalSince1970.isFinite else { throw BackupError.invalid }
            if let snapshot = record.profileSnapshot {
                guard snapshot.height.isFinite, (50...300).contains(snapshot.height),
                      snapshot.birthDate.timeIntervalSince1970.isFinite else { throw BackupError.invalid }
            }
        }
        let ids = Set(measurements.map(\.id))
        for reference in references {
            let optionalValues = [reference.waterPercent, reference.musclePercent, reference.proteinPercent,
                                  reference.boneMass, reference.skeletalMusclePercent,
                                  reference.subcutaneousFatPercent, reference.visceralFat].compactMap { $0 }
            guard ids.contains(reference.measurementID), reference.weight.isFinite, reference.weight > 0,
                  reference.bodyFat.isFinite, (0...100).contains(reference.bodyFat),
                  optionalValues.allSatisfy({ $0.isFinite && $0 >= 0 }),
                  reference.measuredAt.timeIntervalSince1970.isFinite,
                  reference.importedAt.timeIntervalSince1970.isFinite else { throw BackupError.invalid }
        }
    }

    /// Pure merge: conflicts keep local values unless the user explicitly opts in.
    func merged(with incoming: Self, replaceConflicts: Bool) -> Self {
        func merge<T: Identifiable & Equatable>(_ local: [T], _ other: [T]) -> [T] where T.ID == UUID {
            var result = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
            for item in other where result[item.id] == nil || replaceConflicts { result[item.id] = item }
            return result.values.sorted { $0.id.uuidString < $1.id.uuidString }
        }
        let mergedMeasurements = merge(measurements, incoming.measurements)
        // Reference identity also has a semantic key: one official reference per measurement.
        var mergedReferences = references
        for reference in incoming.references {
            let conflict = mergedReferences.firstIndex {
                $0.id == reference.id || $0.measurementID == reference.measurementID
            }
            if let index = conflict {
                if replaceConflicts { mergedReferences[index] = reference }
            } else { mergedReferences.append(reference) }
        }
        return Self(primary: replaceConflicts ? incoming.primary : primary,
                    members: merge(members, incoming.members), measurements: mergedMeasurements,
                    references: mergedReferences)
    }

    func preview(against local: Self) -> [BackupPreviewRow] {
        func row<T: Identifiable & Equatable>(_ title: String, _ incoming: [T], _ existing: [T]) -> BackupPreviewRow where T.ID == UUID {
            let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
            return BackupPreviewRow(title: title,
                added: incoming.filter { byID[$0.id] == nil }.count,
                identical: incoming.filter { byID[$0.id] == $0 }.count,
                conflicts: incoming.filter { byID[$0.id] != nil && byID[$0.id] != $0 }.count)
        }
        let localReferences = Dictionary(uniqueKeysWithValues: local.references.map { ($0.measurementID, $0) })
        let referenceByID = Dictionary(uniqueKeysWithValues: local.references.map { ($0.id, $0) })
        var referenceRow = BackupPreviewRow(title: String(localized: "阿福参考"), added: 0, identical: 0, conflicts: 0)
        for reference in references {
            if let existing = referenceByID[reference.id] ?? localReferences[reference.measurementID] {
                if existing == reference { referenceRow.identical += 1 } else { referenceRow.conflicts += 1 }
            } else { referenceRow.added += 1 }
        }
        return [row(String(localized: "本人资料"), [primary], [local.primary]),
                row(String(localized: "家庭成员"), members, local.members),
                row(String(localized: "测量记录"), measurements, local.measurements), referenceRow]
    }

    func conflictDetails(against local: Self) -> [BackupConflict] {
        var conflicts: [BackupConflict] = []
        func describe(_ member: FamilyMember) -> String {
            "\(member.name) · \(member.sex.rawValue) · \(member.height) cm · \(member.birthDate.formatted(date: .numeric, time: .omitted)) · \(member.referenceWeight) kg"
        }
        if primary != local.primary {
            conflicts.append(BackupConflict(id: primary.id, title: String(localized: "本人资料"),
                local: describe(local.primary), incoming: describe(primary)))
        }
        for member in members {
            if let old = local.members.first(where: { $0.id == member.id }), old != member {
                conflicts.append(BackupConflict(id: member.id, title: member.name,
                    local: describe(old), incoming: describe(member)))
            }
        }
        for record in measurements {
            if let old = local.measurements.first(where: { $0.id == record.id }), old != record {
                func describe(_ item: BodyMeasurement) -> String {
                    "\(item.date.formatted()) · \(item.weight) kg · \(item.bodyFat)% · ADC \(item.adcIndex.map { String($0 + 1) } ?? "—") · \(item.algorithmVersion ?? "legacy")"
                }
                conflicts.append(BackupConflict(id: record.id, title: record.id.uuidString,
                    local: describe(old), incoming: describe(record)))
            }
        }
        for reference in references {
            if let old = local.references.first(where: { $0.id == reference.id || $0.measurementID == reference.measurementID }), old != reference {
                conflicts.append(BackupConflict(id: reference.id, title: String(localized: "阿福参考") + " · " + reference.measurementID.uuidString,
                    local: "\(old.measuredAt.formatted()) · \(old.weight) kg · \(old.bodyFat)% · \(old.note ?? "")",
                    incoming: "\(reference.measuredAt.formatted()) · \(reference.weight) kg · \(reference.bodyFat)% · \(reference.note ?? "")"))
            }
        }
        return conflicts
    }

    func csv() -> String {
        let formatter = ISO8601DateFormatter()
        let refs = Dictionary(uniqueKeysWithValues: references.map { ($0.measurementID, $0) })
        func cell(_ value: String) -> String {
            // Prevent spreadsheet formula execution when opening user-entered names/notes.
            let safe = ["=", "+", "-", "@", "\t", "\r", "\n"].contains(where: value.hasPrefix) ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        func number(_ value: Double?) -> String { value.map { String($0) } ?? "" }
        let header = ["id", "measured_at", "member_id", "member_name", "weight_kg", "bmi", "body_fat_percent",
                      "muscle_kg", "water_percent", "protein_percent", "bone_kg", "adc_index_1_based",
                      "adc1_raw", "adc2_raw", "impedance1_ohm", "impedance2_ohm", "selected_impedance_ohm",
                      "algorithm", "profile_height_cm", "profile_sex", "profile_birth_date",
                      "reference_id", "reference_time", "reference_weight_kg", "reference_body_fat_percent", "reference_note"]
        var lines = [header.joined(separator: ",")]
        for record in measurements.sorted(by: { $0.date < $1.date }) {
            let reference = refs[record.id]
            let values: [String] = [record.id.uuidString, formatter.string(from: record.date), record.memberID?.uuidString ?? "",
                record.memberName ?? "", number(record.weight), number(record.bmi), number(record.bodyFat),
                number(record.muscle), number(record.water), number(record.protein), number(record.boneMass),
                record.adcIndex.map { String($0 + 1) } ?? "",
                number(record.rawADCs?.first), number(record.rawADCs.flatMap { $0.count > 1 ? $0[1] : nil }),
                number(record.normalizedImpedances?.first), number(record.normalizedImpedances.flatMap { $0.count > 1 ? $0[1] : nil }),
                number(record.impedance), record.algorithmVersion ?? "", number(record.profileSnapshot?.height),
                record.profileSnapshot?.sex.rawValue ?? "", record.profileSnapshot.map { formatter.string(from: $0.birthDate) } ?? "",
                reference?.id.uuidString ?? "", reference.map { formatter.string(from: $0.measuredAt) } ?? "",
                number(reference?.weight), number(reference?.bodyFat), reference?.note ?? ""]
            lines.append(values.map(cell).joined(separator: ","))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }
}

struct BackupPreviewRow: Identifiable {
    let title: String
    var added: Int
    var identical: Int
    var conflicts: Int
    var id: String { title }
}

struct BackupConflict: Identifiable {
    let id: UUID
    let title: String
    let local: String
    let incoming: String
}

enum BackupError: LocalizedError {
    case invalid, version
    var errorDescription: String? {
        switch self {
        case .invalid: String(localized: "备份数据不完整或无效，请选择本 App 导出的完整 JSON 备份。")
        case .version: String(localized: "不支持此备份格式或版本，请更新 App 后重试。")
        }
    }
}
