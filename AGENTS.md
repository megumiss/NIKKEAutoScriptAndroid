# 旧版 Kotlin Android 协作指南

本文件只适用于 NIKKEAutoScriptAndroid 的 `codex/legacy-kotlin` 分支。默认使用简体中文沟通，代码标识符沿用所在模块的命名风格。Flutter Android/iOS 工程在 `main` 分支维护，两套工程的规则、构建和验证独立处理。

## 开始工作

- 先查看 `git status --short` 和相关文件，保留已有的未提交改动，只修改当前任务需要的内容。
- 当前仓库根目录是旧版 Kotlin Android 工程，`app/` 为应用模块。本分支不包含 `mobile/`，不调用 Flutter 的构建或版本脚本。
- 构建入口、签名和分支说明见 [README.md](README.md)。文档中的历史结果和授权不代表当前测试结果或本次授权；当前会话已给出的授权在原范围内有效。
- 本任务已读且未变更的内容不重复读取。目标明确的低风险、可逆操作按上下文继续；仅在关键信息无法推断，或敏感、范围外操作尚缺必要授权时确认。
- 优先使用 `rg` 搜索。遵循现有结构，避免无关重构、整仓格式化和顺带升级依赖。
- 只有视觉、交互或可访问性变化才使用 UI 设计指导，原生界面沿用 Kotlin 和 Android 现有组件。

## 目录与实现约定

| 路径 | 职责 |
| --- | --- |
| `app/src/main/java/com/megumiss/nkas/` | 页面、Termux 初始化、无线调试配对与服务管理 |
| `app/src/main/assets/` | 初始化和服务脚本 |
| `app/src/main/res/` | Android 界面、图标和通知资源 |
| `app/build.gradle.kts` | 版本、SDK、依赖、签名和 APK 输出 |
| `.github/workflows/android-build.yml` | 旧版 Android 构建 |

- Kotlin、XML 和脚本沿用相邻代码风格；页面文案使用简体中文。
- 初始化、配对、取消、服务启停和通知逻辑复用当前模块，处理对应的成功、失败和重复操作。
- 不从其他仓库或 Flutter 分支通过本机绝对路径引用构建输入。

## 工具链与验证

版本以 Gradle 配置和 CI 为准；当前使用 JDK 17、Gradle 8.9、compileSdk 35、minSdk 30。Android 构建需要 Android SDK，通过 `ANDROID_HOME` 或未跟踪的 `local.properties` 配置。

在仓库根目录执行：

```powershell
.\gradlew.bat --no-daemon :app:assembleDebug
```

代码、资源或构建配置修改完成后运行上述构建；纯文档修改核对内容、引用路径和 `git diff --check`，不触发应用构建。文档提交附带的版本字符串同步只检查版本值，不扩大验证范围。

协议、配对、初始化或服务生命周期变化应验证受影响流程；构建通过不等于真机验收。通过的检查只在相关输入变化、新失败或尚未覆盖的风险出现时重跑，环境缺失时说明未完成的检查。

## 提交与版本

- 每次 Git 提交都必须递增应用版本一次，包括代码、文档和配置变更。
- 以当前分支上一条提交为基准，修改 `app/build.gradle.kts` 的 `appVersionName`，修订号加 1，逢 10 归零并向左进位；次版本同样逢 10 进位。`versionCode` 同时加 1。
- 旧版历史版本 `0.3.39` 在拆分提交中按此规则递增为 `0.4.0`，`versionCode` 从 50 递增为 51；以后从这个基准继续递增。
- 关于页从 Android 包信息读取版本；本分支不维护 Flutter 的 `pubspec.yaml` 或 `about_page.dart`。
- 仅在准备提交时升版，同一次提交的构建、测试或提交重试不重复递增。版本配置与本次修改一起提交。

## 文件与交付

- 不提交签名密钥、`keystore.properties`、`local.properties` 或含凭据的日志；保留 `keystore.properties.example` 作为配置示例。
- 不提交 APK、Gradle/Kotlin 缓存和其他构建产物，保留 Gradle Wrapper 和已跟踪资源。
- 完成后检查本次差异与 `git diff --check`，说明修改内容、实际运行的验证及未完成的检查。
