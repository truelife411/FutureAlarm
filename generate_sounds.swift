import Foundation

// 简单的 WAV 文件写入器（生成 PCM 音频）
struct WAVWriter {
    static func write(samples: [Int16], to url: URL, sampleRate: Int = 44100) {
        var data = Data()
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate * Int(numChannels) * Int(bitsPerSample) / 8)
        let blockAlign = UInt16(numChannels * bitsPerSample / 8)
        let dataSize = UInt32(samples.count * 2)
        
        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(36 + dataSize).littleEndianBytes)
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndianBytes)
        data.append(UInt16(1).littleEndianBytes)
        data.append(numChannels.littleEndianBytes)
        data.append(UInt32(sampleRate).littleEndianBytes)
        data.append(byteRate.littleEndianBytes)
        data.append(blockAlign.littleEndianBytes)
        data.append(bitsPerSample.littleEndianBytes)
        data.append("data".data(using: .ascii)!)
        data.append(dataSize.littleEndianBytes)
        for s in samples { data.append(s.littleEndianBytes) }
        try? data.write(to: url)
    }
}

extension FixedWidthInteger {
    var littleEndianBytes: Data {
        var v = self.littleEndian
        return withUnsafeBytes(of: &v) { Data($0) }
    }
}

// 统一使用 Double 类型避免 Float16 推断问题
let sampleRate: Int = 44100
let duration: Double = 29.0
let totalSamples: Int = Int(Double(sampleRate) * duration)
let PI: Double = 3.14159265358979

func clamp(_ x: Double) -> Double { return max(-1.0, min(1.0, x)) }

// === 1. 马林巴琴铃声（C大调上行琶音）===
func generateMarimba() -> [Int16] {
    var samples = [Int16](repeating: 0, count: totalSamples)
    let notes: [(freq: Double, startTime: Double)] = [
        (523.25, 0.0), (659.25, 0.4), (783.99, 0.8), (1046.50, 1.2)
    ]
    let patternDuration: Double = 3.0
    
    for i in 0..<totalSamples {
        let t = Double(i) / Double(sampleRate)
        let cycleT = t.truncatingRemainder(dividingBy: patternDuration)
        var value: Double = 0
        for note in notes {
            let noteT = cycleT - note.startTime
            if noteT >= 0 && noteT < 1.5 {
                let envelope = exp(-noteT * 4.0)
                let f1 = sin(2 * PI * note.freq * noteT)
                let f2 = sin(2 * PI * note.freq * 2 * noteT) * 0.3
                let f3 = sin(2 * PI * note.freq * 3 * noteT) * 0.15
                let f4 = sin(2 * PI * note.freq * 4 * noteT) * 0.08
                let partial = (f1 + f2 + f3 + f4) * envelope
                value += partial
            }
        }
        samples[i] = Int16(clamp(value * 0.5) * 32767)
    }
    return samples
}

// === 2. 经典机械闹钟 ===
func generateClassicAlarm() -> [Int16] {
    var samples = [Int16](repeating: 0, count: totalSamples)
    let freq: Double = 2000.0
    for i in 0..<totalSamples {
        let t = Double(i) / Double(sampleRate)
        let pulseT = t.truncatingRemainder(dividingBy: 0.5)
        let squareWave: Double = (sin(2 * PI * freq * t) > 0) ? 1.0 : -1.0
        let envelope = exp(-pulseT * 15)
        let value = squareWave * envelope * 0.4
        samples[i] = Int16(clamp(value) * 32767)
    }
    return samples
}

