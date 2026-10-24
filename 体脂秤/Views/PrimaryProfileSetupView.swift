import SwiftUI

struct PrimaryProfileSetupView: View {
    @EnvironmentObject private var profile: UserProfile
    @AppStorage(AppLanguage.storageKey, store: .standard) private var language = AppLanguage.system.rawValue
    @State private var sex: Sex?
    @State private var height = ""
    @State private var birthDate: Date?
    @State private var selectingBirthday = false
    @State private var birthdayDraft = Date()

    private var heightValue: Double? {
        Double(height.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }
    private var canContinue: Bool {
        guard sex != nil, let heightValue, let birthDate else { return false }
        return (100...230).contains(heightValue)
            && UserProfile.isValid(height: heightValue, birthDate: birthDate)
    }
    private var birthdayRange: ClosedRange<Date> {
        Calendar.current.date(from: DateComponents(year: 1900, month: 1, day: 1))!...Date()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("先完善你的资料", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.title2.bold())
                    Text("性别、身高和出生日期会影响身体成分估算。请填写真实资料，不使用预设值代替。资料保存在本机。")
                        .foregroundStyle(.secondary)
                }
                Section {
                    Picker("性别", selection: $sex) {
                        Text("请选择性别").tag(Optional<Sex>.none)
                        Text("女").tag(Optional(Sex.female))
                        Text("男").tag(Optional(Sex.male))
                    }
                    HStack {
                        Text("身高")
                        Spacer()
                        TextField("请输入", text: $height)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                        Text("cm").foregroundStyle(.secondary)
                    }
                    Button {
                        birthdayDraft = birthDate ?? Date()
                        selectingBirthday = true
                    } label: {
                        HStack {
                            Text("出生日期").foregroundStyle(.primary)
                            Spacer()
                            if let birthDate {
                                Text(birthDate, style: .date)
                            } else {
                                Text("请选择出生日期").foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("个人资料")
                } footer: {
                    Text("请填写 100–230 cm 的身高，并选择不晚于今天的出生日期。")
                }
                Section {
                    Picker("语言", selection: $language) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                }
                Section {
                    Button("保存并开始使用") {
                        guard let sex, let heightValue, let birthDate else { return }
                        profile.completeProfile(sex: sex, height: heightValue, birthDate: birthDate)
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(!canContinue)
                }
            }
            .navigationTitle("欢迎使用")
            .sheet(isPresented: $selectingBirthday) {
                NavigationStack {
                    DatePicker("出生日期", selection: $birthdayDraft, in: birthdayRange, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                        .navigationTitle("选择出生日期")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("取消") { selectingBirthday = false }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("确认") {
                                    birthDate = birthdayDraft
                                    selectingBirthday = false
                                }
                            }
                        }
                }
            }
        }
    }
}
