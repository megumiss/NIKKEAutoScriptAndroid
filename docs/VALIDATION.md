# 原生控制验证与交付记录

## 工程拆分本地验证（2026-09-14）

Flutter 工程已上移到 `main` 分支的仓库根目录，版本为 `1.1.1`；旧版 Kotlin Android 工程在 `codex/legacy-kotlin` 分支独立维护，版本为 `0.4.0`。本次 Windows 本地检查：

- 238 个保留的移动端文件均已上移，逐项核对迁移前后的内容；签名配置、构建入口、工作流和文档路径已同步。
- Flutter analyze 无问题，47 项 Flutter 测试和 37 项 Kotlin JVM 测试通过。
- Go 两个包的测试、4 项原生构建工具回归、63 条 Go 许可证清单及 87 条原生许可证资源检查通过。
- 现有 tsnet AAR 的三种 ABI 校验通过；Flutter Release APK 构建、包内原生资源校验和 APK 签名验证通过。
- 旧版 Kotlin 工程在独立工作目录完成 `:app:assembleDebug`，不依赖 Flutter 工程。
- 双端工作流的 YAML、21 个 shell 步骤、工作目录和缓存输入路径已检查；两分支的文档链接和 `git diff --check` 通过。

iOS 构建、XCTest 和 Go race 由 GitHub Actions 验证。交付时核对拆分提交对应的完整双端工作流；以下历史 CI 链接不能代替当前提交的构建结果。此次目录迁移未进行真机链路验收，验收场景沿用本文后续章节。

## 历史验证（2026-09-13）

2026-09-13，Windows 本地与 GitHub Actions 验证：

| 检查 | 状态 |
| --- | --- |
| Go 核心和移动端绑定测试 | 通过，包含停止活动连接、释放监听、重复清理和凭据处理 |
| Android tsnet AAR | 已构建；armv7、arm64、x86_64 三 ABI |
| Kotlin JVM 测试 | 37 项通过；包括带/不带 adb 前缀的地址、回环 ADB 握手和传输、AUTH、取消握手、输入协议 |
| Flutter analyze / test | analyze 无问题；47 项测试通过，包含控制连接页面的保存、取消注册和画面重连 |
| iOS 固定源码与嵌入补丁 | `--prepare-only` 通过，包含原始 vendor 补丁和应用内启动补丁 |
| 许可证、资源与工作流静态检查 | 87 条原生声明、scrcpy SHA-256、三 ABI 检查通过；工作流 21 个 shell 步骤语法检查通过 |
| 原生构建工具回归 | 4 项通过，覆盖依赖归并、排除主机库、Windows 补丁换行和跨平台许可证顺序 |
| Go race | Linux CI 通过；Windows 本地未运行 |
| iOS 原生框架三架构构建与链接 | macOS CI 通过，包含真机 arm64 和模拟器 arm64/x86_64 |
| iOS 应用构建、XCTest、IPA | macOS CI 通过：模拟器应用、九项协议 XCTest、未签名 IPA 与包内资源校验 |
| Android Release APK 与包内校验 | CI 通过，包含签名、三 ABI、scrcpy 与许可证资产检查 |
| 真机链路 | 未运行；由用户验收 |

阶段提交 `8655cb3`（计划迁移与 Go 核心）、`fde8854`（Android / Flutter 控制）、`8818366`（iOS 原生控制与固定 ADB 构建）及后续 CI 修复已推送到 `android/main`。用户已授权自动构建、修复、提交和推送循环。