// === 3. 温和钢琴和弦 ===
func generatePiano() -> [Int16] {
    var samples = [Int16](repeating: 0, count: totalSamples)
    let chordFreqs: [Double] = [261.63, 329.63, 392.00, 523.25]
    let patternDuration: Double = 4.0
    for i in 0..<totalSamples {
        let t = Double(i) / Double(sampleRate)
        let cycleT = t.truncatingRemainder(dividingBy: patternDuration)
        var value: Double = 0
        for freq in chordFreqs {
            let attack = min(1.0, cycleT * 20)
            let decay = exp(-cycleT * 1.2)
            let f1 = sin(2 * PI * freq * cycleT)
            let f2 = sin(2 * PI * freq * 2 * cycleT) * 0.4
            let f3 = sin(2 * PI * freq * 3 * cycleT) * 0.2
            let partial = (f1 + f2 + f3) * attack * decay
            value += partial
        }
        samples[i] = Int16(clamp(value * 0.25) * 32767)
    }
    return samples
}

// === 4. 鸟鸣 ===
func generateBirdChirp() -> [Int16] {
    var samples = [Int16](repeating: 0, count: totalSamples)
    for i in 0..<totalSamples {
        let t = Double(i) / Double(sampleRate)
        let cycleT = t.truncatingRemainder(dividingBy: 1.5)
        var value: Double = 0
        for chirpIndex in 0..<3 {
            let chirpStart = Double(chirpIndex) * 0.15
            let chirpT = cycleT - chirpStart
            if chirpT >= 0 && chirpT < 0.1 {
                let freq = 2500 + 1500 * (chirpT / 0.1)
                let envelope = sin(PI * chirpT / 0.1)
                value += sin(2 * PI * freq * chirpT) * envelope
            }
        }
        samples[i] = Int16(clamp(value * 0.4) * 32767)
    }
    return samples
}

// === 5. 电子警报 ===
func generateElectronicAlarm() -> [Int16] {
    var samples = [Int16](repeating: 0, count: totalSamples)
    for i in 0..<totalSamples {
        let t = Double(i) / Double(sampleRate)
        let isHigh = Int(t / 0.3) % 2 == 0
        let freq: Double = isHigh ? 1000.0 : 800.0
        let squareWave: Double = (sin(2 * PI * freq * t) > 0) ? 1.0 : -1.0
        let tremolo = 0.5 + 0.5 * sin(2 * PI * 5 * t)
        let value = squareWave * tremolo * 0.3
        samples[i] = Int16(clamp(value) * 32767)
    }
    return samples
}

// === 6. 海浪 ===
func generateOceanWaves() -> [Int16] {
    var samples = [Int16](repeating: 0, count: totalSamples)
    var rng = SystemRandomNumberGenerator()
    for i in 0..<totalSamples {
        let t = Double(i) / Double(sampleRate)
        let noise = Double.random(in: -1...1, using: &rng)
        let wave = 0.5 + 0.5 * sin(2 * PI * 0.33 * t)
        let value = noise * wave * 0.3
        samples[i] = Int16(clamp(value) * 32767)
    }
    return samples
}

// === 生成所有铃声 ===
let sounds: [(name: String, samples: [Int16])] = [
    ("Marimba", generateMarimba()),
    ("Classic", generateClassicAlarm()),
    ("Piano", generatePiano()),
    ("Bird", generateBirdChirp()),
    ("Electronic", generateElectronicAlarm()),
    ("Ocean", generateOceanWaves()),
]

let outputDir = "FutureAlarm/Sounds"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for (name, samples) in sounds {
    let wavPath = "\(outputDir)/\(name).wav"
    let cafPath = "\(outputDir)/\(name).caf"
    let wavURL = URL(fileURLWithPath: wavPath)
    WAVWriter.write(samples: samples, to: wavURL)
    
    let task = Process()
    task.launchPath = "/usr/bin/afconvert"
    task.arguments = ["-f", "caff", "-d", "ima4", "-c", "1", wavPath, cafPath]
    try? task.run()
    task.waitUntilExit()
    try? FileManager.default.removeItem(at: wavURL)
    print("✅ \(name).caf (\(samples.count) samples, \(String(format: "%.1f", Double(samples.count)/44100.0))s)")
}
print("\n🎉 全部 6 个铃声生成完毕！")
