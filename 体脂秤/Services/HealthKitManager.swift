import Foundation
import HealthKit
import Combine

enum HealthBodyMetric: String, CaseIterable, Hashable {
    case weight
    case bmi
    case bodyFat
    case leanBodyMass

    var title: String {
        switch self {
        case .weight: String(appLocalized: "体重")
        case .bmi: "BMI"
        case .bodyFat: String(appLocalized: "体脂率")
        case .leanBodyMass: String(appLocalized: "去脂体重")
        }
    }

    var typeIdentifier: HKQuantityTypeIdentifier {
        switch self {
        case .weight: .bodyMass
        case .bmi: .bodyMassIndex
        case .bodyFat: .bodyFatPercentage
        case .leanBodyMass: .leanBodyMass
        }
    }
}

struct HealthDataSourceSummary: Identifiable {
    let id: String
    let name: String
    let bundleIdentifier: String
    let providerName: String
    let isCurrentApp: Bool
    var metrics: Set<HealthBodyMetric>
    var latestDate: Date
    var sampleCount: Int

    var metricText: String {
        HealthBodyMetric.allCases
            .filter(metrics.contains)
            .map(\.title)
            .joined(separator: String(appLocalized: "、"))
    }
}

struct HealthWeightSampleSummary: Identifiable {
    let id: UUID
    let date: Date
    let weightKilograms: Double
    let sourceName: String
    let providerName: String
    let bundleIdentifier: String
}

/// A HealthKit quantity stays independent: never fabricate a complete BIA record
/// or join weight/body-fat samples from different times or sources.
struct HealthTrendSample: Identifiable {
    let id: UUID
    let date: Date
    let metric: HealthBodyMetric
    let value: Double
    let sourceName: String
    let sourceID: String
}

struct HealthDuplicateWeightGroup: Identifiable {
    let id: UUID
    let samples: [HealthWeightSampleSummary]

    var date: Date {
        samples.map(\.date).max() ?? .distantPast
    }

    var averageWeightKilograms: Double {
        guard !samples.isEmpty else { return 0 }
        return samples.map(\.weightKilograms).reduce(0, +) / Double(samples.count)
    }

    var weightSpreadKilograms: Double {
        guard let minimum = samples.map(\.weightKilograms).min(),
              let maximum = samples.map(\.weightKilograms).max() else {
            return 0
        }
        return maximum - minimum
    }

    var timeSpanMinutes: Double {
        guard let earliest = samples.map(\.date).min(),
              let latest = samples.map(\.date).max() else {
            return 0
        }
        return latest.timeIntervalSince(earliest) / 60.0
    }

    var sourceText: String {
        var seen = Set<String>()
        return samples.compactMap { sample in
            guard seen.insert(sample.sourceName).inserted else { return nil }
            return sample.sourceName
        }
        .joined(separator: " ↔ ")
    }
}

@MainActor
final class HealthKitManager: ObservableObject {
    static let enabledKey = "afu.health.enabled"
    static let weightKey = "afu.health.weight"
    static let bmiKey = "afu.health.bmi"
    static let bodyFatKey = "afu.health.bodyFat"
    static let leanBodyMassKey = "afu.health.leanBodyMass"
    private static let archiveMetadataKey = "xuanlprk.measurementArchiveV1"

    @Published private(set) var statusText = String(appLocalized: "尚未连接 Apple 健康")
    @Published private(set) var lastSyncText: String?
    @Published private(set) var sourceSummaries: [HealthDataSourceSummary] = []
    @Published private(set) var duplicateWeightGroups: [HealthDuplicateWeightGroup] = []
    @Published private(set) var sourceStatusText = String(appLocalized: "尚未扫描 Apple 健康数据来源")
    @Published private(set) var isScanningSources = false
    @Published private(set) var recoveryStatusText: String?
    @Published private(set) var isRecoveringMeasurements = false
    @Published private(set) var trendSamples: [HealthTrendSample] = []
    @Published private(set) var isLoadingTrends = false
    @Published private(set) var trendStatusText = ""