已验证的 CI 记录：[Android APK 与 33 项 JVM 测试](https://github.com/megumiss/NIKKEAutoScriptAndroid/actions/runs/34747072044/job/103697074164)；[iOS 完整构建、九项 XCTest 与未签名 IPA](https://github.com/megumiss/NIKKEAutoScriptAndroid/actions/runs/34749063803/job/103702315459)。这些记录分别对应提交 `4f46ea4` 和 `2cdfd81`；下载交付产物时，应核对完整双端构建的提交号，并确认两项任务均成功。

## 真机验收准备

- 准备一个启用 TCP ADB 的 redroid，端口为 `5555`，记录 Tailscale IP 和 MagicDNS 名称。
- 准备能访问该目标的 tailnet AuthKey，目标 ACL 允许到 `5555` 的连接。
- 从外网测试局域网地址时，先确认对应子网路由已发布并获批。
- 先从现有 ADB 客户端确认远端会接受授权；有授权对话框的 Android 设备需在设备侧接受 RSA 身份。
- 运行 `Flutter Release`，先确认 native、JVM、Flutter 与 XCTest 检查通过，再安装自己签名或重签的构建。
- 使用已有 NKAS API v2 后端，让截图回退也有可检查的来源。

## 场景和预期

| 场景 | 操作 | 预期 |
| --- | --- | --- |
| 控制连接页面 | 从设置或画面页进入“控制连接”子页面，编辑后分别保存和返回；小屏下弹出键盘 | 与其他子页面一致的头部、返回和滑动切换动画；保存按钮底部悬浮，保存后返回，未保存的编辑不提交；输入项和按钮可滚动访问，画面入口返回后重新连接 |
| 首次注册 | 开启 Tailscale，输入 AuthKey 并验证 | 节点状态变为已注册；AuthKey 输入清空，不出现在普通设置或日志中 |
| 复用身份 | 关闭并重启 App，AuthKey 留空连接 | 复用同一节点身份 |
| 地址格式与转发 | 分别使用 `host:port` 和 `adb://host:port` 保存目标，测试内网直连与外网 Tailscale | 两种写法均可保存并连接；内部回环转发地址通过解析，无前缀错误 |
| IPv4 / MagicDNS | 分别保存 `adb://100.x.x.x:5555` 和 DNS 地址 | 都能显示远端实时画面，控制目标与保存值一致 |
| 输入 | 长按一秒再抬起，滑动后取消，点击四角 | 长按持续；取消会释放；坐标不超出画面边缘 |
| 系统键和文本 | 返回、主页，输入 ASCII 与少量多字节文本 | 按键正确；300 UTF-8 字节上限明确，超长文本不发送 |
| 首帧和截图回退 | 连接后观察状态，再断开远端网络 | 首帧前显示截图；失败后清除旧 Texture 并恢复两秒轮询 |
| 网络切换 | Wi-Fi 与蜂窝网络切换 | 旧会话关闭，前台重新连接；连续失败最多自动重试三次 |
| Android 后台 | 在实时连接时切到其他 App，再返回 | 活动服务保持连接；若后台断线，回前台恢复；停止控制后服务结束 |
| iOS 后台 | 进入后台十秒，再回前台 | 后台停止视频和转发；回前台重新建立连接 |
| 快速开关 | 连续连接、断开、切换设置或实例十次 | 旧事件不会覆盖新画面；主动停止后不自动重新连接 |
| 取消注册 | 在等待 Tailscale 注册时点击取消 | 页面恢复可操作，不被待完成的平台调用锁住 |
| 清除身份 | 确认清除，再尝试不填 AuthKey 连接 | 旧转发全部关闭，需要新的 AuthKey；旧 key 不复用 |
| 本机虚拟屏幕 | Android 先完成 Termux 无线配对，再选本机模式 | 使用回环无线调试端点创建虚拟屏幕；远程 ADB 身份与本机身份分离 |

文本注入受 Android 输入法与 scrcpy 本身支持范围限制，UTF-8 编码正确不等于所有应用都支持所有 Unicode 字符。首版没有音频、录制、多指、文件管理或终端页面。

## 原生 API 最小诊断

可在调试代码中通过 `NkasPlatform` 顺序调用：

1. `tsnetConfigure(key)` → `tsnetConnect()`。
2. `tsnetStartForward(endpoint, localPort: 0)`，确认返回的临时端口只监听 `127.0.0.1`。
3. `nativeAdbConnect('127.0.0.1:<port>')` 连接刚创建的转发。也可省略独立转发步骤，直接调用 `nativeAdbConnect(endpoint, useTailscale: true)`，由会话创建并管理转发。
4. `nativeAdbShell('getprop ro.product.model')` 应返回目标型号；`nativeAdbPush` 到 `/data/local/tmp/nkas-probe.txt` 后 `nativeAdbPull` 应返回相同字节，再通过 shell 删除该测试文件。
5. `nativeAdbClose()`，检查 `tsnetStatus().forwardCount == 0`。重复停止/清理应成功。

`tsnetStopForward(id)` 只停止指定转发；若它承载当前控制，会同时结束控制并取消自动重连。`tsnetStopAll()` 关闭全部转发并保留 tsnet 实例；`tsnetClose()` 还会关闭 tsnet 实例。iOS 的应用内 ADB smart-socket server 是进程级单例，只绑定本机临时端口，不随每次视频重连重复启动。

## 用户完成验收后记录

保留工作流运行链接、Android/iOS 版本、设备型号、App 提交号、目标 redroid 版本，以及失败步骤和对应的连接状态。分享日志前移除账号、AuthKey 和私有状态文件内容。

iOS 两个 XCFramework 的 Xcode 导入与九项协议 XCTest 已通过 CI。真机仍需核验 H.264 首帧、旋转恢复，以及支持 H.265 的设备上的实际解码。

## 再分发前的许可证事项

`assets/licenses/` 收录 Go、AOSP、压缩库、protobuf/Abseil、BoringSSL、scrcpy、Bouncy Castle、Conscrypt 等依赖的原文与来源。固定 `adb-mobile` 的独立移植胶水没有顶层许可证，已保留此来源状态；对外再分发前需确认该部分授权。
