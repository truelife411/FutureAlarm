import Foundation
import AVFoundation
import MediaPlayer

// MARK: - 系统音量管理器（闹钟响铃时临时提升系统音量，关闹钟后恢复）
final class VolumeManager {
    static let shared = VolumeManager()

    private let volumeView = MPVolumeView()
    private var savedVolume: Float?
    private var isBoosted = false

    private init() {}

    /// 把系统音量临时提升到用户设定的闹钟音量（或最大），绕过物理音量键的限制
    func boost() {
        guard !isBoosted else { return }
        let current = AVAudioSession.sharedInstance().outputVolume
        savedVolume = current
        isBoosted = true

        let target: Float = {
            let v = UserDefaults.standard.float(forKey: "AlarmVolume")
            return (v > 0.01) ? v : 1.0
        }()
        // 当前音量已经 ≥ 目标则无需调整
        if current >= target - 0.01 { return }

        setSystemVolume(target)
        print("🔊 系统音量已临时提升: \(String(format: "%.0f", current * 100))% → \(String(format: "%.0f", target * 100))%")
    }

    /// 恢复到闹钟响铃前的音量
    func restore() {
        guard isBoosted, let saved = savedVolume else { return }
        isBoosted = false
        savedVolume = nil
        setSystemVolume(saved)
        print("🔊 系统音量已恢复: \(String(format: "%.0f", saved * 100))%")
    }

    private func setSystemVolume(_ volume: Float) {
        guard let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider else {
            print("⚠️ 无法找到 MPVolumeView 滑块")
            return
        }
        // 异步放到下一个 runloop，避免在 MPVolumeView 还没布局完时设置失败
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            slider.value = max(0, min(1, volume))
        }
    }
}

// MARK: - 铃声定义
struct AlarmSound: Identifiable, Equatable {
    let id: String          // 文件名（不含扩展名，稳定键，不翻译）
    let displayName: String // 显示名（已废弃，保留仅为兼容；实际显示用 localizedDisplayName）
    let icon: String        // SF Symbol 图标

    // 💡 本地化显示名：按 id 查翻译表，跟随当前 App 语言
    var localizedDisplayName: String {
        switch id {
        case "Marimba":    return Localization.shared.t("sound.marimba")
        case "Classic":    return Localization.shared.t("sound.classicAlarm")
        case "Piano":      return Localization.shared.t("sound.pianoChord")
        case "Bird":       return Localization.shared.t("sound.morningBirds")
        case "Electronic": return Localization.shared.t("sound.electronic")
        case "Ocean":      return Localization.shared.t("sound.oceanWaves")
        default:           return id
        }
    }

    // 所有预设铃声（文件名必须与 Sounds 目录下的 .caf 文件一致）
    static let all: [AlarmSound] = [
        AlarmSound(id: "Marimba",    displayName: "马林巴琴", icon: "music.note"),
        AlarmSound(id: "Classic",    displayName: "经典闹钟", icon: "alarm"),
        AlarmSound(id: "Piano",      displayName: "钢琴和弦", icon: "pianokeys"),
        AlarmSound(id: "Bird",       displayName: "清晨鸟鸣", icon: "bird"),
        AlarmSound(id: "Electronic", displayName: "电子警报", icon: "bolt.fill"),
        AlarmSound(id: "Ocean",      displayName: "海浪声",   icon: "water.waves"),
    ]

    // 默认铃声
    static let `default` = all[0]

    // 通过 id 查找
    static func find(byId id: String) -> AlarmSound {
        all.first(where: { $0.id == id }) ?? .default
    }

    // 💡 用户配置的"默认铃声"（用于新建闹钟时的初始铃声）。存 UserDefaults。
    private static let defaultSoundKey = "DefaultAlarmSound"

    // 读取用户设定的默认铃声 id；未设置时回退到 Marimba（all[0]）
    static func defaultSoundId() -> String {
        UserDefaults.standard.string(forKey: defaultSoundKey) ?? AlarmSound.default.id
    }

    // 设置默认铃声 id
    static func setDefaultSoundId(_ id: String) {
        UserDefaults.standard.set(id, forKey: defaultSoundKey)
    }
}

// MARK: - 铃声试听管理器
@MainActor
class SoundManager: ObservableObject {
    static let shared = SoundManager()

    @Published var currentlyPlayingId: String?

    private var audioPlayer: AVAudioPlayer?