    var onMeasurementsRecovered: (([BodyMeasurement]) -> Int)?

    private lazy var healthStore = HKHealthStore()
    private let isDemo: Bool
    private var pendingSaveTasks: [UUID: Task<Void, Never>] = [:]
    private let sourceSampleLimit = 200
    private static let duplicateTimeWindow: TimeInterval = 5 * 60
    private static let duplicateWeightToleranceKilograms = 0.1

    init(isDemo: Bool = false) {
        self.isDemo = isDemo
        guard !isDemo else { return }
        UserDefaults.standard.register(defaults: [
            Self.enabledKey: false,
            Self.weightKey: true,
            Self.bmiKey: true,
            Self.bodyFatKey: true,
            Self.leanBodyMassKey: true
        ])
        refreshStatus()
    }

    var isAvailable: Bool {
        !isDemo && HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() {
        guard isAvailable else {
            statusText = String(appLocalized: "此设备不支持 Apple 健康")
            return
        }

        let writeTypes = enabledWriteTypes()
        guard !writeTypes.isEmpty else {
            statusText = String(appLocalized: "请至少选择一个同步项目")
            return
        }

        healthStore.requestAuthorization(toShare: writeTypes, read: readableBodyTypes()) { [weak self] success, error in
            guard let manager = self else { return }
            let message = success
                ? String(appLocalized: "已请求 Apple 健康写入权限")
                : (error?.localizedDescription ?? String(appLocalized: "未获得 Apple 健康权限"))
            Task { @MainActor in
                manager.statusText = message
                if success {
                    await manager.restoreMeasurementsFromHealth()
                }
            }
        }
    }

    func requestMeasurementRecovery() {
        guard isAvailable else {
            recoveryStatusText = String(appLocalized: "此设备不支持 Apple 健康")
            return
        }
        healthStore.requestAuthorization(toShare: [], read: readableBodyTypes()) { [weak self] success, error in
            guard let manager = self else { return }
            Task { @MainActor in
                if success {
                    await manager.restoreMeasurementsFromHealth()
                } else {
                    manager.recoveryStatusText = error?.localizedDescription ?? String(appLocalized: "未获得 Apple 健康读取权限")
                }
            }
        }
    }

    func requestDataSourceAccess() {
        guard isAvailable else {
            sourceStatusText = String(appLocalized: "此设备不支持 Apple 健康")
            return
        }

        healthStore.requestAuthorization(toShare: [], read: readableBodyTypes()) { [weak self] success, error in
            guard let manager = self else { return }
            Task { @MainActor in
                if success {
                    manager.refreshDataSources()
                    await manager.refreshTrends()
                } else {
                    manager.sourceStatusText = error?.localizedDescription ?? String(appLocalized: "未获得 Apple 健康读取权限")
                }
            }
        }
    }

    func requestTrendAccess() {
        guard isAvailable else { return }
        healthStore.requestAuthorization(toShare: [], read: readableBodyTypes()) { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                if success { await self.refreshTrends() }
                else { self.trendStatusText = error?.localizedDescription ?? String(appLocalized: "未获得 Apple 健康读取权限") }
            }
        }
    }

    func refreshTrends() async {
        guard isAvailable, !isLoadingTrends else { return }
        isLoadingTrends = true
        defer { isLoadingTrends = false }
        do {
            var points: [HealthTrendSample] = []
            for metric in [HealthBodyMetric.weight, .bodyFat, .bmi] {
                guard let type = HKQuantityType.quantityType(forIdentifier: metric.typeIdentifier) else { continue }
                let samples = try await trendQuantitySamples(for: type)
                for sample in samples {
                    let unit: HKUnit = metric == .weight ? .gramUnit(with: .kilo) : (metric == .bodyFat ? .percent() : .count())
                    let value = sample.quantity.doubleValue(for: unit) * (metric == .bodyFat ? 100 : 1)
                    guard value.isFinite, value > 0 else { continue }
                    let source = sample.sourceRevision.source
                    points.append(HealthTrendSample(id: sample.uuid, date: sample.endDate, metric: metric,
                        value: value, sourceName: source.name, sourceID: source.bundleIdentifier))
                }
            }
            trendSamples = points.sorted { $0.date < $1.date }
            trendStatusText = points.isEmpty ? String(appLocalized: "没有读到记录。请在“健康”中确认已允许本 App 读取身体测量数据。") : ""
        } catch {
            trendStatusText = String(appLocalized: "读取失败：\(error.localizedDescription)")
        }
    }

