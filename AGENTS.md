# 项目协作指南

本文件只适用于 NIKKEAutoScriptMobile 仓库；NIKKEAutoScript 的规则、构建和验证独立处理。默认使用简体中文沟通，代码标识符沿用所在模块的命名风格。

## 开始工作

- 先查看 `git status --short` 和相关文件，保留已有的未提交改动，只修改当前任务需要的内容。
- 当前 `main` 分支的仓库根目录就是 Flutter Android/iOS 工程，`android/` 是 Flutter 的 Android 宿主。旧版独立 Kotlin 应用只在 `codex/legacy-kotlin` 分支维护，使用该分支自己的指南与构建入口。
- 按任务读取相关文档章节。项目介绍见 [README](README.md)，连接配置见 [使用说明](docs/USAGE.md)；架构和原生控制契约见 [项目结构与执行流程](docs/ARCHITECTURE.md)，开发检查见 [开发与验证](docs/DEVELOPMENT.md)，编译签名见 [构建与发布](BUILD.md)；需要设备验收时查 [设备验收](docs/VALIDATION.md) 的对应场景。旧版 Kotlin 工程的文档与验证独立维护。
- 文档中的计划、历史验证结果和历史授权不代表当前实现、当前测试结果或本次任务授权；当前会话用户已明确给出的授权在原范围内有效。发现差异时结合当前代码和用户要求核实，按本次改动同步相关文档。
- 本任务已读且未变更的内容不重复读取。目标明确的低风险、可逆操作按上下文继续；仅在关键信息无法推断，或敏感、范围外操作尚缺必要授权时确认。
- 按任务和技术栈选择 Skill：视觉、交互或可访问性变化才使用 UI 设计指导；纯协议、数据解析、文档或构建说明修改不触发 UI、品牌或营销流程。Flutter 与 Kotlin 使用各自现有组件，不能套用 React 组件安装步骤。
- 优先使用 `rg` 搜索代码。遵循现有结构，避免无关重构、整仓格式化和顺带升级依赖。

## 目录与职责

| 路径 | 职责 |
| --- | --- |
| `lib/app/` | Flutter 应用入口、导航和页面壳层 |
| `lib/features/` | 总览、实例、画面、日志、部署、设置等业务页面 |
| `lib/core/api/` | NKAS API v2 客户端与数据模型 |
| `lib/core/connection/` | 后端连接状态及实例状态、队列、日志 WebSocket |
| `lib/core/platform/` | Flutter 原生平台桥、控制配置与平台差异 |
| `lib/core/widgets/`、`lib/theme.dart` | 共享组件和主题 Tokens |
| `android/app/src/main/kotlin/` | Flutter Android 端的平台桥、ADB、scrcpy、解码和前台服务 |
| `ios/Runner/` | iOS 平台桥、ADB 运行时、scrcpy、VideoToolbox 与 Texture |
| `native/tsnet/` | Go 移动端绑定和 `forwarder/` 移植副本 |
| `native/adb/` | iOS ADB 嵌入补丁、CMake 配置与链接检查 |
| `tool/` | 原生库构建、资源验证、许可证收集和版本工具 |
| `test/`、`android/app/src/test/`、`ios/RunnerTests/` | Flutter、Kotlin JVM、iOS 协议测试；Go 测试与源码同目录 |
| `.github/workflows/` | Flutter Android/iOS 双端构建工作流 |

## 实现约定

- API 请求与数据解析集中在 `ApiClient` 和数据模型中；连接与订阅逻辑复用 `lib/core/connection/`，页面不要重复实现同一套协议。
- Flutter 原生调用通过 `NkasPlatform`。变更方法名、参数或事件结构时，核对 Android 的 `NkasPlatformBridge.kt`、iOS 对应处理和相关测试，保留平台能力判断。
- 实时视频与输入通过应用内原生 ADB、scrcpy 和可选 tsnet 转发直连目标 Android。后端提供任务数据和截图回退；后端实例与控制目标是独立配置。
- 调整控制生命周期时，检查取消连接、重复停止、旧会话事件、首帧到达和截图回退。iOS 进入后台停止视频与转发，Android 活动控制使用前台服务。
- tsnet 转发只监听 `127.0.0.1`，支持系统分配临时端口。保留 IPv4、IPv6、MagicDNS 和取消、关闭、清除身份的现有语义。
- `native/tsnet/forwarder/` 是经过移动端适配的副本；同步上游时保留取消、状态清理与错误脱敏差异，构建不得依赖其他仓库的本机绝对路径。

