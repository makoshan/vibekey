# 宏键盘 / 宏软件开源生态调研

> 调研日期：2026-08-25。所有结论标注来源与观察方式，区分「读到的事实」与「推断」。
> 起因：调研 https://github.com/zclucas/RMT 及宏键盘开源软件，为 VibeKey（AU05 第三方客户端）找参考。

---

## 00. 一句话结论

RMT 跟 VibeKey **不同层**（它是 Windows 上的纯软件宏引擎，没有硬件），能借鉴的是**动作执行层的架构**，不是设备层。

但顺着这条线挖到三个**直接命中 VibeKey 的东西**，价值远大于 RMT 本身：

1. `brendanwelsh/ulanzi-d100h-homebrew` — 同 VID `0xFFF1`（KEHWIN BLE 芯片组）姊妹机的社区逆向笔记；
2. **UlanziDeck 官方插件 SDK 是公开的、Apache-2.0、可商用**，WebSocket `127.0.0.1:3906`，Node 主服务；
3. `UlanziTechnology/OpenCodexMicro`（2026-08-24 推送）— **Ulanzi 官方自己做的 "Codex 任务状态盘" 插件**，跟 VibeKey 的产品设想高度重叠。

对应一个**便宜实验**（见 04 节）：先花半小时验证 AU05 能不能挂官方插件，再决定要不要继续啃 TEA 输出帧。

---

## 01. RMT（若梦兔）是什么

来源：GitHub API + `README.en.md` + `CLAUDE.md`（master 分支，2026-08-25 读取）

| 项 | 值 |
| --- | --- |
| 仓库 | https://github.com/zclucas/RMT |
| Star / Fork | 1088 / 89（2026-08-25） |
| 语言 | AutoHotkey v2，Windows only（x64 + x86 发行版） |
| License | **AGPL-3.0** |
| 创建 / 最近推送 | 2025-01-07 / 2026-08-25（活跃） |
| 最新 Release | RMTv1.2.1（2026-08-23） |
| 文档 | https://zclucas.github.io/RMT/ |

**它不是宏键盘。** 没有任何硬件、HID、固件成分。它是"键鼠手柄宏 + 视觉自动化（图像/颜色/OCR）+ 逻辑控制 + 多线程"的 Windows 桌面工具，主力场景是游戏辅助和办公自动化，社群在 QQ 群 / B 站。

### 1.1 值得抄的架构（来自仓库自带的 CLAUDE.md）

```
RMT.ahk (入口)
  └─ Main/BindUtil.ahk          全局热键注册与触发       ← 触发层
     Main/TriggerKeyData.ahk    触发键数据结构
     Main/WindowHotkeyManager   按窗口/进程区分热键
  └─ Main/DataClass.Ahk         宏数据结构（58KB）        ← 数据层
  └─ Main/Util/MacroUtil.ahk    OnTriggerMacroOnce()     ← 执行层核心
  └─ Main/WorkPool.ahk          多线程调度（44KB）
     Thread/Work.exe            worker 编译成独立 exe，共享内存 + RingBuffer 通信
  └─ Plugins/                   OpenCV / RapidOcr / ViGEm / AhiDriver / C# RMT.dll
```

四点对 VibeKey 有用：

1. **"新增一条指令"是文档化的 5 步流程**（路径注册 → 数据结构 → GUI → 编辑器入口 → `OnTriggerMacroOnce` 分支）。VibeKey 现在 `ShortcutRunner` 只有"注入组合键 / 粘贴文本"两种动作，早晚要扩，先把这个扩展点定义清楚比事后重构便宜。
2. **触发与执行解耦**：触发层只产出 `(控件, 状态, 上下文窗口)`，执行层查表。VibeKey 已经是这个形状（`DeviceMonitor` → `ProfileStore` → `ShortcutRunner`），继续保持。
3. **按前台进程区分映射**（`WindowHotkeyManager`）。VibeKey 的场景是 Claude Code / Codex / 相册整理，天然需要"当前 App 决定按键含义"，这是刚需不是锦上添花。
4. **配置分享仓库** https://zclucas.github.io/RMT-Setting/ — 一个纯静态站承载社区宏配置。对 VibeKey 是零成本的社区冷启动方案（预设 JSON + GitHub Pages）。

