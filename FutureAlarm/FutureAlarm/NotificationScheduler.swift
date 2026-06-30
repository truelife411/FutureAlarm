import Foundation
import UserNotifications

class NotificationScheduler {
    static let shared = NotificationScheduler()
    
    // 每次轰炸的持续时长：例如发 5 个通知，每个相隔 30 秒，总计轰炸 2.5 分钟
    private let bombardmentCount = 5
    private let notificationInterval: TimeInterval = 30
    
    // 最大系统通知限制
    private let maxPendingNotifications = 64
    
    private init() {}
    
    // 请求权限
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    // 核心引擎：重新计算并排期所有闹钟
    func scheduleAll(alarms: [Alarm]) {
        let center = UNUserNotificationCenter.current()
        
        // 1. 暴力清除：撤销目前系统中所有的未发出的通知，腾出 64 个坑位
        center.removeAllPendingNotificationRequests()
        
        // 2. 筛选出处于开启状态的闹钟
        let activeAlarms = alarms.filter { $0.isOn }
        
        var scheduledCount = 0
        
        // 3. 遍历每一个需要响铃的闹钟
        for alarm in activeAlarms {
            // 安全限制：如果坑位快满了，停止添加，保证系统不崩溃
            if scheduledCount + bombardmentCount > maxPendingNotifications {
                print("⚠️ 达到 iOS 系统 64 个通知上限，部分远期闹钟被截断。")
                break
            }
            
            // 计算这个闹钟下一次应该响铃的具体时间
            guard let nextTriggerDate = calculateNextTriggerDate(for: alarm) else { continue }
            
            // 4. 执行“连发轰炸”逻辑
            for i in 0..<bombardmentCount {
                // 每个通知向后推迟 30 秒
                let triggerDate = nextTriggerDate.addingTimeInterval(Double(i) * notificationInterval)
                
                let content = UNMutableNotificationContent()
                // 💡 通知文案绕过 SwiftUI，必须显式调用本地化（跟随当前 App 语言）
                content.title = Localization.shared.t("notif.title", ["label": alarm.label])

                if alarm.requireMission {
                    content.body = Localization.shared.t("notif.missionBody")
                } else {
                    content.body = Localization.shared.t("notif.normalBody")
                }
                
                // 使用用户选中的铃声（从 App bundle 加载 .caf 文件）
                // 文件名必须与 Sounds 目录下的文件一致
                let soundFileName = "\(alarm.soundName).caf"
                if Bundle.main.url(forResource: alarm.soundName, withExtension: "caf") != nil {
                    content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: soundFileName))
                } else {
                    // 如果找不到文件，回退到系统默认
                    content.sound = UNNotificationSound.default
                }
                
                // 标记为时间敏感，突破用户的专注模式
                if #available(iOS 15.0, *) {
                    content.interruptionLevel = .timeSensitive
                }
                
                // 将我们要传递的自定义数据塞进 userInfo，方便 App 启动时读取
                content.userInfo = [
                    "alarmId": alarm.id.uuidString,
                    "requireMission": alarm.requireMission,
                    "soundName": alarm.soundName
                ]
                
                // 创建绝对时间触发器
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                
                let request = UNNotificationRequest(
                    identifier: "\(alarm.id.uuidString)_bomb_\(i)",
                    content: content,
                    trigger: trigger
                )
                
                center.add(request) { error in
                    if let error = error {
                        print("排期失败: \(error.localizedDescription)")
                    }
                }
                
