import SwiftUI

// MARK: - 动态绑定的毛玻璃闹钟卡片
// 外层负责「左滑露出按钮」+「整卡点击进入编辑」
// 内层负责具体内容渲染
struct DynamicGlassAlarmCard: View {
    let alarm: Alarm
    // 💡 点击整张卡片进入编辑的回调（由 ContentView 注入）
    var onEdit: (Alarm) -> Void

    // 💡 左滑相关状态
    @State private var offset: CGFloat = 0          // 当前左移量（负值）
    @State private var isOpen: Bool = false          // 是否处于「露出按钮」的展开态
    private let revealedWidth: CGFloat = 172          // = 70(编辑)+12(间距)+70(删除)+20(trailing)，刚好完整露出

    var body: some View {
        ZStack {
            // 1. 底层：左滑露出的操作按钮（编辑 + 删除）
            HStack(spacing: 0) {
                Spacer()
                HStack(spacing: 12) {
                    Button(action: {
                        closeThen { onEdit(alarm) }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 20, weight: .semibold))
                            Text(L("common.edit"))
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(width: 70, height: 80)
                        .background(Color.blue.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        closeThen {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    AlarmManager.shared.deleteAlarm(id: alarm.id)
                                }
                            }
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 20, weight: .semibold))
                            Text(L("common.delete"))
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(width: 70, height: 80)
                        .background(Color.red.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 20)
                .opacity(isOpen || offset < -5 ? 1 : 0)   // 拖动中才显现，避免常态闪现
                .animation(.easeOut(duration: 0.2), value: isOpen)
            }

            // 2. 上层：实际卡片内容，可被拖动
            CardContent(alarm: alarm, onEdit: onEdit)
                .offset(x: offset)
        }
        .contentShape(Rectangle())
        // 💡 点击空白处：仅用于收起左滑展开的按钮，不再进入编辑。
        // 编辑入口统一收敛到右下角「✎」按钮（见 CardContent Row 3），避免误触。
        .onTapGesture {
            if isOpen {
                close()
            }
        }
        // 🚨 左滑手势
        .gesture(
            DragGesture(minimumDistance: 15)
                .onChanged { value in
                    // 仅响应水平拖动，忽略垂直（交给 ScrollView 滚动）
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    let base: CGFloat = isOpen ? -revealedWidth : 0
                    let next = min(0, base + value.translation.width)   // 不允许往右超过起点
                    offset = max(next, -revealedWidth - 30)             // 留一点弹性
                }
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    let shouldOpen = isOpen
                        ? (value.translation.width < 30)   // 已展开，除非明显右滑否则保持
                        : (value.translation.width < -revealedWidth / 2)
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        isOpen = shouldOpen
                        offset = shouldOpen ? -revealedWidth : 0
                    }
                }
        )
        .padding(.horizontal, 20)
        .opacity(alarm.isOn ? 1.0 : 0.6)
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            isOpen = false
            offset = 0
        }
    }
    private func closeThen(_ action: @escaping () -> Void) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            isOpen = false
            offset = 0
        }
        // 等收起动画结束后再触发动作，视觉更顺滑
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { action() }
    }
}

// MARK: - 卡片实际内容（独立出来，避免手势干扰）
private struct CardContent: View {
    let alarm: Alarm
    var onEdit: (Alarm) -> Void

    // 💡 观察 localization：语言/时间格式变化时，卡片文案与时间显示即时刷新
    @EnvironmentObject private var localization: Localization

