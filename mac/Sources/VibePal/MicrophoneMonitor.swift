import AVFoundation

@MainActor
final class MicrophoneMonitor: ObservableObject {
    @Published var level: Double = 0
    @Published var errorMessage: String?

    private let engine = AVAudioEngine()
    private var hasTap = false

    static func normalizedLevel(decibels: Double) -> Double {
        min(max((decibels + 60) / 60, 0), 1)
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startEngine()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    if granted { self?.startEngine() }
                    else { self?.errorMessage = "需要麦克风权限才能测试" }
                }
            }
        default:
            errorMessage = "请在系统设置中允许 VibePal 使用麦克风"
        }
    }

    func stop() {
        engine.stop()
        if hasTap {
            engine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
        level = 0
    }

    private func startEngine() {
        guard !engine.isRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            let meanSquare = (0..<count).reduce(0.0) { $0 + Double(samples[$1] * samples[$1]) } / Double(max(count, 1))
            let decibels = 20 * log10(max(sqrt(meanSquare), 0.000_001))
            Task { @MainActor in self?.level = Self.normalizedLevel(decibels: decibels) }
        }
        hasTap = true
        do {
            engine.prepare()
            try engine.start()
            errorMessage = nil
        } catch {
            stop()
            errorMessage = "麦克风启动失败：\(error.localizedDescription)"
        }
    }
}
