import SwiftUI

// MARK: - 主视图 (已接入真实数据模型)
struct ContentView: View {
    @StateObject private var alarmManager = AlarmManager.shared
    @EnvironmentObject private var localization: Localization
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingAddView = false
    @State private var editingAlarm: Alarm? = nil
    @State private var showingSettings = false
    @State private var showClearPausedAlert = false

    var body: some View {
        ZStack {
            LiquidBackgroundView()

            VStack(spacing: 0) {
                // 顶部标题栏：左齿轮(设置) | 中标题居中 | 右加号（固定不滚动）
                HStack {
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                    Text(L("common.alarms"))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: {
                        editingAlarm = nil
                        showingAddView = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
                .padding(.bottom, 16)

                ScrollView {
                    VStack(spacing: 24) {
                        // 动态渲染真实闹钟列表（按 今天/未来/已暂停 分组，毛玻璃分隔条隔开）
                    let grouped: [AlarmSection: [Alarm]] = {
                        var dict: [AlarmSection: [Alarm]] = [:]
                        for a in alarmManager.alarms {
                            dict[a.section(), default: []].append(a)
                        }
                        return dict
                    }()

                    // 固定顺序：今天 → 未来 → 已暂停
                    // 💡 "今天"组即使为空也必须显示分隔标题，让用户知道今天没有闹钟
                    ForEach(AlarmSection.allCases, id: \.self) { section in
                        let alarms = grouped[section] ?? []

                        // 已暂停 / 未来 组为空时不渲染
                        if section != .today && alarms.isEmpty { EmptyView() }

                        // 💡 每个组都显示分隔标题（含第一组"今天"）
                        // 已暂停组：右侧显示"全部清空"按钮
                        if section == .paused && !alarms.isEmpty {
                            HStack(spacing: 12) {
                                Text(section.title)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.7))
                                Rectangle()
                                    .fill(Color.white.opacity(0.15))
                                    .frame(height: 1)
                                Spacer()
                                Button(action: {
                                    showClearPausedAlert = true
                                }) {
                                    Text(L("home.clearAllPaused"))
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.white.opacity(0.15))
                                        .clipShape(Capsule())
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.horizontal, 28)
                            .padding(.top, 8)
                        } else {
                            SectionDivider(title: section.title)
                        }

                        if alarms.isEmpty && section == .today {
                            // 今天没有闹钟时给个轻量提示
                            Text(L("home.noAlarmsToday"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.35))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 6)
                        }

                        // 该组下的所有卡片
                        ForEach(alarms, id: \.id) { alarm in
                            DynamicGlassAlarmCard(alarm: alarm) { toEdit in
                                editingAlarm = toEdit
                                showingAddView = true
                            }
                        }
                    }

                    // 💡 底部留白，避免最后一张卡片被遮挡
                    Color.clear.frame(height: 30)
                    }
                    .padding(.bottom, 50)
                }
            }
        }
        .alert(L("home.clearAllPaused"), isPresented: $showClearPausedAlert) {
            Button(L("common.cancel"), role: .cancel) { }
            Button(L("home.clearAllPaused"), role: .destructive) {
                alarmManager.clearAllPaused()
            }
        } message: {
            Text(L("home.confirmClearPaused"))
        }
        .preferredColorScheme(.dark)
        // 💡 同一个 sheet：editingAlarm 为 nil 是新建，非 nil 是编辑
        // ⚠️ iOS 17+ sheet 不会自动继承 environmentObject，必须显式传递
        .sheet(isPresented: $showingAddView) {
            AddAlarmView(alarmManager: alarmManager, editAlarm: editingAlarm)
                .environmentObject(localization)
        }
        // 💡 设置页：语言 + 时间格式（自管理内部选择器）
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(localization)
        }
        .onAppear {
            // 冷启动：检查 UserDefaults 中是否有待处理的快捷动作
            // didFinishLaunching 设值在 ContentView 创建之前，直接消费
            openAddAlarmIfPending()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                openAddAlarmIfPending()
            }
            // App 启动时请求通知权限并重排一次
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                if granted {
                    DispatchQueue.main.async {
                        AlarmManager.shared.rescheduleAllNotifications()
                    }
                }
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                openAddAlarmIfPending()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    openAddAlarmIfPending()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    openAddAlarmIfPending()
                }
            }
        }
    }

    private let shortcutKey = "PendingAddAlarmShortcut"

    private func openAddAlarmIfPending() {
        if UserDefaults.standard.bool(forKey: shortcutKey) {
            UserDefaults.standard.set(false, forKey: shortcutKey)
            editingAlarm = nil
            showingAddView = true
        }
    }
}