### 1.2 不建议抄的

- AHK v2 全栈（Windows only，与 macOS 无关）；
- worker 编译成独立 exe + 共享内存的 IPC（AHK 没有真线程的历史包袱，Swift/Rust 不需要）；
- 单文件 113KB 的 `MacroEditGui.ahk`。

---

## 02. 直接命中 AU05 的三个发现

### 2.1 姊妹机逆向笔记：ulanzi-d100h-homebrew

来源：https://github.com/brendanwelsh/ulanzi-d100h-homebrew （2026-08-25 读取 docs/ 全部）

D100H Dial Creative Controller，**VID `0xfff1` / PID `0x0082`**，厂商串 `KEHWIN`、产品串 `Dial_Lite`。

> `0xfff1` 是 BLE 控制器芯片组带来的通用/未注册 VID，所以设备看起来完全不像 "Ulanzi"。
> Ulanzi 的**有线**产品线（如 D200）用的是 VID `0x2207`，D100H 不是。

**AU05 也是 `0xFFF1`** → 与 D100H 同一 BLE 芯片组家族，同一 ODM。它的笔记因此有参考价值。

对照表（D100H 观察 vs AU05 已知）：

| 维度 | D100H（社区笔记） | AU05（本项目 PROTOCOL.md） |
| --- | --- | --- |
| VID | `0xfff1` | `0xfff1` ✅ 同 |
| PID | `0x0082` | `0x00dd` |
| 厂商口 | `0xfff1/0x01`、`0xfffd/0x01`，**只观察到心跳** | `0xfffc/0x01`，心跳 ~10.1s + 按键流 |
| 厂商口加密 | 未讨论（只有心跳，没往下走） | **TEA，32 轮，delta 0x9E3779B9，8 字节 ECB，静态 128 位密钥** |
| 默认模式 | 消费页可读（音量/媒体），键盘页 Windows 不给读 | 消费页 + 键盘页，✕ 键与侧边键默认哑 |
| 自定义配置能否下发到设备 | **不能**。关掉 Studio 立刻回落出厂映射，没有 "Save to device" | 未验证，但同架构 |

**最有价值的一条**：D100H 作者花最多时间确认的结论是 —— *自定义映射不落盘到设备，Studio 一关就回落*。如果 AU05 同理（大概率，同 ODM 同架构），那么**任何第三方客户端都必须常驻**，"配好就撒手"这条路根本不存在。这一条直接决定 VibeKey 的产品形态，值得单独真机验证一次。

工具：`tools/sniff.js`（node-hid，几十行，列 HID 设备 + dump 所有接口原始报文）。比 lldb 那套轻，适合做默认模式的快速回归验证。

**待验证（未做）**：AU05 是否也存在第二个厂商口（D100H 有 `0xfff1` 和 `0xfffd` 两个）。本项目目前只记录了 `0xfffc`。

### 2.2 UlanziDeck 官方插件 SDK 是公开的

来源：`UlanziTechnology/UlanziDeckPlugin-SDK`（78 star，Apache-2.0，2026-07-17 推送）、
`plugin-common-node`、`plugin-common-html`、以及 d100h-homebrew 里 vendor 的一份完整 `ulanzi-api/README.md`。

这是一套 **Stream Deck SDK 的克隆**：

```
com.ulanzi.<name>.ulanziPlugin/
├── manifest.json          # 插件 UUID 必须正好 4 段，Action UUID 必须 >4 段
├── plugin/app.js          # Node v20 主服务，常驻
├── property-inspector/    # 配置页（webview）
└── ulanzi-api/            # SDK，唯一运行时依赖是 ws
```

- 宿主启动主服务时传 `argv[2]=address(127.0.0.1)`、`argv[3]=port(3906)`、`argv[4]=language`；
- 事件：`onRun` / `onKeyDown` / `onKeyUp` / `onAdd` / `onClear`，旋钮 `onDialRotate`（`'left'|'right'|'hold-left'|'hold-right'`）/ `onDialDown` / `onDialUp`；
- 回写显示：`setStateIcon(context, stateIndex, text)` —— **这正是 VibeKey 想要的"状态写回设备"，而且不用碰 TEA**；
- macOS 安装路径：`~/Library/Application Support/Ulanzi/UlanziDeck/Plugins/`；
- **Apache-2.0，明确允许商业 / 闭源插件**，投稿邮箱 `service@ulanzi.com`，市场在 https://ugc.ulanzistudio.com/home/1 。