    private func trendQuantitySamples(for type: HKQuantityType) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type,
                predicate: HKQuery.predicateForSamples(withStart: nil, end: .now, options: .strictEndDate),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]) { _, samples, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: samples as? [HKQuantitySample] ?? []) }
                }
            healthStore.execute(query)
        }
    }

    func refreshDataSources() {
        guard isAvailable, !isScanningSources else { return }

        isScanningSources = true
        sourceStatusText = String(appLocalized: "正在检查最近一年的身体测量记录…")

        Task { [weak self] in
            guard let manager = self else { return }
            do {
                var summaries: [String: HealthDataSourceSummary] = [:]
                var weightSamples: [HealthWeightSampleSummary] = []

                for metric in HealthBodyMetric.allCases {
                    guard let type = HKQuantityType.quantityType(forIdentifier: metric.typeIdentifier) else {
                        continue
                    }
                    let samples = try await manager.recentSamples(for: type)
                    for sample in samples {
                        let source = sample.sourceRevision.source
                        let bundleIdentifier = source.bundleIdentifier
                        let key = bundleIdentifier
                        let currentBundleIdentifier = Bundle.main.bundleIdentifier
                        let providerName = Self.providerName(
                            sourceName: source.name,
                            bundleIdentifier: bundleIdentifier
                        )

                        if metric == .weight {
                            weightSamples.append(HealthWeightSampleSummary(
                                id: sample.uuid,
                                date: sample.endDate,
                                weightKilograms: sample.quantity.doubleValue(
                                    for: .gramUnit(with: .kilo)
                                ),
                                sourceName: source.name,
                                providerName: providerName,
                                bundleIdentifier: bundleIdentifier
                            ))
                        }

                        if var existing = summaries[key] {
                            existing.metrics.insert(metric)
                            existing.latestDate = max(existing.latestDate, sample.endDate)
                            existing.sampleCount += 1
                            summaries[key] = existing
                        } else {
                            summaries[key] = HealthDataSourceSummary(
                                id: key,
                                name: source.name,
                                bundleIdentifier: bundleIdentifier,
                                providerName: providerName,
                                isCurrentApp: bundleIdentifier == currentBundleIdentifier,
                                metrics: [metric],
                                latestDate: sample.endDate,
                                sampleCount: 1
                            )
                        }
                    }
                }

                manager.sourceSummaries = summaries.values.sorted {
                    if $0.isCurrentApp != $1.isCurrentApp {
                        return $0.isCurrentApp
                    }
                        return $0.latestDate > $1.latestDate
                    }
                manager.duplicateWeightGroups = Self.detectDuplicateWeightGroups(in: weightSamples)
                manager.sourceStatusText = manager.sourceSummaries.isEmpty
                    ? String(appLocalized: "没有读到记录。请在“健康”中确认已允许本 App 读取身体测量数据。")
                    : Self.sourceStatus(
                        sourceCount: manager.sourceSummaries.count,
                        duplicateCount: manager.duplicateWeightGroups.count
                    )
            } catch {
                manager.sourceSummaries = []
                manager.duplicateWeightGroups = []
                manager.sourceStatusText = String(appLocalized: "读取失败：\(error.localizedDescription)")
            }
            manager.isScanningSources = false
        }
    }

    func save(_ measurement: BodyMeasurement) {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey), isAvailable else { return }

        let samples = makeSamples(for: measurement)
        guard !samples.isEmpty else {
            statusText = String(appLocalized: "没有选择需要同步的项目")
            return
        }

        let measurementID = measurement.id
        let task = Task { [weak self] in
            guard let manager = self else { return }
            defer { manager.pendingSaveTasks[measurementID] = nil }

            do {
                try await manager.saveSamples(samples)
                let formatter = DateFormatter()
                formatter.dateFormat = "MM-dd HH:mm"
                manager.lastSyncText = String(appLocalized: "最近同步：\(formatter.string(from: measurement.date))")
                manager.statusText = String(appLocalized: "已写入 Apple 健康")
            } catch {
                manager.statusText = error.localizedDescription
            }
        }
        pendingSaveTasks[measurementID] = task
    }

    func delete(_ measurement: BodyMeasurement) async throws -> Int {
        guard !isDemo else { return 0 }
        guard isAvailable else { return 0 }
        if let pendingSaveTask = pendingSaveTasks[measurement.id] {
            await pendingSaveTask.value
        }
        var deletedCount = 0

        for metric in HealthBodyMetric.allCases {
            guard let type = HKQuantityType.quantityType(forIdentifier: metric.typeIdentifier) else {
                continue
            }
            let syncIdentifier = Self.syncIdentifier(
                measurementID: measurement.id,
                metric: metric.syncMetricName
            )
            let predicate = HKQuery.predicateForObjects(
                withMetadataKey: HKMetadataKeySyncIdentifier,
                allowedValues: [syncIdentifier]
            )
            deletedCount += try await deleteObjects(of: type, predicate: predicate)
        }

        statusText = deletedCount > 0
            ? String(appLocalized: "已从 Apple 健康删除 \(deletedCount) 条关联数据")
            : String(appLocalized: "Apple 健康中没有这次测量的关联数据")
        return deletedCount
    }

    func refreshStatus() {
        guard !isDemo else { return }
        guard isAvailable else {
            statusText = String(appLocalized: "此设备不支持 Apple 健康")
            return
        }
        if !UserDefaults.standard.bool(forKey: Self.enabledKey) {
            statusText = String(appLocalized: "同步尚未开启")
            return
        }

        let statuses = enabledWriteTypes().map { healthStore.authorizationStatus(for: $0) }
        if statuses.contains(.sharingDenied) {
            statusText = String(appLocalized: "部分项目未获写入权限")
        } else if !statuses.isEmpty && statuses.allSatisfy({ $0 == .sharingAuthorized }) {
            statusText = String(appLocalized: "已连接 Apple 健康")
        } else {
            statusText = String(appLocalized: "等待 Apple 健康授权")
        }
    }

    private func enabledWriteTypes() -> Set<HKSampleType> {
        var types = Set<HKSampleType>()
        let defaults = UserDefaults.standard

        if defaults.bool(forKey: Self.weightKey),
           let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            types.insert(type)
        }
        if defaults.bool(forKey: Self.bmiKey),
           let type = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex) {
            types.insert(type)
        }
        if defaults.bool(forKey: Self.bodyFatKey),
           let type = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) {
            types.insert(type)
        }
        if defaults.bool(forKey: Self.leanBodyMassKey),
           let type = HKQuantityType.quantityType(forIdentifier: .leanBodyMass) {
            types.insert(type)
        }
        return types
    }

    private func readableBodyTypes() -> Set<HKObjectType> {
        Set(HealthBodyMetric.allCases.compactMap {
            HKQuantityType.quantityType(forIdentifier: $0.typeIdentifier)
        })
    }

    private func recentSamples(for type: HKQuantityType) async throws -> [HKQuantitySample] {
        let startDate = Calendar.current.date(byAdding: .year, value: -1, to: .now)
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: .now,
            options: .strictEndDate
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: sourceSampleLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            healthStore.execute(query)
        }
    }

    private func restoreMeasurementsFromHealth() async {
        guard !isRecoveringMeasurements else { return }
        isRecoveringMeasurements = true
        recoveryStatusText = String(appLocalized: "正在从 Apple 健康恢复本 App 档案…")

        do {
            var recoveredByID: [UUID: BodyMeasurement] = [:]
            for metric in HealthBodyMetric.allCases {
                guard let type = HKQuantityType.quantityType(forIdentifier: metric.typeIdentifier) else {
                    continue
                }
                let samples = try await archivedSamples(for: type)
                for sample in samples {
                    guard sample.sourceRevision.source.bundleIdentifier == Bundle.main.bundleIdentifier,
                          let archive = sample.metadata?[Self.archiveMetadataKey] as? String,
                          let data = archive.data(using: .utf8),
                          let measurement = try? JSONDecoder().decode(BodyMeasurement.self, from: data) else {
                        continue
                    }
                    recoveredByID[measurement.id] = measurement
                }
            }

            let measurements = recoveredByID.values.sorted { $0.date > $1.date }
            let importedCount = onMeasurementsRecovered?(measurements) ?? 0
            if measurements.isEmpty {
                recoveryStatusText = String(appLocalized: "Apple 健康中没有找到可恢复的本 App 完整档案")
            } else if importedCount == 0 {
                recoveryStatusText = String(appLocalized: "本地记录已经完整，无需重复恢复")
            } else {
                recoveryStatusText = String(appLocalized: "已从 Apple 健康恢复 \(importedCount) 条本地记录")
            }
        } catch {
            recoveryStatusText = String(appLocalized: "恢复失败：\(error.localizedDescription)")
        }
        isRecoveringMeasurements = false
    }

    private func archivedSamples(for type: HKQuantityType) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: Self.archiveMetadataKey)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            healthStore.execute(query)
        }
    }

    private func deleteObjects(
        of type: HKObjectType,
        predicate: NSPredicate
    ) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            healthStore.deleteObjects(of: type, predicate: predicate) { success, count, error in
                if success {
                    continuation.resume(returning: count)
                } else {
                    continuation.resume(
                        throwing: error ?? HealthArchiveError.deletionFailed
                    )
                }
            }
        }
    }

    private func saveSamples(_ samples: [HKSample]) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(samples) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: error ?? HealthArchiveError.saveFailed
                    )
                }
            }
        }
    }

    private static func providerName(sourceName: String, bundleIdentifier: String) -> String {
        let value = "\(sourceName) \(bundleIdentifier)".lowercased()
        let providers: [(needles: [String], name: String)] = [
            (["huawei"], String(appLocalized: "华为")),
            (["xiaomi", "mijia", "mi home"], String(appLocalized: "小米")),
            (["withings", "health mate"], "Withings"),
            (["garmin"], "Garmin"),
            (["renpho"], "RENPHO"),
            (["eufy"], "Eufy"),
            (["inbody"], "InBody"),
            (["omron"], String(appLocalized: "欧姆龙")),
            (["fitbit", "google health"], "Fitbit / Google"),
            (["fitdays"], "Fitdays"),
            (["okok"], "OKOK"),
            (["feelfit"], "Feelfit"),
            (["ailink"], "AiLink")
        ]

        return providers.first(where: { provider in
            provider.needles.contains(where: value.contains)
        })?.name ?? sourceName
    }

    private static func detectDuplicateWeightGroups(
        in samples: [HealthWeightSampleSummary]
    ) -> [HealthDuplicateWeightGroup] {
        let sortedSamples = samples.sorted { $0.date > $1.date }
        var consumedSampleIDs = Set<UUID>()
        var groups: [HealthDuplicateWeightGroup] = []

        for anchor in sortedSamples {
            guard !consumedSampleIDs.contains(anchor.id) else { continue }

            let matchingSamples = sortedSamples.filter { candidate in
                guard !consumedSampleIDs.contains(candidate.id) else { return false }
                let timeDifference = abs(candidate.date.timeIntervalSince(anchor.date))
                let weightDifference = abs(candidate.weightKilograms - anchor.weightKilograms)
                return timeDifference <= duplicateTimeWindow
                    && weightDifference <= duplicateWeightToleranceKilograms
            }

            let distinctSources = Set(matchingSamples.map(\.bundleIdentifier))
            guard matchingSamples.count > 1, distinctSources.count > 1 else { continue }

            matchingSamples.forEach { consumedSampleIDs.insert($0.id) }
            groups.append(HealthDuplicateWeightGroup(
                id: anchor.id,
                samples: matchingSamples.sorted { $0.date < $1.date }
            ))
        }

        return groups.sorted { $0.date > $1.date }
    }

    private static func sourceStatus(sourceCount: Int, duplicateCount: Int) -> String {
        guard duplicateCount > 0 else {
            return String(appLocalized: "发现 \(sourceCount) 个数据来源，未发现明显重复")
        }
        return String(appLocalized: "发现 \(sourceCount) 个数据来源，\(duplicateCount) 组可能重复")
    }

    private func makeSamples(for measurement: BodyMeasurement) -> [HKQuantitySample] {
        let defaults = UserDefaults.standard
        var samples: [HKQuantitySample] = []

        if defaults.bool(forKey: Self.weightKey),
           let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            samples.append(sample(
                type: type,
                unit: .gramUnit(with: .kilo),
                value: measurement.weight,
                measurement: measurement,
                metadata: metadata(for: measurement, metric: "weight")
            ))
        }

        if defaults.bool(forKey: Self.bmiKey),
           let type = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex) {
            samples.append(sample(
                type: type,
                unit: .count(),
                value: measurement.bmi,
                measurement: measurement,
                metadata: metadata(for: measurement, metric: "bmi")
            ))
        }

        if defaults.bool(forKey: Self.bodyFatKey),
           let type = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) {
            samples.append(sample(
                type: type,
                unit: .percent(),
                value: measurement.bodyFat / 100.0,
                measurement: measurement,
                metadata: metadata(for: measurement, metric: "body-fat")
            ))
        }

        if defaults.bool(forKey: Self.leanBodyMassKey),
           let type = HKQuantityType.quantityType(forIdentifier: .leanBodyMass) {
            let leanBodyMass = measurement.weight * (1.0 - measurement.bodyFat / 100.0)
            samples.append(sample(
                type: type,
                unit: .gramUnit(with: .kilo),
                value: leanBodyMass,
                measurement: measurement,
                metadata: metadata(for: measurement, metric: "lean-body-mass")
            ))
        }

        return samples
    }

    private func metadata(for measurement: BodyMeasurement, metric: String) -> [String: Any] {
        let algorithm = (100.0...1500.0).contains(measurement.impedance)
            ? "segal_1988_v1"
            : "deurenberg_bmi_fallback_v1"
        var metadata: [String: Any] = [
            HKMetadataKeySyncIdentifier: Self.syncIdentifier(
                measurementID: measurement.id,
                metric: metric
            ),
            HKMetadataKeySyncVersion: 1,
            "xuanlprk.bodyAlgorithm": algorithm,
            "xuanlprk.impedanceOhm": measurement.impedance
        ]
        if let archiveData = try? JSONEncoder().encode(measurement),
           let archive = String(data: archiveData, encoding: .utf8) {
            metadata[Self.archiveMetadataKey] = archive
        }
        if let adcIndex = measurement.adcIndex {
            metadata["xuanlprk.adcNumber"] = adcIndex + 1
        }
        return metadata
    }

    private static func syncIdentifier(measurementID: UUID, metric: String) -> String {
        "afu-scale-\(measurementID.uuidString)-\(metric)"
    }

    private func sample(
        type: HKQuantityType,
        unit: HKUnit,
        value: Double,
        measurement: BodyMeasurement,
        metadata: [String: Any]
    ) -> HKQuantitySample {
        HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: unit, doubleValue: value),
            start: measurement.date,
            end: measurement.date,
            metadata: metadata
        )
    }
}

private extension HealthBodyMetric {
    var syncMetricName: String {
        switch self {
        case .weight: "weight"
        case .bmi: "bmi"
        case .bodyFat: "body-fat"
        case .leanBodyMass: "lean-body-mass"
        }
    }
}

private enum HealthArchiveError: LocalizedError {
    case saveFailed
    case deletionFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed:
            String(appLocalized: "写入 Apple 健康失败")
        case .deletionFailed:
            String(appLocalized: "Apple 健康未能删除关联数据")
        }
    }
}
