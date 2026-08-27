import Foundation

/// 能力探测:把厂商 SDK 里所有「问」的接口打一遍,把设备回的原文按时间顺序落盘。
///
/// 为什么值得单独做一件事:`kwdm.dylib` 是 Ulanzi 多款设备共用的 SDK(里面还有
/// 空鼠、激光笔、放大镜那些演示器的功能),不能假设 AU05 都支持。设备自己知道答案 ——
/// `getDeviceSupport*` 一族就是用来问的。问一遍比逐个抓包猜快得多。
///
/// 回复是异步的、也不带调用序号,所以这里**不做**请求-响应配对:
/// 一份带时间戳的原文清单已经够定标了,配对反而会把猜测写进代码。
enum CapabilityProbe {
    /// `bool f(const char *deviceId)` 形式。名字都对着 dylib 的导出符号,有测试兜底。
    static let plain = [
        // 身份
        "getDeviceName", "getDeviceSN", "getDeviceUUID", "getDeviceId",
        "getDeviceVersion", "getDeviceHardwareVersion", "getDeviceFlashId",
        "getDeviceVendorId", "getDeviceProductId", "getDeviceMacAddress",
        "getDeviceActive", "getConnectionMode",
        // 这台到底支持什么 —— 整个探测最值钱的四条
        "getDeviceSupportButtonFunc", "getDeviceSupportMicrophone",
        "getDeviceSupportLedEffect", "getDeviceSupportCursorFunction",
        // 按键与旋钮
        "getDeviceAIButtonFunc", "getDeviceAudioButtonSystemMode", "getDeviceHooksMode",
        "getDeviceKeyPageUpLongPressFunction", "getDeviceKeyPageDownLongPressFunction",
        "getDeviceWheelEnableStatus", "getDeviceWheelLevel",
        // 灯与屏
        "getDeviceIndicatorLightAllParams", "getDeviceLedEffect",
        "getDeviceBrightness", "getDeviceLcdGifParam",
        // 麦克风
        "getDeviceMicrophoneEnable", "getDeviceMicNRLevel", "getDeviceMicrophoneUIFlickMode",
        // 震动
        "getDeviceMotorStrength", "getDeviceMotorVibrationParams",
        // 电源
        "getDeviceBattery", "getDeviceChargingStatus", "getDeviceSleepTime",
        "getDeviceStandbyTime", "getDeviceStandbyStatus", "getDeviceScreenShutdownTime",
    ]

    /// `bool f(const char *deviceId, int index)` 形式,逐个按键问。
    static let indexed = [
        "getDeviceButtonFunc", "getDeviceButtonParam",
        "getDeviceButtonShortcutFunction", "getDeviceButtonShortcutFunction2",
    ]

    /// 问到第几号按键为止。设备只有六个控件,多问两个是为了看编号从 0 还是 1 起。
    static let indexRange = 0..<8

    /// 两次调用的间隔。SDK 一次性灌太多请求会丢回复。
    /// ponytail: 0.12s 是拍的,真机上回复不全就往大调。
    static let spacing: TimeInterval = 0.12

    /// 打完最后一发之后再等多久收尾 —— 回复是异步的。
    static let tail: TimeInterval = 2.0
}

extension DeviceMonitor {
    /// 跑一次能力探测,完成后把报告落盘并回调路径。设备不在线直接回 nil。
    func runCapabilityProbe(completion: @escaping (URL?) -> Void) {
        guard let dev = deviceID, !probing else { completion(nil); return }

        probing = true
        probeStart = Date()
        probeLog = [
            "# VibePal 能力探测",
            "# 时间: \(ISO8601DateFormatter().string(from: Date()))",
            "# 设备: \(dev)   SDK: \(sdkVersion ?? "?")",
            "# 「→」是我们发出的调用和它的返回值,缩进行是设备回的原文。",
            "",
        ]

        var queue: [(String, () -> Bool)] = CapabilityProbe.plain.map { name in
            (name, { [weak self] in self?.call(name, dev) ?? false })
        }
        for name in CapabilityProbe.indexed {
            for i in CapabilityProbe.indexRange {
                queue.append(("\(name)(\(i))", { [weak self] in
                    self?.askIndexed(name, dev, Int32(i)) ?? false
                }))
            }
        }

        var next = 0
        Timer.scheduledTimer(withTimeInterval: CapabilityProbe.spacing, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard next < queue.count else {
                timer.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + CapabilityProbe.tail) {
                    self.probing = false
                    completion(self.writeProbeReport())
                }
                return
            }
            let (label, run) = queue[next]
            next += 1
            self.probeLog.append("→ \(label) = \(run())")
        }
    }

    private func writeProbeReport() -> URL? {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VibePal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        let name = "probe-" + stamp.string(from: Date()).replacingOccurrences(of: ":", with: "") + ".txt"
        let url = dir.appendingPathComponent(name)

        do {
            try (probeLog.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            vlog("probe 报告: \(url.path)")
            return url
        } catch {
            vlog("probe 写入失败: \(error)")
            return nil
        }
    }
}
