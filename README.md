<div align="center">

<img alt="NKAS Mobile" src="assets/nkas.png" width="192" height="192" />

# NIKKEAutoScriptMobile

**胜利女神：NIKKE 自动日常脚本 [NIKKEAutoScript](https://github.com/megumiss/NIKKEAutoScript) 的 Android / iOS 移动客户端。**

在手机上管理脚本实例、任务与调度，查看运行日志，并通过 scrcpy 实时查看和控制 Android 设备。

[项目官网](https://nkas.megumiss.top) · [后端项目](https://github.com/megumiss/NIKKEAutoScript) · [版本下载](https://github.com/megumiss/NIKKEAutoScriptMobile/releases) · [问题反馈](https://github.com/megumiss/NIKKEAutoScriptMobile/issues)

</div>

NKAS Mobile 使用 Flutter 构建，配合 NKAS API v2 后端使用。自动化任务由后端执行；移动端负责配置、调度和查看运行结果。Android 可通过 Termux 在本机部署后端，Android 与 iOS 均可连接远程后端，并控制具备 ADB 访问能力的 Android 真机、模拟器或 redroid。

游戏任务和区服支持范围以[后端项目](https://github.com/megumiss/NIKKEAutoScript)为准，国服不在其支持范围内。iOS 作为管理和远程控制客户端使用，不在 iPhone 或 iPad 上运行游戏自动化后端。

## 功能

- **实例与任务**：查看实例运行状态，启动或停止脚本，调整任务配置、执行顺序和调度时间。
- **运行信息**：查看任务队列、活动日历、实时日志与历史日志，下载日志用于排查。
- **画面与控制**：查看后端实例截图，通过原生 ADB 和 scrcpy 获取 Android 实时画面，支持点击、长按、滑动、返回、主页和文本输入。
- **远程连接**：支持直连 Android 设备，或通过应用内 Tailscale 访问控制目标。
- **Android 本机运行**：引导安装 Termux、初始化 NKAS、配对无线调试，并提供本机虚拟屏幕控制。
- **后端维护**：修改部署配置、管理后端安全入口、检查和执行后端更新。

移动端支持 Android 8.0+、iOS 15.0+；Android 本机无线调试配对需要 Android 11+，虚拟屏幕取决于目标系统支持。实时控制面向 Android，PC 后端的任务和截图仍通过 API 管理。控制画面不包含音频、录制或多指操作。

## 开始使用

1. 安装对应平台的应用，按提示完成对后端项目 `megumiss/NIKKEAutoScript` 的 STAR 验证。未签名的 iOS IPA 需要自行签名后安装。
2. 在“设置 → 后端地址”填写已部署的 NKAS 地址；开启安全入口时填写完整入口链接。Android 本机运行可先在“初始化 NKAS”中完成部署。
3. 需要实时控制时，在“设置 → 控制连接”配置 Android 目标，再到“画面”页点击“连接设备”。后端地址与 ADB 控制地址分别配置。

连接示例、Tailscale 注册和本机部署步骤见[连接与使用](docs/USAGE.md)。后端安装参见 [NKAS 安装指南](https://github.com/megumiss/NIKKEAutoScript/wiki/Installation-Guide.zh-CN)。

## 项目文档

| 文档 | 内容 |
| --- | --- |
| [连接与使用](docs/USAGE.md) | 后端连接、安全入口、Tailscale 与 Android 本机部署 |
| [项目结构与执行流程](docs/ARCHITECTURE.md) | 模块职责、后端数据链路、ADB / scrcpy 控制链路与生命周期 |
| [开发与验证](docs/DEVELOPMENT.md) | 开发约定、检查范围、依赖与许可证维护 |
| [构建与发布](BUILD.md) | Android / iOS 编译、签名、版本号与 GitHub Actions |
| [设备验收](docs/VALIDATION.md) | 连接、输入、后台切换及异常恢复的验收场景 |

## 开源协议

主项目源码采用 [GNU General Public License v3.0 only（GPL-3.0-only）](LICENSE)，单独声明许可证的组件除外。`native/tsnet/` 保留 [Apache-2.0 许可证](native/tsnet/LICENSE)；第三方版权、许可证和来源见 [NOTICE](NOTICE) 与 [assets/licenses](assets/licenses/)，应用内也可通过“关于 → 开源许可证”查看。

分发 APK、IPA 或其他 GPLv3 二进制时，须按许可证提供对应源码、必要构建脚本和许可声明。iOS ADB 移植胶水的授权范围，以及 BoringSSL OpenSSL/SSLeay 条款与 GPLv3 的链接兼容性，仍需在再分发前确认，详见[许可证与分发核查](docs/DEVELOPMENT.md#许可证与分发核查)。

## 使用风险与免责声明

- 使用自动化脚本可能违反《胜利女神：NIKKE》的用户协议，存在账号被限制或封禁的风险，请自行评估并承担后果。
- 本项目仅供学习与技术交流，按开源许可证“原样”提供，不承诺账号安全、运行稳定性或数据完整性；在适用法律允许的范围内，作者不对使用造成的账号、设备或数据损失承担责任。
- 本项目为非官方开源项目，与 SHIFT UP、腾讯 / Level Infinite 无关联，游戏名称及相关素材的版权归各自所有者所有。
- ADB 可对目标设备执行操作，请仅连接自己拥有或获授权管理的设备。后端入口密钥、Tailscale AuthKey 与设备私钥属于敏感信息，不要公开；远程后端建议使用 HTTPS，并限制后端与 ADB 端口的访问范围。
- 使用前请阅读以上风险说明和[开源协议](LICENSE)；如无法接受，请停止使用。