`manifest.md` 里 `Devices` 字段枚举的机型是 `D200 | D200H | Dial | D200X` —— **没有 AU05**。但该字段留空 = 全部机型，OpenCodexMicro 的所有 action 就没写 `Devices`。所以 AU05 能否绑定属于**未验证**，是 04 节实验要回答的问题。

已知坑（d100h 作者踩过）：`decodeContext(context)` 返回 `{uuid, key, actionid}`，其中 `uuid` 才是 action 类型，`actionid` 是每次放置生成的实例 GUID。拿 `actionid` 去比对 action 类型永远不匹配，症状是"插件加载正常、动作能拖上去、按了没反应"。

### 2.3 Ulanzi 官方已经做了 Codex 状态盘

来源：https://github.com/UlanziTechnology/OpenCodexMicro （4 star，2026-08-24 推送，即调研前一天）

> "Control Codex Desktop from an Ulanzi D200 Series through Ulanzi Studio."
> "The entire project was vibe-coded with Codex."

它做的事：把 Codex 的实时 Micro 状态通过本地 Bridge 暴露出来，做成 Ulanzi Studio 插件 —— 5 个任务键显示 **idle / working / complete / attention / error** 五种状态，加上 Fast / Usage / Pin / New / Fork / Steer / Mic / Submit 控制键，旋钮滚任务列表。macOS 13+，Ulanzi Studio 3.0.1+。

**这跟 VibeKey 的状态机几乎一样**（本项目定义了 idle / thinking / working / error / attention / notification / sweeping / sleeping 八态）。

含义分两面：

- **坏消息**：这个产品设想 Ulanzi 官方已经在做，而且是官方渠道分发，只支持 D200 系列 + 只对 Codex。
- **好消息**：它证明了 (a) 走插件路能拿到状态回写能力，(b) 官方乐见其成甚至自己下场，(c) VibeKey 的差异化空间清楚了 —— **支持 Claude Code、覆盖 AU05 这个官方没做的机型、不依赖 Studio 常驻**。第三点是唯一必须啃 TEA 才能拿到的差异化。

顺带：仓库里有 `poc/codex-micro-usb/virtual_codex_micro.c` + `virtual-hid.entitlements.plist` —— 官方也试过在 macOS 上造虚拟 HID 设备。

### 2.4 有线机型的完整逆向先例

`jcalado/companion-surface-d200`（MIT）—— Bitfocus Companion 的 Ulanzi D200/D200X surface 插件，13 键 5×3、196×196 图标、亮度控制、状态窗七种模式。
**线协议是用 USBPcap 抓 Ulanzi Studio 抓出来的**，参考了 `redphx/strmdck`。写法：https://jcalado.com/posts/ulanzi-d200-companion/

对 VibeKey 的意义：D200 是 VID `0x2207` 的有线盘，协议跟 AU05 的 `0xFFF1` + TEA 不是一套，**代码不能直接搬**。但它证明了"逆完 Ulanzi 私有协议 → 做成通用宿主的一个 surface"这条路走得通，且 MIT 可参考实现方式。

---

## 03. 通用宏键盘开源生态（背景）

### 3.1 固件侧（可编程键盘的主流答案）

| 项目 | 语言 | 定位 |
| --- | --- | --- |
| **QMK** | C | 事实标准，功能最全最稳，**仅有线** |
| **VIA** | — | QMK 之上的实时改键，免重刷固件，桌面 + Web 双端 |
| **Vial** | — | VIA 的开源版，多支持编码器、tap-dance、combo、**设备端存宏** |
| **KMK** | CircuitPython | 主打无线 / DIY，代价是延迟与内存 |
| **ZMK** | C | 无线（BLE）方向的主力 |

