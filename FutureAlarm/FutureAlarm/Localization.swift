import Foundation
import SwiftUI

// MARK: - 支持的语言
enum AppLanguage: String, CaseIterable {
    case zh
    case en

    // 显示名（用于语言选择列表）
    var displayName: String {
        switch self {
        case .zh: return "中文"
        case .en: return "English"
        }
    }

    // 对应的 Locale，用于 DateFormatter 派生
    var localeIdentifier: String {
        switch self {
        case .zh: return "zh_CN"
        case .en: return "en"
        }
    }
}

// MARK: - 时间显示格式（12 小时制 / 24 小时制）
enum TimeFormat: String, CaseIterable {
    case h12   // 12 小时制（带上午/下午、AM/PM）
    case h24   // 24 小时制

    var displayName: String {
        switch self {
        case .h12: return Localization.shared.t("settings.timeFormat.12")
        case .h24: return Localization.shared.t("settings.timeFormat.24")
        }
    }
}

// MARK: - 本地化管理器（单例，App 内语言切换）
// 纯代码方案：不依赖 .strings/.xcstrings 文件，集中维护翻译字典。
// 切换语言时 @Published language 变化 → 根视图 id(language) 重建 → 全 App 刷新。
final class Localization: ObservableObject {
    static let shared = Localization()

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: languageKey)
        }
    }

    // 💡 时间显示格式（12/24 小时制）。切换时同样触发全 App 刷新。
    @Published var timeFormat: TimeFormat {
        didSet {
            UserDefaults.standard.set(timeFormat.rawValue, forKey: timeFormatKey)
        }
    }

    private let languageKey = "AppLanguage"
    private let timeFormatKey = "AppTimeFormat"

    private init() {
        if let saved = UserDefaults.standard.string(forKey: languageKey),
           let lang = AppLanguage(rawValue: saved) {
            language = lang
        } else {
            // 首次安装：跟随系统语言。系统为中文 → zh，其余 → en。
            // （需求：程序默认中文；系统非中英时，英文为主通用兜底）
            let preferredLangs = Locale.preferredLanguages
            if preferredLangs.first(where: { $0.hasPrefix("zh") }) != nil {
                language = .zh
            } else {
                language = .en
            }
        }

        // 时间格式：读 UserDefaults；缺失时跟随系统偏好
        if let saved = UserDefaults.standard.string(forKey: timeFormatKey),
           let fmt = TimeFormat(rawValue: saved) {
            timeFormat = fmt
        } else {
            // 用系统短时间格式检测：若输出含 "AM"/"PM"/"上午"/"下午" 则为 12 小时制
            let f = DateFormatter()
            f.locale = Locale.current
            f.timeStyle = .short
            let sample = f.string(from: Date())
            let is12 = sample.localizedCaseInsensitiveContains("AM")
                || sample.localizedCaseInsensitiveContains("PM")
                || sample.contains("上午") || sample.contains("下午")
            timeFormat = is12 ? .h12 : .h24
        }
    }

    // 切换语言
    func setLanguage(_ lang: AppLanguage) {
        language = lang
    }

    // 切换时间格式
    func setTimeFormat(_ fmt: TimeFormat) {
        timeFormat = fmt
    }

    // 核心翻译函数：按 key + 当前语言查字典，缺失时回退到 key 本身
    func t(_ key: String) -> String {
        if let dict = translations[key], let value = dict[language] {
            return value
        }
        return key
    }

    // MARK: - 翻译字典（key → [语言: 文案]）
    // 集中管理所有面向用户的文案，新增文案只需在此添加一行。
    private let translations: [String: [AppLanguage: String]] = [
        // 通用
        "common.alarm":        [.zh: "闹钟", .en: "Alarm"],
        "common.alarms":       [.zh: "闹钟", .en: "Alarms"],
        "common.cancel":       [.zh: "取消", .en: "Cancel"],
        "common.save":         [.zh: "保存", .en: "Save"],
        "common.done":         [.zh: "完成", .en: "Done"],
        "common.ok":           [.zh: "好的", .en: "OK"],
        "common.edit":         [.zh: "编辑", .en: "Edit"],
        "common.delete":       [.zh: "删除", .en: "Delete"],
        "common.settings":     [.zh: "设置", .en: "Settings"],

        // 语言设置
        "settings.language":         [.zh: "语言", .en: "Language"],
        "settings.chooseLanguage":   [.zh: "选择语言", .en: "Choose Language"],
        "settings.timeFormat":       [.zh: "时间格式", .en: "Time Format"],
        "settings.chooseTimeFormat": [.zh: "选择时间格式", .en: "Choose Time Format"],
        "settings.timeFormat.12":    [.zh: "12 小时制", .en: "12-Hour"],
        "settings.timeFormat.24":    [.zh: "24 小时制", .en: "24-Hour"],
        "settings.defaultSound":     [.zh: "默认铃声", .en: "Default Sound"],

        // 主界面
        "home.noAlarmsToday":  [.zh: "今天没有闹钟", .en: "No alarms today"],

        // 闹钟分组
        "section.today":       [.zh: "今天", .en: "Today"],
        "section.future":      [.zh: "未来", .en: "Upcoming"],
        "section.paused":      [.zh: "已暂停", .en: "Paused"],

        // 闹钟类型（卡片展示 + 添加界面分段）
        "type.once":           [.zh: "单次闹钟", .en: "One-Time"],
        "type.repeating":      [.zh: "重复闹钟", .en: "Repeating"],
        "type.dated":          [.zh: "指定日期闹钟", .en: "Date-Specific"],
        "type.quick":          [.zh: "计时闹钟", .en: "Timer"],

        // 添加/编辑闹钟界面
        "add.title.add":       [.zh: "添加闹钟", .en: "Add Alarm"],
        "add.title.edit":      [.zh: "编辑闹钟", .en: "Edit Alarm"],
        "add.date":            [.zh: "日期", .en: "Date"],
        "add.time":            [.zh: "时间", .en: "Time"],
        "add.pickDate":        [.zh: "选择日期", .en: "Select Date"],
        "add.repeat":          [.zh: "重复", .en: "Repeat"],
        "add.label":           [.zh: "标签", .en: "Label"],
        "add.labelPlaceholder":[.zh: "闹钟", .en: "Alarm"],
        "add.mission":         [.zh: "响铃后需右滑关闭闹钟", .en: "Slide right to dismiss after ringing"],
        "add.sound":           [.zh: "铃声", .en: "Sound"],
        "add.countdownDuration":[.zh: "倒计时时长", .en: "Countdown Duration"],
        "add.hours":           [.zh: "小时", .en: "Hours"],
        "add.minutes":         [.zh: "分钟", .en: "Minutes"],
        "add.willRingAt":      [.zh: "将于", .en: "Rings at"],
        "add.setDuration":     [.zh: "请设置时长", .en: "Please set a duration"],
        "add.ringsWord":       [.zh: "响铃", .en: ""],  // 中文格式串内嵌，英文留空

        // 默认标签（新闹钟）
        "label.default":       [.zh: "新闹钟", .en: "New Alarm"],
        // 计时闹钟默认标签（极速闹钟历史数据回填用，逻辑判断用 isQuickAlarm 标记）
        "label.quick":         [.zh: "计时闹钟", .en: "Timer"],
        // 预置示例闹钟
        "preset.weekday":      [.zh: "工作日 起床", .en: "Weekday Wake-up"],
        "preset.weekend":      [.zh: "周末 懒觉", .en: "Weekend Sleep-in"],

        // 错误提示
        "error.cannotSave":    [.zh: "无法保存", .en: "Cannot Save"],
        "error.needWeekday":   [.zh: "请至少选择一个重复的星期。", .en: "Please select at least one day to repeat."],
        "error.needDuration":  [.zh: "请设置倒计时时长（小时或分钟至少填一个）。", .en: "Please set a countdown duration (hours or minutes)."],
        "error.invalidDate":   [.zh: "日期格式无效，请重新选择。", .en: "Invalid date, please choose again."],
        "error.pastTime":      [.zh: "所选时间已过，请选择未来的时间。", .en: "That time has passed, please choose a future time."],

        // 卡片：倒计时与日期
        "card.today":          [.zh: "今天", .en: "Today"],
        "card.tomorrow":       [.zh: "明天", .en: "Tomorrow"],
        "card.dayAfter":       [.zh: "后天", .en: "Day after tomorrow"],
        "card.skipped":        [.zh: "已跳过", .en: "Skipped"],
        "card.ringingSoon":    [.zh: "即将响铃", .en: "Ringing soon"],
        "card.skipThis":       [.zh: "跳过",    .en: "Skip"],
        "card.undoSkip":       [.zh: "退回",    .en: "Undo"],
        "card.editAlarm":      [.zh: "编辑闹钟", .en: "Edit Alarm"],
        "card.deleteAlarm":    [.zh: "删除闹钟", .en: "Delete Alarm"],
        // 倒计时模板：{days}{hours}{mins} 为占位符，拼接时替换
        "countdown.dh":        [.zh: "还有 {days}天{hours}小时 响", .en: "Rings in {days}d {hours}h"],
        "countdown.hm":        [.zh: "还有 {hours}小时{mins}分 响", .en: "Rings in {hours}h {mins}m"],
        "countdown.m":         [.zh: "还有 {mins}分钟 响", .en: "Rings in {mins} min"],

        // 铃声选择
        "sound.pickerTitle":   [.zh: "选择铃声", .en: "Choose Sound"],
        "sound.marimba":       [.zh: "马林巴琴", .en: "Marimba"],
        "sound.classicAlarm":  [.zh: "经典闹钟", .en: "Classic Alarm"],
        "sound.pianoChord":    [.zh: "钢琴和弦", .en: "Piano Chord"],
        "sound.morningBirds":  [.zh: "清晨鸟鸣", .en: "Morning Birds"],
        "sound.electronic":    [.zh: "电子警报", .en: "Electronic"],
        "sound.oceanWaves":    [.zh: "海浪声", .en: "Ocean Waves"],

        // 主屏幕长按图标快捷动作
        "shortcut.addAlarm":    [.zh: "添加闹钟", .en: "Add Alarm"],

        // 通知文案
        "notif.title":         [.zh: "⏰ 闹钟: {label}", .en: "⏰ Alarm: {label}"],
        "notif.missionBody":   [.zh: "⚠️ 必须点击进入 App 解锁才能停止响铃！", .en: "⚠️ Open the app and slide to stop the alarm!"],
        "notif.normalBody":    [.zh: "该起床啦！点击通知关闭。", .en: "Time to wake up! Tap to dismiss."],

        // 唤醒任务界面
        "wake.title":          [.zh: "清醒时间！", .en: "Wake Up!"],
        "wake.instruction":    [.zh: "必须向右滑动到底部才能关闭持续警报", .en: "Slide all the way right to stop the alarm"],
        "wake.slideHint":      [.zh: "滑动以关闭闹钟 >>>", .en: "Slide to dismiss alarm >>>"],

        // 计时闹钟预设按钮文案
        "preset.m":            [.zh: "{m}分",      .en: "{m}m"],
        "preset.hm":           [.zh: "{h}时{m}分",  .en: "{h}h {m}m"],
        "preset.h":            [.zh: "{h}时",      .en: "{h}h"],

        // 星期名（短）—— 用于重复选择按钮
        "weekday.0": [.zh: "日", .en: "Su"],
        "weekday.1": [.zh: "一", .en: "Mo"],
        "weekday.2": [.zh: "二", .en: "Tu"],
        "weekday.3": [.zh: "三", .en: "We"],
        "weekday.4": [.zh: "四", .en: "Th"],
        "weekday.5": [.zh: "五", .en: "Fr"],
        "weekday.6": [.zh: "六", .en: "Sa"],
    ]

    // 便捷：带参数的翻译（替换 {placeholder}）
    func t(_ key: String, _ params: [String: String]) -> String {
        var s = t(key)
        for (k, v) in params {
            s = s.replacingOccurrences(of: "{\(k)}", with: v)
        }
        return s
    }

    // 当前语言对应的 Locale（供 DateFormatter 使用）
    var locale: Locale {
        Locale(identifier: language.localeIdentifier)
    }

    // 💡 供 DatePicker/UI 使用的 Locale：在语言 locale 基础上覆盖小时制。
    // iOS DatePicker 的 12/24 小时由 locale 的 hourCycle 决定（中文默认 24、英文默认 12），
    // 单纯设语言 locale 无法跟随用户的"时间格式"设置，故这里用 Unicode 扩展 -u-hc-xx 显式覆盖。
    var uiLocale: Locale {
        // 24 小时制用 "h23"，12 小时制用 "h12"（午夜 12:xx AM，符合习惯）
        let hourCycle = (timeFormat == .h24) ? "h23" : "h12"
        // 例：zh_CN-u-hc-h23 / en-u-hc-h12
        return Locale(identifier: "\(language.localeIdentifier)-u-hc-\(hourCycle)")
    }
}

// MARK: - 便捷全局函数
func L(_ key: String) -> String { Localization.shared.t(key) }
func L(_ key: String, _ params: [String: String]) -> String { Localization.shared.t(key, params) }
