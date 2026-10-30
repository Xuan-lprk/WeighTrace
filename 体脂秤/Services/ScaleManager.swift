import SwiftUI
import Foundation
@preconcurrency import CoreBluetooth
import Combine

struct DiscoveredScale: Identifiable { let peripheral: CBPeripheral; let name: String; let identifier: String; let rssi: Int; var id: UUID { peripheral.identifier } }

enum ConnectionState: Equatable { case bluetoothOff, idle, scanning, connecting, connected, measuring
    var title: String { switch self { case .bluetoothOff: String(appLocalized: "蓝牙未开启"); case .idle: String(appLocalized: "等待连接"); case .scanning: String(appLocalized: "正在搜索体脂秤"); case .connecting: String(appLocalized: "正在连接"); case .connected: String(appLocalized: "已连接，等待上秤"); case .measuring: String(appLocalized: "正在测量") } }
    var icon: String { self == .bluetoothOff ? "bluetooth.slash" : "dot.radiowaves.left.and.right" }
    var color: Color { self == .bluetoothOff ? .red : (self == .connected || self == .measuring ? .green : .orange) }
}

@MainActor final class ScaleManager: NSObject, ObservableObject {
    private let defaults: UserDefaults
    let isDemo: Bool
    private var isSuspendedForDemo = false
    private var resumeScanAfterDemo = false

    func suspendForDemo() {
        resumeScanAfterDemo = isScanning || activePeripheral != nil
        isSuspendedForDemo = true
        central?.stopScan()
        isScanning = false
        if let activePeripheral { central?.cancelPeripheralConnection(activePeripheral) }
    }

    func resumeAfterDemo() {
        isSuspendedForDemo = false
        if resumeScanAfterDemo { startScan() }
        resumeScanAfterDemo = false
    }

    func loadDemoMeasurements(_ records: [BodyMeasurement]) {
        guard isDemo else { return }
        history = records.sorted { $0.date > $1.date }
        currentMeasurement = history.first
        liveWeight = currentMeasurement?.weight ?? 0
        rawADCs = currentMeasurement?.rawADCs ?? []
        normalizedImpedances = currentMeasurement?.normalizedImpedances ?? []
        impedance = currentMeasurement?.impedance ?? 0
        selectedADCIndex = 0
        isStable = true
        deviceName = "AFU-WL-TZ-A1 · DEMO"
        connectionState = .connected
    }
    private static let pairedPeripheralIDKey = "afu.pairedPeripheralID"
    private let serviceUUID = CBUUID(string: "0000FFB0-0000-1000-8000-00805F9B34FB")
    private var central: CBCentralManager!
    private var activePeripheral: CBPeripheral?
    weak var profile: UserProfile?
    weak var healthKit: HealthKitManager?
    weak var comparisonStore: ComparisonStore?
    @Published var connectionState: ConnectionState = .idle
    @Published var discoveredDevices: [DiscoveredScale] = []
    @Published var liveWeight = 0.0
    @Published var impedance = 0.0
    @Published var selectedADCIndex: Int?
    @Published private(set) var rawADCs: [Double] = []
    @Published private(set) var normalizedImpedances: [Double] = []
    @Published var currentMeasurement: BodyMeasurement?
    @Published var reviewMeasurement: BodyMeasurement?
    @Published var history: [BodyMeasurement] = []
    @Published var deviceName: String?
    @Published var isScanning = false
    @Published var isMeasuring = false
    @Published var isStable = false
    @Published var unrecognizedWeight: Double?
    @Published var debugLogs: [String] = []
    private var hasSavedMeasurement = false
    @Published private(set) var repeatCapture: RepeatabilityCapture?
    @Published private(set) var repeatReports: [RepeatabilityReport] = []
    @Published private(set) var weighedSubjects: [WeighedSubject] = []
    @Published private(set) var assistedRecords: [AssistedWeightRecord] = []
    @Published private(set) var assistedCapture: AssistedWeighingCapture?

