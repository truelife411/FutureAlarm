import Foundation
import SwiftUI

// MARK: - 闹钟数据模型

// 💡 重复模式：按星期（默认，兼容旧数据）/ 按每月几号
enum RepeatMode: Int, Codable {
    case weekly = 0   // 按星期（0-6）
    case monthly = 1  // 按每月几号（1-31）
}

struct Alarm: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var time: Date
    var isOn: Bool
    var label: String
    var repeatDays: [Int]
    // 💡 重复模式：按星期 / 按每月几号（与 repeatDays/repeatMonthDays 配合使用）
    var repeatMode: RepeatMode
    // 💡 按每月几号重复（1-31）。仅当 repeatMode == .monthly 时有效。
    var repeatMonthDays: [Int]
    // 💡 已跳过的响铃日列表（每个元素均为当天的 startOfDay）。
    // 重复闹钟可累积跳过多次，引擎计算下一次响铃时会跳过这些日子、往后找下一个合法日。
    var skippedDates: [Date]
    var requireMission: Bool
    var soundName: String   // 铃声文件名（对应 Sounds 目录下的 .caf）
    var scheduledDate: Date? // 💡 指定日期闹钟：非 nil 表示"未来某天某刻响一次"。此时 repeatDays 必须为空。
    var isQuickAlarm: Bool   // 💡 极速闹钟标记（语言无关，持久化）。true=极速闹钟，复用 scheduledDate 存触发时刻。

    init(time: Date = Date(), isOn: Bool = true, label: String = "闹钟", repeatDays: [Int] = [], repeatMode: RepeatMode = .weekly, repeatMonthDays: [Int] = [], skippedDates: [Date] = [], requireMission: Bool = true, soundName: String = "Marimba", scheduledDate: Date? = nil, isQuickAlarm: Bool = false) {
        self.time = time
        self.isOn = isOn
        self.label = label
        self.repeatDays = repeatDays
        self.repeatMode = repeatMode
        self.repeatMonthDays = repeatMonthDays
        self.skippedDates = skippedDates
        self.requireMission = requireMission
        self.soundName = soundName
        self.scheduledDate = scheduledDate
        self.isQuickAlarm = isQuickAlarm
    }

    // 💡 兼容旧版本持久化：旧字段名为 skipNextDate（单个日期），
    // 新版本改为 skippedDates（数组）。解码时把旧的 skipNextDate 迁移进来。
    // isQuickAlarm 为后加字段，缺失时回退为 false（兼容旧数据）。
    private enum CodingKeys: String, CodingKey {
        case id, time, isOn, label, repeatDays, repeatMode, repeatMonthDays, skippedDates
        case skipNextDate   // 旧字段，仅用于解码兼容
        case requireMission, soundName, scheduledDate, isQuickAlarm
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        time = try c.decode(Date.self, forKey: .time)
        isOn = try c.decode(Bool.self, forKey: .isOn)
        label = try c.decode(String.self, forKey: .label)
        repeatDays = try c.decode([Int].self, forKey: .repeatDays)
        // repeatMode / repeatMonthDays 为后加字段，缺失时回退默认值（兼容旧数据）
        repeatMode = try c.decodeIfPresent(RepeatMode.self, forKey: .repeatMode) ?? .weekly
        repeatMonthDays = try c.decodeIfPresent([Int].self, forKey: .repeatMonthDays) ?? []
        // 新版本字段优先；缺失时回退到旧字段 skipNextDate（兼容历史数据）
        if let arr = try c.decodeIfPresent([Date].self, forKey: .skippedDates) {
            skippedDates = arr
        } else if let single = try c.decodeIfPresent(Date.self, forKey: .skipNextDate) {
            skippedDates = [single]
        } else {
            skippedDates = []
        }
        requireMission = try c.decode(Bool.self, forKey: .requireMission)
        soundName = try c.decode(String.self, forKey: .soundName)
        scheduledDate = try c.decodeIfPresent(Date.self, forKey: .scheduledDate)
        isQuickAlarm = try c.decodeIfPresent(Bool.self, forKey: .isQuickAlarm) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(time, forKey: .time)
        try c.encode(isOn, forKey: .isOn)
        try c.encode(label, forKey: .label)
        try c.encode(repeatDays, forKey: .repeatDays)
        try c.encode(repeatMode, forKey: .repeatMode)
        try c.encode(repeatMonthDays, forKey: .repeatMonthDays)
        try c.encode(skippedDates, forKey: .skippedDates)
        try c.encode(requireMission, forKey: .requireMission)
        try c.encode(soundName, forKey: .soundName)
        try c.encodeIfPresent(scheduledDate, forKey: .scheduledDate)
        try c.encode(isQuickAlarm, forKey: .isQuickAlarm)
    }

    // 💡 是否为"指定日期型"闹钟（一次性，未来某天某刻响）。极速闹钟也复用 scheduledDate，需排除。
    var isDatedAlarm: Bool { scheduledDate != nil && !isQuickAlarm }

    // 💡 是否为重复闹钟（按星期或按月循环）。互斥：重复 / 指定日期 / 单次 / 极速
    var isRepeatingAlarm: Bool { !repeatDays.isEmpty || !repeatMonthDays.isEmpty }

    // 💡 闹钟类型文案（用于主界面展示，跟随当前语言）
    var typeLabel: String {
        if isQuickAlarm { return Localization.shared.t("type.quick") }
        if isDatedAlarm { return Localization.shared.t("type.dated") }
        if repeatMode == .monthly && !repeatMonthDays.isEmpty { return Localization.shared.t("type.monthly") }
        if isRepeatingAlarm { return Localization.shared.t("type.repeating") }
        return Localization.shared.t("type.once")
    }
}