## 界面与代码风格

- Flutter 视觉、布局或交互改动按需对照 [设计规范](DESIGN.md) 的相关章节和 `design/nkas-mobile-interactive.html` 的对应页面；已有实现足以确定的小改动直接复用。保持 `shadcn_ui`、Lucide 图标、`theme.dart` 与共享组件的一致性。
- 颜色和通用尺寸优先使用现有主题定义；兼顾浅色、深色、小屏、键盘遮挡、SafeArea 和可访问性，避免在页面中散落重复样式。
- 页面文案沿用简体中文；连接、任务和日志状态来自真实数据，提供加载、空态和错误反馈。
- Dart 遵循 `analysis_options.yaml`，仅对改动文件运行 `dart format`；Go 改动使用 `gofmt`；Kotlin、Swift 和 Python 沿用相邻代码风格。

## 工具链与构建

版本以构建配置、锁文件和 CI 为准。当前 Flutter 工作流使用 Flutter **3.47.2**、Go **1.23.12**、JDK **17**、Android NDK **28.2.13676358**；gomobile 与 Tailscale 版本已固定。Flutter Android 最低 API **26**，iOS 最低 **15.0**。

以下 Windows 示例使用 PowerShell。Android 构建需要配置 Android SDK；`ANDROID_HOME` 指向 SDK，Go 的 `PATH` 与 `GOROOT` 应匹配。iOS 构建与 XCTest 需要 macOS、Xcode 和相应 SDK。

### 按改动选择检查

按受影响的层选择检查，跨层改动合并对应要求。表中命令在指定目录执行；首次准备依赖、依赖清单变化或本地依赖缺失时执行 `flutter pub get`。

| 改动范围 | 工作目录 | 必要检查 |
| --- | --- | --- |
| 纯文档（含 AGENTS.md） | 仓库根目录 | 核对内容、引用路径和 `git diff --check`，不触发应用构建 |
| Flutter 源码 | 仓库根目录 | `flutter analyze`、`flutter test`；交互变化验证相关页面流程 |
| Go 源码 | `native/tsnet/` | `go test ./...` |
| Go 并发、取消或生命周期 | `native/tsnet/` | 另执行 `go test -race ./...`，需要支持 cgo 的 C 工具链 |
| 原生构建或版本工具 | 仓库根目录 | `python -m unittest discover -s tool -p 'test_*.py'`；版本工具回归需要 PowerShell |
| Swift 源码 | 仓库根目录 | `python tool/check_swift_scope.py`；有 macOS 环境时执行 Runner XCTest 与模拟器构建 |
| 原生库、资源或平台构建配置 | 仓库根目录 | `python tool/verify_native.py`（可用 `--android` / `--ios` 限定平台），并完成相关平台构建 |
| Go 依赖或许可证清单 | 仓库根目录 | `python tool/collect_native_licenses.py go --check` |

Android/iOS 原生平台桥、协议或生命周期行为变化应运行对应 Kotlin JVM / XCTest 回归，按下方示例选择受影响平台的命令。检查通过后，仅在相关输入变化、新失败或尚未覆盖的风险出现时重跑；环境缺失时说明未完成的必要检查。

以下是完整构建示例，按上述改动范围选用。Flutter Android 原生测试和调试构建，在仓库根目录执行：