    func addWeighedSubject(name: String, kind: WeighedSubjectKind) {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !name.isEmpty else { return }
        weighedSubjects.append(WeighedSubject(id: UUID(), name: name, kind: kind))
        saveAssistedData()
    }
    func startAssistedWeighing(subject: WeighedSubject) {
        guard repeatCapture == nil, assistedCapture == nil, activePeripheral?.state == .connected else { return }
        assistedCapture = AssistedWeighingCapture(subject: subject)
        reviewMeasurement = nil; currentMeasurement = nil
    }
    func endAssistedWeighing() {
        assistedCapture = nil
        hasSavedMeasurement = true; isStable = false
        impedance = 0; rawADCs = []; normalizedImpedances = []; selectedADCIndex = nil
    }
    func deleteAssistedRecord(id: UUID) {
        if assistedCapture?.result?.id == id { endAssistedWeighing() }
        assistedRecords.removeAll { $0.id == id }; saveAssistedData()
    }
    func restoreAssistedData(subjects: [WeighedSubject], records: [AssistedWeightRecord]) {
        weighedSubjects = subjects; assistedRecords = records.sorted { $0.date > $1.date }; saveAssistedData()
    }
    private func saveAssistedData() {
        if let data = try? JSONEncoder().encode(weighedSubjects) { defaults.set(data, forKey: "afu.assisted.subjects") }
        if let data = try? JSONEncoder().encode(assistedRecords) { defaults.set(data, forKey: "afu.assisted.records") }
    }

