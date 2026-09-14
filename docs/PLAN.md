# NKAS Mobile 原生远程控制计划

## 项目定位

本计划在 `NIKKEAutoScriptAndroid` 仓库根目录 执行，覆盖 Android 和 iOS 的应用内 Tailscale、原生 ADB、scrcpy 视频与输入、Flutter 页面及构建交付。

基础库已重命名为 `tsnet-forwarder`，模块路径为 `github.com/megumiss/tsnet-forwarder`，Go 源码和公开包在该仓库根目录。其本地目录仍为 `D:\PCR\libtsnet-android`。基础库保持独立，不包含 NKAS 业务或 Flutter 页面。

移动端使用 `native/tsnet/forwarder` 中的移植副本及 `native/tsnet/bridge.go` 绑定，构建不依赖开发者机器上的绝对路径。该副本增加移动端取消、关闭、清除身份和错误脱敏约束。基础库尚未发布可固定引用的版本；后续同步需审查这些差异。

目标链路：

```text
Android / iOS app
  -> Go tsnet forwarder
  -> 127.0.0.1:临时端口
  -> Tailscale IP、MagicDNS 或已批准子网路由中的地址:5555
  -> redroid ADB
```

视频和控制数据不经过 NKAS 后端，也不使用 WebView、VNC 或 `ws-scrcpy`。

## 参考项目

- `wsvn53/scrcpy-mobile`：参考 `libtsnet` 的应用内 TCP forwarder、状态管理、清理和连接生命周期。
- `Miuzarte/ScrcpyForAndroid`：参考 Android 原生 ADB 协议、RSA 密钥、TLS ADB、scrcpy server、MediaCodec 和触摸控制。该项目本身是 Apache 2.0，但依赖仍需分别保留许可证。
- `tailscale/tailscale-android`：参考 Android 构建工具链和 Tailscale 依赖版本。官方项目主要是完整 `VpnService`，不是本项目的最终架构。
- `Genymobile/scrcpy`：使用匹配版本的 `scrcpy-server`，保留其版权和许可证声明。

`scrcpy-mobile` 的顶层许可证不能覆盖所有子模块；正式复制或改写代码前必须生成 `NOTICE` 和第三方许可证清单。

## 阶段一：Android tsnet forwarder

### 1. 基础库和移动端构建基线

- 基础库名称为 `tsnet-forwarder`，源码位于仓库根目录；移动端工作在本仓库完成。
- 主项目许可证采用 GPL-3.0-only；独立基础库和 `native/tsnet/` 保留 Apache-2.0。
- 源码提交到仓库，AAR/APK 由 CI 和 Release 构建，不提交生成物。
- 固定 Go、Android SDK、NDK、Gradle、Kotlin 和 `tailscale.com` 版本。
- 初始 Android `minSdk 26`，优先构建 `arm64-v8a`，验证后扩展其他 ABI。

### 2. Go API

Go 层只导出 Android 友好的简单类型，避免把 `context.Context`、channel、复杂 map 或 Go 内部结构暴露给 gomobile：

- `Configure(authKey, hostname, stateDir)`
- `Connect()`
- `StartForward(remoteHost, remotePort, localPort)`
- `StopForward(forwardID)`
- `StopAll()`
- `Status()`
- `Close()`
- `Interrupt()`、`ClearState()` 和 `HasPersistedLogin(stateDir)`

行为约定：

- `localPort=0` 时自动选择空闲端口。
- 监听只绑定 `127.0.0.1`，不暴露局域网。
- 远端地址使用 `net.JoinHostPort`，支持 IPv4、IPv6 和 MagicDNS。
- 每条本地连接通过 `tsnet.Server.Dial()` 建立远端 TCP 连接。
- 状态至少包含配置、连接中、已连接、失败、已关闭和 forward 数量。
- 日志包含目标地址、端口和错误阶段，但绝不输出 AuthKey 或状态文件内容。

### 3. 认证和状态

