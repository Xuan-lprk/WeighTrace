import Foundation

enum WeighedSubjectKind: String, CaseIterable, Codable, Identifiable {
    case pet, luggage, parcel
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pet: String(localized: "宠物")
        case .luggage: String(localized: "行李")
        case .parcel: String(localized: "包裹")
        }
    }
    var icon: String {
        switch self { case .pet: "pawprint.fill"; case .luggage: "suitcase.fill"; case .parcel: "shippingbox.fill" }
    }
}

struct WeighedSubject: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    let kind: WeighedSubjectKind
}

struct AssistedWeightRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let subjectID: UUID
    let baselineDate: Date
    let date: Date
    let baselineWeight: Double
    let combinedWeight: Double
    var weight: Double { combinedWeight - baselineWeight }
}

/// Weight-only capture, with a new observed step-off between phases.
/// No impedance or body composition is used for assisted weighing.
struct AssistedWeighingCapture {
    let subject: WeighedSubject
    private(set) var waitingForStepOff = true
    private(set) var baselineWeight: Double?
    private(set) var baselineDate: Date?
    private(set) var result: AssistedWeightRecord?
    private(set) var message: String?

    mutating func receiveWeight(_ weight: Double, stable: Bool, at date: Date = Date()) -> AssistedWeightRecord? {
        guard result == nil, weight.isFinite, weight >= 0 else { return nil }
        if weight < 1 { waitingForStepOff = false; return nil }
        guard !waitingForStepOff, stable, weight > 3 else { return nil }
        waitingForStepOff = true
        if let baselineWeight, let baselineDate {
            guard date.timeIntervalSince(baselineDate) >= 0, date.timeIntervalSince(baselineDate) <= 600 else {
                self.baselineWeight = nil; self.baselineDate = nil
                message = String(localized: "间隔超过 10 分钟，请离秤后重新称自己。")
                return nil
            }
            guard weight > baselineWeight else {
                message = String(localized: "抱物后的重量应高于本人重量，请离秤后重试第二步。")
                return nil
            }
            let record = AssistedWeightRecord(id: UUID(), subjectID: subject.id, baselineDate: baselineDate,
                date: date, baselineWeight: baselineWeight, combinedWeight: weight)
            result = record; message = nil
            return record
        }
        baselineWeight = weight; baselineDate = date; message = nil
        return nil
    }

    mutating func disconnect() {
        waitingForStepOff = true
        if result == nil { baselineWeight = nil; baselineDate = nil; message = String(localized: "连接中断，请重新连接并从称自己开始。") }
    }
}

/// Index-based timeline, independent of sampling intervals; empty histories have no frame.
enum MeasurementPlayback {
    static func index(progress: Double, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let safeProgress = progress.isFinite ? min(1, max(0, progress)) : 0
        return min(count - 1, Int((safeProgress * Double(count - 1)).rounded()))
    }
}
