# 构建与发布

本文覆盖 Android / iOS 的依赖准备、编译、签名与交付。日常开发检查见[开发与验证](docs/DEVELOPMENT.md)，设备行为见[设备验收](docs/VALIDATION.md)。除特别说明外，命令均在仓库根目录执行；任何步骤失败时先处理错误，再继续后续步骤。

## 工具链

版本以[工作流](.github/workflows/flutter-release.yml)、[Flutter 依赖](pubspec.yaml)及[原生构建脚本](tool/)为准。

| 工具或平台 | 配置 |
| --- | --- |
| Flutter | 3.47.2，使用 SDK 自带的 Dart |
| Go | 1.23.12，`PATH` 与 `GOROOT` 指向同一套安装 |
| Python / Git | Python 3、可用的 Git 命令行 |
| Android | JDK 17、Android SDK / Command-line Tools / Platform Tools、NDK 28.2.13676358 |
| Android API | 最低 26；compileSdk / targetSdk 跟随所用 Flutter SDK |
| iOS | macOS、Xcode 和对应 SDK、CMake；最低 iOS 15.0 |
| 原生依赖 | gomobile `v0.0.0-20240806205939-81131f6468ab`、Tailscale 1.80.3、scrcpy server 4.1 |

Windows 可构建 Android；iOS 编译、XCTest 与签名需要 macOS。仓库根目录是 Flutter 工程，`android/` 是 Android 宿主工程。开发者的本地目录名称不影响构建。

首次克隆或依赖变化后执行：

```powershell
flutter --version
flutter doctor -v
flutter pub get
```

### Android 环境

将 Flutter、JDK、Go、Python、Git 加入 `PATH`，设置 `ANDROID_HOME` 指向 Android SDK，并确认 `JAVA_HOME` 指向 JDK 17。Android Studio 的 SDK Manager 可安装所需 SDK 与 Command-line Tools；NDK 版本必须与构建配置一致。

PowerShell 示例（先按自己的安装位置设置环境变量）：

```powershell
flutter config --android-sdk "$env:ANDROID_HOME"
flutter config --jdk-dir "$env:JAVA_HOME"
& "$env:ANDROID_HOME\cmdline-tools\latest\bin\sdkmanager.bat" 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0' 'ndk;28.2.13676358'
flutter doctor --android-licenses
flutter doctor -v
```

SDK Platform 和 Build Tools 应满足所用 Flutter 版本的要求；上面列出的是本工程工具链的安装示例。

## 原生产物与缓存

| 构建入口 | 产物 | 架构 |
| --- | --- | --- |
| `python tool/build_tsnet.py android` | `native/android/nkas-tsnet.aar` | armeabi-v7a、arm64-v8a、x86_64 |
| `python3 tool/build_tsnet.py ios` | `native/apple/NkasTsnet.xcframework` | 真机 arm64、模拟器 arm64 / x86_64 |
| `python3 tool/build_ios_adb.py` | `native/apple/AdbMobile.xcframework` | 真机 arm64、模拟器 arm64 / x86_64 |

首次准备、产物缺失或不完整，以及原生源码、依赖、构建脚本、补丁或工具链变化时重建。仅修改 Dart 或文档且原生产物有效时可复用，无需执行 `flutter clean`。AAR、XCFramework、APK、IPA 与构建缓存不提交到 Git。

Android Gradle 会下载并校验 scrcpy server；iOS 使用仓库内的同版本资源。`tool/verify_native.py` 无参数时检查源码中的声明、许可证清单和资源；使用 `--android` 或 `--ios` 时再检查对应平台的完整原生产物，不能用无参数检查代替平台完整检查。

## Android 构建

### 调试包与原生回归

在 PowerShell 中执行。已有有效 AAR 且构建输入未变化时，可跳过生成步骤。

```powershell
flutter pub get
python -X utf8 tool/build_tsnet.py android
flutter build apk --debug --config-only

Push-Location android
try {
    .\gradlew.bat :app:testDebugUnitTest --console=plain
    if ($LASTEXITCODE -ne 0) { throw 'Android 原生测试失败。' }
} finally {
    Pop-Location
}

python -X utf8 tool/verify_native.py --android
flutter build apk --debug
python -X utf8 tool/verify_native.py --apk build/app/outputs/flutter-apk/app-debug.apk
```

输出为 `build/app/outputs/flutter-apk/app-debug.apk`。`--config-only` 生成宿主所需的 Flutter 配置，再调用 Gradle 测试；不要绕过 Gradle 原生资源检查。

### 正式版签名

正式构建读取仓库根目录的 `keystore.properties`，可参考 [keystore.properties.example](keystore.properties.example)：

