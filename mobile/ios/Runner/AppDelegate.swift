import Flutter
import Security
import UIKit

final class NkasStarBridge: NSObject, FlutterStreamHandler {
  static let shared = NkasStarBridge()

  private let channelName = "com.megumiss.nkas/platform"
  private let eventsName = "com.megumiss.nkas/platform_events"
  private let workerBaseURL = "https://nkas-star.megumiss.top"
  private let repository = "megumiss/NIKKEAutoScript"
  private let licenseKey = "nkas_license"
  private let oauthStateKey = "nkas_oauth_state"
  private let serialKey = "nkas_serial"
  private let publicKeyPEM = """
  -----BEGIN PUBLIC KEY-----
  MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqt+mvxSSyA4rsWro38Q1
  NGB3MABuZBL8dkdJDwW3Bd18yaXC8h1EO/JnxKLIa0T1kubuasSECtclYMuP/3sM
  QkwdUqLy0YY0LXBW+Tt0kwcpsWaaIU27iUKk6jkQUyaw0FFFE5VxUf/TORMHnxzr
  jt8MlKKJYhTT5ODI5WjrXaUQQ7T1z+YSAvGgMqiCpso1GOeb1eosbjOsiAYJOwoW
  DYxZ+XdlxVMMJuxPqkuHjZY7+HtBV/P4562mCqmPDivo7h9gd/EQeGFmwWid7jI6
  /SkfgvhL+u3j68h7olOVefEX5M8aTxc5eR0AQ5G6VYB/DWboXZ8GnVYJUzM4akR6
  mwIDAQAB
  -----END PUBLIC KEY-----
  """

  private var methodChannel: FlutterMethodChannel?
  private var eventSink: FlutterEventSink?
  private var pendingEvents: [[String: Any]] = []
  private let adbClient = NkasIosAdbClient()
  private var scrcpySession: NkasIosScrcpySession?
  private var scrcpyControl: NkasIosScrcpyControl?
  fileprivate var textureRegistry: FlutterTextureRegistry?
  private var videoTexture: NkasIosVideoTexture?

  func register(binaryMessenger: FlutterBinaryMessenger) {
    guard methodChannel == nil else { return }
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
    let events = FlutterEventChannel(name: eventsName, binaryMessenger: binaryMessenger)
    events.setStreamHandler(self)
    methodChannel = channel
  }