// MARK: - 闹钟分组（用于主界面分隔：今天 / 未来 / 已暂停）
enum AlarmSection: Int, CaseIterable {
    case today       // 今天响
    case future      // 明天及以后响
    case paused      // 已关闭（isOn=false）

    // 跟随当前语言，每次访问实时计算
    var title: String {
        switch self {
        case .today:  return Localization.shared.t("section.today")
        case .future: return Localization.shared.t("section.future")
        case .paused: return Localization.shared.t("section.paused")
        }
    }
}

extension Alarm {
    // 返回该闹钟所属分组（基于下一次真实响铃时刻）
    func section() -> AlarmSection {
        if !isOn { return .paused }
        guard let next = NotificationScheduler.shared.nextTriggerDate(for: self) else {
            return .future // 已跳过的单次闹钟归入未来组兜底
        }
        return Calendar.current.isDateInToday(next) ? .today : .future
    }
}

// MARK: - 闹钟管理器 (全局状态与持久化)
@MainActor
class AlarmManager: ObservableObject {
    // 变成单例，方便在通知代理等非 UI 处调用
    static let shared = AlarmManager()

    @Published var alarms: [Alarm] = [] {
        didSet { saveAlarms() }
    }

    private let saveKey = "SavedFutureAlarms"

    private init() {
        loadAlarms()
    }

    // 💡 杀手功能：智能排序
    // 规则：1) 开启的排前、关闭的排后；2) 同状态下按"下一次真实响铃时刻"由近到远排序
    // 复用 NotificationScheduler 的权威计算，重复闹钟按真实下次合法星期排序
    func sortAlarms() {
        let now = Date()

        // 💡 顺手清理已过期的跳过日（早于今天的 skippedDates 已无意义），
        // 防止累积式跳过导致列表无限膨胀拖慢 contains 检查。
        var cleaned = alarms
        let todayStart = Calendar.current.startOfDay(for: now)
        var didClean = false
        for i in cleaned.indices {
            let filtered = cleaned[i].skippedDates.filter { $0 >= todayStart }
            if filtered.count != cleaned[i].skippedDates.count {
                cleaned[i].skippedDates = filtered
                didClean = true
            }
        }

        var sorted = cleaned
        sorted.sort { a, b in
            if a.isOn != b.isOn {
                return a.isOn // 开启的排在前面
            }
            // 状态相同：按下一次响铃的精确 Date 排序（nil 视为"永不再响"排最后）
            let da = nextTriggerDateOrFarFuture(a, now: now)
            let db = nextTriggerDateOrFarFuture(b, now: now)
            return da < db
        }

        // 避免死循环触发 didSet：只有内容确实变化时才写回
        if didClean || sorted != alarms {
            alarms = sorted
        }
    }

    // 返回闹钟下一次响铃的 Date；若不会再响则返回一个极远未来值用于排序兜底
    private func nextTriggerDateOrFarFuture(_ alarm: Alarm, now: Date) -> Date {
        if let d = NotificationScheduler.shared.nextTriggerDate(for: alarm) {
            return d
        }
        // 永不再响（如单次闹钟命中跳过日）→ 排到该分组最末尾
        return Date.distantFuture
    }
    
    // 💡 杀手功能：单次闹钟响铃后自动设为关闭
    // 单次闹钟 = 没有重复日（含"无重复的单次"和"指定日期型"两种，都不会循环）
    func disableOneTimeAlarm(id: String) {
        // 先通过 id 取到闹钟，避免后续 sortAlarms() 重排导致 index 失效引发崩溃
        guard let index = alarms.firstIndex(where: { $0.id.uuidString == id }) else { return }
        guard alarms[index].repeatDays.isEmpty && alarms[index].repeatMonthDays.isEmpty else { return } // 只有单次闹钟才自动关闭

        let label = alarms[index].label // 提前快照，防止下面排序后 index 失效
        alarms[index].isOn = false      // 触发 didSet → 保存并重排通知
        sortAlarms()                    // 数组重排，此后 index 不再可用
        print("✅ 已经自动关闭单次闹钟: \(label)")
    }
    