```properties
storeFile=release.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=YOUR_KEY_ALIAS
keyPassword=YOUR_KEY_PASSWORD
```

`storeFile` 相对于仓库根目录解析。已有安装用户需要沿用同一套应用 ID 与签名密钥，密钥文件、密码和 `keystore.properties` 不入库。

准备好 AAR、签名及[版本与构建标识](#版本与构建标识)后执行：

```powershell
flutter build apk --release
python -X utf8 tool/verify_native.py --apk build/app/outputs/flutter-apk/app-release.apk
& "$env:ANDROID_HOME\build-tools\36.0.0\apksigner.bat" verify --verbose build/app/outputs/flutter-apk/app-release.apk
```

`apksigner` 路径按已安装的 Build Tools 调整。输出为 `build/app/outputs/flutter-apk/app-release.apk`，每次构建会覆盖。Debug 和 Release 签名通常不同，不能直接互相覆盖安装。

需要按架构分包时执行：

```powershell
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64,android-x64 --android-project-arg=force-version-code-ignoring-abi=true
foreach ($abi in @('armeabi-v7a', 'arm64-v8a', 'x86_64')) {
    python -X utf8 tool/verify_native.py --apk "build/app/outputs/flutter-apk/app-$abi-release.apk" --abi $abi
    if ($LASTEXITCODE -ne 0) { throw "APK 校验失败：$abi" }
}
```

分包命名为 `app-<ABI>-release.apk`。`--abi` 校验指定架构的原生库及资源；省略时要求完整的三个架构。`force-version-code-ignoring-abi=true` 让分包与通用包都使用 `pubspec.yaml` 中的构建号，避免 Flutter 默认的 ABI 版本号偏移影响后续覆盖安装。

## iOS 构建

### 框架、模拟器与 XCTest

在 macOS 的终端执行。已有有效框架且输入未变化时，可跳过对应原生构建步骤。

```bash
flutter pub get
python3 tool/build_tsnet.py ios
python3 tool/build_ios_adb.py
python3 tool/collect_native_licenses.py ios --check
python3 tool/verify_native.py --ios
flutter build ios --simulator --debug --no-codesign
xcrun simctl list devices available
```

从设备列表选择一个可用 iPhone 模拟器，将其 UDID 填入下列命令：

```bash
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination 'platform=iOS Simulator,id=<模拟器 UDID>' -destination-timeout 120 \
  -resultBundlePath build/ios/NativeTests.xcresult CODE_SIGNING_ALLOWED=NO
```

每次 XCTest 使用尚不存在的结果目录，或自行指定新的 `-resultBundlePath`。

ADB 构建脚本在 `build/native-adb/` 下载固定版本源码、应用补丁，并对各架构执行链接检查、归并实际链接的静态库，再生成 XCFramework。`python3 tool/build_ios_adb.py --prepare-only` 只检查源码准备和补丁，可在无 Xcode 环境执行，不能代替 iOS 编译与链接验证。构建缓存中的源码不用于直接开发；改动保存在 `native/adb/` 补丁和构建配置中。

### IPA 与签名

不签名的设备构建：

```bash
flutter build ios --release --no-codesign
python3 tool/verify_native.py --app build/ios/iphoneos/Runner.app
```

将 `Runner.app` 放入 `Payload/Runner.app` 并打包为 ZIP、使用 `.ipa` 扩展名，即得到供后续签名的 IPA。工作流会自动完成此打包。未签名 IPA 无法直接安装，需使用自己的签名方式或侧载工具重新签名。

正式签名需在 Xcode 配置 Team、证书和匹配 `com.megumiss.nkas.mobile` 的描述文件，再使用 Xcode 导出或 `flutter build ipa --release --export-options-plist=<导出配置路径>`。Ad Hoc 分发需包含设备 UDID；TestFlight / App Store 使用对应分发证书和导出配置。工作流的 `ios_signed` 路径使用 Ad Hoc 导出配置，不自动上传商店。

## GitHub Actions

[Flutter Release](.github/workflows/flutter-release.yml) 通过 `workflow_dispatch` 手动触发，流程为：

1. 公共检查：核对显示版本和正整数构建号，执行 Flutter analyze/test、Go race、原生工具测试、许可证和资源核查。
2. Android：生成 AAR、执行 Kotlin 测试，构建并逐个校验 armeabi-v7a、arm64-v8a、x86_64 分包和 universal 通用包，共四个签名 APK。
3. iOS：生成 XCFramework、编译模拟器应用、执行 XCTest、生成 IPA 并检查包内资源。
4. 完整双端构建成功后：下载本次运行的安装包，生成 `SHA256SUMS`，自动创建并发布与显示版本对应的 GitHub Release（例如 `v1.2.1`），标签指向本次构建提交。

默认构建两端。`ios_only` 用于排障，跳过 Android 和 Release 发布，保留公共检查与 iOS artifacts；`ios_signed` 选择带 Apple 签名的 IPA，默认生成未签名 IPA。工作流保留 Actions artifacts，安装包使用 `nkas-mobile-<显示版本>-<构建号>-android-<ABI或universal>.apk`、`nkas-mobile-<显示版本>-<构建号>-ios-<signed或unsigned>.ipa` 命名。

仅发布任务授予 `contents: write`，使用内置 `GITHUB_TOKEN` 创建 Release，无需额外发布令牌。新 Release 先创建草稿，全部附件上传成功后公开；同版本、同提交重试会复用 Release 并更新同名附件。已有版本标签若指向其他提交则拒绝发布，需要先升版。构建失败或取消不会进入发布任务。工作流不自动修改源码版本或分配构建号，发布前须按下节分配版本。

| 用途 | Repository Secrets |
| --- | --- |
| Android Release（运行 Android 任务时必需） | `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD` |
| iOS 签名（启用 `ios_signed` 时必需） | `IOS_CERTIFICATE_BASE64`、`IOS_CERTIFICATE_PASSWORD`、`IOS_PROVISIONING_PROFILE_BASE64`、`IOS_TEAM_ID` |
| iOS 临时 keychain（可选） | `IOS_KEYCHAIN_PASSWORD` |

证书、keystore 和描述文件以 Base64 放入对应 Secret，不写进工作流文件或提交日志。下载产物时核对提交、构建号和对应平台任务的结果；构建通过后仍需执行[设备验收](docs/VALIDATION.md)。

## 版本与构建标识

用户可见版本来自 `pubspec.yaml` 的 `version`，`lib/features/settings/about_page.dart` 的 `appVersion` 同步前三段。日常提交、文档修改和本地验证不自动升版。准备发布时使用：

```powershell
.\tool\bump-version.ps1 -Part Patch -DryRun
.\tool\bump-version.ps1 -Part Patch
```

| 变更类型 | 参数 | 示例 |
| --- | --- | --- |
| 修复和小幅改进 | `Patch`（默认） | `1.1.9 → 1.1.10` |
| 兼容的新功能 | `Minor` | `1.9.3 → 1.10.0` |
| 不兼容变更 | `Major` | `1.9.3 → 2.0.0` |

脚本保留已有的 `+构建号`。例如 `1.2.0+42` 中，`1.2.0` 为显示版本，`42` 为 Android `versionCode` / iOS `CFBundleVersion`。对外分发的新包使用高于此前分发包的正整数构建号，本地与 CI 共用同一编号序列；将其写入 `pubspec.yaml` 的 `+N`，或本地通过 Flutter 的 `--build-number N` 指定。工作流读取 `pubspec.yaml`，不自动使用 Actions 运行序号。

同一候选版本的构建或测试重试不重复递增显示版本；同一显示版本下分发新的包仍需分配新的构建号。本地验证且不分发可以复用构建号。提交哈希只能用于源码追踪，不能转为平台构建号；有未提交改动的产物标记 `dirty`。

发布前同步两个版本文件，确认平台构建、许可证和设备验收结果，并用匹配显示版本的 Git 标签标识发布提交。升版脚本本身不提交、不打标签、不推送。

## 常见构建问题

| 现象 | 处理 |
| --- | --- |
| 找不到 Flutter / Java / Go | 检查 `PATH`，JDK 需包含 `java` 和 `javac`；`GOROOT` 不应指向另一版本 |
| 找不到 SDK / NDK 或许可未接受 | 检查 `ANDROID_HOME`、固定 NDK 版本及 `flutter doctor -v` |
| `Missing native tsnet binding` | 生成 AAR 并运行 `python tool/verify_native.py --android` |
| `local.properties` 缺失或 `flutter.sdk not set` | 在根目录先执行 `flutter build apk --debug --config-only` |
| iOS 框架缺失或架构不匹配 | 在 macOS 重建对应 XCFramework，执行 `--ios` 校验 |
| 签名有效但无法覆盖安装 | 对比应用 ID、签名证书和构建号；使用 `apksigner verify --print-certs` 检查 Android 证书 |
| 依赖下载失败 | 检查 Flutter/Pub、Google Maven、Maven Central、Gradle、Go 模块和 GitHub 的网络访问 |

本地构建不依赖 GitHub Secrets，签名配置使用本地文件；各机器的 SDK、缓存和签名路径不写入仓库文档作为固定前提。
