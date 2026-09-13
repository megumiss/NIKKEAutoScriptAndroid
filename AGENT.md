# 项目协作指南

本文件供在 NIKKEAutoScriptAndroid 仓库中工作的 AI 编程助手参考，覆盖整个仓库。默认使用简体中文沟通，代码标识符沿用所在模块的命名风格。

## 开始工作

- 先查看 `git status --short` 和相关文件，保留已有的未提交改动，只修改当前任务需要的内容。
- 先确认目标工程：根目录 `app/` 是 Kotlin Android 应用，`mobile/` 是独立的 Flutter Android/iOS 应用；两者有各自的 Gradle 工程和构建入口。
- 阅读 [移动端说明](mobile/README.md)；涉及界面时阅读 [设计规范](mobile/DESIGN.md)，涉及原生控制时阅读 [实施计划](mobile/docs/PLAN.md) 和 [验收记录](mobile/docs/VALIDATION.md)。
- 文档中的计划、历史验证结果和历史授权不代表当前实现、当前测试结果或本次任务授权。发现差异时结合当前代码和用户要求核实，按本次改动同步相关文档。
- 优先使用 `rg` 搜索代码。遵循现有结构，避免无关重构、整仓格式化和顺带升级依赖。

## 目录与职责

| 路径 | 职责 |
| --- | --- |
| `app/src/main/java/com/megumiss/nkas/` | 根工程的 Android 页面、Termux 初始化、无线调试配对与服务管理 |
| `app/src/main/assets/` | 根工程的初始化和服务脚本 |
| `mobile/lib/app/` | Flutter 应用入口、导航和页面壳层 |
| `mobile/lib/features/` | 总览、实例、画面、日志、部署、设置等业务页面 |
| `mobile/lib/core/api/` | NKAS API v2 客户端与数据模型 |
| `mobile/lib/core/connection/` | 后端连接状态及实例状态、队列、日志 WebSocket |
| `mobile/lib/core/platform/` | Flutter 原生平台桥、控制配置与平台差异 |
| `mobile/lib/core/widgets/`、`mobile/lib/theme.dart` | 共享组件和主题 Tokens |
| `mobile/android/app/src/main/kotlin/` | Flutter Android 端的平台桥、ADB、scrcpy、解码和前台服务 |
| `mobile/ios/Runner/` | iOS 平台桥、ADB 运行时、scrcpy、VideoToolbox 与 Texture |
| `mobile/native/tsnet/` | Go 移动端绑定和 `forwarder/` 移植副本 |
| `mobile/native/adb/` | iOS ADB 嵌入补丁、CMake 配置与链接检查 |
| `mobile/tool/` | 原生库构建、资源验证、许可证收集和版本工具 |
| `mobile/test/`、`mobile/android/app/src/test/`、`mobile/ios/RunnerTests/` | Flutter、Kotlin JVM、iOS 协议测试；Go 测试与源码同目录 |
| `.github/workflows/` | 根 Android 工程与 Flutter 双端构建工作流 |

## 实现约定

- API 请求与数据解析集中在 `ApiClient` 和数据模型中；连接与订阅逻辑复用 `mobile/lib/core/connection/`，页面不要重复实现同一套协议。
- Flutter 原生调用通过 `NkasPlatform`。变更方法名、参数或事件结构时，核对 Android 的 `NkasPlatformBridge.kt`、iOS 对应处理和相关测试，保留平台能力判断。
- 实时视频与输入通过应用内原生 ADB、scrcpy 和可选 tsnet 转发直连目标 Android。后端提供任务数据和截图回退；后端实例与控制目标是独立配置。
- 调整控制生命周期时，检查取消连接、重复停止、旧会话事件、首帧到达和截图回退。iOS 进入后台停止视频与转发，Android 活动控制使用前台服务。
- tsnet 转发只监听 `127.0.0.1`，支持系统分配临时端口。保留 IPv4、IPv6、MagicDNS 和取消、关闭、清除身份的现有语义。
- `mobile/native/tsnet/forwarder/` 是经过移动端适配的副本；同步上游时保留取消、状态清理与错误脱敏差异，构建不得依赖其他仓库的本机绝对路径。

## 界面与代码风格

- 界面改动先对照 `mobile/design/nkas-mobile-interactive.html`、`mobile/DESIGN.md` 和当前实现。复用 `shadcn_ui`、Lucide 图标、`theme.dart` 与共享组件。
- 颜色和通用尺寸优先使用现有主题定义；兼顾浅色、深色、小屏、键盘遮挡、SafeArea 和可访问性，避免在页面中散落重复样式。
- 页面文案沿用简体中文；连接、任务和日志状态来自真实数据，提供加载、空态和错误反馈。
- Dart 遵循 `mobile/analysis_options.yaml`，仅对改动文件运行 `dart format`；Go 改动使用 `gofmt`；Kotlin、Swift 和 Python 沿用相邻代码风格。

