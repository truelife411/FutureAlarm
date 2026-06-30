import SwiftUI

// MARK: - 液态玻璃风格防赖床任务界面（与闹钟主界面风格统一）
struct WakeUpMissionView: View {
    @ObservedObject var wakeUpState: WakeUpState

    // 滑动解锁状态
    @State private var dragOffset: CGSize = .zero
    @State private var isUnlocked = false
    let buttonWidth: CGFloat = 300
    let triggerDistance: CGFloat = 200

    var body: some View {
        ZStack {
            // 1. 液态玻璃背景：直接复用主界面的 LiquidBackgroundView，保证风格完全一致
            LiquidBackgroundView()

            // 2. 警报脉冲光圈（解锁前持续扩散，用紫色呼应主界面，不再铺满全屏）
            Circle()
                .stroke(
                    AngularGradient(colors: [Color.purple.opacity(0.9), Color.pink.opacity(0.6), Color.purple.opacity(0.9)],
                                    center: .center),
                    lineWidth: 3
                )
                .frame(width: 240, height: 240)
                .scaleEffect(isUnlocked ? 0.1 : 3.2)
                .opacity(isUnlocked ? 0.0 : 0.5)
                .animation(isUnlocked
                           ? .easeOut(duration: 0.4)
                           : .easeOut(duration: 1.8).repeatForever(autoreverses: false),
                           value: !isUnlocked)

            VStack(spacing: 50) {
                // 顶部巨大的时间与提示
                VStack(spacing: 18) {
                    Image(systemName: "alarm.waves.fill")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(colors: [.purple, .pink],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .shadow(color: .purple.opacity(0.6), radius: 20)

                    Text(L("wake.title"))
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)

                    Text(L("wake.instruction"))
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.top, 90)

                Spacer()

                // 滑动解锁组件
                ZStack(alignment: .leading) {
                    // 滑动槽 —— 毛玻璃质感（与卡片一致）
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                        .frame(width: buttonWidth, height: 80)

                    Text(L("wake.slideHint"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(width: buttonWidth, alignment: .center)

                    // 可滑动的按钮 —— 紫色渐变玻璃球，与主界面开关色调一致
                    Capsule()
                        .fill(
                            LinearGradient(colors: [Color.purple.opacity(0.85), Color.pink.opacity(0.7)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1)
                        )
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: "bell.slash.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .shadow(color: .purple.opacity(0.4), radius: 12, x: 0, y: 4)
                        .offset(x: dragOffset.width)
                        .gesture(
                            DragGesture()
                                .onChanged { gesture in
                                    // 限制只能向右滑动，且不超过槽的宽度
                                    if gesture.translation.width > 0 && gesture.translation.width < (buttonWidth - 80) {
                                        dragOffset = gesture.translation
                                    }
                                }
                                .onEnded { gesture in
                                    // 如果滑动的距离超过了触发阈值，就解锁
                                    if gesture.translation.width > triggerDistance {
                                        withAnimation(.spring()) {
                                            dragOffset.width = buttonWidth - 80
                                            isUnlocked = true
                                        }

                                        // 震动反馈
                                        let generator = UINotificationFeedbackGenerator()
                                        generator.notificationOccurred(.success)

                                        // 💡 立即停止铃声：取消后续轰炸通知 + 停止 App 内播放的音频
                                        if let activeId = wakeUpState.activeAlarmId {
                                            NotificationScheduler.shared.cancelPendingBombardment(for: activeId)
                                        }
                                        SoundManager.shared.stop()
                                        UNUserNotificationCenter.current().removeAllDeliveredNotifications()

                                        // 立即关闭界面
                                        wakeUpState.completeMission()
                                    } else {
                                        // 没滑够距离，弹回原位
                                        withAnimation(.spring()) {
                                            dragOffset = .zero
                                        }
                                        let generator = UIImpactFeedbackGenerator(style: .rigid)
                                        generator.impactOccurred()
                                    }
                                }
                        )
                }
                .padding(.bottom, 100)
            }
        }
    }
}