- 在应用内连接设置中输入 AuthKey。
- AuthKey 仅在内存中用于注册，不写入日志、普通设置或构建产物。
- 正式使用优先 ephemeral、preauthorized key。
- 后续通过可插拔的 `AuthKeyProvider` 接入后端签发或 OAuth，不把后端逻辑写进核心库。
- `stateDir` 使用 Android `filesDir/tsnet`，并从 Android 备份中排除。
- 首次成功注册后持久化节点状态；一次性 AuthKey 不得在删除状态后复用。
- 提供明确的清除状态接口，清除前停止所有 forward。

### 4. Android AAR

- 使用 `gomobile bind -target android` 生成 AAR。
- Kotlin 包装层负责线程切换、生命周期、错误转换和日志接收。
- 不使用系统 Tailscale App，不启动 `VpnService`，不要求用户授权 VPN。
- 先验证 `tsnet.Server` 在 Android 无 TUN 的应用内场景能否稳定启动和 `Dial`。

### 5. 移动端验证入口

独立基础库的示例不作为本仓库交付物。Flutter 连接设置和原生桥提供以下验证能力：

1. AuthKey、hostname、state directory 配置。
2. 远端 host 和 port 配置。
3. `Connect`、`Start Forward`、`Stop`、`Cleanup` 操作。
4. 当前状态、回环监听端口和结构化日志显示。
5. TCP echo 或 ADB 端口探测。

首个真实环境固定为：

```text
远程设备：redroid
远端端口：5555
连接地址：Tailscale IP 或 MagicDNS
原始地址格式：adb://ip:5555
```

退出标准：

- Android 真机成功启动 tsnet。
- 能通过 Tailscale 访问 redroid。
- 本地临时端口能连到远端 `5555`。
- 停止、重连、网络切换和进程退出后没有残留监听端口。

## 阶段二：原生 ADB

参考 `Miuzarte/ScrcpyForAndroid` 完成 Android 原生 ADB；iOS 复用固定版本的 `adb-mobile`。代码与构建配置先完成，真机链路由用户验收：

- Android ADB RSA 密钥生成和持久化。
- 普通 TCP ADB `CNXN/AUTH`。
- Android 11+ TLS ADB `STLS`。
- shell、push、pull 和远程 socket。
- `host:port` 和 `adb://host:port` 解析。
- 连接 `127.0.0.1:forwardPort`，不让 ADB 直接处理 Tailscale。
- 保留 pairing API，但不阻塞 redroid 的普通 `5555` 场景。

验证方式：通过转发端口执行 `getprop ro.product.model`，再 push 一个测试文件。

## 阶段三：原生 scrcpy

参考 `scrcpy-mobile` 和 Miuzarte 项目实现最小控制能力：

- 推送并启动匹配版本的 `scrcpy-server`。
- 接收视频元数据和 H.264/H.265 数据包。
- 使用 Android `MediaCodec` 解码到 `Surface`。
- 支持点击、滑动、长按、返回、主页和文本输入。
- 处理断开、关键帧丢失、解码失败和重连。

首版不加入录制、文件管理、终端和画中画，先保证显示和输入链路稳定。

## 阶段四：Flutter 接入

Flutter 接入要求：

- Flutter 只负责页面和状态展示。
- 原生层负责 tsnet、ADB、scrcpy、Surface 和输入事件。
- 通过平台桥传递连接状态、视频 Surface、输入事件、错误和日志。
- 远程 Android 容器使用 `remote_adb` 模式。
- Android 本机虚拟屏幕使用独立的 `local_virtual_display` 模式，不经过 Tailscale。
- NKAS 后端只提供连接元数据，不承载视频和控制流。

## 阶段五：生命周期和 iOS 对齐

Android：

- 活动控制会话使用前台服务保持连接。
- 无活动 forward 时停止服务并清理资源。
- 网络变化后重新建立 Tailscale 和 ADB。
- 所有停止和清理接口幂等。

iOS：