struct LiquidBackgroundView: View {
    @State private var isAnimating = false
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.1).ignoresSafeArea()
            Circle().fill(Color.purple.opacity(0.5)).frame(width: 300, height: 300).blur(radius: 60).offset(x: isAnimating ? 100 : -50, y: isAnimating ? -150 : 50)
            Circle().fill(Color.blue.opacity(0.4)).frame(width: 400, height: 400).blur(radius: 80).offset(x: isAnimating ? -150 : 150, y: isAnimating ? 100 : -200)
            Circle().fill(Color.pink.opacity(0.3)).frame(width: 250, height: 250).blur(radius: 70).offset(x: isAnimating ? 50 : -100, y: isAnimating ? 250 : 150)
        }
        .ignoresSafeArea()
        .onAppear { withAnimation(.easeInOut(duration: 8.0).repeatForever(autoreverses: true)) { isAnimating = true } }
    }
}

// MARK: - 毛玻璃分组分隔条（与卡片同款材质，用于"今天/未来/已暂停"分组隔离）
struct SectionDivider: View {
    let title: String
    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
    }
}

// MARK: - 设置页（语言 + 时间格式）
struct SettingsView: View {
    @EnvironmentObject private var localization: Localization
    @Environment(\.presentationMode) var presentationMode
    @State private var showingLanguagePicker = false
    @State private var showingTimeFormatPicker = false
    // 💡 默认铃声：本地 State，进入界面时从 UserDefaults 读取，改动即时持久化
    @State private var defaultSoundId: String = AlarmSound.defaultSoundId()

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.1).ignoresSafeArea()

                Form {
                    // 语言
                    Section(header: Text(L("settings.language")).foregroundColor(.gray)) {
                        Button {
                            showingLanguagePicker = true
                        } label: {
                            HStack {
                                Text(L("settings.language"))
                                    .foregroundColor(.white)
                                Spacer()
                                Text(localization.language.displayName)
                                    .foregroundColor(.gray)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray.opacity(0.5))
                            }
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.1))

                    // 时间格式
                    Section(header: Text(L("settings.timeFormat")).foregroundColor(.gray)) {
                        Button {
                            showingTimeFormatPicker = true
                        } label: {
                            HStack {
                                Text(L("settings.timeFormat"))
                                    .foregroundColor(.white)
                                Spacer()
                                Text(localization.timeFormat.displayName)
                                    .foregroundColor(.gray)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray.opacity(0.5))
                            }
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.1))

                    // 默认铃声：点击进入铃声选择，选定后即时存 UserDefaults
                    Section(header: Text(L("settings.defaultSound")).foregroundColor(.gray)) {
                        NavigationLink {
                            SoundPickerView(selectedSoundName: $defaultSoundId)
                                .onDisappear {
                                    // 离开铃声选择页时持久化用户选择
                                    AlarmSound.setDefaultSoundId(defaultSoundId)
                                }
                        } label: {
                            HStack {
                                Text(L("settings.defaultSound"))
                                    .foregroundColor(.white)
                                Spacer()
                                Text(AlarmSound.find(byId: defaultSoundId).localizedDisplayName)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.1))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(L("common.settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("common.done")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.purple)
                    .fontWeight(.bold)
                }
            }
            .toolbarBackground(Color(red: 0.05, green: 0.05, blue: 0.1), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            // 💡 语言选择
            .confirmationDialog(
                L("settings.chooseLanguage"),
                isPresented: $showingLanguagePicker,
                titleVisibility: .visible
            ) {
                ForEach(AppLanguage.allCases, id: \.self) { lang in
                    Button(lang.displayName) {
                        localization.setLanguage(lang)
                    }
                }
                Button(L("common.cancel"), role: .cancel) {}
            }
            // 💡 时间格式选择
            .confirmationDialog(
                L("settings.chooseTimeFormat"),
                isPresented: $showingTimeFormatPicker,
                titleVisibility: .visible
            ) {
                ForEach(TimeFormat.allCases, id: \.self) { fmt in
                    Button(fmt.displayName) {
                        localization.setTimeFormat(fmt)
                    }
                }
                Button(L("common.cancel"), role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
    }
}