    func startRepeatCheck(member: FamilyMember) {
        guard assistedCapture == nil, repeatCapture == nil else { return }
        repeatCapture = RepeatabilityCapture(member: member)
        reviewMeasurement = nil
        currentMeasurement = nil
    }
    func endRepeatCheck() {
        repeatCapture = nil
        // Require a fresh step-off after experiments before normal saving resumes.
        hasSavedMeasurement = true
        impedance = 0; rawADCs = []; normalizedImpedances = []; selectedADCIndex = nil
        isStable = false
    }
    func confirmRepeatStepOff() {
        repeatCapture?.confirmStepOff()
    }
    func removeRepeatReport(id: UUID) {
        repeatReports.removeAll { $0.id == id }; saveRepeatReports()
    }
    func restoreRepeatReports(_ reports: [RepeatabilityReport]) {
        repeatReports = reports.sorted { $0.date > $1.date }; saveRepeatReports()
    }
    private func saveRepeatReports() {
        if let data = try? JSONEncoder().encode(repeatReports) {
            defaults.set(data, forKey: "afu.repeatability.reports")
        }
    }
    private func collectRepeatCheck() {
        guard var capture = repeatCapture, capture.captureIfReady() else { return }
        repeatCapture = capture
        if capture.measurements.count == 3 {
            let report = RepeatabilityReport(id: UUID(), date: Date(), measurements: capture.measurements)
            repeatReports.insert(report, at: 0); saveRepeatReports()
            // Keep the completed capture active until the user explicitly exits experiment mode.
        }
    }
    func updateAnnotation(id: UUID, tags: [String], note: String) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        history[index].tags = Array(Set(tags)).sorted()
        history[index].note = String(note.prefix(500))
        if currentMeasurement?.id == id { currentMeasurement = history[index] }
        if reviewMeasurement?.id == id { reviewMeasurement = history[index] }
        saveHistory()
    }

    func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        debugLogs.insert("[\(timestamp)] \(message)", at: 0)
        if debugLogs.count > 100 {
            debugLogs.removeLast()
        }
        print("[ScaleManager] \(message)")
    }
    
    func clearDebugLogs() {
        debugLogs = []
    }

    init(defaults: UserDefaults = .standard, isDemo: Bool = false) {
        self.defaults = defaults
        self.isDemo = isDemo
        super.init()
        if !isDemo { central = CBCentralManager(delegate: self, queue: .main) }
        loadHistory()
        if let data = defaults.data(forKey: "afu.repeatability.reports"),
           let reports = try? JSONDecoder().decode([RepeatabilityReport].self, from: data) { repeatReports = reports }
        if let data = defaults.data(forKey: "afu.assisted.subjects"),
           let subjects = try? JSONDecoder().decode([WeighedSubject].self, from: data) { weighedSubjects = subjects }
        if let data = defaults.data(forKey: "afu.assisted.records"),
           let records = try? JSONDecoder().decode([AssistedWeightRecord].self, from: data) { assistedRecords = records }
        log("ScaleManager initialized")
    }
    func startScan() {
        guard !isDemo, !isSuspendedForDemo else { return }
        if activePeripheral?.state == .connected {
            isScanning = false
            connectionState = isMeasuring ? .measuring : .connected
            return
        }
        if activePeripheral?.state == .connecting { return }
        discoveredDevices = []
        isScanning = true
        guard central.state == .poweredOn else {
            if central.state == .unknown {
                connectionState = .scanning
            } else {
                connectionState = .bluetoothOff
            }
            return
        }
        connectionState = .scanning
        // 与 CLI/Bleak 一致：先接收全部广播，再在 didDiscover 中解析并筛选。
        // 这台秤的 0xAC 协议数据可能放在 0x27AC Service Data 中；
        // 若只按 FFB0 服务扫描，部分 iOS/iPadOS 设备可能收不到完整广播。
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }
    func connect(_ device: DiscoveredScale) {
        guard !isDemo, !isSuspendedForDemo else { return }
        guard connectionState != .connecting, activePeripheral == nil else { return }
        central.stopScan()
        isScanning = false
        connectionState = .connecting
        activePeripheral = device.peripheral
        deviceName = device.name
        central.connect(device.peripheral)
    }
    func forgetPairedScale() {
        guard !isDemo else { return }
        defaults.set(false, forKey: "afu.hasPairedScale")
        defaults.removeObject(forKey: Self.pairedPeripheralIDKey)
        if let activePeripheral {
            central.cancelPeripheralConnection(activePeripheral)
        } else {
            connectionState = .idle
        }
        deviceName = nil
        discoveredDevices = []
    }
    private func finishMeasurement() {
        guard repeatCapture == nil, assistedCapture == nil else { return }
        guard liveWeight > 0, let profile, profile.isComplete else { return }
        guard !hasSavedMeasurement else { return }
        hasSavedMeasurement = true
        let isNewMember = profile.shouldSuggestNewMember(for: liveWeight, history: history)
        let member = profile.matchedMember(for: liveWeight, history: history)
        let measurement = BodyAlgorithm.measure(
            weight: liveWeight,
            impedance: impedance,
            member: member,
            adcIndex: selectedADCIndex,
            rawADCs: rawADCs,
            normalizedImpedances: normalizedImpedances
        )
        currentMeasurement = measurement
        reviewMeasurement = measurement
        history.insert(measurement, at: 0)
        if isNewMember && unrecognizedWeight == nil { unrecognizedWeight = liveWeight }
        saveHistory()
        let isPrimaryMember = member.id == profile.primaryMember.id
        if isPrimaryMember && (!isNewMember || profile.members.isEmpty) {
            healthKit?.save(measurement)
        }
        log("[BLE] Stored stable measurement: weight=\(liveWeight) kg, impedance=\(impedance) Ohm")
    }
    func dismissReview(for measurementID: UUID) {
        if reviewMeasurement?.id == measurementID {
            reviewMeasurement = nil
        }
    }
    func deleteMeasurement(_ measurement: BodyMeasurement) async -> String? {
        do {
            _ = try await healthKit?.delete(measurement)
        } catch {
            log("[HealthKit] Failed to delete measurement \(measurement.id): \(error.localizedDescription)")
            return String(appLocalized: "Apple 健康删除失败：\(error.localizedDescription)。本地记录仍保留，避免留下无法追踪的健康数据。")
        }

        history.removeAll { $0.id == measurement.id }
        if currentMeasurement?.id == measurement.id {
            currentMeasurement = nil
        }
        if reviewMeasurement?.id == measurement.id {
            reviewMeasurement = nil
        }
        comparisonStore?.removeReferences(for: measurement.id)
        saveHistory()
        log("[History] Deleted local measurement and linked HealthKit samples: \(measurement.id)")
        return nil
    }
    @discardableResult
    func mergeRestoredHistory(_ measurements: [BodyMeasurement]) -> Int {
        let existingIDs = Set(history.map(\.id))
        let additions = measurements.filter { !existingIDs.contains($0.id) }
        guard !additions.isEmpty else { return 0 }
        history.append(contentsOf: additions)
        history.sort { $0.date > $1.date }
        saveHistory()
        log("[History] Restored \(additions.count) measurements from HealthKit archive")
        return additions.count
    }
    func clearUnrecognizedWeight() { unrecognizedWeight = nil }
    // File restores are local only: never call HealthKit.save or open a measurement review.
    func restoreBackup(_ records: [BodyMeasurement]) {
        history = records.sorted { $0.date > $1.date }
        if let currentMeasurement, let restored = history.first(where: { $0.id == currentMeasurement.id }) {
            self.currentMeasurement = restored
        }
        saveHistory()
    }
    func assignUnrecognizedMeasurement(to member: FamilyMember) {
        guard let measurement = currentMeasurement, let index = history.firstIndex(where: { $0.id == measurement.id }) else { return }
        var updated = BodyAlgorithm.measure(
            id: measurement.id,
            date: measurement.date,
            weight: measurement.weight,
            impedance: measurement.impedance,
            member: member,
            adcIndex: measurement.adcIndex,
            rawADCs: measurement.rawADCs,
            normalizedImpedances: measurement.normalizedImpedances
        )
        updated.tags = measurement.tags; updated.note = measurement.note
        currentMeasurement = updated; history[index] = updated; saveHistory()
    }
    private func saveHistory() { if let data = try? JSONEncoder().encode(history) { defaults.set(data, forKey: "afu.scale.history") } }
    private func loadHistory() { if let data = defaults.data(forKey: "afu.scale.history"), let saved = try? JSONDecoder().decode([BodyMeasurement].self, from: data) { history = saved } }
}

