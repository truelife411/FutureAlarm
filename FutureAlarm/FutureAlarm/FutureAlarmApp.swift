import SwiftUI
import UserNotifications

// 💡 主屏幕快捷动作标志位存 UserDefaults，避免 SwiftUI 生命周期导致的
// singleton/State 时序问题。AppDelegate 设值，ContentView 在 onAppear/onChange 读取。
private let shortcutKey = "PendingAddAlarmShortcut"

@main
struct FutureAlarmApp: App {
    @StateObject private var wakeUpState = WakeUpState()
    @StateObject private var localization = Localization.shared

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(localization)
                .onAppear {
                    appDelegate.notificationDelegate.wakeUpState = wakeUpState
                    // 💡 App 启动时启动后台闹钟引擎（静音保活 + 定时检测）
                    BackgroundAlarmEngine.shared.refresh()
                }
                .fullScreenCover(isPresented: $wakeUpState.isShowingMission) {
                    WakeUpMissionView(wakeUpState: wakeUpState)
                }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UIWindowSceneDelegate {
    let notificationDelegate = NotificationDelegate()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        UIApplication.shared.shortcutItems = nil
        if let shortcut = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            handleShortcut(shortcut)
        }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // 💡 修复冷启动问题：冷启动时 shortcutItem 不一定通过 launchOptions 传进来，
        // 而是会在 options.shortcutItem 里传递给 Scene！
        if let shortcut = options.shortcutItem {
            handleShortcut(shortcut)
        }

        let config = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        config.delegateClass = AppDelegate.self
        return config
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        let ok = handleShortcut(shortcutItem)
        completionHandler(ok)
    }

    private func handleShortcut(_ item: UIApplicationShortcutItem) -> Bool {
        guard item.type == "com.futurealarm.addAlarm" else { return false }
        UserDefaults.standard.set(true, forKey: shortcutKey)
        return true
    }
}
