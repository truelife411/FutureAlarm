import Foundation
import UserNotifications
import SwiftUI

// MARK: - 全局唤醒状态管理
@MainActor
class WakeUpState: ObservableObject {
    @Published var isShowingMission: Bool = false
    @Published var activeAlarmId: String? = nil

    init() {
        // 💡 监听后台闹钟引擎的触发信号，弹出任务界面
        NotificationCenter.default.addObserver(
            forName: .init("BackgroundAlarmTriggered"), object: nil, queue: .main
        ) { [weak self] note in
            let id = note.userInfo?["alarmId"] as? String ?? ""
            DispatchQueue.main.async {
                self?.triggerMission(for: id)
            }
        }
    }

    // 强制弹出任务界面
    func triggerMission(for alarmId: String) {
        self.activeAlarmId = alarmId
        self.isShowingMission = true
    }

    // 任务完成，关闭界面并停止轰炸
    func completeMission() {
        let activeId = self.activeAlarmId
        self.isShowingMission = false
        // 任务完成，如果是单次闹钟，顺便把它关闭
        if let activeId = activeId {
            AlarmManager.shared.disableOneTimeAlarm(id: activeId)
            // 💡 修复前台响铃 bug：取消该闹钟"还没送达"的后续轰炸通知，
            //    否则 30s 后的 xxx_bomb_1~4 还会继续响
            NotificationScheduler.shared.cancelPendingBombardment(for: activeId)
        }
        self.activeAlarmId = nil
        // 💡 清理已送达的通知（含正在播放的系统提示音），并强制停止系统声音
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        // 💡 关闭后刷新后台引擎：恢复静音保活等待下一个闹钟
        BackgroundAlarmEngine.shared.refresh()
    }
}

// MARK: - 通知点击代理
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var wakeUpState: WakeUpState?

    // 当 App 在前台时，如果通知来了，也会直接触发这个方法 (模拟强制弹窗)
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {

        let userInfo = notification.request.content.userInfo
        let requireMission = userInfo["requireMission"] as? Bool ?? false
        let alarmId = userInfo["alarmId"] as? String ?? ""
        let soundName = userInfo["soundName"] as? String ?? "Marimba"

        // 💡 关键修复：前台时不让系统播通知声音（系统声音无法中途停止，会响满 29s）
        //    改用 App 内 AVAudioPlayer 循环播放，右滑关闭时可立即 stop()
        DispatchQueue.main.async {
            self.wakeUpState?.triggerMission(for: alarmId)
            SoundManager.shared.playAlarmLoop(soundName: soundName)
        }
        // 不传 .sound —— 由 App 内接管声音播放，确保能被立即停止
        completionHandler([])
    }

    // 当用户点击了通知横幅时触发
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {

        let userInfo = response.notification.request.content.userInfo
        let requireMission = userInfo["requireMission"] as? Bool ?? false
        let alarmId = userInfo["alarmId"] as? String ?? ""
        let soundName = userInfo["soundName"] as? String ?? "Marimba"

        if requireMission {
            // 💡 点通知进入 App：此时系统已停止它自己的声音，改由 App 内 AVAudioPlayer 接管循环播放
            //    这样右滑关闭时才能立即停止（系统声音无法中途停止）
            DispatchQueue.main.async {
                self.wakeUpState?.triggerMission(for: alarmId)
                SoundManager.shared.playAlarmLoop(soundName: soundName)
            }
        } else {
            // 非任务闹钟：横幅点击直接关闭单次闹钟即可，无需接管声音
            DispatchQueue.main.async { AlarmManager.shared.disableOneTimeAlarm(id: alarmId) }
        }

        completionHandler()
    }
}
