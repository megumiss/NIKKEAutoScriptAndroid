# NKAS Mobile

Flutter 移动客户端连接 NKAS API v2，提供实例、任务、日志、更新和画面页面。Android / iOS 的实时控制由应用内原生 ADB、scrcpy 与可选 tsnet 转发完成。

```text
Flutter 控制页面
  → Android MediaCodec / iOS VideoToolbox + Texture
  → 原生 scrcpy 视频与输入
  → 原生 ADB
  → 可选 127.0.0.1 临时端口 → 应用内 Tailscale → 远程 Android
```

后端提供任务数据与截图回退；实时视频和触摸数据直接连接 Android 目标。Tailscale 不要求安装系统客户端或授权 VPN。

## 设置和使用

1. 在“设置”中配置 NKAS 后端，完成现有的访问验证。
2. 在“设置”中进入“控制连接”独立页面，选择远程 Android，填写 `host:port` 或 `adb://host:port`。IPv6 使用 `[address]:port`。点击“保存”后返回；顶部返回按钮放弃尚未保存的编辑。
3. 通过 Tailscale 连接时开启开关，填写节点名。首次注册输入 AuthKey，点击“验证连接”；已保存节点身份时可留空。目标的 tailnet ACL 和 Android ADB 服务必须允许连接。
4. 在“画面”页连接设备。首个解码帧到达后显示实时画面；支持单指点击、长按、滑动、返回、主页和最多 300 UTF-8 字节的文本输入。

从外网通过 Tailscale 访问 `192.168.x.x` 等局域网地址时，需要有子网路由器发布对应网段，并在 tailnet 中批准路由、允许访问目标端口。

画面顶部显示实际“控制目标”。后端实例切换决定任务和回退截图来源，控制地址在“控制连接”中单独设置。断开或视频失败时恢复两秒截图轮询。

画面页的设置按钮也会进入同一个“控制连接”页面：进入前停止实时控制，返回后按当前配置重新连接。Tailscale 验证过程中可点击“取消连接”，待操作结束后再返回。

Android 还提供“本机虚拟屏幕”。先在“初始化 NKAS”中通过 Termux 完成无线调试配对；原生客户端会导入已配对的本机身份，使用独立的 ADB 密钥目录。本机模式不使用 Tailscale；实际视频和输入由原生代码处理。无线配对需要 Android 11+，虚拟屏幕能力还取决于目标系统。

iOS 只控制远程 Android，退到后台会停止视频和转发，回前台重新连接。Android 在活动控制期间使用前台服务；网络中断后在前台恢复连接，连续失败最多自动重试三次，随后可手动连接。

AuthKey 仅用于内存中的注册请求；节点状态保存在应用私有目录并排除系统备份。清除身份会先断开连接，后续注册需要新的 AuthKey。

## 工程结构

| 路径 | 内容 |
| --- | --- |
| `lib/` | Flutter 页面、API v2 客户端与原生平台桥 |
| `android/app/src/main/kotlin/` | 原生 ADB、scrcpy、MediaCodec、前台服务和 Termux 配对入口 |
| `ios/Runner/` | 应用内 ADB 运行时、scrcpy、VideoToolbox 与 Texture |
| `native/tsnet/` | Go 绑定与 tsnet 转发核心 |
| `native/adb/` | iOS ADB 嵌入补丁、CMake 配置与链接检查入口 |
| `tool/` | 原生库构建、许可证收集、资源和 ABI 验证 |
| `assets/licenses/` | 随应用打包的第三方声明；“关于 → 开源许可证”可查看 |
| `docs/PLAN.md` | 从基础库项目迁入的实施计划 |
| `docs/VALIDATION.md` | 构建检查记录与真机验收路径 |

