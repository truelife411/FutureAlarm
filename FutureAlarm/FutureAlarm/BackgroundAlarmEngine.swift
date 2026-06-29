import Foundation

// MARK: - 后台闹钟引擎
// 核心职责：用静音音频保活，让 App 在后台持续运行，Timer 每秒检测闹钟到点，
// 到点用 SoundManager.playAlarmLoop 接管（.playback 类别绕过静音开关）。
// 解决"静音模式下系统通知声音不响"的问题。
@MainActor
final class BackgroundAlarmEngine {
    static let shared = BackgroundAlarmEngine()

    private var tickTimer: DispatchSourceTimer?
    private var triggeredKeys: Set<String> = []  // 防重入：已触发的 闹钟id+日期

    private init() {}

    /// 刷新引擎状态：根据是否有开启的闹钟决定启停
    /// - Parameter alarms: 可选传入闹钟列表，避免在 AlarmManager 初始化期间回访单例导致 dispatch_once 死锁
    func refresh(alarms: [Alarm]? = nil) {
        let hasActive: Bool
        if let alarms = alarms {
            hasActive = alarms.contains { $0.isOn }
        } else {
            hasActive = AlarmManager.shared.alarms.contains { $0.isOn }
        }
        // 💡 每次刷新时清理 triggeredKeys，避免跳过闹钟后同一天内无法再次触发
        triggeredKeys.removeAll()
        if hasActive {
            start()
        } else {
            stop()
        }
    }

    /// 启动：静音保活 + 定时检测
    private func start() {
        SoundManager.shared.startSilentKeepAlive()

        // Timer 已在跑则跳过
        if tickTimer != nil { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        // 💡 首次检测延迟 0.5s（更快响应），之后每秒检测
        timer.schedule(deadline: .now() + 0.5, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.checkAlarms()
        }
        timer.resume()
        tickTimer = timer
        print("⏰ 后台闹钟引擎已启动（检测间隔 1s）")
    }

    /// 停止：停保活 + 停 Timer
    private func stop() {
        tickTimer?.cancel()
        tickTimer = nil
        SoundManager.shared.stopSilentKeepAlive()
        triggeredKeys.removeAll()
        print("⏰ 后台闹钟引擎已停止")
    }

    /// 每秒检查：是否有闹钟到点
    private func checkAlarms() {
        let now = Date()
        for alarm in AlarmManager.shared.alarms where alarm.isOn {
            guard let trigger = NotificationScheduler.shared.nextTriggerDate(for: alarm) else { continue }
            guard trigger <= now, now.timeIntervalSince(trigger) < 120 else { continue }

            let dayKey = Calendar.current.startOfDay(for: trigger).timeIntervalSince1970
            let key = "\(alarm.id.uuidString)_\(dayKey)"
            guard !triggeredKeys.contains(key) else { continue }
            triggeredKeys.insert(key)

            triggerAlarm(alarm)
            return
        }
    }

    /// 触发闹钟：播放铃声 + 发通知让 WakeUpState 弹出任务界面
    private func triggerAlarm(_ alarm: Alarm) {
        print("🔔 后台引擎触发闹钟: \(alarm.label)")
        SoundManager.shared.playAlarmLoop(soundName: alarm.soundName)
        NotificationCenter.default.post(
            name: .init("BackgroundAlarmTriggered"),
            object: nil,
            userInfo: ["alarmId": alarm.id.uuidString]
        )
    }
}