```powershell
flutter pub get
python tool/build_tsnet.py android
flutter build apk --debug --config-only
Push-Location android
.\gradlew.bat :app:testDebugUnitTest --console=plain
Pop-Location
python tool/verify_native.py --android
flutter build apk --debug
```

`build_tsnet.py` 生成必需的 `native/android/nkas-tsnet.aar`，包含 `armeabi-v7a`、`arm64-v8a`、`x86_64`。产物缺失、不完整，或原生源码、依赖、构建脚本、工具链变化时重建；输入未变且产物有效时复用，不因 Dart 或文档修改重复构建，也不要绕过 Gradle 资源检查。

iOS 完整构建在 macOS 的仓库根目录执行；tsnet 和 ADB 原生库同样只在缺失、无效或对应构建输入变化时重建：

```bash
flutter pub get
python3 tool/build_tsnet.py ios
python3 tool/build_ios_adb.py
python3 tool/verify_native.py --ios
flutter build ios --simulator --debug --no-codesign
```

XCTest、签名和发布产物校验参考 `.github/workflows/flutter-release.yml` 与 [构建与发布](BUILD.md)。

## 提交、发布与版本号

- 日常 Git 提交不自动递增版本号，包括代码、文档和配置变更。仅在准备正式发布或用户明确要求升版时调整；普通打包、测试和提交重试不触发升版。
- 用户可见版本采用 `主版本.次版本.修订号`：修复和小幅改进递增修订号，兼容的新功能递增次版本并将修订号归零，不兼容变更递增主版本并将后两段归零。各段不按十进制进位，例如 `1.1.9 → 1.1.10`、`1.9.3 → 1.10.0`。
- Flutter 版本来源为 `pubspec.yaml` 的 `version`，可以带整数构建号，如 `1.1.3+42`。`lib/features/settings/about_page.dart` 的 `appVersion` 只同步前三段 `1.1.3`。
- 准备发布时使用现有脚本；`-Part` 可选 `Patch`（默认）、`Minor`、`Major`。脚本只递增用户可见版本，保留已有的 `+构建号`：

```powershell
.\tool\bump-version.ps1 -Part Patch -DryRun
.\tool\bump-version.ps1 -Part Patch
```

- 第一条命令仅预览，第二条实际更新两个版本文件。以计划发布的版本为基准，同一候选版本的构建、测试或提交重试不重复升版；正式发布时用匹配版本的 Git 标签标识发布提交。
- 对外分发的安装包使用单调递增的正整数构建号，通过 `version` 的 `+N` 或 Flutter 的 `--build-number N` 指定。它对应 Android `versionCode` 和 iOS `CFBundleVersion`；本地与 CI 发包须从同一编号序列分配，新分发包的编号应高于此前已分发包。本地验证且不分发的构建可以复用已有编号。
- 提交哈希用于源码追踪，可记录在产物文件名或发布记录中，不能直接作为平台构建号；截断或转成整数的哈希也不保证递增。工作区含未提交改动时标记 `dirty`，不将该包宣称为对应提交的可复现产物。
- 升版提交前检查两处用户可见版本一致，并将版本文件一并提交。仅版本字符串同步不扩大原任务的验证范围；DryRun 用于自检，不要求用户再次确认已授权的操作。版本调整不自动授权提交、打标签或推送。

## 文件与验证要求

- 不提交签名密钥、`keystore.properties`、`local.properties`、AuthKey、节点私有状态或含凭据的日志。AuthKey 仅用于内存中的注册请求，节点状态保存在应用私有目录并排除系统备份。
- 不提交生成的 AAR、XCFramework、APK、IPA 和构建缓存；保留锁文件、原生补丁及已跟踪资源。变更原生依赖或 scrcpy 版本时同步核对资源校验、`NOTICE` 与 `assets/licenses/`。
- 验证范围统一按“按改动选择检查”执行；保留协议、并发和生命周期修复的必要回归。
- 完成后检查本次差异与 `git diff --check`，说明修改内容、实际运行的验证及未完成的检查。构建通过不等于真机链路验收；需要设备验证时读取对应验收场景。
