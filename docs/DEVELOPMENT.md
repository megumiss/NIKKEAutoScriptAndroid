# 开发与验证

工程与运行链路见[项目结构与执行流程](ARCHITECTURE.md)，工具链安装、原生库准备和打包命令见[构建与发布](../BUILD.md)。本文说明修改代码时的约定与检查范围。

## 开始开发

1. 在仓库根目录查看 `git status --short`，保留已有未提交改动。
2. 按[构建与发布](../BUILD.md#工具链)准备工具；首次克隆、依赖清单变化或依赖缺失时执行 `flutter pub get`。
3. 按所选平台准备 AAR 或 XCFramework，使用 `flutter devices` 选择设备，通过 `flutter run -d <设备 ID>` 调试。
4. Android / iOS 原生能力在相应平台验证；Web 预览不具备同等 ADB、Termux 或 Tailscale 平台能力。

`main` 分支根目录是 Flutter 工程。旧版独立 Kotlin 客户端在 [`codex/legacy-kotlin`](https://github.com/megumiss/NIKKEAutoScriptMobile/tree/codex/legacy-kotlin) 分支维护，使用该分支自己的构建入口。

## 修改约定

- HTTP 请求和数据解析集中在 `ApiClient` 与 `lib/core/api/`，连接状态和订阅复用 `lib/core/connection/`。
- 原生调用通过 `NkasPlatform`。修改方法、参数、事件或会话生命周期时，同时核对 Android、iOS 和回归测试，保留平台能力判断。
- 后端实例与原生控制目标分开配置；不要让切换实例隐式改写控制地址，也不要让远程后端地址覆盖本机 Termux 部署配置。
- UI 遵循[设计规范](../DESIGN.md)、`lib/theme.dart` 与共享组件；状态来自实际响应，提供加载、空态和错误反馈。
- Dart 遵循 `analysis_options.yaml`，仅格式化改动文件；Go 使用 `gofmt`，Kotlin、Swift 和 Python 沿用相邻代码风格。

仅对本次改动文件执行格式化，以下路径为示例：

```powershell
dart format lib/features/settings/about_page.dart
git diff --check
```

## 按改动选择检查

跨层修改合并对应要求。以下为检查入口，不是测试通过记录；每次提交或发布的结果以实际执行为准。

| 改动范围 | 工作目录 | 检查 |
| --- | --- | --- |
| Markdown 文档 | 根目录 | 核对内容、链接与 `git diff --check`，不要求应用构建 |
| Flutter 源码 | 根目录 | `flutter analyze`、`flutter test`；交互改动验证相关页面流程 |
| Go 源码 | `native/tsnet/` | `go test ./...` |
| Go 并发、取消和生命周期 | `native/tsnet/` | 另执行 `go test -race ./...`，需支持 cgo 的 C 工具链 |
| 原生构建、版本工具 | 根目录 | `python -m unittest discover -s tool -p 'test_*.py'`；版本工具回归需要 PowerShell |
| Android 平台桥、协议或生命周期 | `android/` | 准备 AAR 和 Flutter 配置后执行 `gradlew :app:testDebugUnitTest` |
| iOS 平台桥、协议或生命周期 | 根目录（macOS） | 准备框架后执行 Runner XCTest |
| 原生库、资源或平台构建配置 | 根目录 | `python tool/verify_native.py --android` / `--ios`，并完成相关平台构建 |
| Go 依赖或许可证清单 | 根目录 | `python tool/collect_native_licenses.py go --check` |

Gradle、XCTest 与完整构建示例见[构建与发布](../BUILD.md)。检查通过后，只有输入变化、新失败或尚未覆盖的风险需要重复验证。缺少 SDK、设备或签名环境时，记录未完成的检查，不能用其他平台结果替代。

协议和生命周期修改重点覆盖：取消连接、重复停止、旧会话事件、首帧到达、截图回退、前后台切换和重连。真机操作按[设备验收](VALIDATION.md)执行。

## 原生依赖与资源维护

`native/tsnet/forwarder/` 是 [tsnet-forwarder](https://github.com/megumiss/tsnet-forwarder) 的移动端移植副本，构建使用本仓库源码。同步时保留取消、状态清理、Android 网络接口适配与错误脱敏语义，不依赖其他仓库的本机绝对路径。

依赖版本固定在 `native/tsnet/go.mod`、`go.sum`、Android Gradle、原生构建脚本和补丁中。修改原生依赖或 scrcpy 版本后，应同步核对下载地址、哈希、架构、`NOTICE` 和许可证清单，并重建受影响原生产物。

更新清单（仅在相应依赖或来源变化时执行）：

```powershell
python tool/collect_native_licenses.py go
python tool/collect_native_licenses.py go --check
```

iOS 清单依赖构建脚本准备的固定源码：

```bash
python3 tool/build_ios_adb.py --prepare-only
python3 tool/collect_native_licenses.py ios
python3 tool/collect_native_licenses.py ios --check
```

不要提交生成的 AAR、XCFramework、APK、IPA、构建缓存、`local.properties`、签名密钥、`keystore.properties`、AuthKey、节点私有状态或含凭据的日志。保留锁文件、原生补丁和已跟踪资源。

## 许可证与分发核查

主项目为 [GPL-3.0-only](../LICENSE)，`native/tsnet/` 保留其 [Apache-2.0 许可](../native/tsnet/LICENSE)。[NOTICE](../NOTICE) 与 [assets/licenses](../assets/licenses/) 记录独立组件的版权、许可原文和来源；[LICENSES/Apache-2.0.txt](../LICENSES/Apache-2.0.txt) 供 AOSP 清单引用。

分发 GPLv3 二进制时提供对应源码、必要构建脚本和许可证，并保留第三方声明。两项依赖来源问题需要单独核实：

- 固定的 `adb-mobile` 提交未提供覆盖全部移植胶水的顶层许可证。已修改 AOSP 文件保留 Apache-2.0 声明，父项目 `scrcpy-mobile` 的 MIT 许可证不覆盖这个独立子模块；再分发该部分前需确认上游授权范围。
- BoringSSL 含 OpenSSL/SSLeay 等条款。GPLv3 二进制再分发前需核查所链接组件的兼容性，以及是否需要额外链接许可。

清单检查和编译成功只验证工程输入与产物，不代表上述授权或分发兼容性已经确认。
