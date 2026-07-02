import SwiftUI

// 💡 闹钟类型：单次型 / 重复型 / 指定日期型 / 极速型（倒计时到点响一次）
enum AlarmMode: Hashable {
    case once        // 单次闹钟（只响一次，不指定具体日期，到点即响）
    case repeating   // 重复闹钟（按星期）
    case dated       // 指定日期时间闹钟（一次性，未来某天）
    case quick       // 极速闹钟（从现在起倒计时 N 小时 M 分钟后响一次）
}

// 💡 新建/编辑复用：editAlarm 传入即为编辑模式，否则为新建模式
struct AddAlarmView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject private var localization: Localization
    @ObservedObject var alarmManager: AlarmManager
    var editAlarm: Alarm?   // nil = 新建；非 nil = 编辑该闹钟

    @State private var selectedTime = Date()
    // 💡 标签默认值用本地化文案；进入界面时 onAppear 会再按需重置
    @State private var label = ""
    @State private var requireMission = true
    @State private var selectedSoundName = "Marimba"
    @State private var showingSoundPicker = false

    // 💡 标签输入框焦点：进入聚焦时若仍是默认值则清空，方便用户直接输入
    @FocusState private var labelFieldFocused: Bool
    // 💡 标记当前标签是否仍是默认占位文案（用标记位判断，不依赖具体字符串，本地化安全）
    @State private var isUsingDefaultLabel = true

    // 循环选择状态（星期短名已改用本地化 L("weekday.\(index)")，无需固定数组）
    @State private var selectedDays: Set<Int> = []
    // 💡 重复模式切换：按星期 / 按每月几号
    @State private var repeatMode: RepeatMode = .weekly
    @State private var selectedMonthDays: Set<Int> = []

    // 💡 闹钟类型切换 + 指定日期
    @State private var alarmMode: AlarmMode = .once
    @State private var selectedDate: Date = Date()       // 指定日期型用的日期（默认今天）

    // 💡 极速闹钟：从现在起倒计时 N 小时 M 分钟后响一次
    // 用 @AppStorage 持久化，进入界面时回显上次设置的值
    @AppStorage("quickAlarmHours") private var quickHours: Int = 0
    @AppStorage("quickAlarmMinutes") private var quickMinutes: Int = 25

    // 💡 计时闹钟：5 个可自定义的快捷时长预设（JSON 数组，单位秒）
    @AppStorage("quickAlarmPresets") private var presetsData: String = ""
    @State private var lastTappedPresetValue: Int? = nil   // 记录最近点击的预设值（用于滚轮调整时写回）

    // 默认预设值：1分、2分、5分、10分、30分（单位秒）
    private let defaultPresets: [Int] = [60, 120, 300, 600, 1800]

    // 解析/持久化预设数组
    private var presets: [Int] {
        get {
            guard !presetsData.isEmpty,
                  let data = presetsData.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([Int].self, from: data),
                  arr.count == 5 else {
                return defaultPresets
            }
            return arr
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let str = String(data: data, encoding: .utf8) {
                presetsData = str
            }
        }
    }

    // 当前滚轮对应的总秒数
    private var currentTotalSeconds: Int {
        quickHours * 3600 + quickMinutes * 60
    }

    // 格式化预设按钮文案（跟随当前语言）
    private func presetLabel(for totalSeconds: Int) -> String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        if h > 0 && m > 0 {
            return L("preset.hm", ["h": "\(h)", "m": "\(m)"])
        } else if h > 0 {
            return L("preset.h", ["h": "\(h)"])
        } else {
            return L("preset.m", ["m": "\(m)"])
        }
    }

    // 滚轮变化时同步更新预设列表
    private func updateActivePreset() {
        let newValue = currentTotalSeconds
        guard newValue > 0 else { return }

        if let lastValue = lastTappedPresetValue {
            // 情况 A：用户点击了某个预设 → 将该预设提到首位（值变则更新，不变则仅移动位置）
            var current = presets
            guard let idx = current.firstIndex(of: lastValue) else {
                lastTappedPresetValue = nil
                return
            }
            // 从原位置移除
            current.remove(at: idx)
            // 去重保护：如果新值改变了且已存在于其他预设中，则跳过更新
            if newValue != lastValue && current.contains(newValue) {
                lastTappedPresetValue = nil
                return
            }
            // 插入首位
            current.insert(newValue, at: 0)
            if let data = try? JSONEncoder().encode(current),
               let str = String(data: data, encoding: .utf8) {
                presetsData = str
            }
            lastTappedPresetValue = newValue
        } else {
            // 情况 B：用户手动调滚轮（未点击预设）→ 将新时长插入首位，挤掉最后一个
            var current = presets
            // 去重：如果该值已存在，先移除旧位置
            if let existingIdx = current.firstIndex(of: newValue) {
                current.remove(at: existingIdx)
            }
            current.insert(newValue, at: 0)
            // 保持最多 5 个
            if current.count > 5 {
                current = Array(current.prefix(5))
            }
            if let data = try? JSONEncoder().encode(current),
               let str = String(data: data, encoding: .utf8) {
                presetsData = str
            }
        }
    }

    // 💡 错误提示（过期时间拦截）
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    // 是否处于编辑模式（常量，避免在 body 里反复判断）
    private var isEditing: Bool { editAlarm != nil }

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.1).ignoresSafeArea()

                Form {
                    // 💡 顶部分段控件：单次闹钟 / 重复闹钟 / 指定日期闹钟 / 极速闹钟
                    Section {
                        Picker("", selection: $alarmMode) {
                            Text(L("type.once")).tag(AlarmMode.once)
                            Text(L("add.type.repeating")).tag(AlarmMode.repeating)
                            Text(L("type.dated")).tag(AlarmMode.dated)
                            Text(L("type.quick")).tag(AlarmMode.quick)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
                    }

                    if alarmMode == .dated {
                        // 💡 指定日期闹钟：日期在前，时间在后（与时间一样都带标题文字）
                        Section(header: Text(L("add.date")).foregroundColor(.gray)) {
                            DatePicker(L("add.pickDate"), selection: $selectedDate,
                                       in: Date()...,     // 只能选今天及以后
                                       displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .foregroundColor(.white)
                                // 💡 uiLocale 在语言 locale 基础上覆盖小时制（12/24h），并修中文显示英文星期
                                .environment(\.locale, Localization.shared.uiLocale)
                                .environment(\.colorScheme, .dark)
                        }
                        .listRowBackground(Color.white.opacity(0.1))

                        Section(header: Text(L("add.time")).foregroundColor(.gray)) {
                            DatePicker(L("add.time"), selection: $selectedTime, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .environment(\.locale, Localization.shared.uiLocale)
                                .environment(\.colorScheme, .dark)
                        }
                        .listRowBackground(Color.white.opacity(0.1))
                    } else if alarmMode == .repeating {
                        // 💡 重复型：先选时间，再选重复规则（至少选一个，否则保存时拦截）
                        Section {
                            DatePicker(L("add.time"), selection: $selectedTime, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .environment(\.locale, Localization.shared.uiLocale)
                                .environment(\.colorScheme, .dark)
                        }
                        .listRowBackground(Color.white.opacity(0.1))

                        // 💡 重复规则：切换器 + 对应选择器
                        Section(header: Text(L("add.repeat")).foregroundColor(.gray)) {
                            // 按星期 / 按每月几号 切换器
                            Picker("", selection: $repeatMode) {
                                Text(L("repeat.weekly")).tag(RepeatMode.weekly)
                                Text(L("repeat.monthly")).tag(RepeatMode.monthly)
                            }
                            .pickerStyle(.segmented)
                            .listRowBackground(Color.clear)
                            .padding(.bottom, 4)

                            // 按星期选择器（7 个圆形按钮）
                            if repeatMode == .weekly {
                                HStack {
                                    ForEach(0..<7) { index in
                                        Text(L("weekday.\(index)"))
                                            .font(.system(size: 14, weight: .bold))
                                            .frame(width: 36, height: 36)
                                            .background(selectedDays.contains(index) ? Color.purple : Color.white.opacity(0.2))
                                            .foregroundColor(.white)
                                            .clipShape(Circle())
                                            .onTapGesture {
                                                if selectedDays.contains(index) {
                                                    selectedDays.remove(index)
                                                } else {
                                                    selectedDays.insert(index)
                                                }
                                            }
                                        if index < 6 { Spacer() }
                                    }
                                }
                                .padding(.vertical, 8)
                            } else {
                                // 按每月几号选择器（31 个圆形按钮，7 列网格）
                                let columns = Array(repeating: GridItem(.flexible()), count: 7)
                                LazyVGrid(columns: columns, spacing: 10) {
                                    ForEach(1...31, id: \.self) { day in
                                        Text("\(day)")
                                            .font(.system(size: 14, weight: .bold))
                                            .frame(width: 36, height: 36)
                                            .background(selectedMonthDays.contains(day) ? Color.purple : Color.white.opacity(0.2))
                                            .foregroundColor(.white)
                                            .clipShape(Circle())
                                            .onTapGesture {
                                                if selectedMonthDays.contains(day) {
                                                    selectedMonthDays.remove(day)
                                                } else {
                                                    selectedMonthDays.insert(day)
                                                }
                                            }
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        .listRowBackground(Color.clear)
                    } else if alarmMode == .quick {
                        // 💡 计时闹钟：滚轮选时长（小时 + 分钟），到点响一次
                        Section(header: Text(L("add.countdownDuration")).foregroundColor(.gray)) {
                            // 快捷预设按钮行（5 个可自定义时长，升序展示）
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(presets, id: \.self) { seconds in
                                        Button(action: {
                                            quickHours = seconds / 3600
                                            quickMinutes = (seconds % 3600) / 60
                                            lastTappedPresetValue = seconds
                                        }) {
                                            Text(presetLabel(for: seconds))
                                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .background(seconds == currentTotalSeconds ? Color.purple : Color.white.opacity(0.12))
                                                .foregroundColor(seconds == currentTotalSeconds ? .white : .white.opacity(0.7))
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                            .padding(.bottom, 10)

                            HStack(spacing: 0) {
                                // 小时滚轮
                                VStack(spacing: 0) {
                                    Text(L("add.hours"))
                                        .font(.system(size: 13))
                                        .foregroundColor(.gray)
                                    Picker(L("add.hours"), selection: $quickHours) {
                                        ForEach(0..<24, id: \.self) { h in
                                            Text("\(h)").tag(h)
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                    .frame(maxWidth: .infinity)
                                    .environment(\.colorScheme, .dark)
                                }
                                // 分钟滚轮
                                VStack(spacing: 0) {
                                    Text(L("add.minutes"))
                                        .font(.system(size: 13))
                                        .foregroundColor(.gray)
                                    Picker(L("add.minutes"), selection: $quickMinutes) {
                                        ForEach(0..<60, id: \.self) { m in
                                            Text("\(m)").tag(m)
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                    .frame(maxWidth: .infinity)
                                    .environment(\.colorScheme, .dark)
                                }
                            }
                            .frame(height: 160)
                            // 💡 预览：从现在起多久后响铃
                            HStack {
                                Text(L("add.willRingAt"))
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                                Text(quickPreviewString)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundColor(.purple)
                                Spacer()
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.1))
                    } else {
                        // 💡 单次型：只选时间，响一次即关闭，无重复日、无指定日期
                        Section {
                            DatePicker(L("add.time"), selection: $selectedTime, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .environment(\.locale, Localization.shared.uiLocale)
                                .environment(\.colorScheme, .dark)
                        }
                        .listRowBackground(Color.white.opacity(0.1))
                    }

                    // 💡 标签 + 任务开关（所有模式统一显示标签输入框）
                    Section {
                        HStack {
                            Text(L("add.label"))
                                .foregroundColor(.white)
                            Spacer()
                            TextField(L("add.labelPlaceholder"), text: $label)
                                .focused($labelFieldFocused)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.trailing)
                                // 💡 聚焦时：若仍是默认占位文案，则清空，方便用户直接输入。
                                // 用标记位判断而非字符串比较，避免本地化后失效。
                                .onChange(of: labelFieldFocused) { focused in
                                    if focused && isUsingDefaultLabel {
                                        isUsingDefaultLabel = false
                                        label = ""
                                    }
                                }
                        }

                        Toggle(L("add.mission"), isOn: $requireMission)
                            .tint(.purple)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(Color.white.opacity(0.1))

                    // 铃声选择
                    Section(header: Text(L("add.sound")).foregroundColor(.gray)) {
                        Button(action: {
                            showingSoundPicker = true
                        }) {
                            HStack {
                                Image(systemName: AlarmSound.find(byId: selectedSoundName).icon)
                                    .foregroundColor(.purple)
                                Text(L("add.sound"))
                                    .foregroundColor(.white)
                                Spacer()
                                Text(AlarmSound.find(byId: selectedSoundName).localizedDisplayName)
                                    .foregroundColor(.gray)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray.opacity(0.5))
                            }
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.1))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(isEditing ? L("add.title.edit") : L("add.title.add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L("common.cancel")) { presentationMode.wrappedValue.dismiss() }
                        .foregroundColor(.purple)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("common.save")) {
                        attemptSave()
                    }
                    .foregroundColor(.purple)
                    .fontWeight(.bold)
                }
            }
            .alert(L("error.cannotSave"), isPresented: $showError) {
                Button(L("common.ok"), role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
        .preferredColorScheme(.dark)
        // 💡 进入界面时，若是编辑模式则用原闹钟数据回填表单
        .onAppear {
            if let editing = editAlarm {
                selectedTime = editing.time
                label = editing.label
                isUsingDefaultLabel = false   // 编辑模式直接用原标签，非默认占位
                requireMission = editing.requireMission
                selectedSoundName = editing.soundName
                selectedDays = Set(editing.repeatDays)
                repeatMode = editing.repeatMode
                selectedMonthDays = Set(editing.repeatMonthDays)
                // 根据已有数据回填模式：极速 / 指定日期 / 重复 / 单次 四者互斥
                // 极速闹钟识别：用专门的判定函数（语言无关），不依赖具体显示文案
                if editing.isQuickAlarm {
                    alarmMode = .quick
                } else if editing.isDatedAlarm {
                    alarmMode = .dated
                    selectedDate = editing.scheduledDate ?? Date()
                } else if !editing.repeatDays.isEmpty || !editing.repeatMonthDays.isEmpty {
                    alarmMode = .repeating
                } else {
                    alarmMode = .once
                }
            } else {
                // 新建模式：标签用当前语言的默认占位文案，铃声用用户设定的默认铃声
                label = L("label.default")
                isUsingDefaultLabel = true
                selectedSoundName = AlarmSound.defaultSoundId()
            }
        }
        .sheet(isPresented: $showingSoundPicker) {
            SoundPickerView(selectedSoundName: $selectedSoundName)
        }
    }

    // 💡 极速闹钟：从现在起倒计时 N 小时 M 分钟后响铃的预览文案
    private var quickPreviewString: String {
        let totalSeconds = TimeInterval(quickHours * 3600 + quickMinutes * 60)
        if totalSeconds <= 0 { return L("add.setDuration") }
        let target = Date().addingTimeInterval(totalSeconds)
        let f = DateFormatter()
        f.locale = Localization.shared.locale
        // 中文格式串内嵌"响铃"，英文用简洁格式
        if Localization.shared.language == .zh {
            f.dateFormat = "M月d日 HH:mm"
        } else {
            f.dateFormat = "MMM d, HH:mm"
        }
        let dateStr = f.string(from: target)
        let rings = L("add.ringsWord")
        return rings.isEmpty ? dateStr : "\(dateStr) \(rings)"
    }

    // 💡 保存前校验
    private func attemptSave() {
        // 重复闹钟：必须至少选择一个重复日，否则不给保存
        if alarmMode == .repeating {
            if repeatMode == .weekly && selectedDays.isEmpty {
                errorMessage = L("error.needWeekday")
                showError = true
                return
            }
            if repeatMode == .monthly && selectedMonthDays.isEmpty {
                errorMessage = L("error.needMonthDay")
                showError = true
                return
            }
        }

        // 极速闹钟：小时和分钟不能都为 0
        if alarmMode == .quick && quickHours == 0 && quickMinutes == 0 {
            errorMessage = L("error.needDuration")
            showError = true
            return
        }

        if alarmMode == .dated {
            // 拼出精确触发时刻 = selectedDate 的年月日 + selectedTime 的时分
            let cal = Calendar.current
            let dayComp = cal.dateComponents([.year, .month, .day], from: selectedDate)
            let timeComp = cal.dateComponents([.hour, .minute], from: selectedTime)
            var merged = DateComponents()
            merged.year = dayComp.year; merged.month = dayComp.month; merged.day = dayComp.day
            merged.hour = timeComp.hour; merged.minute = timeComp.minute
            guard let target = cal.date(from: merged) else {
                errorMessage = L("error.invalidDate")
                showError = true
                return
            }
            if target <= Date() {
                errorMessage = L("error.pastTime")
                showError = true
                return
            }
        }
        save()
        presentationMode.wrappedValue.dismiss()
    }

    // 💡 统一保存逻辑：新建走 append，编辑走就地更新（按 id 定位，安全）
    private func save() {
        // 💡 计时闹钟：保存时将当前时长更新到快捷预设
        if alarmMode == .quick {
            updateActivePreset()
        }

        // 根据模式决定 scheduledDate 和 repeatDays（四者互斥）
        // - dated：指定日期时间闹钟，repeatDays 必空
        // - repeating：重复型，scheduledDate 必空，repeatDays 非空
        // - quick：极速闹钟，把倒计时折算成绝对时刻存入 scheduledDate，复用"指定日期时间"引擎响一次
        // - once：单次型，两者都空
        var finalScheduledDate: Date? = nil
        if alarmMode == .dated {
            finalScheduledDate = selectedDate
        } else if alarmMode == .quick {
            let totalSeconds = TimeInterval(quickHours * 3600 + quickMinutes * 60)
            finalScheduledDate = Date().addingTimeInterval(totalSeconds)
        }
        let finalRepeatDays: [Int] = (alarmMode == .repeating && repeatMode == .weekly) ? Array(selectedDays).sorted() : []
        let finalRepeatMonthDays: [Int] = (alarmMode == .repeating && repeatMode == .monthly) ? Array(selectedMonthDays).sorted() : []
        let finalRepeatMode: RepeatMode = (alarmMode == .repeating) ? repeatMode : .weekly
        // 标签：用户未输入（空）则回退默认标签；计时闹钟同样支持自定义标签
        let finalLabel: String
        if label.trimmingCharacters(in: .whitespaces).isEmpty {
            finalLabel = L("label.default")
        } else {
            finalLabel = label
        }
        // 极速闹钟的触发时刻由倒计时决定，time 字段也同步成该时刻，保证卡片显示一致
        let finalTime: Date = (alarmMode == .quick) ? (finalScheduledDate ?? Date()) : selectedTime
        let finalIsQuick: Bool = (alarmMode == .quick)

        if let editing = editAlarm {
            // 编辑模式：按 id 找到原闹钟并更新字段
            if let idx = alarmManager.alarms.firstIndex(where: { $0.id == editing.id }) {
                // 单次闹钟 = 没有重复日（含"无重复单次"和"指定日期型"两种），保存后自动重新启用
                let wasOneTime = alarmManager.alarms[idx].repeatDays.isEmpty && alarmManager.alarms[idx].repeatMonthDays.isEmpty
                alarmManager.alarms[idx].time = finalTime
                alarmManager.alarms[idx].label = finalLabel
                alarmManager.alarms[idx].requireMission = requireMission
                alarmManager.alarms[idx].soundName = selectedSoundName
                alarmManager.alarms[idx].repeatDays = finalRepeatDays
                alarmManager.alarms[idx].repeatMode = finalRepeatMode
                alarmManager.alarms[idx].repeatMonthDays = finalRepeatMonthDays
                alarmManager.alarms[idx].scheduledDate = finalScheduledDate
                alarmManager.alarms[idx].isQuickAlarm = finalIsQuick
                if wasOneTime && !alarmManager.alarms[idx].isOn {
                    alarmManager.alarms[idx].isOn = true
                }
                // 💡 上面任意一次字段写入都会触发 didSet → handleChange 自动重排 + 持久化 + 重排通知，
                //    无需手动 sortAlarms()
            }
        } else {
            // 新建模式
            let newAlarm = Alarm(
                time: finalTime,
                isOn: true,
                label: finalLabel,
                repeatDays: finalRepeatDays,
                repeatMode: finalRepeatMode,
                repeatMonthDays: finalRepeatMonthDays,
                requireMission: requireMission,
                soundName: selectedSoundName,
                scheduledDate: finalScheduledDate,
                isQuickAlarm: finalIsQuick
            )
            alarmManager.alarms.append(newAlarm)   // didSet → handleChange 自动重排
        }
    }
}