## 工具链与构建

版本以构建配置、锁文件和 CI 为准。当前 Flutter 工作流使用 Flutter **3.47.2**、Go **1.23.12**、JDK **17**、Android NDK **28.2.13676358**；gomobile 与 Tailscale 版本已固定。Flutter Android 最低 API **26**，iOS 最低 **15.0**；根 Kotlin 工程使用 compileSdk **35**、minSdk **30**。

以下 Windows 示例使用 PowerShell。Android 构建需要配置 Android SDK；`ANDROID_HOME` 指向 SDK，Go 的 `PATH` 与 `GOROOT` 应匹配。iOS 构建与 XCTest 需要 macOS、Xcode 和相应 SDK。

### 按改动选择检查

表中命令在指定目录执行，首次运行 Flutter 检查前执行 `flutter pub get`。

| 检查 | 工作目录 | 命令 |
| --- | --- | --- |
| Flutter 静态分析 | `mobile/` | `flutter analyze` |
| Flutter 测试 | `mobile/` | `flutter test` |
| Go 测试 | `mobile/native/tsnet/` | `go test ./...` |
| Go 并发检查 | `mobile/native/tsnet/` | `go test -race ./...`，需要支持 cgo 的 C 工具链 |
| 原生构建工具回归 | `mobile/` | `python -m unittest discover -s tool -p 'test_*.py'` |
| 原生资源检查 | `mobile/` | `python tool/verify_native.py` |
| Go 许可证清单检查 | `mobile/` | `python tool/collect_native_licenses.py go --check` |

Flutter Android 原生测试和调试构建，在 `mobile/` 执行：

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

`build_tsnet.py` 生成必需的 `mobile/native/android/nkas-tsnet.aar`，包含 `armeabi-v7a`、`arm64-v8a`、`x86_64`。缺少该文件时应先构建，不要绕过 Gradle 检查。

根 Kotlin Android 工程在仓库根目录执行：

```powershell
.\gradlew.bat --no-daemon :app:assembleDebug
```

iOS 在 macOS 的 `mobile/` 目录执行：

```bash
flutter pub get
python3 tool/build_tsnet.py ios
python3 tool/build_ios_adb.py
python3 tool/verify_native.py --ios
flutter build ios --simulator --debug --no-codesign
```

XCTest、签名和发布产物校验参考 `.github/workflows/flutter-release.yml` 与 `mobile/README.md`；根工程使用 `.github/workflows/android-build.yml`。

## 提交与版本号

- 每次 Git 提交都必须将应用版本号递增一次，包括代码、文档和配置变更；版本修改与本次改动一并提交。
- 版本格式为 `主版本.次版本.修订号`，每次修订号加 1，逢 10 归零并向左进位；次版本同样逢 10 进位，主版本可继续递增。例如 `1.0.8 → 1.0.9 → 1.1.0`、`1.9.9 → 2.0.0`。
- 当前 Flutter 应用以 `mobile/pubspec.yaml` 的 `version` 为版本来源，必须同步 `mobile/lib/features/settings/about_page.dart` 的 `appVersion`。使用现有脚本，在仓库根目录执行：

```powershell
.\mobile\tool\bump-version.ps1 -DryRun
.\mobile\tool\bump-version.ps1
```

- 第一条命令仅预览，第二条命令实际更新两个文件。以当前分支上一条提交的版本为基准，确保本次提交恰好递增一次；同一次提交的构建、测试或提交重试不重复递增。
- 提交前检查两个版本值一致，并将版本文件加入同一次提交。

## 文件与验证要求

- 不提交签名密钥、`keystore.properties`、`local.properties`、AuthKey、节点私有状态或含凭据的日志。AuthKey 仅用于内存中的注册请求，节点状态保存在应用私有目录并排除系统备份。
- 不提交生成的 AAR、XCFramework、APK、IPA 和构建缓存；保留锁文件、原生补丁及已跟踪资源。变更原生依赖或 scrcpy 版本时同步核对资源校验、`mobile/NOTICE` 与 `mobile/assets/licenses/`。
- 行为变更运行相关层的检查；涉及协议、并发或生命周期的修复应覆盖对应回归场景。纯文档变更核对内容、引用路径和差异格式即可。
- 完成后检查差异与 `git diff --check`，说明修改内容、实际运行的验证及未完成的检查。构建通过不等于真机链路验收，设备验证参考 `mobile/docs/VALIDATION.md`。