extension ScaleManager: @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("[BLE] Central manager state updated: \(central.state.rawValue)")
        if central.state == .poweredOn {
            if isScanning {
                connectionState = .scanning
                central.scanForPeripherals(
                    withServices: nil,
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
                )
            } else {
                connectionState = .idle
            }
        } else {
            connectionState = .bluetoothOff
            isScanning = false
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? String(appLocalized: "未知设备")
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
        let afuData = Self.afuAdvertisementData(
            manufacturerData: manufacturerData,
            serviceData: serviceData
        )
        let isAFU = afuData != nil
        let matchesPrefix = name.uppercased().hasPrefix("AFU-WL")
        
        guard matchesPrefix, isAFU else { return }

        log("[BLE] Discovered supported scale: \(name) (\(peripheral.identifier.uuidString)), RSSI: \(RSSI), serviceData: \(serviceData?.keys.map(\.uuidString) ?? [])")
        
        let discoveredMac = Self.macAddress(from: afuData)
        log("[BLE] Discovered scale MAC: \(discoveredMac ?? "nil")")
        
        // QR Scanner auto-connection removed
        
        let pairedID = defaults.string(forKey: Self.pairedPeripheralIDKey)
        let isLegacyPairing = defaults.bool(forKey: "afu.hasPairedScale") && pairedID == nil
        let isKnownPeripheral = pairedID == peripheral.identifier.uuidString
        if isLegacyPairing || isKnownPeripheral {
            log("[BLE] Auto-connecting to paired scale: \(name)")
            connect(DiscoveredScale(peripheral: peripheral, name: name, identifier: peripheral.identifier.uuidString, rssi: RSSI.intValue))
            return
        }
        
        if !discoveredDevices.contains(where: { $0.id == peripheral.identifier }) {
            log("[BLE] Adding device to list: \(name)")
            discoveredDevices.append(DiscoveredScale(peripheral: peripheral, name: name, identifier: peripheral.identifier.uuidString, rssi: RSSI.intValue))
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard !isSuspendedForDemo else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        log("[BLE] Connected to: \(peripheral.name ?? "nil") (\(peripheral.identifier.uuidString))")
        deviceName = peripheral.name ?? deviceName
        defaults.set(true, forKey: "afu.hasPairedScale")
        defaults.set(peripheral.identifier.uuidString, forKey: Self.pairedPeripheralIDKey)
        connectionState = .connected
        peripheral.delegate = self
        // targetMacAddress reset removed
        log("[BLE] Discovering services for: \(serviceUUID)")
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("[BLE] Failed to connect to \(peripheral.name ?? "nil"), error: \(String(describing: error))")
        activePeripheral = nil
        connectionState = .idle
        if defaults.bool(forKey: "afu.hasPairedScale") {
            startScan()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("[BLE] Disconnected from: \(peripheral.name ?? "nil"), error: \(String(describing: error))")
        connectionState = .idle
        activePeripheral = nil
        liveWeight = 0.0
        impedance = 0.0
        selectedADCIndex = nil
        rawADCs = []
        normalizedImpedances = []
        isStable = false
        isMeasuring = false
        hasSavedMeasurement = false
        repeatCapture?.disconnect()
        assistedCapture?.disconnect()
        if defaults.bool(forKey: "afu.hasPairedScale") {
            log("[BLE] Restarting scan after disconnection...")
            startScan()
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            log("[BLE] Service discovery error: \(error.localizedDescription)")
            return
        }
        guard let services = peripheral.services else {
            log("[BLE] No services discovered")
            return
        }
        log("[BLE] Discovered \(services.count) services: \(services.map { $0.uuid.uuidString })")
        services.forEach { service in
            log("[BLE] Discovering characteristics for service: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            log("[BLE] Characteristics discovery error: \(error.localizedDescription)")
            return
        }
        guard let characteristics = service.characteristics else {
            log("[BLE] No characteristics discovered for service: \(service.uuid)")
            return
        }
        log("[BLE] Discovered \(characteristics.count) characteristics for service \(service.uuid): \(characteristics.map { "\($0.uuid.uuidString) (prop: \($0.properties.rawValue))" })")
        
        characteristics.filter { $0.properties.contains(.notify) || $0.properties.contains(.indicate) }.forEach { characteristic in
            log("[BLE] Subscribing to notifications for characteristic: \(characteristic.uuid)")
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard !isSuspendedForDemo else { return }
        if let error = error {
            log("[BLE] Error updating value for characteristic \(characteristic.uuid): \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else {
            log("[BLE] Characteristic \(characteristic.uuid) value is empty")
            return
        }
        let hexString = data.map { String(format: "%02hhX", $0) }.joined(separator: " ")
        log("[BLE] Received raw data on \(characteristic.uuid): [\(hexString)] (\(data.count) bytes)")
        
        receive(data)
    }
    
    private static func afuAdvertisementData(
        manufacturerData: Data?,
        serviceData: [CBUUID: Data]?
    ) -> Data? {
        var candidates: [Data] = []

        if let manufacturerData {
            candidates.append(manufacturerData)
        }

        for (uuid, payload) in serviceData ?? [:] {
            guard let uuid16 = uuid16(from: uuid), String(format: "%04X", uuid16).contains("AC") else {
                continue
            }
            var reconstructed = Data([
                UInt8(uuid16 & 0x00FF),
                UInt8((uuid16 >> 8) & 0x00FF)
            ])
            reconstructed.append(payload)
            candidates.append(reconstructed)
        }

        // 与 CLI 相同：0x27 的 flags 表示连接型、体脂秤 category=2、subtype=7。
        return candidates.first { data in
            guard data.count >= 2, data[0] == 0xAC else { return false }
            let flags = data[1]
            let category = (flags & 0x70) >> 4
            let subtype = flags & 0x0F
            return category == 2 && subtype == 7
        }
    }

    private static func uuid16(from uuid: CBUUID) -> UInt16? {
        let value = uuid.uuidString.uppercased()
        let shortValue: String
        if value.count == 4 {
            shortValue = value
        } else if value.hasPrefix("0000"), value.hasSuffix("-0000-1000-8000-00805F9B34FB") {
            shortValue = String(value.dropFirst(4).prefix(4))
        } else {
            return nil
        }
        return UInt16(shortValue, radix: 16)
    }
    
    private static func macAddress(from advertisementData: Data?) -> String? {
        guard let advertisementData, advertisementData.count >= 8, advertisementData[0] == 0xAC else { return nil }
        let macBytes = advertisementData[2..<8].reversed()
        return macBytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
    
    private func receive(_ data: Data) {
        guard let packet = AFUPacket(data: data) else {
            let hexString = data.map { String(format: "%02hhX", $0) }.joined(separator: " ")
            log("[BLE] Failed to parse raw data packet: [\(hexString)]")
            return
        }
        log("[BLE] Successfully parsed packet of type: \(packet.type)")
        switch packet.type {
        case .weight:
            if var capture = assistedCapture {
                if let record = capture.receiveWeight(packet.weight, stable: packet.stable) {
                    assistedRecords.insert(record, at: 0); saveAssistedData()
                }
                assistedCapture = capture
            }
            repeatCapture?.receiveWeight(packet.weight, stable: packet.stable)
            collectRepeatCheck()
            let wasMeasuring = isMeasuring
            liveWeight = packet.weight
            isStable = packet.stable
            isMeasuring = !packet.stable
            connectionState = packet.stable ? .connected : .measuring
            log("[BLE] Weight packet - liveWeight: \(liveWeight), stable: \(isStable)")
            
            if liveWeight < 1.0 || (!wasMeasuring && isMeasuring && !hasSavedMeasurement) {
                impedance = 0
                selectedADCIndex = nil
                rawADCs = []
                normalizedImpedances = []
            }
            // 稳定包之后的短暂波动仍属于同一次上秤；只有离秤才解锁下一条记录。
            if liveWeight < 1.0 {
                hasSavedMeasurement = false
            }
            if isMeasuring && liveWeight > 3.0 {
                currentMeasurement = nil
            }
            
            if packet.stable && impedance > 0 { finishMeasurement() }
        case .impedance:
            let packetWeight = packet.adcWeight > 0 ? packet.adcWeight : liveWeight
            let normalized = AFUPacket.normalizeImpedances(packet.adcs, weight: packetWeight)
            repeatCapture?.receiveADCs(raw: packet.adcs, impedances: normalized, packetWeight: packet.adcWeight)
            collectRepeatCheck()
            rawADCs = packet.adcs
            normalizedImpedances = normalized
            let preferredIndex = defaults.integer(forKey: ImpedanceADCChoice.storageKey)
            let preferredValue = normalized.indices.contains(preferredIndex) ? normalized[preferredIndex] : nil
            if let preferredValue, (100.0...1500.0).contains(preferredValue) {
                impedance = preferredValue
                selectedADCIndex = preferredIndex
            } else if let fallback = normalized.enumerated().first(where: { (100.0...1500.0).contains($0.element) }) {
                impedance = fallback.element
                selectedADCIndex = fallback.offset
            } else {
                impedance = 0
                selectedADCIndex = nil
            }
            let selectedLabel = selectedADCIndex.map { "ADC \($0 + 1)" } ?? "none"
            log("[BLE] Impedance packet - raw ADCs: \(packet.adcs), normalized: \(normalized), selected: \(selectedLabel) = \(impedance)")
            if isStable { finishMeasurement() }
        case .history:
            guard repeatCapture == nil, assistedCapture == nil else { return }
            if let item = packet.historyMeasurement(profile: profile, history: history) {
                history.insert(item, at: 0)
                saveHistory()
                log("[BLE] History packet - added measurement: \(item)")
            } else {
                log("[BLE] History packet - failed to build history measurement")
            }
        case .settings:
            log("[BLE] Settings packet - ignored")
            break
        }
    }
}