关键对照：QMK/VIA/Vial 系设备把配置**存在键盘里**（raw HID 口 `0xFF60`，公开协议，主机 App 关掉照常工作）。
**AU05、D100H、D200 全是反面**：配置存在主机、宿主 App 必须常驻。这不是 bug，是这类"带屏创作者控制器"的通用商业设计（Stream Deck 也一样）。所以 VibeKey 注定是常驻应用，不要试图做成"配一次就走"。

### 3.2 宿主侧（Stream Deck 类）

- **`nekename/OpenDeck`** — Rust + Tauri v2 后端 / SvelteKit 前端，**兼容原版 Elgato Stream Deck 插件**，也支持 OpenAction API。v2.11.1（2026-04）。**架构上跟 VibeKey 最像**，Rust 技术栈也对得上，值得读它怎么组织 device backend / plugin host / profile store 三层。
- **Macro Deck 2**、**Deckboard** — 手机当宏面板，Windows/Linux。
- **`python-elgato-streamdeck`** — 逆向出来的 Stream Deck 协议库，多 HID backend 抽象，是"第三方驱动闭源硬件"的教科书实现。
- Den Delimarsky 的两篇逆向记录（Stream Deck / Stream Deck Plus），方法论可直接套。

### 3.3 便宜宏键盘的第三方配置软件（跟 VibeKey 同一问题类）

- **`rOzzy1987/MacroPad`**（C#，435★）—— *"你买了个中国宏键盘，配套软件看不懂？我也是。"* 逆了一批廉价宏盘的配置协议，且比原厂软件做得好：**按硬件扫描码处理**，非美式键盘布局也能正确录制回放。
- **`kamaaina/macropad_tool`**（Rust，181★）—— 同类，Rust 实现，Linux/Win/macOS，支持层、LED。作者动机写得很直白：卖家只给一个 Google Drive 上的 Windows exe，可疑、且没暴露全部硬件能力。
- **`prcutler/awesome-macropad`**（358★）—— 生态导航。

### 3.4 逆向参考资料

- **openrazer wiki / Reverse-Engineering-USB-Protocol** — 私有 HID 协议逆向的标准流程文档。
- **libratbag / piper**、**OpenRGB** — 社区维护的外设私有协议数据库，看它们怎么组织"每设备一个 driver + 共享抽象"。
- **Solaar**（Logitech）— 厂商私有 HID++ 协议的完整开源实现。
- **USBPcap + Wireshark**（Windows）/ 本项目已有的 lldb 断 `IOHIDDeviceSetReport`（macOS）。

---

## 04. 建议：先做一个半小时的实验

现状：VibeKey 已经解出 TEA 密钥、能解密电量与按键通知，**卡在输出方向**（状态动画流写回设备）。这是最贵的一段。

在继续啃之前，先回答一个问题：**AU05 能不能挂 UlanziDeck 插件？**

实验（不改任何现有代码）：

1. 从 `UlanziTechnology/UlanziDeckPlugin-SDK` 的 demo 拷一个最小插件，UUID 用 4 段，action 用 `Controllers: ["Keypad"]` 且**不写 `Devices` 字段**；
2. 丢进 `~/Library/Application Support/Ulanzi/UlanziDeck/Plugins/`，重启 Ulanzi Studio；
3. 看 AU05 的按键配置面板里能不能选到这个 action；
4. 能选到 → 拖上去，按一下看 `onRun` 有没有到；再试 `setStateIcon` 能不能改设备显示。

三种结果，三条路：

| 结果 | 含义 | 建议 |
| --- | --- | --- |
| action 能绑 + `setStateIcon` 生效 | 状态回写这段**可以不逆**，Studio 代劳 | 双轨：插件版先发（几天，覆盖 Claude Code，官方只做了 Codex），独立版慢慢磨 |
| action 能绑但没有显示回写 | 输入能白嫖，输出仍需逆 | 输入侧改用插件（省掉 TEA 解密维护），继续逆输出帧 |
| AU05 根本不在 Studio 的插件设备列表里 | 官方还没把 Vibe Key 纳入 UlanziDeck | 只能走现有全逆向路线 —— 但至少确认了没有捷径，不再犹豫 |

顺带另一个便宜验证：**关掉 Ulanzi Studio，看 AU05 的自定义映射还在不在。** D100H 的答案是"立刻回落出厂映射"。如果 AU05 一样，就坐实了"第三方客户端必须常驻"，产品文案和 onboarding 要照这个写。