  func handle(url: URL) {
    guard url.scheme == "nkas", url.host == "auth", url.path == "/callback" else { return }
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    var query: [String: String] = [:]
    for item in components?.queryItems ?? [] {
      query[item.name] = item.value ?? ""
    }
    guard let expected = UserDefaults.standard.string(forKey: oauthStateKey),
          query["state"] == expected else {
      emit(["type": "star", "authorized": false, "error": "验证回调无效，请重新验证"])
      return
    }
    UserDefaults.standard.removeObject(forKey: oauthStateKey)

    if let error = query["error"], !error.isEmpty {
      let message: String
      switch error {
      case "repository_not_starred":
        message = "当前 GitHub 账号尚未 Star 项目，请完成 Star 后重试"
      case "oauth_cancelled":
        message = "GitHub 验证已取消"
      case "oauth_not_configured":
        message = "Star 验证服务尚未配置，请联系项目维护者"
      default:
        message = "GitHub 验证失败，请稍后重试"
      }
      emit(["type": "star", "authorized": false, "error": message])
      return
    }

    guard let token = query["key"], let license = parseAndVerify(token) else {
      emit(["type": "star", "authorized": false, "error": "验证密钥无效或已过期，请重新验证"])
      return
    }
    UserDefaults.standard.set(token, forKey: licenseKey)
    emit(license)
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getStarStatus":
      result(currentStar())
    case "beginStarVerification":
      beginVerification(result: result)
    case "clearStarAuthorization":
      UserDefaults.standard.removeObject(forKey: licenseKey)
      UserDefaults.standard.removeObject(forKey: oauthStateKey)
      result(currentStar())
    case "getSerial":
      result(UserDefaults.standard.string(forKey: serialKey) ?? "")
    case "setSerial":
      let arguments = call.arguments as? [String: Any]
      let serial = (arguments?["serial"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      UserDefaults.standard.set(serial, forKey: serialKey)
      result(serial)
    case "nativeAdbConnect":
      let arguments = call.arguments as? [String: Any]
      let endpoint = (arguments?["endpoint"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !endpoint.isEmpty else {
        result(FlutterError(code: "native_adb_endpoint", message: "ADB 地址不能为空", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        do {
          try self?.adbClient.connect(endpoint: endpoint)
          DispatchQueue.main.async { result(["endpoint": endpoint]) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "native_adb_connect", message: error.localizedDescription, details: nil)) }
        }
      }
    case "nativeAdbShell":
      let arguments = call.arguments as? [String: Any]
      let command = (arguments?["command"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !command.isEmpty else {
        result(FlutterError(code: "native_adb_command", message: "ADB shell 命令不能为空", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        do {
          let output = try self?.adbClient.shell(command) ?? ""
          DispatchQueue.main.async { result(output) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "native_adb_shell", message: error.localizedDescription, details: nil)) }
        }
      }
    case "nativeAdbClose":
      adbClient.close()
      result(true)
    case "nativeAdbPush":
      let arguments = call.arguments as? [String: Any]
      let remotePath = (arguments?["remotePath"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      let typedData = arguments?["data"] as? FlutterStandardTypedData
      let mode = UInt32(arguments?["mode"] as? Int ?? 0o644)
      guard !remotePath.isEmpty, let typedData else {
        result(FlutterError(code: "native_adb_push", message: "push 参数无效", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        do {
          try self?.adbClient.push(typedData.data, remotePath: remotePath, mode: mode)
          DispatchQueue.main.async { result(true) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "native_adb_push", message: error.localizedDescription, details: nil)) }
        }
      }
    case "nativeAdbPull":
      let arguments = call.arguments as? [String: Any]
      let remotePath = (arguments?["remotePath"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !remotePath.isEmpty else {
        result(FlutterError(code: "native_adb_pull", message: "pull 路径不能为空", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        do {
          let data = try self?.adbClient.pull(remotePath: remotePath) ?? Data()
          DispatchQueue.main.async { result(FlutterStandardTypedData(bytes: data)) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "native_adb_pull", message: error.localizedDescription, details: nil)) }
        }
      }
    case "nativeScrcpyStart":
      let arguments = call.arguments as? [String: Any]
      let endpoint = (arguments?["endpoint"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      let video = arguments?["video"] as? Bool ?? true
      let control = arguments?["control"] as? Bool ?? true
      let maxSize = arguments?["maxSize"] as? Int ?? 0
      let videoBitRate = arguments?["videoBitRate"] as? Int ?? 0
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        guard let self else { return }
        do {
          if !endpoint.isEmpty { try self.adbClient.connect(endpoint: endpoint) }
          guard let serverURL = Bundle.main.url(forResource: "scrcpy-server-v4.1", withExtension: nil) else {
            throw NkasIosAdbError.remote("iOS 包内缺少 scrcpy-server-v4.1")
          }
          let serverData = try Data(contentsOf: serverURL)
          self.scrcpySession?.close()
          let session = try NkasIosScrcpySession.start(
            adb: self.adbClient,
            serverJar: serverData,
            options: NkasIosScrcpyOptions(video: video, control: control, maxSize: maxSize, videoBitRate: videoBitRate)
          )
          self.scrcpySession = session
          self.scrcpyControl = session.controlStream.map(NkasIosScrcpyControl.init)
          if video, let textureRegistry = self.textureRegistry {
            let texture = NkasIosVideoTexture(registry: textureRegistry)
            self.videoTexture = texture
            try session.startVideo(
              onSize: { [weak self] width, height in
                self?.emit(["type": "scrcpyVideo", "state": "size", "width": width, "height": height])
              },
              onFrame: { [weak texture] buffer in texture?.publish(buffer) },
              onError: { [weak self] error in
                self?.emit(["type": "scrcpyVideo", "state": "failed", "error": error.localizedDescription])
              },
              onStopped: { [weak self] in self?.emit(["type": "scrcpyVideo", "state": "stopped"]) }
            )
          }
          self.emit(["type": "scrcpyServer", "state": "started", "message": session.command])
          self.emit([
            "type": "scrcpyVideo", "state": "started", "deviceName": session.metadata?.deviceName,
            "codecId": session.metadata.map { NSNumber(value: $0.codecId) },
          ])
          DispatchQueue.main.async {
            result([
            "scid": session.scid,
              "command": session.command,
              "deviceName": session.metadata?.deviceName,
              "codecId": session.metadata.map { NSNumber(value: $0.codecId) },
              "textureId": self.videoTexture?.textureId,
              "video": video,
              "control": control,
            ])
          }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "native_scrcpy_start", message: error.localizedDescription, details: nil)) }
        }
      }
    case "nativeScrcpyStop":
      scrcpySession?.close()
      scrcpySession = nil
      scrcpyControl = nil
      videoTexture?.dispose()
      videoTexture = nil
      emit(["type": "scrcpyVideo", "state": "stopped"])
      result(true)
    case "nativeScrcpyBack":
      let action = (call.arguments as? [String: Any])?["action"] as? Int ?? 0
      do { guard let scrcpyControl else { throw NkasIosAdbError.notConnected }; try scrcpyControl.back(action: action); result(true) }
      catch { result(FlutterError(code: "native_scrcpy_control", message: error.localizedDescription, details: nil)) }
    case "nativeScrcpyText":
      let text = (call.arguments as? [String: Any])?["text"] as? String ?? ""
      do { guard let scrcpyControl else { throw NkasIosAdbError.notConnected }; try scrcpyControl.text(text); result(true) }
      catch { result(FlutterError(code: "native_scrcpy_control", message: error.localizedDescription, details: nil)) }
    case "nativeScrcpyKeycode":
      let arguments = call.arguments as? [String: Any]
      do {
        guard let scrcpyControl else { throw NkasIosAdbError.notConnected }
        try scrcpyControl.keycode(action: arguments?["action"] as? Int ?? 0, keycode: arguments?["keycode"] as? Int ?? 0, repeatCount: arguments?["repeat"] as? Int ?? 0, metaState: arguments?["metaState"] as? Int ?? 0)
        result(true)
      } catch { result(FlutterError(code: "native_scrcpy_control", message: error.localizedDescription, details: nil)) }
    case "nativeScrcpyTouch":
      let arguments = call.arguments as? [String: Any]
      do {
        guard let scrcpyControl else { throw NkasIosAdbError.notConnected }
        try scrcpyControl.touch(action: arguments?["action"] as? Int ?? 0, pointerId: UInt64(arguments?["pointerId"] as? Int ?? 0), x: arguments?["x"] as? Int ?? 0, y: arguments?["y"] as? Int ?? 0, width: arguments?["screenWidth"] as? Int ?? 0, height: arguments?["screenHeight"] as? Int ?? 0, pressure: arguments?["pressure"] as? Double ?? 1, actionButton: arguments?["actionButton"] as? Int ?? 0, buttons: arguments?["buttons"] as? Int ?? 0)
        result(true)
      } catch { result(FlutterError(code: "native_scrcpy_control", message: error.localizedDescription, details: nil)) }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func beginVerification(result: @escaping FlutterResult) {
    let state = UUID().uuidString
    UserDefaults.standard.set(state, forKey: oauthStateKey)
    var components = URLComponents(string: "\(workerBaseURL)/oauth/start")!
    components.queryItems = [URLQueryItem(name: "state", value: state)]
    guard let url = components.url else {
      result(FlutterError(code: "invalid_url", message: "无法生成验证地址", details: nil))
      return
    }
    UIApplication.shared.open(url, options: [:]) { opened in
      if opened {
        result(nil)
      } else {
        result(FlutterError(code: "browser_unavailable", message: "无法打开浏览器，请检查系统浏览器", details: nil))
      }
    }
  }

  private func currentStar() -> [String: Any] {
    guard let token = UserDefaults.standard.string(forKey: licenseKey),
          let license = parseAndVerify(token) else {
      UserDefaults.standard.removeObject(forKey: licenseKey)
      return ["type": "star", "authorized": false]
    }
    return license
  }

  private func parseAndVerify(_ token: String) -> [String: Any]? {
    let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 3,
          let payloadData = decodeBase64URL(parts[1]),
          let signature = decodeBase64URL(parts[2]),
          let payloadObject = try? JSONSerialization.jsonObject(with: payloadData),
          let payload = payloadObject as? [String: Any],
          payload["starred"] as? Bool == true,
          payload["repo"] as? String == repository,
          let username = payload["sub"] as? String,
          let expiresAt = (payload["exp"] as? NSNumber)?.int64Value,
          expiresAt > Int64(Date().timeIntervalSince1970),
          verifySignature(message: "\(parts[0]).\(parts[1])", signature: signature) else {
      return nil
    }
    return [
      "type": "star",
      "authorized": true,
      "ok": true,
      "username": username,
      "repository": repository,
      "expiresAt": expiresAt,
    ]
  }

  private func verifySignature(message: String, signature: Data) -> Bool {
    let keyText = publicKeyPEM
      .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
      .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
      .components(separatedBy: .whitespacesAndNewlines).joined()
    guard let keyData = Data(base64Encoded: keyText) else { return false }
    let attributes: [CFString: Any] = [
      kSecAttrKeyType: kSecAttrKeyTypeRSA,
      kSecAttrKeyClass: kSecAttrKeyClassPublic,
    ]
    guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, nil),
          SecKeyIsAlgorithmSupported(key, .verify, .rsaSignatureMessagePKCS1v15SHA256) else {
      return false
    }
    var error: Unmanaged<CFError>?
    return SecKeyVerifySignature(
      key,
      .rsaSignatureMessagePKCS1v15SHA256,
      Data(message.utf8) as CFData,
      signature as CFData,
      &error
    )
  }

  private func decodeBase64URL(_ value: String) -> Data? {
    var normalized = value.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    normalized += String(repeating: "=", count: (4 - normalized.count % 4) % 4)
    return Data(base64Encoded: normalized)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    pendingEvents.forEach(events)
    pendingEvents.removeAll()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      if let eventSink = self.eventSink {
        eventSink(event)
      } else {
        self.pendingEvents.append(event)
      }
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    NkasStarBridge.shared.handle(url: url)
    return true
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NkasStarBridge") {
      NkasStarBridge.shared.textureRegistry = registrar.textures
      NkasStarBridge.shared.register(binaryMessenger: registrar.messenger())
    }
  }
}
