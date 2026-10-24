import Foundation
import Combine
import SwiftUI

@MainActor final class UserProfile: ObservableObject {
    private let defaults: UserDefaults
    @Published private(set) var isComplete = false
    // Internal placeholders only. The onboarding gate never displays or uses them
    // as a user's profile until all three fields have been explicitly confirmed.
    @Published var sex: Sex = .female { didSet { savePrimaryProfile() } }
    @Published var height: Double = 165 { didSet { savePrimaryProfile() } }
    @Published var birthDate = Calendar.current.date(byAdding: .year, value: -28, to: .now) ?? .now { didSet { savePrimaryProfile() } }
    @Published var members: [FamilyMember] = []
    private let primaryID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "afu.primary.profile"),
           let saved = try? JSONDecoder().decode(StoredPrimaryProfile.self, from: data),
           Self.isValid(height: saved.height, birthDate: saved.birthDate) {
            sex = saved.sex
            height = saved.height
            birthDate = saved.birthDate
            isComplete = true
        }
        if let data = defaults.data(forKey: "afu.family.members"),
           let saved = try? JSONDecoder().decode([FamilyMember].self, from: data) {
            members = saved
        }
    }
    var primaryMember: FamilyMember { FamilyMember(id: primaryID, name: String(appLocalized: "本人"), sex: sex, height: height, birthDate: birthDate, referenceWeight: 60) }
    @discardableResult
    func completeProfile(sex: Sex, height: Double, birthDate: Date) -> Bool {
        guard Self.isValid(height: height, birthDate: birthDate) else { return false }
        isComplete = false
        self.sex = sex
        self.height = height
        self.birthDate = birthDate
        isComplete = true
        savePrimaryProfile()
        return true
    }

    static func isValid(height: Double, birthDate: Date) -> Bool {
        let earliest = Calendar.current.date(from: DateComponents(year: 1900, month: 1, day: 1))!
        // Preserve the existing backup schema's wider height range.
        return height.isFinite && (50...300).contains(height)
            && birthDate >= earliest && birthDate <= Date()
    }
    func addMember(_ member: FamilyMember) { members.append(member); saveMembers() }
    func restoreBackup(primary: FamilyMember, family: [FamilyMember]) {
        guard completeProfile(sex: primary.sex, height: primary.height, birthDate: primary.birthDate) else { return }
        members = family
        saveMembers()
    }
    func removeMembers(at offsets: IndexSet) { members.remove(atOffsets: offsets); saveMembers() }
    func matchedMember(for weight: Double, history: [BodyMeasurement]) -> FamilyMember {
        let candidates = [primaryMember] + members
        let ranked = candidates.map { member -> (FamilyMember, Double) in
            let records = history.filter { $0.memberID == member.id }.prefix(3)
            let reference = records.isEmpty ? member.referenceWeight : records.map(\.weight).reduce(0, +) / Double(records.count)
            return (member, abs(reference - weight))
        }
        return ranked.min(by: { $0.1 < $1.1 })?.0 ?? primaryMember
    }
    func shouldSuggestNewMember(for weight: Double, history: [BodyMeasurement]) -> Bool {
        let candidates = [primaryMember] + members
        let smallestDifference = candidates.map { member -> Double in
            let records = history.filter { $0.memberID == member.id }.prefix(3)
            let reference = records.isEmpty ? member.referenceWeight : records.map(\.weight).reduce(0, +) / Double(records.count)
            return abs(reference - weight)
        }.min() ?? 0
        return smallestDifference > 7
    }
    private func saveMembers() { if let data = try? JSONEncoder().encode(members) { defaults.set(data, forKey: "afu.family.members") } }
    private func savePrimaryProfile() {
        guard isComplete else { return }
        let profile = StoredPrimaryProfile(sex: sex, height: height, birthDate: birthDate)
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: "afu.primary.profile")
        }
    }

    private struct StoredPrimaryProfile: Codable {
        let sex: Sex
        let height: Double
        let birthDate: Date
    }
}