---

## 04b. 实验结果（2026-08-25 实测，Studio 3.2.11 / macOS）

探针插件已装在 `~/Library/Application Support/Ulanzi/UlanziDeck/Plugins/com.ulanzi.vibeprobe.ulanziPlugin/`，
两个动作（Keypad + Encoder，`Devices` 留空），主服务把每个 SDK 事件按 JSONL 写进同目录 `probe.log`。

### 已证实

| # | 结论 | 证据 |
| --- | --- | --- |
| 1 | **AU05 是 Studio 的一等设备** | `config/device_source.json`: `{Model: "AU05", Name: "Vibe Key", Type: "AU05", UUID: "41503533303032090100A85407400C78"}`；`defProfile/AU05/` 与 D200/D200H/D200X/Dial 并列 |
| 2 | **第三方插件在 macOS 上能加载并连上** | `probe.log`: `boot argv=["127.0.0.1","3906","zh-CN"] node v20.18.0` → `connected ok`。与 SDK 文档的 argv 约定完全一致 |
| 3 | **AU05 的槽位接受插件动作绑定** | 把 `vibeprobe.key` 绑到 Keypad `0_2`、`vibeprobe.dial` 绑到 Encoder `0_3` 后重启 Studio，两个都收到 `add` + `setactive:true`，`decodeContext` 正常解出 `{uuid, key, actionid}` |
| 4 | **SDK `manifest.md` 里 `Devices` 枚举不含 AU05 不是障碍** | 留空 = 全设备，实测 AU05 生效 |

### 官方默认配置给出的完整槽位表

来自 `defProfile/AU05/Default_Profile/Default Profile.ulanziDeckProfile` 内的 profile manifest：

| Controller | 槽位 | 控件 | 出厂动作 |
| --- | --- | --- | --- |
| Keypad | `0_0` | 🎤 语音 | Hotkey `Fn` |
| Keypad | `0_1` | ✓ 确认 | Hotkey `Return` |
| Keypad | `0_2` | ✕ 取消 | Hotkey `Esc` |
| Encoder | `0_3` | 旋钮 导航 | `knob_press=Return`、`knob_rotate_left=↓`、`knob_rotate_right=↑` |

两点更正/补充 PROTOCOL.md：

- ✕ 键"默认无标准键码"只对**离线模式**成立；Studio 在跑时它是 `Esc`。旋钮按下同理，出厂是 `Return`，本机当前被改成 `⌃Space`（与"切换输入法"的观察吻合）。
- **默认配置里只有 4 个控件，没有侧边键。** 侧边键很可能不是可编程键（模式/配对键），与"侧边键默认哑"一致。

### 卡住的地方：设备没进自定义模式

用仓库自带的 `vibekey watch` 监听 `0xfffc`，**25 秒零帧**——PROTOCOL.md 记录的 ~10.1s 心跳完全没有出现，Studio 正在运行也一样。

- `vibekey list` 能看到 AU05 的全部 5 个 HID 接口（含 `0xfffc usage=0x01`），设备在 USB 上（`USB Product Name = "AU05"`, VID `0xFFF1` / PID `0x00DD`）；
- `vibekey watch` **能成功打开** `0xfffc` → 说明没有别的进程独占它，不是抢设备的问题；
- `config/device.json`（Studio 认为"已连接"的设备表）里**只有一条陈旧的 "Ulanzi Deck 5x3"（Model 20GBA9901），没有 AU05**；
- 所以插件收不到 `run` / `dialrotate`，**不是插件路径的问题，是设备根本没被 Studio 激活**。

这**同时解释了本项目"deviceKeyEvent 一条都没出现过"的现象**——不是 VibePal 的解码或 hook 有问题，是上游就没有事件流。在解决"如何让 AU05 进入自定义模式"之前，插件路和自研路会卡在同一个点上。

### 下一步（按性价比）

