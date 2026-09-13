# NKAS 旧版 Kotlin Android 客户端

本分支 `codex/legacy-kotlin` 独立保留旧版原生 Android 客户端，包括 Termux 初始化、无线调试配对和服务管理。Flutter Android/iOS 客户端位于 [`main` 分支](https://github.com/megumiss/NIKKEAutoScriptAndroid/tree/main)，本分支不依赖 Flutter 或原来的 `mobile/` 目录。

## 工程结构

| 路径 | 内容 |
| --- | --- |
| `app/src/main/java/com/megumiss/nkas/` | Kotlin 页面、初始化、配对与服务管理 |
| `app/src/main/assets/` | Termux 初始化和服务脚本 |
| `app/src/main/res/` | Android 界面资源 |
| `app/build.gradle.kts` | 应用版本、Android 构建与签名配置 |
| `.github/workflows/android-build.yml` | 旧版 Android 构建工作流 |

## 本地构建

需要 JDK 17、Android SDK Platform 35 与 Build Tools 35.0.0；应用最低支持 Android 11（API 30）。在仓库根目录配置 `local.properties` 的 `sdk.dir`，或设置 `ANDROID_HOME`，然后执行：

```powershell
.\gradlew.bat --no-daemon :app:assembleDebug
```

APK 输出到 `app/build/outputs/apk/debug/`，其中 `nkas-mobile-v<版本>-<ABI>.apk` 为按版本和架构命名的副本，`universal` 包支持全部配置的架构。

正式签名使用仓库根目录的 `keystore.properties`，格式见 `keystore.properties.example`；`storeFile` 相对于仓库根目录解析。配置后运行 `:app:assembleRelease`。密钥、签名配置、`local.properties` 和生成的 APK 均不提交。

## 分支与验证

向 `codex/legacy-kotlin` 推送提交或发起以它为目标的 Pull Request，会运行旧版 Android Debug 工作流。Flutter 的构建和双端验证在 `main` 分支独立维护。

每次提交前递增 `app/build.gradle.kts` 的 `appVersionName` 和 `versionCode`，并运行与改动相应的检查。关于页从 Android 包信息读取版本，无需维护 Flutter 版本文件。协作约定见 [AGENTS.md](AGENTS.md)。
