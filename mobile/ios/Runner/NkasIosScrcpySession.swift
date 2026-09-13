import CoreVideo
import Foundation

struct NkasIosScrcpyOptions {
  let video: Bool
  let control: Bool
  let maxSize: Int
  let videoBitRate: Int
}

struct NkasIosScrcpyMetadata {
  let deviceName: String
  let codecId: UInt32
}

/// Owns the remote scrcpy server and its ADB streams. Video decoding is kept
/// as a separate layer so a connection can still be used for control while a
/// decoder is restarting.
final class NkasIosScrcpySession {
  let scid: UInt32
  let command: String
  let metadata: NkasIosScrcpyMetadata?
  let videoStream: NkasIosAdbStream?
  let controlStream: NkasIosAdbStream?

  private let serverStream: NkasIosAdbStream
  private let adb: NkasIosAdbClient
  private var closed = false
  private var videoThread: Thread?
  private var videoDecoder: NkasIosVideoDecoder?

  private init(
    adb: NkasIosAdbClient,
    scid: UInt32,
    command: String,
    serverStream: NkasIosAdbStream,
    videoStream: NkasIosAdbStream?,
    controlStream: NkasIosAdbStream?,
    metadata: NkasIosScrcpyMetadata?
  ) {
    self.adb = adb
    self.scid = scid
    self.command = command
    self.serverStream = serverStream
    self.videoStream = videoStream
    self.controlStream = controlStream
    self.metadata = metadata
  }

  static func start(
    adb: NkasIosAdbClient,
    serverJar: Data,
    options: NkasIosScrcpyOptions
  ) throws -> NkasIosScrcpySession {
    guard !serverJar.isEmpty else { throw NkasIosAdbError.remote("scrcpy-server 资源为空") }
    let scid = UInt32.random(in: 1..<0x7fff_ffff)
    let remotePath = "/data/local/tmp/nkas-scrcpy-server.jar"
    try adb.push(serverJar, remotePath: remotePath)
    let command = buildCommand(remotePath: remotePath, scid: scid, options: options)
    let serverStream = try adb.openShellStream(command)
    do {
      let socketName = String(format: "scrcpy_%08x", scid)
      let first = try openWithRetry(adb: adb, name: socketName)
      let videoStream = options.video ? first : nil
      let controlStream: NkasIosAdbStream?
      if options.control {
        controlStream = videoStream == nil ? first : try openWithRetry(adb: adb, name: socketName)
      } else {
        controlStream = nil
      }
      let metadata = videoStream.map(readMetadata)
      return NkasIosScrcpySession(
        adb: adb,
        scid: scid,
        command: command,
        serverStream: serverStream,
        videoStream: videoStream,
        controlStream: controlStream,
        metadata: metadata
      )
    } catch {
      serverStream.close()
      throw error
    }
  }

  func startServerMonitor(_ callback: @escaping (String?, Error?) -> Void) {
    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let self else { return }
      do {
        let data = try self.serverStream.readToClose()
        if !self.closed {
          let output = String(data: data, encoding: .utf8)
          callback(output, nil)
        }
      } catch {
        if !self.closed { callback(nil, error) }
      }
    }
  }

  func startVideo(
    onSize: @escaping (Int, Int) -> Void,
    onFrame: @escaping (CVPixelBuffer) -> Void,
    onError: @escaping (Error) -> Void,
    onStopped: @escaping () -> Void
  ) throws {
    guard let videoStream else { throw NkasIosVideoError.notConfigured }
    guard videoThread == nil else { return }
    videoThread = Thread { [weak self] in
      guard let self else { return }
      do {
        var width = 0
        var height = 0
        var configuration: Data?
        let decoder = NkasIosVideoDecoder(onFrame: onFrame)
        self.videoDecoder = decoder
        while !self.closed {
          let header = try videoStream.readExactly(12)
          let ptsAndFlags = header.uint64BE(at: 0)
          if ptsAndFlags & (1 << 63) != 0 {
            width = Int(header.uint32BE(at: 8 - 4))
            height = Int(header.uint32BE(at: 8))
            guard width > 0, height > 0 else { throw NkasIosVideoError.invalidConfiguration }
            onSize(width, height)
            if let configuration { try decoder.configure(configuration, width: width, height: height) }
            continue
          }
          let length = Int(header.uint32BE(at: 8))
          guard length >= 0, length <= 32 * 1024 * 1024 else { throw NkasIosVideoError.invalidConfiguration }
          let payload = try videoStream.readExactly(length)
          if ptsAndFlags & (1 << 62) != 0 {
            configuration = payload
            if width > 0, height > 0 { try decoder.configure(payload, width: width, height: height) }
          } else {
            try decoder.decode(payload, ptsUs: ptsAndFlags & ((1 << 61) - 1))
          }
        }
      } catch {
        if !self.closed { onError(error) }
      }
      onStopped()
    }
    videoThread?.start()
  }

  func close() {
    guard !closed else { return }
    closed = true
    videoStream?.close()
    if videoStream == nil || videoStream !== controlStream { controlStream?.close() }
    serverStream.close()
    videoThread?.cancel()
    videoThread = nil
    videoDecoder?.close()
    videoDecoder = nil
    adb.close()
  }

  private static func buildCommand(remotePath: String, scid: UInt32, options: NkasIosScrcpyOptions) -> String {
    var args = [
      "CLASSPATH=\(remotePath)", "app_process", "/", "com.genymobile.scrcpy.Server", "4.1",
      "scid=\(String(format: "%x", scid))", "tunnel_forward=true",
    ]
    if !options.video { args.append("video=false") }
    args.append("audio=false")
    if !options.control { args.append("control=false") }
    if options.maxSize > 0 { args.append("max_size=\(options.maxSize)") }
    if options.videoBitRate > 0 { args.append("video_bit_rate=\(options.videoBitRate)") }
    return args.joined(separator: " ")
  }

  private static func openWithRetry(adb: NkasIosAdbClient, name: String) throws -> NkasIosAdbStream {
    var lastError: Error?
    for _ in 0..<100 {
      do { return try adb.openLocalAbstract(name) }
      catch { lastError = error; Thread.sleep(forTimeInterval: 0.1) }
    }
    throw lastError ?? NkasIosAdbError.remote("无法连接 scrcpy socket")
  }

  private static func readMetadata(_ stream: NkasIosAdbStream) -> NkasIosScrcpyMetadata {
    do {
      _ = try stream.readExactly(1)
      let rawName = try stream.readExactly(64)
      let name = String(data: rawName.prefix(while: { $0 != 0 }), encoding: .utf8) ?? "Android"
      let codec = try stream.readExactly(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
      return NkasIosScrcpyMetadata(deviceName: name, codecId: codec)
    } catch {
      return NkasIosScrcpyMetadata(deviceName: "Android", codecId: 0)
    }
  }
}

private extension Data {
  func uint32BE(at offset: Int) -> UInt32 {
    UInt32(self[index(startIndex, offsetBy: offset)]) << 24 |
      UInt32(self[index(startIndex, offsetBy: offset + 1)]) << 16 |
      UInt32(self[index(startIndex, offsetBy: offset + 2)]) << 8 |
      UInt32(self[index(startIndex, offsetBy: offset + 3)])
  }

  func uint64BE(at offset: Int) -> UInt64 {
    var value: UInt64 = 0
    for index in 0..<8 { value = (value << 8) | UInt64(self[self.index(startIndex, offsetBy: offset + index)]) }
    return value
  }
}