1. **看一眼 Studio 界面**：它到底显不显示 "Vibe Key 已连接"？这一步决定后面所有方向，且只需要肉眼。（本次因 osascript 无辅助访问权限、未去改系统权限，没能自动截到 Studio 窗口。）
2. 若 Studio 显示未连接 → 问题在配对/连接方式（有线 vs 2.4G 接收器 vs BLE），先把 Studio 与设备连通，其余问题自动消失。
3. 若 Studio 显示已连接但 `0xfffc` 仍静默 → 说明激活命令走的不是 `0xfffc`，需要重新抓一次 Studio 启动瞬间的 `IOHIDDeviceSetReport`（`scratchpad/driver.py` 已就绪）。

### 现场状态（可回滚）

- 探针插件仍在 Plugins 目录，动作仍绑在 ✕ 和旋钮上 —— 一旦设备激活即可立刻拿到事件；
- 原始 profile 备份在会话 scratchpad 的 `ProfilesV2.backup/`，还原即可恢复 ✕=Esc、旋钮=⌃Space。

---

## 06. 功能对标:VibePal 还缺什么(2026-08-26)

对标对象(GitHub 星标):`dekuNukem/duckyPad` 1325★(开源宏键盘事实标杆)、
`bitfocus/companion` 2270★、`nekename/OpenDeck` 2081★、`AutoHotkey` 13017★、
`zclucas/RMT` 1088★、QMK/Vial 系。

### 触发侧

| 能力 | 谁有 | VibePal |
| --- | --- | --- |
| 单击 | 全部 | ✅ |
| **按前台 App 自动切预设** | duckyPad(专门开了 `duckyPad-profile-autoswitcher` 仓库,基于规则匹配活动窗口)、RMT(`WindowHotkeyManager`) | ❌ **最该补** |
| 长按 / 双击 / 连击 | Vial(tap-dance)、duckyPad | ❌ |
| 旋钮按住+旋转 | UlanziDeck SDK 有 `hold-left`/`hold-right` 事件 | ❌(AU05 硬件是否支持未验证) |
| 层 / 页 | QMK/Vial、Stream Deck 系全部 | ❌ |

### 动作侧

| 能力 | 谁有 | VibePal |
| --- | --- | --- |
| 组合键 | 全部 | ✅ |
| **组合键序列** | 全部 | ✅ 2026-08-26 补上 |
| 插入文本 | 全部 | ✅ |
| 启动/切换 App | 全部 | ✅ |
| 打开 URL | Stream Deck 系、RMT | ❌ |
| 运行 shell / 脚本 | RMT、Hammerspoon、Companion | ❌ |
| 媒体键 / 音量 | 全部 | ❌ |
| 鼠标动作 | RMT、duckyScript | ❌ |
| 延时 / 等待 | RMT、duckyScript | ❌(和弦间固定 30ms,用户改不了) |
| 变量 / 条件 / 循环 | duckyScript(图灵完备)、RMT | ❌ |

### 反馈与配置

| 能力 | 谁有 | VibePal |
| --- | --- | --- |
| 设备 LED / 状态显示 | duckyPad(RGB+OLED)、Stream Deck 系 | ❌ 卡在厂商协议,见本文 04b |
| 多预设 | 全部 | ✅ 4 套内置 |
| 导入 / 导出 / 分享配置 | RMT(配置分享站)、duckyPad(SD 卡) | ❌ 只存 UserDefaults |
| 插件 / 扩展 | Stream Deck / UlanziDeck / Companion | ❌ |

### 按性价比排序的建议

1. **按前台 App 自动切预设** —— 预设名字已经是「Claude」「Codex」「相册整理」了,
   本质就是 per-app 配置,却要手动切,等于没用。`NSWorkspace.shared.notificationCenter`
   的 `didActivateApplicationNotification` + 一张 bundleID → profileID 表,约 40 行。
   duckyPad 为这一个功能单开了仓库,说明它是刚需不是锦上添花。
2. **长按 / 双击** —— AU05 只有 4 个可编程控件,靠按法给每个键翻倍是唯一便宜的扩容路。
   Carbon 除 `kEventHotKeyPressed` 外还有 `kEventHotKeyReleased`,拿得到按下时长,
   不用上 CGEventTap(待实测)。