    // 💡 杀手功能：删除闹钟
    func deleteAlarm(id: UUID) {
        alarms.removeAll(where: { $0.id == id })
    }

    // 💡 清空所有已暂停的闹钟
    func clearAllPaused() {
        let count = alarms.filter { !$0.isOn }.count
        alarms.removeAll(where: { !$0.isOn })
        sortAlarms()
        print("🗑️ 已清空 \(count) 个已暂停闹钟")
    }

    // 💡 跳过本次（累积式）：把"当前最近一次响铃日"永久加入跳过列表，
    // 引擎会自动跳过这些日子、往后找下一个合法日，并触发重新排序。
    // 重复闹钟可无限次跳过，每次都把那一天的 startOfDay 追加进 skippedDates。
    func skipNextOccurrence(of id: UUID) {
        guard let idx = alarms.firstIndex(where: { $0.id == id }) else { return }
        let before = NotificationScheduler.shared.nextTriggerDate(for: alarms[idx])
        guard let current = before else {
            print("⚠️ 跳过失败：该闹钟已无下次响铃")
            return
        }
        // 把"当前最近一次响铃那天"的 startOfDay 追加进跳过列表（去重防呆）
        let day = Calendar.current.startOfDay(for: current)
        if !alarms[idx].skippedDates.contains(where: { Calendar.current.isDate($0, inSameDayAs: day) }) {
            alarms[idx].skippedDates.append(day)
        }

        // didSet 已自动 saveAlarms + 重排通知；这里再主动重排卡片顺序
        sortAlarms()

        // 诊断：确认跳过后确实推进到了更晚的一次响铃
        let after = NotificationScheduler.shared.nextTriggerDate(for: alarms[idx])
        print("⏭️ 跳过本次：原=\(before.map { describe($0) } ?? "nil") → 新=\(after.map { describe($0) } ?? "nil")，累计跳过 \(alarms[idx].skippedDates.count) 次")
    }

    // 💡 退回上一次跳过：移除最近一次跳过日，恢复到上一个响铃时间
    // 若被跳过那天的响铃时刻已过（比如跳过了今天上午的闹钟，现在已是下午），则不接受退回
    func undoSkippedDate(of id: UUID) {
        guard let idx = alarms.firstIndex(where: { $0.id == id }) else { return }
        guard !alarms[idx].skippedDates.isEmpty else {
            print("⚠️ 退回失败：该闹钟没有跳过记录")
            return
        }
        let removed = alarms[idx].skippedDates.last!
        // 拼出该跳过日当天的精确响铃时刻 = 那天的年月日 + 闹钟设定的时分
        let calendar = Calendar.current
        let dayComp = calendar.dateComponents([.year, .month, .day], from: removed)
        let timeComp = calendar.dateComponents([.hour, .minute], from: alarms[idx].time)
        var merged = DateComponents()
        merged.year = dayComp.year; merged.month = dayComp.month; merged.day = dayComp.day
        merged.hour = timeComp.hour; merged.minute = timeComp.minute
        if let ringTime = calendar.date(from: merged), ringTime <= Date() {
            print("⚠️ 退回失败：被跳过的 \(describe(removed)) 响铃时刻已过，无法退回")
            // 顺手清理这条已过期的跳过记录
            alarms[idx].skippedDates.removeLast()
            sortAlarms()
            return
        }
        alarms[idx].skippedDates.removeLast()
        sortAlarms()
        print("↩️ 已退回跳过：恢复 \(describe(removed))，剩余跳过 \(alarms[idx].skippedDates.count) 次")
    }

    private func describe(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }
    
    private func loadAlarms() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([Alarm].self, from: data) {
            self.alarms = decoded
            sortAlarms()
            return
        }
        self.alarms = [
            Alarm(time: Date().addingTimeInterval(3600 * 7), isOn: true, label: Localization.shared.t("preset.weekday"), repeatDays: [1,2,3,4,5]),
            Alarm(time: Date().addingTimeInterval(3600 * 9), isOn: false, label: Localization.shared.t("preset.weekend"), repeatDays: [0, 6])
        ]
        sortAlarms()
    }
    
    func saveAlarms() {
        if let encoded = try? JSONEncoder().encode(alarms) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
        rescheduleAllNotifications()
        // 💡 闹钟增删改后刷新后台引擎：有开启闹钟则保活，无则停止
        // ⚠️ 必须直接传入 alarms，避免 AlarmManager 初始化期间 refresh() 回访
        // AlarmManager.shared.alarms 导致 dispatch_once 死锁崩溃
        BackgroundAlarmEngine.shared.refresh(alarms: alarms)
    }
    
    func rescheduleAllNotifications() {
        NotificationScheduler.shared.scheduleAll(alarms: alarms)
    }
}
