# VibeKey

Ulanzi **Vibe Key（AU05）** 的第三方 macOS 客户端。官方 Ulanzi Studio 没做 AU05 的
agent 场景，这个项目把它接到 Claude Code / Codex：六个实体控件可自定义，agent 的
运行状态映射到键盘指示灯。

> 状态：**能用，但没做完**。哨兵键路线（下面「工作原理」）已经跑通，宏键盘今天就能用；
> 厂商加密口的自主激活和状态动画写回仍是 TODO，见 [PROTOCOL.md](PROTOCOL.md)。

## 两个部件

| | 干什么 |
| --- | --- |
| `mac/` — **VibePal.app** | SwiftUI 配置界面：录快捷键、写进设备固件、监听按键、执行动作 |
| `src/` — **vibekey** CLI | Rust。把 agent 的 hook 事件映射成设备状态，通过厂商 SDK 点灯 |

## 工作原理

AU05 的自定义模式走一个加密的厂商 HID 口（usage page `0xFFFC`），第三方进不去。
绕过去的办法是**哨兵键**：把每个控件在固件里写成一个几乎没人用的功能键（F13–F18），
VibePal 全局抓这几个键，就知道是哪个控件被按了，再执行任意动作 —— 切 App、发组合键、
粘文本。固件本来就能存快捷键并自己发给系统，不需要解密任何东西。

设备信息（电量、序列号、固件版本）和写固件走 Ulanzi Studio 自带的 `kwdm.dylib`
（Kehwin 的厂商 SDK）。本仓库**不分发**该库，运行时从你自己机器上已装的
Ulanzi Studio 里加载。

## 依赖

- macOS 14+，Apple Silicon
- 装了 **Ulanzi Studio**（只为那个 `kwdm.dylib`；装完不需要常驻运行）
- 首次启动要给 VibePal **辅助功能** + **输入监视**权限

## 构建

```sh
sh mac/build-app.sh release     # 产出 mac/build/VibePal.app
cargo build --release           # 产出 target/release/vibekey
```

## 接到 agent

```sh
vibekey serve &                             # 常驻，持有设备
vibekey hooks claude-code                   # 打印 settings.json 的 hooks 片段
vibekey map claude-code PreToolUse          # 看某个事件映射成什么状态
```

八个状态：`idle` `thinking` `working` `error` `attention` `notification` `sweeping` `sleeping`。
目前只有 `claude-code` 和 `codex` 两个 agent，加新的改 [src/mapping.rs](src/mapping.rs)。

内置四套预设：日常工作、Claude、Codex、相册整理。

## 逆向笔记

- [PROTOCOL.md](PROTOCOL.md) — HID 接口、两种模式、厂商口观察
- [VIBEKEY_STATUS.md](VIBEKEY_STATUS.md) — 现状、证据边界、哪些是观察哪些是推断
- [RESEARCH-macropad-oss.md](RESEARCH-macropad-oss.md) — 宏键盘开源生态调研
- [vibe-key-reverse.html](vibe-key-reverse.html) — 可视化版本

## 边界

为互操作做的分析，不是破解。本仓库：

1. 不包含厂商通道的加密密钥，也不分发固件、官方 App 或其版权素材。（唯一保留的是 `sdkInit` 的 App Key —— 它是调用本机 SDK 的客户端标识，不解密任何东西。）
2. 不绕过付费、订阅或账号授权；
3. 加解密一律交给你自己机器上合法安装的厂商 SDK，本仓库不实现也不发布替代实现。

不是法律意见。按自己所在辖区判断。

## License

MIT，见 [LICENSE](LICENSE)。与 Ulanzi、Kehwin 无关联，未获其背书。
