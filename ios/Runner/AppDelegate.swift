import Flutter
import Network
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
  private lazy var nativeSession = NkasNativeSession { [weak self] event in self?.emit(event) }
  fileprivate var textureRegistry: FlutterTextureRegistry? {
    didSet { nativeSession.textureRegistry = textureRegistry }
  }
  private var pathMonitor: NWPathMonitor?
  private let pathQueue = DispatchQueue(label: "com.megumiss.nkas.network")
  private var pathSignature: String?

  func register(binaryMessenger: FlutterBinaryMessenger) {
    guard methodChannel == nil else { return }
    _ = nativeSession
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
    let events = FlutterEventChannel(name: eventsName, binaryMessenger: binaryMessenger)
    events.setStreamHandler(self)
    methodChannel = channel
    startNetworkMonitor()
    NotificationCenter.default.addObserver(self, selector: #selector(applicationDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
  }

  private func startNetworkMonitor() {
    guard pathMonitor == nil else { return }
    let monitor = NWPathMonitor()
    pathMonitor = monitor
    monitor.pathUpdateHandler = { [weak self] path in
      guard let self else { return }
      let state = path.status == .satisfied ? "connected" : "disconnected"
      // VPN（utun 等 .other 接口）会持续刷新 path（路由、DNS、isExpensive 抖动），
      // 不能当作网络切换，否则每次刷新都会中断进行中的 Tailscale 连接；
      // 只跟踪物理链路类型与可达性的真实变化
      let links = Set(
        path.availableInterfaces.filter { path.usesInterfaceType($0.type) }
          .compactMap { interface -> String? in
            switch interface.type {
            case .wifi: return "wifi"
            case .cellular: return "cellular"
            case .wiredEthernet: return "wired"
            default: return nil
            }
          }
      ).sorted()
      let signature = "\(state):\(links)"
      guard self.pathSignature != signature else { return }
      self.pathSignature = signature
      self.emit(["type": "nativeNetwork", "state": state])
      self.nativeSession.networkChanged(state)
    }
    monitor.start(queue: pathQueue)
  }

  @objc private func applicationDidEnterBackground() {
    nativeSession.setForeground(false)
    emit(["type": "nativeNetwork", "state": "background"])
  }

  @objc private func applicationDidBecomeActive() {
    nativeSession.setForeground(true)
    emit(["type": "nativeNetwork", "state": "foreground"])
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
      UserDefaults.standard.set(serial, forKey: "nkas_control_endpoint")
      result(serial)
    default:
      if !nativeSession.handle(call, result: result) { result(FlutterMethodNotImplemented) }
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
        if self.pendingEvents.count > 200 { self.pendingEvents.removeFirst(self.pendingEvents.count - 200) }
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
      NkasStarBridge.shared.textureRegistry = registrar.textures()
      NkasStarBridge.shared.register(binaryMessenger: registrar.messenger())
    }
  }
}