- 保持与 Android 相同的 forwarder API 语义。
- 参考 `scrcpy-mobile` 使用 Go 静态库或对应绑定。
- 使用 gomobile 生成 `NkasTsnet.xcframework`；使用固定版本 `adb-mobile` 生成 `AdbMobile.xcframework`。
- VideoToolbox 解码 H.264/H.265，Flutter Texture 显示；后台停止视频和转发，回前台恢复。
- 主要保证前台控制场景，遵守 iOS 后台限制。

## 测试和 CI

CI 包含：

- Go 单元测试和 race 检测。
- Kotlin 单元测试。
- AAR 构建。
- Flutter analyze/test、Android APK 构建、iOS 模拟器 XCTest 和 IPA 构建。
- 许可证和 NOTICE 检查。
- ABI 构建检查。

真实设备测试覆盖：

- redroid + TCP ADB `5555`。
- Tailscale IP 和 MagicDNS。
- 网络切换。
- 断开后重连。
- Android 前后台切换。
- 重复启动、停止和清理。

## 当前执行顺序

1. 完成 Go 移动端绑定、取消与清理测试，固定 AAR/XCFramework 构建。
2. Android/iOS 接入相同的 tsnet 平台 API、私有状态目录和回环 ADB 链路。
3. 统一会话启动、停止、输入、断线和网络恢复，Android 使用前台服务。
4. 完成 Flutter 连接设置、两种控制模式、触摸/长按/取消、返回/主页/文本及截图回退。
5. 补齐 iOS 框架构建、CI、许可证、ABI 检查和交付文档。
6. 运行本地检查，按照用户授权提交并推送到 `android/main`，触发 CI 并持续修复构建失败。
7. 对同一提交执行完整双端构建和 XCTest，用户执行真机验收。未运行的检查不得标为通过。

## 目录对应

| 内容 | 当前路径（相对仓库根目录） |
| --- | --- |
| 本计划与验收文档 | `docs/` |
| Go 绑定与转发核心 | `native/tsnet/` |
| 原生库构建器 | `tool/build_tsnet.py`、`tool/build_ios_adb.py` |
| Android 原生实现 | `android/app/src/main/kotlin/com/megumiss/nkas/mobile/` |
| iOS 原生实现 | `ios/Runner/` |
| Flutter 平台 API | `lib/core/platform/` |
| Flutter 连接与控制页面 | `lib/features/settings/`、`lib/features/screen/` |
| 工作流 | `.github/workflows/flutter-release.yml` |

## 进度记录（2026-09-13）

- 已提交 `f17674f`：Android ADB AUTH、payload、WRTE/OKAY、关闭处理；27 项 JVM 测试通过。
- 已提交 `8655cb3`（计划迁移与 Go 核心）、`fde8854`（Android / Flutter 控制）、`8818366`（iOS 原生控制与固定 ADB 构建）。
- Go 核心及绑定测试通过，包含取消活动连接、重复关闭、监听释放、清除身份及错误脱敏。
- `tool/build_tsnet.py android` 已生成并验证 armv7、arm64、x86_64 三种 ABI 的 AAR；产物不入库。
- iOS 已接入 ADB/scrcpy/VideoToolbox、tsnet 与会话恢复；原生框架三架构构建与链接、模拟器应用编译、九项 XCTest 和未签名 IPA 构建均通过 CI。
- Android 已接入 tsnet、原生控制会话、前台服务和独立的本机虚拟屏幕身份；37 项 JVM 测试通过，包含转发地址解析和握手取消。
- Flutter 已完成控制连接子页面（底部悬浮保存、与其他子页面统一的头部和滑动切换动画）、控制目标显示、长按/滑动/取消、首帧展示和截图回退；47 项测试通过，analyze 无问题，覆盖页面保存、取消注册和画面重连。
- iOS 构建器、CI、87 条原生第三方声明和交付文档已补齐；原生构建工具 4 项回归通过。
- `adb-mobile` 的独立移植胶水缺少顶层许可证，已记录来源状态；对外再分发前需确认授权。
- GitHub Actions 已通过公共验证、Go race、Android APK 和 iOS 未签名 IPA 构建及包内资源校验。交付时核对同一提交的完整双端构建，真机验收由用户执行。见 [验收记录](VALIDATION.md)。
