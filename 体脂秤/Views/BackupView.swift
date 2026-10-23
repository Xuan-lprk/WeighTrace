import SwiftUI
import UniformTypeIdentifiers

struct BackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw BackupError.invalid }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct BackupView: View {
    @EnvironmentObject private var scale: ScaleManager
    @EnvironmentObject private var profile: UserProfile
    @EnvironmentObject private var comparisons: ComparisonStore
    @State private var document: BackupFile?
    @State private var exportType = UTType.json
    @State private var exportName = "AFU-Backup"
    @State private var exporting = false
    @State private var importing = false
    @State private var incoming: MeasurementBackup?
    @State private var replaceConflicts = false
    @State private var status: String?

    private var snapshot: MeasurementBackup {
        MeasurementBackup(primary: profile.primaryMember, members: profile.members,
                          measurements: scale.history, references: comparisons.references)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("测量记录", value: "\(scale.history.count)")
                LabeledContent("家庭成员", value: "\(profile.members.count)")
                LabeledContent("阿福参考", value: "\(comparisons.references.count)")
                Button("导出完整备份（JSON）") { export(csv: false) }
                Button("导出分析表（CSV）") { export(csv: true) }
            } header: { Text("导出数据") } footer: {
                Text("JSON 包含资料、测量、双 ADC、算法快照与阿福参考，可用于恢复。CSV 用于分析，不能用于完整恢复。文件包含健康资料，请保存到你信任的位置。")
            }
            Section {
                Button("选择 JSON 备份") { importing = true }
            } header: { Text("导入备份") } footer: {
                Text("可以从“文件”或 iCloud Drive 选择备份。导入不恢复蓝牙绑定和健康权限，也不会向 Apple 健康写入数据。本人资料使用固定身份，请只导入属于你自己的备份。")
            }
            if let incoming {
                Section {
                    Text(incoming.exportedAt, format: .dateTime.year().month().day().hour().minute())
                        .foregroundStyle(.secondary)
                    ForEach(incoming.preview(against: snapshot)) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title).font(.headline)
                            Text("新增 \(row.added) · 重复 \(row.identical) · 冲突 \(row.conflicts)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    DisclosureGroup("查看冲突明细") {
                        ForEach(incoming.conflictDetails(against: snapshot)) { conflict in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(conflict.title).font(.caption.bold())
                                Text("本机：\(conflict.local)").font(.caption)
                                Text("备份：\(conflict.incoming)").font(.caption)
                            }.textSelection(.enabled)
                        }
                        Text("摘要只显示主要字段；其他原始字段或快照不同也会计为冲突。覆盖前建议先导出本机 JSON 备份。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("使用备份覆盖冲突（包括本人资料）", isOn: $replaceConflicts)
                    Text(replaceConflicts
                         ? String(localized: "相同 UUID 或同次测量的参考冲突时，采用备份内容。")
                         : String(localized: "默认保留本机冲突内容，只新增缺少的记录。"))
                        .font(.caption).foregroundStyle(.secondary)
                    Button("确认合并到本机") { restore(incoming) }
                    Button("取消导入", role: .cancel) { self.incoming = nil }
                } header: { Text("导入预览") }
            }
        }
        .navigationTitle("备份与导出")
        .fileExporter(isPresented: $exporting, document: document, contentType: exportType,
                      defaultFilename: exportName) { result in
            switch result {
            case .success: status = String(localized: "文件已导出")
            case .failure(let error): status = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 50_000_000 else { throw BackupError.invalid }
                incoming = try MeasurementBackup.decode(Data(contentsOf: url))
                replaceConflicts = false
            } catch { status = error.localizedDescription }
        }
        .alert("数据操作", isPresented: Binding(get: { status != nil }, set: { if !$0 { status = nil } })) {
            Button("知道了", role: .cancel) { status = nil }
        } message: { Text(status ?? "") }
    }

    private func export(csv: Bool) {
        do {
            let data = csv ? Data(snapshot.csv().utf8) : try snapshot.encoded()
            document = BackupFile(data: data)
            exportType = csv ? .commaSeparatedText : .json
            exportName = (csv ? "AFU-Measurements-" : "AFU-Backup-") + ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            exporting = true
        } catch { status = error.localizedDescription }
    }

    private func restore(_ backup: MeasurementBackup) {
        do {
            let merged = snapshot.merged(with: backup, replaceConflicts: replaceConflicts)
            try merged.validate()
            // Preflight encoding of all collections before mutating any live store.
            _ = try merged.encoded()
            scale.restoreBackup(merged.measurements)
            comparisons.restoreBackup(merged.references)
            profile.restoreBackup(primary: merged.primary, family: merged.members)
            incoming = nil
            status = String(localized: "合并完成，重复导入不会增加同一条记录。Apple 健康未被修改。")
        } catch { status = error.localizedDescription }
    }
}