3. **打开 URL / 运行脚本** —— 各约 10 行(`NSWorkspace.open` / `Process`),
   动作类型从 4 种变 6 种,是投入产出比最高的一档。
   注意:执行任意脚本是信任边界,要在界面上显式标注、不能从导入的配置里静默执行。
4. **配置导入导出 JSON** —— 约 20 行。有了它才谈得上备份和分享。

明确**不建议**做的:自研脚本语言(duckyScript 那种)。VibePal 的价值在设备协议和
agent 状态联动,不在再造一个 AHK。真需要脚本能力时,动作里能调 shell 就够了。

---

## 06b. macOS workflow 生态:能接什么(2026-08-27 调研)

结论:**Apple 快捷指令在 GitHub 上没有权威集合**。它的分享靠 iCloud 链接
(RoutineHub / 各家 gallery),链接会失效、内容会变。搜 `awesome shortcuts apple`
`macos shortcuts collection` 基本无有效结果,最像的 `extratone/shortcutsgallery` 只有 5★。

有真实 GitHub 生态的是另外两家,但都要另装 App:

| 生态 | GitHub 体量 | 程序化入口 |
| --- | --- | --- |
| **Apple 快捷指令** | 无权威集合 | `/usr/bin/shortcuts run <名字>`、`shortcuts list`、`shortcuts://` |
| **Alfred** | `zenorocha/alfred-workflows` 12253★、`alfred-workflows/awesome-alfred-workflows` 3178★、`deanishe/alfred-workflow` 2966★ | `alfred://runtrigger/<workflow>/<trigger>/?argument=` |
| **Raycast** | 扩展分散,`marekbrze/categorized-raycast-extensions` 600★ 做索引 | `raycast://extensions/<author>/<ext>/<cmd>` |
| Hammerspoon | `Hammerspoon/hammerspoon` 15999★,配置仓库一堆 | Lua,需自己写 |

### 对 VibePal 的取法

**一个 `openURL` 字段同时覆盖四家** —— 它们都注册了自己的 scheme。不用一家写一个集成。
加一个 `runShortcut`(走 `shortcuts run`)拿下 Apple 那套。

**推荐库不硬编码第三方清单**:链接会烂、还得维护,而且多半在推荐用户机器上没有的东西。
改成扫本机(`shortcuts list` + `/Applications` 探测),推荐出来的每条都当场能绑。
本机实测:43 条可用 / 45 条,agent 相关的(询问 ChatGPT / Ask ChatGPT / ask-agent-v1 /
Voice ChatGPT 1)自动排在最前,未装的 Raycast 与 Alfred 标注了怎么装。

**也因此不做独立的 shell 动作**:快捷指令里自带「运行 Shell 脚本」和「运行 AppleScript」,
交给它,VibePal 就不用持有「执行任意命令」这个信任边界。

---

## 07. 源清单

**RMT**
- https://github.com/zclucas/RMT · 文档 https://zclucas.github.io/RMT/ · 配置库 https://zclucas.github.io/RMT-Setting/

**Ulanzi 生态**
- https://github.com/brendanwelsh/ulanzi-d100h-homebrew （D100H 逆向笔记，同 VID `0xfff1`）
- https://github.com/UlanziTechnology/UlanziDeckPlugin-SDK （官方插件 SDK，Apache-2.0）
- https://github.com/UlanziTechnology/plugin-common-node · https://github.com/UlanziTechnology/plugin-common-html
- https://github.com/UlanziTechnology/OpenCodexMicro （官方 Codex 状态盘插件，2026-08-24）
- https://github.com/jcalado/companion-surface-d200 （D200 线协议逆向，MIT）· https://jcalado.com/posts/ulanzi-d200-companion/
- 插件市场 https://ugc.ulanzistudio.com/home/1 · 论坛 https://bbs.ulanzistudio.com/

**通用生态**
- https://qmk.fm/ · https://get.vial.today/ · https://github.com/nekename/OpenDeck
- https://github.com/rOzzy1987/MacroPad · https://github.com/kamaaina/macropad_tool · https://github.com/prcutler/awesome-macropad
- https://python-elgato-streamdeck.readthedocs.io/ · https://den.dev/blog/reverse-engineering-stream-deck/
- https://github.com/openrazer/openrazer/wiki/Reverse-Engineering-USB-Protocol
