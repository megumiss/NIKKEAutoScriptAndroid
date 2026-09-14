# 原生控制验证与交付记录

## 初始化重试接续现有任务回归（2026-09-15）

- 超时后重试命中 `bootstrap already running (PID …)` 时，脚本返回的退出码 2 表示已有安装进程。Flutter 同时处理命令回执和原生桥随后发出的失败回执，恢复“正在安装…”、清除误报并重启状态刷新，后续日志继续更新当前步骤。
- 恢复时保留已推进的阶段；安装完成后迟到的重复回执不会重新开启安装状态。其他退出码 2、真实命令错误和脚本失败仍正常报错。
- Windows / Flutter 3.47.2：修改文件定向分析通过，`flutter test --no-pub test/setup_page_test.dart` 共 12 项通过。修复前已复现重试后日志继续输出、按钮却仍为“重试当前安装”；回归覆盖日志与回执的两种先后顺序、既有失败状态恢复和刷新重启。本次未打包、安装或运行真机验证。

## 初始化步骤提示归属回归（2026-09-15）

- 安装命令、脚本状态和启动请求的错误显示在对应安装步骤中；Termux 下载错误只在 Termux 步骤出现一次，ADB 通知显示在连接操作下方。失败自动展开当前步骤，后续日志不会覆盖错误，重试清除旧错误。
- 页面级状态查询错误显示在队列上方，并在查询成功后清除。步骤日志和错误共用按内容收缩、最大高度 190px 的滚动区域。
- Windows / Flutter 3.47.2：修改文件定向分析通过，`flutter test --no-pub test/setup_page_test.dart` 共 8 项通过，包含原有超时回归。修复前已复现安装错误脱离步骤卡片出现在队列底部；本次未打包、安装或运行真机验证。

## 初始化命令超时回归（2026-09-15）

- 对照旧版 Kotlin 提交 `14535ca`：Termux 安装命令的 `exitCode == -2` 只表示原生桥等待回调超过 12 秒，不代表安装脚本退出。Flutter 初始化页保留当前安装状态和日志，继续刷新；真正的非零退出码和脚本 `failed` 状态仍显示失败并允许重试。
- Windows / Flutter 3.47.2：修改文件的定向分析通过，`flutter test --no-pub test/setup_page_test.dart` 共 4 项通过。修复前已复现超时后按钮从“正在安装…”误变为“重试当前安装”。
- 回归覆盖首条日志之前与之后超时、阻止重复安装、继续刷新和推进阶段、完成后迟到的超时，以及真实命令/脚本失败后的重试。本次没有打包、安装或运行真机验证。

## 输入控件与后端地址页面（2026-09-14）

- Windows / Flutter 3.47.2：`flutter analyze --no-pub` 无问题；`flutter test --no-pub` 共 71 项通过。
- 回归覆盖后端地址保存与返回、无效地址、连接失败重试、安全入口存储，以及数字校验、多行保存、失败草稿、下拉、多选、优先级排序、部署模板和调度日期。小屏与键盘场景、浅深色多选及放大文字均通过 Widget 验证。
- 已检查 390×844 的后端地址和部署页面浅深色 Flutter 渲染截图（使用测试数据），并通过交互原型 JavaScript 语法检查。以上不等于 Android/iOS 真机链路验收，本次未进行真机验收。

## 安全入口本地验证（2026-09-14）

本次安全入口为默认关闭、部署页手动启用的后端访问保护，不改变现有 STAR、ADB 或 Tailscale 授权。本次 Windows 验证：

- `flutter analyze` 无问题；`flutter test` 56 项通过。新增覆盖完整入口解析、HTTP 200 未授权判定、手填回环地址不读取/复用本机密钥、加密存储接口与普通地址分离、请求头作用域、入口轮换和并发复核，以及真实 Dart WebSocket Bearer 握手。
- 375px 深色 Flutter 部署页验证了由 schema 生成的 `SecurityEntryEnabled` 开关，入口操作位于同一分组内，无独立卡片或布局溢出。覆盖开启、遮蔽、重新生成、取消关闭及保存失败时显示提示并保留状态；schema 无该字段时不额外显示入口或请求密钥。应用壳层已补齐消息提示所需的 `ScaffoldMessenger`，并通过真实应用组件树回归。
- 配套后端 8 项回归和真实浏览器两站点测试通过：匿名/错误入口被拦截，正确入口登录后地址不含密钥，轮换撤销旧页面/入口/长连接，关闭恢复普通访问、重新开启和新入口恢复可用。后端业务数据为隔离 fixture，没有运行游戏任务。
- Vue build/typecheck、桌面壳 36 项测试及 exe 编译通过；未启动真实部署的 exe。

当前环境缺 Android SDK，实际执行 `flutter build apk --debug --config-only` 报 `No Android SDK found`，因此尚未完成本次 Android Kotlin JVM 回归、APK 构建、Termux 私有凭据读取或加密存储真机验收。Windows 未运行 iOS 构建与 Keychain 真机验证。下方历史构建结果不代表此次变更已通过这些检查。

真机补验：先在 Android 本机 Termux 模式开启入口并重启 App，确认 HTTP、图片、日志/队列/状态 WS 和“打开 Web UI”均可用；在另一客户端重新生成，确认本机自动恢复、远程客户端提示填写新入口；手填同一回环地址时不得自动读取本机凭据。iOS 用远程完整入口连接并重启，确认本设备 Keychain 恢复；换入口后确认旧连接停止。关闭保护后再验证普通地址可连，且游戏任务未因入口操作停止。

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
| 后端地址页面 | 从设置进入“后端地址”，编辑后分别返回、保存，尝试无效地址和完整安全入口；浅深色、小屏和键盘展开 | 独立子页隐藏底部导航，返回放弃未提交草稿；成功连接后返回设置，失败保留输入和错误；保存按钮与输入可访问，当前连接只显示根地址 |
| 共享输入控件 | 在任务、调度、部署、控制连接及初始化中操作文本、多行、数字、日期、下拉、多选、开关和保存；模拟保存失败 | 标签、边界、焦点、禁用和错误样式统一；多行可换行并保存，数字校验不提交错误值；失败保留草稿可重试，多选长列表与星期选项不溢出 |
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

主项目源码采用 GPL-3.0-only，`native/tsnet/` 和其他独立声明许可的组件保留原许可。针对 GPLv3 二进制分发，还需核查 BoringSSL 的 OpenSSL/SSLeay 条款与所需的额外链接许可。历史构建通过和本次主许可证变更均不代表第三方授权或 GPLv3 分发兼容性已验收。
