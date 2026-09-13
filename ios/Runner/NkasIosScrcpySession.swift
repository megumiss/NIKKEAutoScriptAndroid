import CoreVideo
import Foundation

struct NkasIosScrcpyOptions {
  let video: Bool
  let control: Bool
  let maxSize: Int
  let videoBitRate: Int
  var videoCodec = "h264"
}

struct NkasIosScrcpyMetadata {
  let deviceName: String
  let codecId: UInt32
}

final class NkasIosScrcpySession {
  let scid: UInt32
  let command: String
  let metadata: NkasIosScrcpyMetadata?
  let videoStream: NkasIosAdbStream?
  let controlStream: NkasIosAdbStream?
  private let serverStream: NkasIosAdbStream
  private let lock = NSLock()
  private var closed = false
  private var videoStarted = false

  private var isClosed: Bool {
    lock.lock()
    defer { lock.unlock() }
    return closed
  }

  private init(scid: UInt32, command: String, server: NkasIosAdbStream,
               video: NkasIosAdbStream?, control: NkasIosAdbStream?, metadata: NkasIosScrcpyMetadata) {
    self.scid = scid
    self.command = command
    serverStream = server
    videoStream = video
    controlStream = control
    self.metadata = metadata
  }

  static func start(adb: NkasIosAdbClient, serverJar: Data, options: NkasIosScrcpyOptions) throws -> NkasIosScrcpySession {
    guard !serverJar.isEmpty, options.video || options.control,
          (0...65535).contains(options.maxSize), options.videoBitRate >= 0,
          options.videoBitRate <= Int(Int32.max), ["h264", "h265"].contains(options.videoCodec) else {
      throw NkasIosAdbError.protocolError("scrcpy 启动参数无效")
    }
    let scid = UInt32.random(in: 1..<0x7fff_ffff)
    let remotePath = "/data/local/tmp/nkas-scrcpy-\(String(scid, radix: 16)).jar"
    try adb.push(serverJar, remotePath: remotePath)
    let command = buildCommand(remotePath: remotePath, scid: scid, options: options)
    let server = try adb.openShellStream(command)
    var sockets: [NkasIosAdbStream] = []
    do {
      let name = String(format: "scrcpy_%08x", scid)
      let first = try openWithRetry(adb: adb, name: name)
      sockets.append(first)
      guard try first.readExactly(1) == Data([0]) else {
        throw NkasIosAdbError.protocolError("scrcpy socket 握手失败")
      }
      let video = options.video ? first : nil
      let control: NkasIosAdbStream?
      if options.control {
        control = options.video ? try openWithRetry(adb: adb, name: name) : first
        if let control, control !== first { sockets.append(control) }
      } else {
        control = nil
      }
      let rawName = try first.readExactly(64)
      let deviceName = String(decoding: rawName.prefix(while: { $0 != 0 }), as: UTF8.self)
      let codecId = options.video ? UInt32(try first.readExactly(4).bigEndianInteger(at: 0, count: 4)) : 0
      if options.video && codecId != 0x68323634 && codecId != 0x68323635 {
        throw NkasIosVideoError.unsupportedCodec
      }
      return NkasIosScrcpySession(scid: scid, command: command, server: server, video: video,
                                  control: control, metadata: .init(deviceName: deviceName, codecId: codecId))
    } catch {
      sockets.forEach { $0.close() }
      server.close()
      throw error
    }
  }

  func startServerMonitor(onOutput: @escaping (String) -> Void, onExit: @escaping (Error?) -> Void) {
    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let self else { return }
      do {
        while let data = try self.serverStream.readChunk() {
          guard !self.isClosed else { return }
          onOutput(String(decoding: data, as: UTF8.self))
        }
        if !self.isClosed { onExit(nil) }
      } catch {
        if !self.isClosed { onExit(error) }
      }
    }
  }

  func startVideo(onSize: @escaping (Int, Int) -> Void, onFrame: @escaping (CVPixelBuffer) -> Void,
                  onError: @escaping (Error) -> Void, onStopped: @escaping () -> Void) throws {
    guard let videoStream, let metadata else { throw NkasIosVideoError.notConfigured }
    lock.lock()
    guard !closed, !videoStarted else { lock.unlock(); return }
    videoStarted = true
    lock.unlock()
    Thread { [weak self] in
      guard let self else { return }
      do {
        let decoder = try NkasIosVideoDecoder(codecId: metadata.codecId, onFrame: { buffer in
          if !self.isClosed { onFrame(buffer) }
        }, onError: onError)
        defer { decoder.close() }
        var width = 0
        var height = 0
        var waitingForKeyFrame = true
        while !self.isClosed {
          let header = try NkasScrcpyVideoHeader(videoStream.readExactly(12, timeout: nil))
          switch header {
          case .size(let newWidth, let newHeight):
            decoder.close()
            width = newWidth
            height = newHeight
            waitingForKeyFrame = true
            onSize(width, height)
          case .packet(let length, let pts, let configuration, let keyFrame):
            let payload = try videoStream.readExactly(length)
            guard width > 0, height > 0 else { throw NkasIosVideoError.invalidConfiguration }
            if configuration {
              try decoder.configure(payload, width: width, height: height)
              waitingForKeyFrame = true
            } else if keyFrame || !waitingForKeyFrame {
              try decoder.decode(payload, ptsUs: pts)
              waitingForKeyFrame = false
            }
          }
        }
      } catch {
        if !self.isClosed { onError(error) }
      }
      if !self.isClosed { onStopped() }
    }.start()
  }

  func close() {
    lock.lock()
    guard !closed else { lock.unlock(); return }
    closed = true
    lock.unlock()
    videoStream?.close()
    if controlStream !== videoStream { controlStream?.close() }
    serverStream.close()
  }

  static func buildCommand(remotePath: String, scid: UInt32, options: NkasIosScrcpyOptions) -> String {
    var args = [
      "CLASSPATH=\(remotePath)", "app_process", "/", "com.genymobile.scrcpy.Server", "4.1",
      "scid=\(String(scid, radix: 16))", "tunnel_forward=true", "audio=false",
      "video_codec=\(options.videoCodec)", "log_level=warn", "clipboard_autosync=false",
    ]
    if !options.video { args.append("video=false") }
    if !options.control { args.append("control=false") }
    if options.maxSize > 0 { args.append("max_size=\(options.maxSize)") }
    if options.videoBitRate > 0 { args.append("video_bit_rate=\(options.videoBitRate)") }
    return args.joined(separator: " ")
  }

  private static func openWithRetry(adb: NkasIosAdbClient, name: String) throws -> NkasIosAdbStream {
    let deadline = Date().addingTimeInterval(10)
    var lastError: Error = NkasIosAdbError.remote("scrcpy 服务未就绪")
    repeat {
      do { return try adb.openLocalAbstract(name) }
      catch NkasIosAdbError.remote(let message) { lastError = NkasIosAdbError.remote(message) }
      Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    throw lastError
  }
}