                scheduledCount += 1
            }
        }
        
        print("✅ 引擎重排完成，共注入了 \(scheduledCount) 个轰炸通知。")
    }
    
    // 💡 公开接口：返回闹钟"下一次会响铃的确切 Date"，供排序和卡片显示复用
    // nil 表示该闹钟不会再响（如单次闹钟命中跳过日）
    func nextTriggerDate(for alarm: Alarm) -> Date? {
        return calculateNextTriggerDate(for: alarm)
    }

    // 💡 修复前台响铃 bug：用户关闭闹钟时，精准取消该闹钟"还没送达"的轰炸通知
    // 轰炸标识符格式为 "{alarmId}_bomb_{0..4}"，按前缀匹配取消，不影响其它闹钟
    func cancelPendingBombardment(for alarmId: String) {
        let center = UNUserNotificationCenter.current()
        let prefix = "\(alarmId)_bomb_"
        center.getPendingNotificationRequests { requests in
            let idsToCancel = requests
                .map { $0.identifier }
                .filter { $0.hasPrefix(prefix) }
            if !idsToCancel.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: idsToCancel)
                print("🛑 已取消 \(idsToCancel.count) 个未送达的轰炸通知: \(alarmId)")
            }
        }
    }

    // 算法：计算闹钟的下一次触发时间，完美处理"跳过下次"、"单次/循环"、"指定日期"逻辑
    private func calculateNextTriggerDate(for alarm: Alarm) -> Date? {
        let calendar = Calendar.current
        let now = Date()

        // 提取设定的小时和分钟
        let hour = calendar.component(.hour, from: alarm.time)
        let minute = calendar.component(.minute, from: alarm.time)

        // 方案 C：指定日期型闹钟（未来某天某刻响一次）
        if let scheduledDate = alarm.scheduledDate {
            // 用 scheduledDate 的年月日 + time 的时分，拼出精确触发时刻
            let dayComp = calendar.dateComponents([.year, .month, .day], from: scheduledDate)
            var merged = DateComponents()
            merged.year = dayComp.year
            merged.month = dayComp.month
            merged.day = dayComp.day
            merged.hour = hour
            merged.minute = minute
            guard let targetDate = calendar.date(from: merged) else { return nil }
            // 已过期则不再响（保存时 UI 已拦截，这里做兜底）
            if targetDate <= now { return nil }
            return targetDate
        }

        // 方案 A：单次闹钟 (没有设置循环日，包括按星期和按月)
        if alarm.repeatDays.isEmpty && alarm.repeatMonthDays.isEmpty {
            // 先假设是今天这个时间
            guard var targetDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else {
                return nil
            }

            // 如果今天的时间已经过去了，那就排到明天
            if targetDate <= now {
                guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: targetDate) else {
                    return nil
                }
                targetDate = tomorrow
            }

            // 检查是否被用户跳过（单次闹钟跳过本次后即作废）
            if alarm.skippedDates.contains(where: { calendar.isDate(targetDate, inSameDayAs: $0) }) {
                return nil
            }

            return targetDate
        }

        // 方案 B'：按月几号循环闹钟（例如每月1日、10日、20日）
        if alarm.repeatMode == .monthly {
            for dayOffset in 0...366 {
                guard let candidateDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else {
                    continue
                }
                let day = calendar.component(.day, from: candidateDate) // 1-31

                if alarm.repeatMonthDays.contains(day) {
                    guard let targetDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: candidateDate) else {
                        continue
                    }

                    // 如果是今天，且时间已经过了，那么这天就不算，继续找下一天
                    if dayOffset == 0 && targetDate <= now {
                        continue
                    }

                    // 💡 检查这一天是否在"已跳过日期"列表里（累积式，可跳过多次）
                    if alarm.skippedDates.contains(where: { calendar.isDate(targetDate, inSameDayAs: $0) }) {
                        continue
                    }

                    return targetDate
                }
            }
            return nil
        }

        // 方案 B：循环闹钟 (例如工作日)
        // 从今天开始往后扫，跳过所有"已跳过日期"，找到最近的一个合法日子。
        // 范围给到 0...365：用户可能累积跳过很多次，需要足够远的搜索窗口兜底；
        // 同时每年自动做一次"过期跳过日"清理（见 skipNextOccurrence 周边逻辑），不会无限膨胀。
        for dayOffset in 0...365 {
            guard let candidateDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else {
                continue
            }
            let weekday = calendar.component(.weekday, from: candidateDate) - 1 // Calendar 默认 1 是周日，我们转成 0=周日

            // 检查这一天是否在我们设定的循环列表里
            if alarm.repeatDays.contains(weekday) {
                guard let targetDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: candidateDate) else {
                    continue
                }

                // 如果是今天，且时间已经过了，那么这天就不算，继续找下一天
                if dayOffset == 0 && targetDate <= now {
                    continue
                }

                // 💡 杀手功能：检查这一天是否在"已跳过日期"列表里（累积式，可跳过多次）
                if alarm.skippedDates.contains(where: { calendar.isDate(targetDate, inSameDayAs: $0) }) {
                    continue // 跳过这一天，继续往后找下一个合法的日子
                }

                return targetDate
            }
        }

        return nil
    }
}
