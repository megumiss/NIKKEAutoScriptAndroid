import Flutter
import Foundation
import Network

final class NkasNativeSession {
  var textureRegistry: FlutterTextureRegistry?
  private let emit: ([String: Any]) -> Void
  private let queue = DispatchQueue(label: "com.megumiss.nkas.native.session")
  private let inputQueue = DispatchQueue(label: "com.megumiss.nkas.native.input")
  private let stateLock = NSLock()
  private var generation = 0
  private var desired: Request?
  private var foreground = true
  private var networkAvailable = true
  private let settings = NkasControlSettings()
  private lazy var tsnet = NkasTsnetClient(settings: settings)
  private let adb = NkasIosAdbClient()
  private var session: NkasIosScrcpySession?
  private var control: NkasIosScrcpyControl?
  private var texture: NkasIosVideoTexture?
  private var activeRequest: Request?
  private var activeForwardId: String?
  private var startupTimeout: DispatchWorkItem?
  private var frameReady = false
  private var width = 0
  private var height = 0
  private var retries = 0

  private struct Request {
    let id: String
    let endpoint: String
    let tailscale: Bool
    let options: NkasIosScrcpyOptions
  }

  init(emit: @escaping ([String: Any]) -> Void) {
    self.emit = emit
    _ = tsnet
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) -> Bool {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "getNativeControlSettings": result(settings.snapshot())
    case "saveNativeControlSettings", "tsnetConfigure", "tsnetClearState":
      let token = begin(nil)
      execute(call.method, result) { owner in
        try owner.ensureCurrent(token)
        owner.stop()
        switch call.method {
        case "saveNativeControlSettings": return try owner.settings.save(args)
        case "tsnetConfigure": try owner.tsnet.configure(args["authKey"] as? String ?? "")
        default: try owner.tsnet.clearState()
        }
        return owner.emitTsnetStatus()
      }
    case "tsnetStatus": execute(call.method, result) { $0.tsnet.status() }
    case "tsnetConnect":
      execute(call.method, result) { owner in try owner.tsnet.connect(); return owner.emitTsnetStatus() }
    case "tsnetStartForward":
      execute(call.method, result) { owner in
        let endpoint = try NkasIosAdbEndpoint(args["endpoint"] as? String ?? "")
        let value = try owner.tsnet.startForward(endpoint, localPort: args["localPort"] as? Int ?? 0)
        owner.emitTsnetStatus()
        return value
      }
    case "tsnetStopForward":
      let id = args["id"] as? String ?? ""
      stateLock.lock()
      let controlsVideo = id == activeForwardId
      stateLock.unlock()
      let token = controlsVideo ? begin(nil) : nil
      execute(call.method, result) { owner in
        if let token, owner.isCurrent(token) { owner.stop(closeTsnet: false) }
        try owner.tsnet.stopForward(id)
        return owner.emitTsnetStatus()
      }
    case "tsnetStopAll", "tsnetClose", "nativeAdbClose", "nativeScrcpyStop":
      stateLock.lock()
      let expected = desired?.id
      stateLock.unlock()
      if let id = args["requestId"] as? String, id != expected { result(true); return true }
      let token = begin(nil)
      execute(call.method, result) { owner in
        if owner.isCurrent(token) {
          owner.stop(closeTsnet: call.method != "tsnetStopAll")
          if call.method == "tsnetStopAll" { owner.tsnet.stopAll(); owner.emitTsnetStatus() }
        }
        return true
      }
    case "nativeAdbConnect":
      let token = begin(nil)
      execute(call.method, result) { owner in
        try owner.ensureCurrent(token); owner.stop(closeTsnet: false)
        do {
          let endpoint = try NkasIosAdbEndpoint(args["endpoint"] as? String ?? "")
          let route = args["useTailscale"] as? Bool == true ? try owner.route(endpoint) : endpoint.serial
          try owner.ensureCurrent(token)
          try owner.adb.connect(endpoint: route, isCancelled: { !owner.isCurrent(token) })
          try owner.ensureCurrent(token)
          owner.emitTsnetStatus()
          return ["endpoint": endpoint.serial]
        } catch { owner.stop(closeTsnet: false); throw error }
      }
    case "nativeAdbShell":
      execute(call.method, result) { owner in
        let command = args["command"] as? String ?? ""
        guard !command.isEmpty, !command.contains("\0") else { throw NkasIosAdbError.protocolError("ADB 命令无效") }
        return try owner.adb.shell(command)
      }
    case "nativeAdbPush":
      execute(call.method, result) { owner in
        guard let bytes = args["data"] as? FlutterStandardTypedData,
              let mode = UInt32(exactly: args["mode"] as? Int ?? 420) else {
          throw NkasIosAdbError.protocolError("ADB push 参数无效")
        }
        try owner.adb.push(bytes.data, remotePath: args["remotePath"] as? String ?? "", mode: mode)
        return true
      }
    case "nativeAdbPull":
      execute(call.method, result) { owner in
        FlutterStandardTypedData(bytes: try owner.adb.pull(remotePath: args["remotePath"] as? String ?? ""))
      }
    case "nativeScrcpyStart":
      guard (args["mode"] as? String ?? "remote_adb") == "remote_adb" else {
        result(FlutterError(code: "native_mode", message: "iOS 仅支持远程 Android 控制", details: nil)); return true
      }
      var options = NkasIosScrcpyOptions(video: args["video"] as? Bool ?? true,
                                         control: args["control"] as? Bool ?? true,
                                         maxSize: args["maxSize"] as? Int ?? 0,
                                         videoBitRate: args["videoBitRate"] as? Int ?? 0)
      options.videoCodec = args["videoCodec"] as? String ?? "h264"
      let endpoint = args["endpoint"] as? String ?? settings.endpoint
      let request = Request(id: args["requestId"] as? String ?? UUID().uuidString,
                            endpoint: endpoint.isEmpty ? settings.endpoint : endpoint,
                            tailscale: args["useTailscale"] as? Bool ?? settings.tailscaleEnabled, options: options)
      let token = begin(request)
      execute(call.method, result) { owner in owner.retries = 0; return try owner.start(request, token: token) }
    case "nativeScrcpyBack", "nativeScrcpyText", "nativeScrcpyKeycode", "nativeScrcpyTouch":
      input(call, args: args, result: result)
    default: return false
    }
    return true
  }

  private func input(_ call: FlutterMethodCall, args: [String: Any], result: @escaping FlutterResult) {
    let token = currentGeneration()
    queue.async { [self] in
      guard isCurrent(token), let control,
            args["requestId"] == nil || args["requestId"] as? String == activeRequest?.id else {
        DispatchQueue.main.async { result(FlutterError(code: "native_control", message: "控制会话未连接", details: nil)) }
        return
      }
      inputQueue.async { [self] in
        do {
          try ensureCurrent(token)
          switch call.method {
          case "nativeScrcpyBack": try control.back(action: args["action"] as? Int ?? 0)
          case "nativeScrcpyText": try control.text(args["text"] as? String ?? "")
          case "nativeScrcpyKeycode":
            try control.keycode(action: args["action"] as? Int ?? 0, keycode: args["keycode"] as? Int ?? 0,
                                repeatCount: args["repeat"] as? Int ?? 0, metaState: args["metaState"] as? Int ?? 0)
          default:
            try control.touch(action: args["action"] as? Int ?? 0,
                              pointerId: UInt64(bitPattern: Int64(args["pointerId"] as? Int ?? 0)),
                              x: args["x"] as? Int ?? 0, y: args["y"] as? Int ?? 0,
                              width: args["screenWidth"] as? Int ?? 0, height: args["screenHeight"] as? Int ?? 0,
                              pressure: args["pressure"] as? Double ?? 1, actionButton: args["actionButton"] as? Int ?? 0,
                              buttons: args["buttons"] as? Int ?? 0)
          }
          DispatchQueue.main.async { result(true) }
        } catch {
          if error is NWError { fail(error, token: token) }
          if let adbError = error as? NkasIosAdbError, case .connection = adbError { fail(error, token: token) }
          DispatchQueue.main.async { result(FlutterError(code: "native_control", message: error.localizedDescription, details: nil)) }
        }
      }
    }
  }

  func networkChanged(_ state: String) {
    stateLock.lock()
    networkAvailable = state != "disconnected"
    let request = desired
    if request != nil { generation &+= 1 }
    let token = generation
    stateLock.unlock()
    guard request != nil else { return }
    adb.interrupt(); tsnet.interrupt()
    queue.async { [self] in
      guard isCurrent(token) else { return }
      stop()
      if let request { videoEvent(request, "waiting") }
      reconnect(token: token)
    }
  }

  func setForeground(_ active: Bool) {
    stateLock.lock()
    guard foreground != active else { stateLock.unlock(); return }
    foreground = active
    generation &+= 1
    let token = generation
    stateLock.unlock()
    adb.interrupt(); tsnet.interrupt()
    queue.async { [self] in
      guard isCurrent(token) else { return }
      stop()
      if active { reconnect(token: token) }
    }
  }

  private func start(_ request: Request, token: Int) throws -> [String: Any] {
    try ensureCurrent(token)
    stop(closeTsnet: false)
    try ensureCurrent(token)
    guard canStart(token) else { throw NkasIosAdbError.connection("等待前台网络恢复") }
    activeRequest = request
    videoEvent(request, "connecting")
    let timeout = DispatchWorkItem { [weak self] in
      self?.fail(NkasIosAdbError.connection("等待视频首帧超时"), token: token)
    }
    startupTimeout = timeout
    DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: timeout)
    do {
      let endpoint = try NkasIosAdbEndpoint(request.endpoint)
      let route = request.tailscale ? try route(endpoint) : endpoint.serial
      emitTsnetStatus()
      try ensureCurrent(token)
      try adb.connect(endpoint: route, isCancelled: { !self.isCurrent(token) })
      try ensureCurrent(token)
      guard let serverURL = Bundle.main.url(forResource: "scrcpy-server-v4.1", withExtension: nil) else {
        throw NkasIosAdbError.remote("应用内缺少 scrcpy-server-v4.1")
      }
      let running = try NkasIosScrcpySession.start(adb: adb, serverJar: Data(contentsOf: serverURL), options: request.options)
      session = running
      try ensureCurrent(token)
      control = running.controlStream.map { NkasIosScrcpyControl(stream: $0) }
      if request.options.video {
        guard let registry = textureRegistry else { throw NkasIosVideoError.notConfigured }
        let output = DispatchQueue.main.sync { NkasIosVideoTexture(registry: registry) }
        texture = output
        try running.startVideo(onSize: { [weak self] width, height in
          self?.queue.async { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            self.width = width; self.height = height
            self.videoEvent(request, "size", ["width": width, "height": height])
          }
        }, onFrame: { [weak self, weak output] buffer in
          guard let self, self.isCurrent(token) else { return }
          output?.publish(buffer)
          self.queue.async { [weak self, weak output] in
            guard let self, let output, self.isCurrent(token), !self.frameReady else { return }
            self.frameReady = true; self.retries = 0
            self.startupTimeout?.cancel()
            self.videoEvent(request, "started", ["textureId": output.textureId, "width": self.width, "height": self.height])
          }
        }, onError: { [weak self] in self?.fail($0, token: token) },
           onStopped: { [weak self] in self?.fail(NkasIosAdbError.connection("视频连接已断开"), token: token) })
      } else { timeout.cancel() }
      running.startServerMonitor(onOutput: { [weak self] message in
        guard let self, self.isCurrent(token) else { return }
        self.emit(["type": "scrcpyServer", "state": "output", "requestId": request.id, "message": String(message.prefix(2000))])
      }, onExit: { [weak self] in self?.fail($0 ?? NkasIosAdbError.connection("scrcpy 服务已退出"), token: token) })
      try ensureCurrent(token)
      var result: [String: Any] = ["scid": running.scid, "requestId": request.id, "command": running.command,
                                 "video": request.options.video, "control": request.options.control]
      if let metadata = running.metadata { result["deviceName"] = metadata.deviceName; result["codecId"] = metadata.codecId }
      if let texture { result["textureId"] = texture.textureId }
      return result
    } catch {
      stop()
      if isCurrent(token) { videoEvent(request, "failed", ["error": error.localizedDescription]) }
      throw error
    }
  }

  private func route(_ endpoint: NkasIosAdbEndpoint) throws -> String {
    let forward = try tsnet.startForward(endpoint)
    guard let id = forward["id"] as? String, let port = forward["localPort"] as? Int else {
      throw NkasIosAdbError.protocolError("Tailscale 转发响应无效")
    }
    stateLock.lock(); activeForwardId = id; stateLock.unlock()
    return "127.0.0.1:\(port)"
  }

  private func stop(closeTsnet: Bool = true) {
    startupTimeout?.cancel(); startupTimeout = nil
    adb.interrupt()
    session?.close(); session = nil
    control = nil
    texture?.dispose(); texture = nil
    frameReady = false; width = 0; height = 0
    adb.close()
    stateLock.lock()
    let forward = activeForwardId
    activeForwardId = nil
    stateLock.unlock()
    if closeTsnet { tsnet.close() }
    else if let forward { try? tsnet.stopForward(forward) }
    emitTsnetStatus()
    if let request = activeRequest { videoEvent(request, "stopped") }
    activeRequest = nil
  }

  private func fail(_ error: Error, token: Int) {
    stateLock.lock()
    guard generation == token else { stateLock.unlock(); return }
    generation &+= 1
    let next = generation
    stateLock.unlock()
    adb.interrupt(); tsnet.interrupt()
    queue.async { [self] in
      guard isCurrent(next) else { return }
      let request = activeRequest
      stop()
      if let request { videoEvent(request, "failed", ["error": error.localizedDescription]) }
      retries += 1
      if retries <= 3 { reconnect(token: next, delay: Double(1 << (retries - 1))) }
    }
  }

  private func reconnect(token: Int, delay: Double = 1) {
    queue.asyncAfter(deadline: .now() + delay) { [self] in
      guard canStart(token), session == nil else { return }
      stateLock.lock()
      let request = desired
      stateLock.unlock()
      guard let request else { return }
      do { _ = try start(request, token: token) }
      catch { fail(error, token: token) }
    }
  }

  @discardableResult
  private func emitTsnetStatus() -> [String: Any] {
    let value = tsnet.status()
    emit(value.merging(["type": "tsnet"]) { _, new in new })
    return value
  }
  private func videoEvent(_ request: Request, _ state: String, _ values: [String: Any] = [:]) {
    emit(values.merging(["type": "scrcpyVideo", "state": state, "requestId": request.id]) { _, new in new })
  }
  private func execute(_ code: String, _ result: @escaping FlutterResult,
                       operation: @escaping (NkasNativeSession) throws -> Any?) {
    queue.async { [self] in
      do { let value = try operation(self); DispatchQueue.main.async { result(value) } }
      catch { DispatchQueue.main.async { result(FlutterError(code: code, message: error.localizedDescription, details: nil)) } }
    }
  }
  private func begin(_ request: Request?) -> Int {
    stateLock.lock()
    generation &+= 1; desired = request
    let token = generation
    stateLock.unlock()
    adb.interrupt(); tsnet.interrupt()
    return token
  }
  private func currentGeneration() -> Int { stateLock.lock(); defer { stateLock.unlock() }; return generation }
  private func isCurrent(_ token: Int) -> Bool { currentGeneration() == token }
  private func canStart(_ token: Int) -> Bool {
    stateLock.lock(); defer { stateLock.unlock() }
    return generation == token && foreground && networkAvailable
  }
  private func ensureCurrent(_ token: Int) throws {
    guard isCurrent(token) else { throw NkasIosAdbError.connection("控制会话已取消") }
  }
}
