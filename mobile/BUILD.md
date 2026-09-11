# Flutter 构建与签名

构建入口是 `mobile/`。本地检查使用：

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

仓库的 `.github/workflows/flutter-release.yml` 提供 `workflow_dispatch` 和 `v*` Tag 构建。Android 任务在 Ubuntu runner 上生成 APK，iOS 任务在 macOS runner 上生成 IPA。

## Android Secrets

Android Release 使用仓库现有的 release keystore。将以下内容添加到 GitHub repository secrets：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `release.jks` 的 Base64 内容 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_KEY_PASSWORD` | key 密码 |

PowerShell 生成 Base64：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('.\\release.jks'))
```

不要把 `release.jks`、`keystore.properties` 或密码提交到 Git。

## iOS IPA

默认的 iOS Action 模式与 Venera 的公开工作流一致：

```text
flutter build ios --release --no-codesign
Runner.app -> Payload/Runner.app -> .ipa
```

这个 IPA 没有有效的 Apple 签名，适合下载后使用 AltStore、Sideloadly、TrollStore 或其他工具重新签名。Action 手动运行时勾选 `ios_signed`，才会读取 Apple 签名 Secrets 并尝试构建 Ad Hoc IPA：

| Secret | 内容 |
| --- | --- |
| `IOS_CERTIFICATE_BASE64` | Apple `.p12` 证书的 Base64 内容 |
| `IOS_CERTIFICATE_PASSWORD` | `.p12` 导出密码 |
| `IOS_PROVISIONING_PROFILE_BASE64` | 与 `com.megumiss.nkas.mobile.preview` 匹配的 profile |
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
