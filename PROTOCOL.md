# Ulanzi Vibe Key (AU05) — 逆向笔记

设备: **Vibe Key**, 型号 **AU05**, USB VID `0xFFF1` / PID `0x00DD`
来源: 逆 Ulanzi Studio.app (Qt) + ustudio-cli (Node) + 真机 HID 抓包, 2026-08-24

## HID 接口
| usage page | usage | 用途 |
|---|---|---|
| 0x0001 | 0x06 | 标准键盘 ← 默认模式面键键码在这 |
| 0x000c | 0x01 | 消费控制 ← 拨盘音量 |
| 0x0001 | 0x02 | 鼠标 |
| 0x0001 | 0x01 | 指针 |
| 0xfffc | 0x01 | 厂商/控制口(加密) |

## 两种模式
- **默认模式(app 未激活)**: 按键走标准 HID,免加密免逆向。
- **自定义模式(app 发激活命令后)**: 按键改走 0xfffc 加密口,app 映射成宏。

## 控件 → 默认键码(行为测试, 填充中)
| 控件 | 默认行为/键码 |
|---|---|
| 🎤 麦克风 | **Fn / globe 键**(可触发听写) |
| ✓ | **Return/回车** ✅可读 |
| ✕ | **无**(默认哑, 仅自定义模式) ⚠ |
| 侧边键 | **无**(默认哑, 仅自定义模式) ⚠ |
| 拨盘按下 | **切换输入法**(疑 Ctrl+Space/Globe) ✅可读 |
| 拨盘转动 | 待测(疑似音量 Vol±,消费页 0xEA/0xE9) |

## 0xfffc 加密口(仅自定义模式)
- report id `0x55`, 定长 64 字节。
- 心跳: 每 ~10.1s 一帧, 内容恒定
  `55 9a e7 f3 05 32 03 f0 db` + `38 90 c4 99 a3 60 aa ad` 反复填充。
- 填充块 `38 90 c4 99 a3 60 aa ad` = 恒定明文的密文 → 静态密钥 ECB 类。
- **同一控件每次密文逐字节相同**(隔 10s 两按相同)→ 可不破解, 用密文查找表识别按键。
- 密钥疑似每台设备不同 → 若用此口, app 内做一次"学习按键"校准即可通用。
- BLE 路径有 `sendAuthMessage` 鉴权握手(libUlanziFZBle.dylib), 所以优先 USB。

## 待逆向
1. 每个面键默认发的标准键码(行为测试, 便宜)。
2. 每个状态对应的**输出帧**(点亮键盘 LCD/LED)— 需 sudo 抓 app 往 0xfffc 写的 USB 包。
   若输出也是"每状态一条静态帧", 抓 8 条回放即可, 无需破解。

## 结论(2026-08-24)
默认模式只有 ✓/🎤/拨盘可读, ✕ 与侧边键哑 → 要全键可编程 + 状态显示, 必须走自定义模式 + 输出协议, 只能靠 USB 抓包拿到。

## 输出方向抓到了(2026-08-24,lldb 动态)
- 注入(DYLD_INSERT)被 **AMFI 剥离**(app 公证出身,重签无效)→ 改用 **lldb Python 驱动**断点抓,成功。
- app 走 **IOKit `IOHIDDeviceSetReport`**(不是 hidapi hid_write)驱动 AU05。
- 输出帧同结构:`55 + 8字节密文块0 + 恒定填充 38 90 c4 99 a3 60 aa ad`,确定性。
- **输出是动画流**:app 持续 SetReport,多帧循环(抓到约 10 个不同 block0 各出现 ~23 次 = 动画在循环),不是"一状态一帧"。
- 疑似激活/握手帧(boot 时各出现 1 次):`55 79 1f a4...`(双数据块)、`55 86 d5 41...`、`55 45 36 9c...`、`55 08 8d 62...`。
- 加密:**64 位分组 ECB,收发共用同一静态密钥**(填充块两向一致)。
- 捕获工具已就绪:`scratchpad/driver.py`(lldb 断 IOHIDDeviceSetReport/GetReport)。
- 卡点:hook→app 触发状态在 lldb 下没生效,还不能按状态分别录流。

## 剩余工作(要全独立)
1. 定位 app 的加密/解密函数(lldb 断 SetReport 上溯调用栈)→ 拿明文命令格式 + 抠密钥/算法。
2. 有了密钥 → Rust 里实现 encode/decode,全独立、可发。密钥若每台不同则需按设备派生/校准。
3. 或退而求其次:录每状态密文流回放(中等,但密钥每台不同则不通用)。

