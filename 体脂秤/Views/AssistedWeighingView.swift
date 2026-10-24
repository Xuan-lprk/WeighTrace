import SwiftUI
import Charts

struct AssistedWeighingView: View {
    @EnvironmentObject private var scale: ScaleManager
    @State private var selectedID: UUID?
    @State private var adding = false
    @State private var name = ""
    @State private var kind = WeighedSubjectKind.pet
    private var subject: WeighedSubject? { scale.weighedSubjects.first { $0.id == selectedID } }
    private var records: [AssistedWeightRecord] { scale.assistedRecords.filter { $0.subjectID == selectedID }.sorted { $0.date > $1.date } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                if let capture = scale.assistedCapture {
                    captureCard(capture)
                } else {
                    HStack {
                        Picker("称重对象", selection: $selectedID) {
                            Text("请选择").tag(Optional<UUID>.none)
                            ForEach(scale.weighedSubjects) { item in Text(item.name).tag(Optional(item.id)) }
                        }
                        Button { name = ""; adding = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                            .accessibilityLabel(Text("新建称重对象"))
                    }
                    Button { if let subject { scale.startAssistedWeighing(subject: subject) } } label: {
                        Label("开始两步称重", systemImage: "scalemass.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
                    }.buttonStyle(.borderedProminent).tint(.teal)
                        .disabled(subject == nil || scale.repeatCapture != nil || scale.connectionState != .connected || scale.reviewMeasurement != nil)
                    Text("请先连接体脂秤并离秤，再开始。保持衣物和随身物品一致，不超过秤的额定承重；宠物不配合时请停止。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let subject {
                    HStack {
                        Label(subject.name, systemImage: subject.kind.icon).font(.headline)
                        Spacer()
                        Text("\(records.count) 次记录").font(.caption).foregroundStyle(.secondary)
                    }
                    if records.count >= 2 {
                        Chart(records.sorted { $0.date < $1.date }) { record in
                            LineMark(x: .value("日期", record.date), y: .value("重量", record.weight))
                                .foregroundStyle(.teal).symbol(.circle)
                        }.chartYScale(domain: .automatic(includesZero: false)).frame(height: 170)
                    }
                    ForEach(records) { record in
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(record.date, format: .dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                Text("约 \(record.weight, specifier: "%.2f") kg").font(.title3.bold())
                            }
                            Spacer()
                            Button(role: .destructive) { scale.deleteAssistedRecord(id: record.id) } label: { Image(systemName: "trash") }
                                .accessibilityLabel(Text("删除这次抱物记录"))
                        }.padding().background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                Text("两次测量误差会叠加，结果仅作粗略重量参考。对象档案独立保存并包含在 JSON 备份中，不进入身体趋势或 Apple 健康。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding().frame(maxWidth: 850).frame(maxWidth: .infinity)
        }
        .navigationTitle("抱物称重")
        .onAppear { if selectedID == nil { selectedID = scale.assistedCapture?.subject.id ?? scale.weighedSubjects.first?.id } }
        .sheet(isPresented: $adding) {
            NavigationStack {
                Form {
                    TextField("例如：猫猫、出差行李", text: $name)
                        .onChange(of: name) { _, value in if value.count > 40 { name = String(value.prefix(40)) } }
                    Picker("类型", selection: $kind) { ForEach(WeighedSubjectKind.allCases) { Label($0.title, systemImage: $0.icon).tag($0) } }
                }.navigationTitle("新建称重对象")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { adding = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("添加") {
                                scale.addWeighedSubject(name: name, kind: kind)
                                selectedID = scale.weighedSubjects.last?.id
                                adding = false
                            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "person.fill").font(.system(size: 34))
                Image(systemName: "plus").font(.title3)
                Image(systemName: subject?.kind.icon ?? "pawprint.fill").font(.system(size: 34))
                Spacer()
                Image(systemName: "sparkles").foregroundStyle(.mint)
            }
            Text("一起上秤，轻松相减").font(.title2.bold())
            Text("先称自己，再抱着它。两次读数，留下一个小档案。")
                .font(.subheadline).foregroundStyle(.white.opacity(0.75))
        }.padding(25).frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white)
            .background(LinearGradient(colors: [Color(red: 0.06, green: 0.12, blue: 0.22), Color(red: 0.05, green: 0.34, blue: 0.34)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 27))
    }

    private func captureCard(_ capture: AssistedWeighingCapture) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(capture.subject.name).font(.title3.bold())
            HStack(spacing: 10) {
                stepChip("1", title: String(appLocalized: "称自己"), done: capture.baselineWeight != nil)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                stepChip("2", title: String(appLocalized: "抱着称"), done: capture.result != nil)
            }
            if let result = capture.result {
                Text("约 \(result.weight, specifier: "%.2f") kg")
                    .font(.system(size: 46, weight: .bold, design: .rounded)).foregroundStyle(.teal)
                Label("结果已自动保存", systemImage: "checkmark.seal.fill").foregroundStyle(.teal)
                Text(String(format: "%.2f − %.2f = %.2f kg", result.combinedWeight, result.baselineWeight, result.weight))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                if let baseline = capture.baselineWeight { Text("本人重量 \(baseline, specifier: "%.2f") kg").font(.headline) }
                Text(capture.waitingForStepOff ? String(appLocalized: "请离秤，等待低于 1 kg 的读数后再上秤。") :
                    (capture.baselineWeight == nil ? String(appLocalized: "请本人单独上秤，站稳等待稳定读数。") : String(appLocalized: "请同一个人抱着对象上秤，站稳等待稳定读数。")))
                if scale.liveWeight > 3 {
                    Text("实时 \(scale.liveWeight, specifier: "%.2f") kg").font(.title2.monospacedDigit())
                }
                if let message = capture.message { Text(message).font(.caption).foregroundStyle(.orange) }
            }
            Button(capture.result == nil ? "取消本次称重" : "完成并退出") { scale.endAssistedWeighing() }
                .buttonStyle(.bordered)
            Text("离开页面不会结束采集。退出后请先离秤，再开始普通称重。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private func stepChip(_ number: String, title: String, done: Bool) -> some View {
        HStack {
            Image(systemName: done ? "checkmark.circle.fill" : number + ".circle")
            Text(title).font(.subheadline.weight(.semibold))
        }.foregroundStyle(done ? .teal : .secondary).padding(12)
            .background(done ? Color.teal.opacity(0.1) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}