基础库已经改名为 [`tsnet-forwarder`](https://github.com/megumiss/tsnet-forwarder)，Go module 是 `github.com/megumiss/tsnet-forwarder`，源码在该仓库根目录。这里使用 `native/tsnet/forwarder` 中的移动端移植副本，保留取消、状态清理和错误脱敏约束；构建不依赖 `D:\PCR\libtsnet-android` 或其他机器路径。

## Android 构建

需要 Flutter **3.47.2**、Go **1.23.12**、JDK **17**、Android SDK 和 NDK **28.2.13676358**。应用 minSdk 为 **26**。gomobile 固定为 `v0.0.0-20240806205939-81131f6468ab`，Tailscale 固定为 **1.80.3**。

在当前 `mobile` 目录执行：

```powershell
flutter pub get
python tool/build_tsnet.py android
flutter analyze
flutter test
flutter build apk --debug --config-only
Push-Location android
.\gradlew.bat :app:testDebugUnitTest --console=plain
Pop-Location
python tool/verify_native.py --android
flutter build apk --debug
```

`ANDROID_HOME` 需指向 SDK。如果机器设置了旧 `GOROOT`，应先让 `GOROOT` 和 `PATH` 指向同一套 Go 1.23.12。构建脚本生成 `native/android/nkas-tsnet.aar`，包含 `armeabi-v7a`、`arm64-v8a`、`x86_64`；未生成时 Gradle 会给出明确错误。

发布构建使用仓库根目录的 `keystore.properties` 和签名文件，随后执行 `flutter build apk --release`。这些本地凭据不应提交。

## iOS 构建

需要 macOS、Xcode（包含 iOS SDK 和模拟器运行时）、CMake、Go 1.23.12 与 Flutter 3.47.2。部署目标是 **iOS 15.0**。

```bash
flutter pub get
python3 tool/build_tsnet.py ios
python3 tool/build_ios_adb.py
python3 tool/verify_native.py --ios
flutter build ios --simulator --debug --no-codesign
```

两个构建器输出 `native/apple/NkasTsnet.xcframework` 和 `AdbMobile.xcframework`，均包含真机 arm64，以及模拟器 arm64/x86_64。ADB 构建器固定 adb-mobile 和 protobuf 提交，在 `build/native-adb` 中准备源码；每个架构先链接检查，再根据实际链接的依赖合并静态库，并再次检查合并结果。

`python3 tool/build_ios_adb.py --prepare-only` 可在没有 Xcode 时检查固定源码和补丁。脚本只会重置自己的构建缓存，不操作基础库或参考项目。生成的 AAR、XCFramework 和构建缓存不入库。

## 工作流和验证

仓库的 `Flutter Release` 工作流通过 Actions 页面或 `gh workflow run` 触发。它先执行 Flutter、Go race、资源与许可证检查，再构建 Android AAR/APK，以及 iOS 框架、模拟器 XCTest 和 IPA。工作流不会自动发布 Release。

定位 iOS 原生构建问题时可选 `ios_only`，保留公共验证并只构建 iOS。默认构建两端，交付时需确认同一提交的 Android 和 iOS 任务均通过。

Android 工作流需要 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`。iOS 默认生成用于个人重签的未签名 IPA；选中 `ios_signed` 时需要 `IOS_CERTIFICATE_BASE64`、`IOS_CERTIFICATE_PASSWORD`、`IOS_PROVISIONING_PROFILE_BASE64`、`IOS_TEAM_ID`，可选 `IOS_KEYCHAIN_PASSWORD`。描述文件的应用标识应匹配 `com.megumiss.nkas.mobile`。

Go 测试在 `native/tsnet` 中执行 `go test ./...`；race 检测使用 `go test -race ./...`，需要支持 cgo 的 C 工具链。GitHub Actions 已通过 Go race、Android APK、iOS 模拟器编译、九项 XCTest 和未签名 IPA 构建；Windows 本地未运行 race 或 Xcode。真机验收由用户执行，详见 [验收记录](docs/VALIDATION.md)。

## 第三方声明

主代码使用 Apache-2.0；依赖的原文见 [NOTICE](NOTICE) 和 `assets/licenses/`。更新 Go 依赖后运行 `python tool/collect_native_licenses.py go`；准备好固定 iOS 源码后运行 `python tool/collect_native_licenses.py ios`。CI 的 `--check` 会阻止遗漏或过期清单。

固定版本的 `adb-mobile` 未提供覆盖全部移植胶水的顶层许可证；已有 AOSP 文件的 Apache-2.0 声明已保留。对外再分发该部分前，需要确认上游移植胶水的授权。父项目 `scrcpy-mobile` 的许可证不覆盖这个独立子模块。