## 加密定位(2026-08-24,调用栈)
- 发送路径:`kwdm.dylib` `-[KehwinDevice writeWorker]` → `-[HidDevice sendData:value:]` → IOKit `IOHIDDeviceSetReport`。
- **加密在 `kwdm.dylib`(Kehwin 厂商 SDK,体积小)** ,不在 Qt 主程序。
- 下一步:静态分析 kwdm.dylib 找 encrypt/decrypt + 密钥;或 lldb 断 `-[HidDevice sendData:value:]` 读明文参数拿 明文↔密文 对。
- 库路径:/Applications/Ulanzi Studio.app/Contents/Frameworks/ 下找 kwdm.dylib(或 KehwinDevice 相关)。

## 蓝牙可行性:不能(2026-08-24)
问题:官方 app 连不上蓝牙,第三方能否走 BLE?

**结论:AU05 的无线不是蓝牙,是 Nordic nRF 2.4GHz 私有协议 + 自带接收器。**

证据:
1. **BLE 栈只服务 TC002**:`libUlanziFZBle.dylib` 里唯一的设备名过滤是 `Ulanzi TC002`;
   主程序里 BLE 发现类叫 `Tc002Discovery`。TC002 是像素时钟,不是 Vibe Key。
2. **AU05 是两段式**,固件分别 OTA:
   - `[OTA Check] Dongle(AU05_USB)`  ← USB 接收器
   - `[OTA Check] Mic(AU05_Device)`  ← 手持设备(带麦克风)
   - `VibeOtaManager::performVibeKeyChainOta()` = 链式升级两端
3. **射频是 Nordic**:主程序字符串含 `NRF~#P`,配套 `DongleSN` / `DongleVersion` /
   `DongleReboot` / `DongleUpgradeProgress` / `Paired` / "continue to Dongle"。
4. 系统蓝牙已配对/已连接列表里没有 AU05;`device_source.json` 的 `MacAddress` 恒为空。

**对第三方开发的影响:是好消息。** 接收器同样以 USB HID 出现,所以有线/无线两种模式
第三方 app 走的是同一套 HID 代码,不用区分,也不用碰 BLE 鉴权(`BLEManager::sendAuthMessage`)。
注意:接收器的 PID 可能与手持直连不同,枚举时按 VID 0xFFF1 匹配、放宽 PID 更稳。

未做:实机 BLE 广播扫描(ad-hoc 签名工具被 TCC 拒,连 centralManagerDidUpdateState 都不触发)。
如需 100% 确认,用手机 nRF Connect / LightBlue 扫一次即可。

## 突破:kwdm.dylib 是完整导出的 C SDK(2026-08-24)
**加密不用破了。** `Contents/Frameworks/kwdm.dylib` = Kehwin 官方 SDK v2.0.47,
~130 个 C 函数全部导出,自带函数原型字符串。加密/鉴权/分帧它全包,回调吐明文 JSON。

已验证:`dlopen` → 注册回调 → `sdkInit("vibekey", true)` → "Open HID Manager Successfully"。
无需 Ulanzi Studio 运行,只需装着(我们不分发它的 dylib)。

### 关键 API(参数含义来自 SDK 自己的回调选择器)
| 函数 | 说明 |
|---|---|
| `sdkInit(const char*, bool)` / `sdkQuit()` | 初始化 / 退出 |
| `registerDeviceConnectedCallbackListener(cb)` | cb(deviceId) |
| `registerDeviceMessageCallbackListener(cb)` | cb(deviceId, 明文消息) |
| `setDeviceLedEffect(dev, mode, speed, bright, red, green, blue)` | **任意 RGB 灯效** |
| `setDeviceIndicatorLightCurrentMode(dev, int)` | 指示灯模式 |
| `setDeviceHooksMode(dev, int)` | AI hooks 模式开关 |
| `getDeviceBattery(dev)` | → `onMessageDeviceBattery:battery:voltage:charging:chargeFull:lowbat:powerOff:` |
| `setDeviceButtonShortcutFunction(dev, int, char*)` | 按键映射 |
| `startDeviceUploadImage(dev, path, int,int,int)` | LCD 图像上传 |
| `encrypt_data` / `decrypt_data` / `encode` / `decode` | 也导出了 —— v2 干净实现可拿它当预言机 |

### 按键事件
`onMessageDeviceKeyEvent:index:status:physicalIndex:` —— 按键给出 index / 按下抬起 / 物理位号。