    // 💡 每分钟刷新一次，让指定日期闹钟的倒计时实时更新
    @State private var nowTick: Date = Date()
    private let tickTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.locale = Localization.shared.locale
        // 💡 根据时间格式设置：12 小时制用 hh:mm，24 小时制用 HH:mm
        formatter.dateFormat = (Localization.shared.timeFormat == .h24) ? "HH:mm" : "hh:mm"
        return formatter.string(from: alarm.time)
    }
    private var ampmString: String {
        // 💡 24 小时制不显示上午/下午
        if Localization.shared.timeFormat == .h24 { return "" }
        let formatter = DateFormatter()
        formatter.locale = Localization.shared.locale
        formatter.dateFormat = "a"
        return formatter.string(from: alarm.time)
    }
    private var tagsString: String {
        // 💡 类型文案（单次/重复/指定日期/极速）置顶，后接标签 / 铃声 / 任务标记
        var str = alarm.typeLabel
        str += " · \(alarm.label)"
        str += " · 🔔\(AlarmSound.find(byId: alarm.soundName).localizedDisplayName)"
        if alarm.requireMission { str += " ⚠️" }
        return str
    }

    // 💡 "下一次响铃"的相对日期文案：今天 / 明天 / 后天 / 其他显示具体日期
    // ⚠️ 不再自己调 nextTriggerDate，由 body 计算一次后传入，避免重复扫描 365 天。
    // 若已无下次响铃（如单次闹钟被跳过），回退到闹钟设定时间，不显示"已跳过"
    private func ringDateLabel(nextTrigger: Date?) -> String {
        let cal = Calendar.current
        let target = nextTrigger ?? alarm.time
        let calNow = cal.startOfDay(for: nowTick)
        let calTarget = cal.startOfDay(for: target)
        let dayDiff = cal.dateComponents([.day], from: calNow, to: calTarget).day ?? 0
        switch dayDiff {
        case 0:  return Localization.shared.t("card.today")
        case 1:  return Localization.shared.t("card.tomorrow")
        case 2:  return Localization.shared.t("card.dayAfter")
        default:
            let fmt = DateFormatter()
            fmt.locale = Localization.shared.locale
            // 中文内嵌"月/日"，英文用更自然的格式
            fmt.dateFormat = (Localization.shared.language == .zh) ? "M月d日" : "MMM d"
            return fmt.string(from: target)
        }
    }

    // 💡 倒计时文案，跟随当前语言（中文"还有 2天3小时 响" / 英文"Rings in 2d 3h"）
    // ⚠️ 不再自己读 nextRingDate，由 body 传入，统一基准为 nowTick（避免与日期标签不一致）。
    private func countdownText(nextTrigger: Date?) -> String {
        guard let target = nextTrigger else { return "" }
        let secs = target.timeIntervalSince(nowTick)
        if secs <= 0 { return Localization.shared.t("card.ringingSoon") }
        let days = Int(secs) / 86400
        let hours = (Int(secs) % 86400) / 3600
        let mins = (Int(secs) % 3600) / 60
        if days > 0 {
            return Localization.shared.t("countdown.dh", ["days": "\(days)", "hours": "\(hours)"])
        } else if hours > 0 {
            return Localization.shared.t("countdown.hm", ["hours": "\(hours)", "mins": "\(mins)"])
        } else {
            return Localization.shared.t("countdown.m", ["mins": "\(mins)"])
        }
    }

    var body: some View {
        // 💡 性能优化：一次渲染只调一次 NotificationScheduler.nextTriggerDate(for:)，
        // 重复闹钟的 365 天扫描成本较高；下游 ringDateLabel / countdownText 全部复用此值。
        // 同时统一基准为 nowTick，避免日期标签（用实时 Date）与倒计时（用 nowTick）出现 30s 不自洽。
        let nextTrigger = NotificationScheduler.shared.nextTriggerDate(for: alarm)

        return VStack(alignment: .leading, spacing: 5) {
            // Row 1: 日期标签 + 倒计时 + 闹钟开关
            HStack(alignment: .top) {
                // 💡 日期标签后接倒计时（中间用 · 分隔），节省一行空间
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ringDateLabel(nextTrigger: nextTrigger))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(alarm.isOn ? .purple : .purple.opacity(0.5))

                    if alarm.isOn && nextTrigger != nil {
                        Text("·")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.3))

                        Text(countdownText(nextTrigger: nextTrigger))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { alarm.isOn },
                    set: { newValue in
                        // 💡 直接写字段：didSet → handleChange 自动重排 + 持久化 + 重排通知，
                        //    无需手动 sortAlarms()，也不需要 asyncAfter 延迟重排
                        let targetId = alarm.id
                        if let idx = AlarmManager.shared.alarms.firstIndex(where: { $0.id == targetId }) {
                            AlarmManager.shared.alarms[idx].isOn = newValue
                        }
                    }
                ))
                .labelsHidden()
                .tint(Color.purple.opacity(0.8))
            }

            // Row 2: 时间 + 退回/跳过按钮（仅重复闹钟）
            HStack(alignment: .center) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(timeString)
                        .font(.system(size: 54, weight: .semibold, design: .rounded))
                        .foregroundColor(alarm.isOn ? .white : .white.opacity(0.4))

                    if !ampmString.isEmpty {
                        Text(ampmString)
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundColor(alarm.isOn ? .white.opacity(0.7) : .white.opacity(0.3))
                    }
                }

                Spacer()

                if alarm.isOn && alarm.isRepeatingAlarm {
                    HStack(spacing: 10) {
                        if !alarm.skippedDates.isEmpty {
                            Button(action: {
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                                let targetId = alarm.id
                                AlarmManager.shared.undoSkippedDate(of: targetId)
                            }) {
                                Text(L("card.undoSkip"))
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(Capsule())
                                    .foregroundColor(.white)
                            }
                        }

                        Button(action: {
                            let impact = UIImpactFeedbackGenerator(style: .rigid)
                            impact.impactOccurred()
                            let targetId = alarm.id
                            AlarmManager.shared.skipNextOccurrence(of: targetId)
                        }) {
                            Text(L("card.skipThis"))
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Capsule())
                                .foregroundColor(.white)
                        }
                    }
                }
            }

            // Row 3: 标签文案 + 编辑按钮
            HStack {
                Text(tagsString)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)

                Spacer()

                Button(action: { onEdit(alarm) }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.0)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
        )
        // 🚨 上下文菜单：编辑 + 删除（与左滑共存，长按可用）
        .contextMenu {
            Button(action: { onEdit(alarm) }) {
                Label(L("card.editAlarm"), systemImage: "square.and.pencil")
            }
            Button(role: .destructive, action: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        AlarmManager.shared.deleteAlarm(id: alarm.id)
                    }
                }
            }) {
                Label(L("card.deleteAlarm"), systemImage: "trash")
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: alarm.isOn)
        // 💡 倒计时刷新：定时器每 30s 触发 nowTick 更新，驱动 countdownString 重算
        .onReceive(tickTimer) { _ in
            nowTick = Date()
        }
    }
}
