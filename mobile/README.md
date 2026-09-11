# NKAS Mobile Flutter Preview

这是 NKAS 移动端的视觉预览工程，使用 `shadcn_ui`，当前使用假数据，不连接真实 API。

完整架构、迁移边界、里程碑和发布流程见：

`../doc/mobile/flutter-shadcn-ui-plan.md`

## 运行

```powershell
flutter pub get
flutter run -d chrome
```

## 检查和测试

```powershell
dart format lib test
flutter analyze
flutter test
flutter build web --release
```

也可以运行 Android 模拟器或真机：

```powershell
flutter run
```

Android 调试和发布：

```powershell
flutter build apk --debug
flutter build apk --release
flutter build appbundle --release
```

iOS 构建需要 macOS + Xcode：

```bash
flutter run -d <ios-device-or-simulator>
flutter build ios --release
flutter build ipa --release
```

工程独立于仓库现有 `android/` 原生初始化工程，预览确认后再决定嵌入方式。
