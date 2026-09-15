# Flutter 本地构建与签名

本文面向仓库根目录的 Flutter 客户端，命令使用 Windows PowerShell。Windows 可以生成 Android APK；iOS 本地构建需要 macOS 和 Xcode，步骤见 [移动端说明](README.md#ios-构建)。

## 已准备环境的本地打包

确认 Flutter、Android SDK、原生 AAR 和正式版签名均已准备好后，在 `NIKKEAutoScriptMobile` 的本地仓库根目录打开 PowerShell 并执行以下命令。仓库改名不要求重命名本地目录；示例中的工具路径按实际安装位置调整。

以下命令可用于本地构建验证，不会自动分配发布构建号。对外分发前按[版本与构建标识](#版本与构建标识)准备构建号，并传给 Flutter。

```powershell
$env:ANDROID_HOME = 'D:\Android\Sdk'
$env:Path = "D:\tools\flutter\bin;$env:Path"

flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw 'APK 构建失败，请先处理上方错误。' }

python -X utf8 tool/verify_native.py --apk build/app/outputs/flutter-apk/app-release.apk
if ($LASTEXITCODE -ne 0) { throw 'APK 原生资源校验失败。' }

& "$env:ANDROID_HOME\build-tools\36.0.0\apksigner.bat" verify --verbose build/app/outputs/flutter-apk/app-release.apk
if ($LASTEXITCODE -ne 0) { throw 'APK 签名校验失败。' }
```

成功后安装包位于仓库根目录下的：

```text
build/app/outputs/flutter-apk/app-release.apk
```

把 APK 复制到手机后打开安装即可。每次构建会覆盖这个文件，版本名称取自 `pubspec.yaml`。

2026-09-13，本机在提交 `851f81c` 上成功构建 `1.0.6` 正式包：已有缓存时编译约 3 分 20 秒，APK 约 142.2 MiB，签名及原生资源校验通过。首次下载依赖时通常更慢。

仅修改 Flutter 页面或文案时，可以复用现有的 `native/android/nkas-tsnet.aar`。保留 Flutter 和 Gradle 缓存有利于后续增量构建，日常打包无需先运行 `flutter clean`。更换电脑、重新克隆仓库或修改 Go 原生代码时，按下面的首次准备步骤处理。

## 首次准备环境

### 工具版本和路径

先安装下列工具。表中路径来自已有 Windows 构建环境，仅作示例，应替换成自己的安装路径。

| 工具 | 版本要求 | 本机位置或检查方式 |
| --- | --- | --- |
| Flutter SDK | 3.47.2，已包含 Dart | `D:\tools\flutter` |
| JDK | 17，需要 `java` 和 `javac` | `C:\Program Files\Java\jdk-17.0.2` |
| Android SDK | Platform 36、Build Tools 36.0.0、Platform Tools、Command-line Tools | `D:\Android\Sdk` |
| Android NDK | 28.2.13676358 | `D:\Android\Sdk\ndk\28.2.13676358` |
| Go | 1.23.12，用于生成 tsnet AAR | `D:\PCR\tools\go1.23.12` |
| Python | Python 3，本机为 3.12 | `python --version` |
| Git | 可在终端调用 | `git --version` |

在本地仓库根目录设置当前 PowerShell 窗口的环境变量：

```powershell
$env:ANDROID_HOME = 'D:\Android\Sdk'
$env:JAVA_HOME = 'C:\Program Files\Java\jdk-17.0.2'
$env:GOROOT = 'D:\PCR\tools\go1.23.12'
$env:Path = "D:\tools\flutter\bin;$env:JAVA_HOME\bin;$env:GOROOT\bin;$env:ANDROID_HOME\platform-tools;$env:Path"

flutter --version
java -version
javac -version
go version
python --version
git --version
```

Android Studio 的 SDK Manager 可以安装 Command-line Tools。安装后，如缺少对应 SDK 或 NDK，执行：

```powershell
& "$env:ANDROID_HOME\cmdline-tools\latest\bin\sdkmanager.bat" 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0' 'ndk;28.2.13676358'
if ($LASTEXITCODE -ne 0) { throw 'Android SDK 或 NDK 安装失败。' }

flutter config --android-sdk "$env:ANDROID_HOME"
flutter config --jdk-dir "$env:JAVA_HOME"
flutter doctor --android-licenses
flutter doctor -v
```

`flutter config` 会保存工具路径；按提示接受 Android SDK 许可，并确认 `Android toolchain` 检查通过。仅构建 Android APK 时不需要 Visual Studio 的 Windows 桌面开发组件。

### 生成原生 AAR

在仓库根目录中执行：

```powershell
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'Flutter 依赖下载失败。' }

python -X utf8 tool/build_tsnet.py android
if ($LASTEXITCODE -ne 0) { throw 'tsnet AAR 构建失败。' }
```

脚本会下载固定版本的 gomobile、gobind 和 Go 依赖，生成 `native/android/nkas-tsnet.aar`，包含 `armeabi-v7a`、`arm64-v8a`、`x86_64` 三种架构。该文件不提交到 Git，因此新克隆的工程需要先生成它。

AAR 缺失，或 `native/tsnet/` 中的 Go 源码、依赖、绑定构建参数发生变化时，重新运行此脚本。首次 Gradle 构建还会自动下载并校验 scrcpy server。

### 配置正式版签名

正式包读取**仓库根目录**的 `keystore.properties`。已有配置和密钥时继续使用原文件；新电脑需要一并迁移它们。以下是文件布局示例：

```text
NIKKEAutoScriptMobile/
  keystore.properties
  release.jks
  android/
  ios/
  lib/
  pubspec.yaml
```

`keystore.properties` 示例，占位值应替换为实际密钥信息：

```properties
storeFile=release.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=YOUR_KEY_ALIAS
keyPassword=YOUR_KEY_PASSWORD
```

`storeFile` 相对于仓库根目录解析，子目录路径使用 `/`。密钥文件名可以不同，但必须与该字段一致。密钥、密码和配置文件不要提交到 Git。

准备好 AAR 和签名后，回到本文开头执行正式包构建。没有正式签名文件、只想先调试时，可以使用下面的 Debug 构建。

## 调试包与代码检查

以下命令在仓库根目录中执行，并使用上面配置的 Flutter PATH。Debug 构建同样需要先生成 tsnet AAR，但使用 Android 调试签名：

```powershell
flutter build apk --debug
if ($LASTEXITCODE -ne 0) { throw 'Debug APK 构建失败。' }

python -X utf8 tool/verify_native.py --apk build/app/outputs/flutter-apk/app-debug.apk
if ($LASTEXITCODE -ne 0) { throw 'Debug APK 原生资源校验失败。' }
```

产物是 `build/app/outputs/flutter-apk/app-debug.apk`。日常安装使用 Release 包；Debug 与 Release 的签名通常不同，不能直接互相覆盖。

修改 Dart 代码后，在打包前执行：

```powershell
flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'Flutter 静态检查失败。' }
flutter test
if ($LASTEXITCODE -ne 0) { throw 'Flutter 测试失败。' }
```

修改 Android 原生逻辑后，还应执行 Kotlin 回归：

```powershell
flutter build apk --debug --config-only
if ($LASTEXITCODE -ne 0) { throw 'Flutter Android 构建配置生成失败。' }

Push-Location android
try {
    .\gradlew.bat :app:testDebugUnitTest --console=plain
    if ($LASTEXITCODE -ne 0) { throw 'Android 原生测试失败。' }
} finally {
    Pop-Location
}

python -X utf8 tool/verify_native.py --android
if ($LASTEXITCODE -ne 0) { throw 'Android 原生资源校验失败。' }
```

APK 资源检查覆盖原生库架构、scrcpy server 和许可证资产；`apksigner` 检查签名有效性。设备连接、Tailscale 和实时控制按 [真机验收路径](docs/VALIDATION.md) 验证。

## 常见问题

| 现象 | 处理方式 |
| --- | --- |
| 找不到 `flutter`、`java`、`javac` 或 `go` | 检查安装路径与当前窗口的 PATH；JDK 必须包含 `javac`。Flutter 也可用 `& 'D:\tools\flutter\bin\flutter.bat'` 的绝对路径调用。 |
| 提示 Go 版本不匹配、`GOROOT` 指向旧版本 | 同时将 `GOROOT` 和 PATH 中的 Go 设置为 1.23.12，再生成 AAR。 |
| `Missing native tsnet binding` | 在仓库根目录执行 `python -X utf8 tool/build_tsnet.py android`，确认生成 `native/android/nkas-tsnet.aar`。 |
| 找不到 SDK、NDK 或未接受许可 | 检查 `ANDROID_HOME`、NDK 28.2.13676358 和 `flutter doctor --android-licenses`。 |
| `local.properties` 缺失或 `flutter.sdk not set` | 先从仓库根目录执行 `flutter build apk --debug --config-only`，再直接调用 Gradle。 |
| Release 提示密钥文件、别名或密码错误 | 检查仓库根目录的 `keystore.properties`，以及 `storeFile` 指向的实际密钥文件。 |
| APK 签名校验通过，但覆盖安装失败 | 覆盖安装还要求应用 ID、签名与已安装包一致，且版本码不低于旧包。用 `apksigner verify --print-certs <APK路径>` 对比新旧包的证书 SHA-256；沿用旧包的签名密钥重新构建。 |
| 首次构建长时间下载依赖 | 需要访问 Flutter/Pub、Google Maven、Maven Central、Gradle、Go 模块和 GitHub 下载地址。检查对应下载错误，后续保留缓存可减少重复下载。 |

本地打包不依赖 GitHub Actions 或其 Secrets。签名校验通过仅说明该 APK 的签名有效；是否能覆盖云端版，需要再比较两包签名。

## 版本与构建标识

日常提交、文档修改和本地验证构建不自动升版。准备正式发布时，再根据本次发布的改动调整用户可见版本，并同步关于页展示：

| 发布内容 | 参数 | 示例 |
| --- | --- | --- |
| 修复和小幅改进 | `-Part Patch`（默认） | `1.1.9 → 1.1.10` |
| 兼容的新功能 | `-Part Minor` | `1.9.3 → 1.10.0` |
| 不兼容变更 | `-Part Major` | `1.9.3 → 2.0.0` |

```powershell
.\tool\bump-version.ps1 -Part Patch -DryRun
.\tool\bump-version.ps1 -Part Patch
```

第一条仅预览，第二条实际修改 `pubspec.yaml` 和 `lib/features/settings/about_page.dart`。各段数字不逢 10 进位；脚本保留 `version` 中已有的整数构建号，关于页只显示前三段。同一候选版本的重试不重复升版；正式发布时用 `v1.1.4` 这样的 Git 标签记录发布提交，提交和标签操作按当前任务授权执行。

例如 `version: 1.1.3+42` 中，`1.1.3` 是用户可见版本，`42` 是平台构建号。Android 的 `versionCode` 必须是正整数，后续发布的值应更大；iOS 的 `CFBundleVersion` 也不能直接使用提交哈希。构建号由发布流程统一分配，本地与 CI 发包共用同一编号序列，不能分别从自己的计数起点分配。本地验证且不分发的构建可以复用已有编号。

对外发包可以把已分配的构建号写入 `pubspec.yaml` 的 `+N`，也可以通过构建参数覆盖。以下 `42` 仅为示例，应替换为高于此前已分发包的新编号：

```powershell
flutter build apk --release --build-number 42
```

同一用户可见版本可以发布多个测试包，只递增构建号。提交哈希另作源码标识，例如文件名 `nkas-mobile-1.1.3-42-6c9a43d.apk`；它不替代平台构建号，将哈希转为整数也不保证新包的编号更大。记录哈希前检查工作区；含未提交改动的构建应标记 `dirty`。

## 云端构建

仓库的 `.github/workflows/flutter-release.yml` 通过 `workflow_dispatch` 手动触发。Android 任务在 Ubuntu runner 上生成 APK，iOS 任务在 macOS runner 上生成 IPA；默认构建两端，`ios_only` 可用于仅构建 iOS。

当前工作流读取 `pubspec.yaml` 的版本信息，不自动分配递增构建号或发布 Release。计划分发其产物时，须先将已分配的构建号写入 `version` 的 `+N`；不能假定 GitHub 的运行序号或提交哈希已被写入安装包。

## Android Secrets

Android Release 使用仓库现有的 release keystore。将以下内容添加到 GitHub repository secrets：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `release.jks` 的 Base64 内容 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_KEY_PASSWORD` | key 密码 |

在仓库根目录中使用 PowerShell 生成 Base64，密钥文件名按实际配置替换：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath '.\release.jks').Path))
```

不要把 `release.jks`、`keystore.properties` 或密码提交到 Git。

## iOS IPA

默认的 iOS Action 生成未签名 IPA：

```text
flutter build ios --release --no-codesign
Runner.app -> Payload/Runner.app -> .ipa
```

这个 IPA 没有有效的 Apple 签名，适合下载后使用 AltStore、Sideloadly、TrollStore 或其他工具重新签名。Action 手动运行时勾选 `ios_signed`，才会读取 Apple 签名 Secrets 并尝试构建 Ad Hoc IPA：

| Secret | 内容 |
| --- | --- |
| `IOS_CERTIFICATE_BASE64` | Apple `.p12` 证书的 Base64 内容 |
| `IOS_CERTIFICATE_PASSWORD` | `.p12` 导出密码 |
| `IOS_PROVISIONING_PROFILE_BASE64` | 与 `com.megumiss.nkas.mobile` 匹配的 profile |
| `IOS_TEAM_ID` | Apple Developer Team ID |
| `IOS_KEYCHAIN_PASSWORD` | 临时 CI keychain 密码，可随机生成 |

Apple 签名资源的 Base64 可在 macOS 上用：

```bash
base64 -i signing_certificate.p12 | pbcopy
base64 -i profile.mobileprovision | pbcopy
```

签名方式的取舍：

- 只想让用户下载后自行签名安装：不勾选 `ios_signed`，不需要 Apple 证书，产出 unsigned IPA。
- 想让 IPA 直接安装到已注册设备：需要 Apple Development 或 Ad Hoc 证书、匹配的 profile，且设备 UDID 必须被 profile 包含。
- 想上传 TestFlight/App Store：需要 Distribution 证书、App Store provisioning/profile 或自动签名配置，不能使用个人自签证书替代。

因此，“构建”本身可以不签名，但“直接安装的 iOS IPA”必须在某个环节完成签名；下载后再自签就是把这一步移到了用户设备或侧载工具上。

## 网络与代理

GitHub-hosted runner 默认直连下载 Flutter、Pub、Gradle、CocoaPods 和 Xcode 依赖。当前工作流没有硬编码代理；只有组织网络明确要求代理时，才在 runner 环境变量中配置 `HTTP_PROXY`、`HTTPS_PROXY`，不要把代理账号密码写进 YAML。
