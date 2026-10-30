import Foundation

struct RepeatabilityReport: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let measurements: [BodyMeasurement]

    var hasLargeVariation: Bool {
        guard measurements.count == 3 else { return true }
        if Spread(measurements.map(\.weight)).range > 0.2 + 1e-9 { return true }
        return (0...1).contains { index in
            let values = measurements.compactMap { record -> Double? in
                guard let values = record.normalizedImpedances, values.indices.contains(index) else { return nil }
                return values[index]
            }
            let spread = Spread(values)
            return values.count != 3 || spread.range > spread.median * 0.05
        }
    }
}

struct Spread {
    let median: Double
    let minimum: Double
    let maximum: Double
    var range: Double { maximum - minimum }
    init(_ values: [Double]) {
        median = MeasurementTrends.median(values)
        minimum = values.min() ?? 0
        maximum = values.max() ?? 0
    }
}

/// Requires an observed step-off before each capture; accepts stable weight and dual ADC
/// only within that cycle. A disconnect disarms the current cycle, keeping completed captures.
struct RepeatabilityCapture {
    static let stepOffDropKilograms = 30.0
    let member: FamilyMember
    private(set) var measurements: [BodyMeasurement] = []
    private(set) var waitingForStepOff = true
    private(set) var weight = 0.0
    private(set) var stable = false
    private(set) var raw: [Double] = []
    private(set) var impedances: [Double] = []
    private var stepOffReferenceWeight: Double?
    private var stepOffCeiling: Double?

    /// Some scales never notify zero on step-off. Explicit user confirmation is
    /// an alternative boundary; discard every pending value before rearming.
    mutating func confirmStepOff() {
        guard waitingForStepOff, measurements.count < 3 else { return }
        waitingForStepOff = false
        weight = 0; stable = false; raw = []; impedances = []
    }

    mutating func receiveWeight(_ value: Double, stable: Bool) {
        guard value.isFinite, value >= 0, measurements.count < 3 else { return }
        let droppedOff = waitingForStepOff && stepOffReferenceWeight.map {
            $0 - value >= Self.stepOffDropKilograms - 1e-9
        } == true
        if value < 1 || droppedOff {
            if let reference = stepOffReferenceWeight {
                stepOffCeiling = max(1, reference - Self.stepOffDropKilograms)
            }
            waitingForStepOff = false
            weight = 0; self.stable = false; raw = []; impedances = []
        } else if waitingForStepOff {
            // Before the first capture, observe a real on-scale reading rather
            // than guessing a person's weight from profile defaults.
            if measurements.isEmpty {
                stepOffReferenceWeight = max(stepOffReferenceWeight ?? 0, value)
            }
        } else if !waitingForStepOff {
            // Repeated low readings during step-off are not a new weighing.
            if let ceiling = stepOffCeiling, value <= ceiling + 1e-9 {
                weight = 0; self.stable = false; raw = []; impedances = []
                return
            }
            if weight > 3 && abs(weight - value) > 0.2 {
                raw = []; impedances = []
            }
            weight = value
            self.stable = stable
        }
    }

    mutating func receiveADCs(raw: [Double], impedances: [Double], packetWeight: Double) {
        guard !waitingForStepOff, weight > 3,
              raw.count >= 2, impedances.count >= 2,
              impedances.prefix(2).allSatisfy({ (100...1500).contains($0) }),
              packetWeight <= 0 || abs(packetWeight - weight) <= 0.2 else { return }
        self.raw = Array(raw.prefix(2))
        self.impedances = Array(impedances.prefix(2))
    }

    @MainActor mutating func captureIfReady() -> Bool {
        guard !waitingForStepOff, stable, weight > 3, impedances.count == 2, measurements.count < 3 else { return false }
        let measurement = BodyAlgorithm.measure(weight: weight, impedance: impedances[0], member: member,
            adcIndex: 0, rawADCs: raw, normalizedImpedances: impedances)
        measurements.append(measurement)
        stepOffReferenceWeight = weight
        waitingForStepOff = true
        return true
    }

    mutating func disconnect() {
        waitingForStepOff = true; stable = false; weight = 0; raw = []; impedances = []
        stepOffReferenceWeight = measurements.last?.weight
        stepOffCeiling = nil
    }
}

enum MeasurementTag: String, CaseIterable, Identifiable {
    case morning, afterMeal, afterExercise
    var id: String { rawValue }
    var title: String {
        switch self {
        case .morning: String(appLocalized: "晨起")
        case .afterMeal: String(appLocalized: "饭后")
        case .afterExercise: String(appLocalized: "运动后")
        }
    }
}

enum DashboardMetric: String, CaseIterable, Identifiable {
    case bodyFat, bmi, water, muscle, bone, protein
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bodyFat: String(appLocalized: "体脂率")
        case .bmi: "BMI"
        case .water: String(appLocalized: "体水分率")
        case .muscle: String(appLocalized: "肌肉率")
        case .bone: String(appLocalized: "骨量")
        case .protein: String(appLocalized: "蛋白质率")
        }
    }
    func value(_ m: BodyMeasurement) -> String {
        switch self {
        case .bodyFat: String(format: "%.1f%%", m.bodyFat)
        case .bmi: String(format: "%.2f", m.bmi)
        case .water: String(format: "%.1f%%", m.water)
        case .muscle: String(format: "%.1f%%", m.musclePercent)
        case .bone: String(format: "%.1f kg", m.boneMass)
        case .protein: String(format: "%.1f%%", m.protein)
        }
    }
    var source: String {
        self == .bodyFat ? String(appLocalized: "BIA 公式估算") :
        (self == .bmi ? String(appLocalized: "身高与体重计算") : String(appLocalized: "比例粗略推算"))
    }
}