    private init() {
        // 💡 监听 audio session 中断（电话、FaceTime 等），中断结束后重启静音保活
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let interruptionType = AVAudioSession.InterruptionType(rawValue: type) else { return }
            if interruptionType == .ended {
                // 中断结束，如果后台引擎在运行就重启保活
                print("🔄 AudioSession 中断结束，恢复静音保活")
                Task { @MainActor in
                    self.startSilentKeepAlive()
                }
            }
        }
    }

    // 试听某个铃声（点击列表项时调用）
    func preview(sound: AlarmSound) {
        // 如果正在播放同一个铃声，则停止（再点一次 = 暂停）
        if currentlyPlayingId == sound.id {
            stop()
            return
        }

        stop()

        // 加载 bundle 里的音频文件
        guard let url = Bundle.main.url(forResource: sound.id, withExtension: "caf") else {
            print("⚠️ 找不到音频文件: \(sound.id).caf")
            return
        }

        do {
            // 配置音频会话：播放类别，忽略静音开关（试听时也响）
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = 0 // 只播放一次（试听）
            audioPlayer?.play()
            currentlyPlayingId = sound.id

            // 播放结束后自动清除状态
            let timer = Timer.scheduledTimer(withTimeInterval: (audioPlayer?.duration ?? 29) + 0.1, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    if self?.currentlyPlayingId == sound.id {
                        self?.currentlyPlayingId = nil
                    }
                }
            }
            RunLoop.current.add(timer, forMode: .common)
        } catch {
            print("⚠️ 试听失败: \(error.localizedDescription)")
        }
    }

    // 停止试听
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        currentlyPlayingId = nil
        // 💡 停止响铃时恢复系统音量
        VolumeManager.shared.restore()
    }

    // 💡 闹钟响铃：循环播放指定铃声（numberOfLoops = -1 无限循环），可被 stop() 立即停止
    // 前台响铃时用这个代替系统通知声音，解决"系统声音播完才能停"的问题
    func playAlarmLoop(soundName: String) {
        // 已经在循环播放同一个铃声，就不重复启动（轰炸后续通知到来时不打断已响的铃声）
        if currentlyPlayingId == soundName && audioPlayer?.isPlaying == true { return }

        guard let url = Bundle.main.url(forResource: soundName, withExtension: "caf") else {
            print("⚠️ 找不到闹钟铃声: \(soundName).caf")
            return
        }
        do {
            // ⚠️ 关键：不要重新 setCategory/setActive！
            // 后台时重新激活 audio session 可能失败/延迟，导致 AVAudioPlayer 不出声。
            // 静音保活已经把 session 设为 .playback 并激活，直接复用即可绕过静音开关。

            // 确保 session 是 active 状态（前台可能被其他操作打断）
            if !AVAudioSession.sharedInstance().isOtherAudioPlaying {
                try? AVAudioSession.sharedInstance().setActive(true)
            }

            // 💡 响铃时临时提升系统音量到用户设定值，关闹钟后恢复
            VolumeManager.shared.boost()

            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.numberOfLoops = -1  // 无限循环
            newPlayer.volume = 1.0         // AVAudioPlayer 自身满音量，实际响度由系统音量决定

            // 先启动闹钟音频，再停静音保活 —— 零间隙切换，系统不会挂起 App
            audioPlayer?.stop()
            audioPlayer = newPlayer
            audioPlayer?.play()

            // 闹钟已经开始播放，现在安全停止静音保活
            stopSilentKeepAlive()

            currentlyPlayingId = soundName
            print("🔊 闹钟铃声已开始循环播放: \(soundName)")
        } catch {
            print("⚠️ 闹钟铃声播放失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 静音保活（绕过静音开关的核心）
    // 播放一段静音音频循环，让 iOS 允许 App 在后台持续运行（UIBackgroundModes: audio），
    // Timer 得以每秒检查闹钟，到点用 playAlarmLoop 接管（.playback 类别绕过静音）。

    private var keepAlivePlayer: AVAudioPlayer?

    func startSilentKeepAlive() {
        // 已在保活则跳过
        if keepAlivePlayer?.isPlaying == true && AVAudioSession.sharedInstance().isOtherAudioPlaying == false {
            return
        }
        guard let data = makeSilentWAVData() else {
            print("⚠️ 无法生成静音保活音频")
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            keepAlivePlayer = try AVAudioPlayer(data: data)
            keepAlivePlayer?.numberOfLoops = -1   // 无限循环静音
            keepAlivePlayer?.volume = 0.01         // 💡 用极低音量代替 0，避免 iOS 认为"无音频"而挂起
            keepAlivePlayer?.play()
            print("🎧 静音保活已启动 (audioSession active=\(AVAudioSession.sharedInstance().isOtherAudioPlaying ? "mixing" : "exclusive"))")
        } catch {
            print("⚠️ 静音保活启动失败: \(error.localizedDescription)")
        }
    }

    func stopSilentKeepAlive() {
        guard keepAlivePlayer?.isPlaying == true else { return }
        keepAlivePlayer?.stop()
        keepAlivePlayer = nil
        print("🎧 静音保活已停止")
    }

    // 生成 1 秒静音 WAV（PCM 16-bit mono 44.1kHz）的内存 Data，避免文件 I/O
    private func makeSilentWAVData() -> Data? {
        let sampleRate = 44100
        let numSamples = sampleRate  // 1 秒
        let dataSize = numSamples * 2  // 16-bit = 2 bytes/sample

        var data = Data()
        // WAV header
        data.append("RIFF".data(using: .ascii)!)                            // ChunkID
        data.append(UInt32(36 + dataSize).littleEndianBytes)               // ChunkSize
        data.append("WAVE".data(using: .ascii)!)                            // Format
        data.append("fmt ".data(using: .ascii)!)                            // Subchunk1ID
        data.append(UInt32(16).littleEndianBytes)                           // Subchunk1Size (PCM)
        data.append(UInt16(1).littleEndianBytes)                            // AudioFormat (PCM)
        data.append(UInt16(1).littleEndianBytes)                            // NumChannels (mono)
        data.append(UInt32(sampleRate).littleEndianBytes)                   // SampleRate
        data.append(UInt32(sampleRate * 2).littleEndianBytes)               // ByteRate
        data.append(UInt16(2).littleEndianBytes)                            // BlockAlign
        data.append(UInt16(16).littleEndianBytes)                           // BitsPerSample
        data.append("data".data(using: .ascii)!)                            // Subchunk2ID
        data.append(UInt32(dataSize).littleEndianBytes)                     // Subchunk2Size
        // 静音 PCM 数据（全零）
        data.append(Data(count: dataSize))
        return data
    }
}

// UInt 小端字节序扩展（WAV 格式要求小端）
private extension UInt32 {
    var littleEndianBytes: Data {
        withUnsafeBytes(of: self.littleEndian) { Data($0) }
    }
}
private extension UInt16 {
    var littleEndianBytes: Data {
        withUnsafeBytes(of: self.littleEndian) { Data($0) }
    }
}