### 设备身份
deviceId 是 UUID(如 `D750C26A-6EA7-4E8C-A04C-9CED56ED0DC2`),由连接回调下发。
日志确认 USB 端是接收器:`dongleSN=C3D33I021U3670476`,`dongleVersion=4.4.0`。

## 架构:daemon + socket
per-hook 开 SDK 要 2.7s,对每次 PreToolUse 都触发的 hook 不可用(官方也因此跑
`ustudio-cli --singleton-server`)。改成:
- `vibekey serve` 常驻,独占 SDK 与设备,监听 `$HOME/.vibekey.sock`
- `vibekey hook` 只写一行就退出 —— 实测 **0.01s**

未决(需硬件在场标定):`setDeviceLedEffect` 的 mode/speed/bright 取值范围未知,
已做成 `--mode/--speed/--bright` 命令行旋钮,设备一上线即可用 `getDeviceLedEffect` 读回真实值。

## 2026-08-25 追加验证(第三方客户端调研途中实测)

解码器落地为 `tools/tea.py`(纯 Python,无依赖,自带自检向量),可直接 `vibekey watch | python3 tools/tea.py`。

### 明文首字节判方向

| 首字节 | 方向 | 含义 |
|---|---|---|
| `0x0B` | 设备 → 主机 | 通知。`[1]=0x10` 按键、`[1]=0x7B` 电量 |
| `0x06` | 主机 → 设备 | 命令 |

**调试陷阱**:`vibekey watch` 会把本机 app 自己写出去的帧一并显示。看到 `0xfffc` 有流量不等于设备在说话,必须解密看首字节。本次就先把 VibePal 自己的心跳误判成了设备信号。

### 四个 boot 握手帧:确认了一个,还差三个

已知我方两条出站命令加密后的密文前缀:

| 明文 | 密文前 9 字节 | 对应 |
|---|---|---|
| `06 03 0A 01` (`activeQueryReport`) | `55 86 d5 41 50 44 19 ba cc` | **= PROTOCOL 里记的 `55 86 d5 41...`** ✅ |
| `06 01 23 00 01` (`heartbeatReport`) | `55 24 56 9e f2 28 e1 45 a1` | 8 秒心跳 |

即官方 app 在 boot 时发的四帧里,**我们只实现了其中一帧(Active 查询)**。另外三帧 `55 79 1f a4...`(双数据块)、`55 45 36 9c...`、`55 08 8d 62...` 仍是未知命令。

**推断(未验证)**:设备迟迟不进自定义模式、`0xfffc` 上收不到任何 `0x0B` 通知,很可能就是因为激活序列不完整——只发 Active 查询不够。

**下一步**:重跑 `driver.py` 的 lldb 抓包,拿到那三帧的**完整 8/16 字节密文**,用 `tools/tea.py` 解出明文命令,补进 `VibeProtocol`。密钥已知,拿到密文就是一步的事。

### 本次实测到的其它事实

- macOS 上 `0xfffc` 是**独占接口**:两个 hidapi 进程同时开会报 `(0xE00002C5) exclusive access and device already open`。调试时先确认没有遗留的 watcher。
- VibePal 加载了 `kwdm.dylib`,但**并不持有** `0xfffc`——它在跑的时候第三方仍能打开该接口。
- Ulanzi Studio 界面显示"已连接"时,`config/device.json`(Studio 的已连接设备表)里仍然没有 AU05,且 `0xfffc` 全程静默。"界面已连接" ≠ "自定义模式已激活"。

### Studio 侧的槽位表(来自厂商默认配置,非推断)

`~/Library/Application Support/Ulanzi/UlanziDeck/defProfile/AU05/Default_Profile/` 内的 profile manifest:

| Controller | 槽位 | 控件 | 出厂动作 |
|---|---|---|---|
| Keypad | `0_0` | 🎤 语音 | `Fn` |
| Keypad | `0_1` | ✓ 确认 | `Return` |
| Keypad | `0_2` | ✕ 取消 | `Esc` |
| Encoder | `0_3` | 旋钮 | `press=Return`、`rotate_left=↓`、`rotate_right=↑` |

- ✕ 键"默认无标准键码"只对**离线模式**成立;Studio 在跑时它是 `Esc`。
- **默认配置里只有 4 个控件,没有侧边键** —— 侧边键多半不是可编程键。
- Studio 3.2.11 把 AU05 当一等设备:`config/device_source.json` 里 `Model: AU05 / Name: "Vibe Key" / UUID: 41503533303032090100A85407400C78`。
