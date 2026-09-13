import Foundation
import Network

struct NkasIosAdbEndpoint {
  let host: String
  let port: Int
  var serial: String { "\(host.contains(":") ? "[\(host)]" : host):\(port)" }

  init(_ value: String) throws {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let raw = value.hasPrefix("adb://") ? String(value.dropFirst(6)) : value
    guard let colon = raw.lastIndex(of: ":"),
          let port = Int(raw[raw.index(after: colon)...]), (1...65535).contains(port) else {
      throw NkasIosAdbError.invalidEndpoint(value)
    }
    let rawHost = String(raw[..<colon])
    let bracketed = rawHost.hasPrefix("[") && rawHost.hasSuffix("]")
    let host = bracketed ? String(rawHost.dropFirst().dropLast()) : rawHost
    guard !host.isEmpty,
          host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
          !host.contains(where: { "/?#@\0[]".contains($0) }),
          (!host.contains(":") || bracketed) else {
      throw NkasIosAdbError.invalidEndpoint(value)
    }
    self.host = host
    self.port = port
  }
}

// adb-mobile owns the device transport, RSA/TLS authentication and ADB flow
// control. Every service below has its own local smart socket.
final class NkasIosAdbClient {
  private let lock = NSLock()
  private var endpoint: NkasIosAdbEndpoint?
  private var port = 0
  private var sockets: [UUID: NkasIosAdbSocket] = [:]
  private var revision = 0
  private var interrupted = false

  func connect(endpoint value: String, isCancelled: () -> Bool = { false }) throws {
    let parsed = try NkasIosAdbEndpoint(value)
    close()
    lock.lock()
    interrupted = false
    let token = revision
    lock.unlock()
    guard !isCancelled() else { throw NkasIosAdbError.notConnected }
    let serverPort = try NkasAdbRuntime.shared.start()
    guard serverPort > 0 else { throw NkasIosAdbError.connection("ADB 服务未启动") }
    let socket = try newSocket(port: serverPort, token: token)
    defer { socket.close() }
    lock.lock()
    guard revision == token, !interrupted else { lock.unlock(); throw NkasIosAdbError.notConnected }
    port = serverPort
    endpoint = parsed
    lock.unlock()
    var response = ""
    do {
      try socket.request("host:connect:\(parsed.serial)")
      response = try socket.readProtocolString()
      let probe = try transport()
      probe.close()
    } catch {
      close()
      throw NkasIosAdbError.connection(response.isEmpty ? error.localizedDescription : response)
    }
  }

  func shell(_ command: String) throws -> String {
    let stream = try openShellStream(command)
    defer { stream.close() }
    return String(decoding: try stream.readToClose(), as: UTF8.self)
  }

  func openLocalAbstract(_ name: String) throws -> NkasIosAdbStream {
    try open("localabstract:\(name)")
  }

  func openShellStream(_ command: String) throws -> NkasIosAdbStream {
    try open("shell:\(command)")
  }

  func push(_ data: Data, remotePath: String, mode: UInt32 = 0o644) throws {
    try validatePath(remotePath)
    let stream = try open("sync:")
    defer { stream.close() }
    let path = Data("\(remotePath),\(mode)".utf8)
    try stream.write(syncHeader("SEND", UInt32(path.count)) + path)
    var offset = 0
    while offset < data.count {
      let count = min(64 * 1024, data.count - offset)
      try stream.write(syncHeader("DATA", UInt32(count)) + data.subdata(in: offset..<(offset + count)))
      offset += count
    }
    try stream.write(syncHeader("DONE", UInt32(clamping: Int(Date().timeIntervalSince1970))))
    let header = try stream.readExactly(8)
    let id = String(decoding: header.prefix(4), as: UTF8.self)
    let length = header.uint32LE(at: 4)
    if id == "FAIL" { throw try syncFailure(stream, length: length) }
    guard id == "OKAY", length == 0 else { throw NkasIosAdbError.protocolError("ADB push 响应无效") }
  }

  func pull(remotePath: String) throws -> Data {
    try validatePath(remotePath)
    let stream = try open("sync:")
    defer { stream.close() }
    let path = Data(remotePath.utf8)
    try stream.write(syncHeader("RECV", UInt32(path.count)) + path)
    var result = Data()
    while true {
      let header = try stream.readExactly(8)
      let id = String(decoding: header.prefix(4), as: UTF8.self)
      let length = header.uint32LE(at: 4)
      switch id {
      case "DATA":
        guard length <= 64 * 1024, result.count + Int(length) <= 128 * 1024 * 1024 else {
          throw NkasIosAdbError.protocolError("ADB pull 数据超出限制")
        }
        result.append(try stream.readExactly(Int(length)))
      case "DONE":
        return result
      case "FAIL":
        throw try syncFailure(stream, length: length)
      default:
        throw NkasIosAdbError.protocolError("未知 ADB 同步响应：\(id)")
      }
    }
  }

  func close() {
    lock.lock()
    revision &+= 1
    interrupted = true
    let active = Array(sockets.values)
    sockets.removeAll()
    let previous = endpoint
    let serverPort = port
    endpoint = nil
    port = 0
    lock.unlock()
    active.forEach { $0.close() }
    if let previous, let socket = try? NkasIosAdbSocket(port: serverPort) {
      defer { socket.close() }
      do {
        try socket.connect(timeout: 1)
        try socket.request("host:disconnect:\(previous.serial)", timeout: 1)
      } catch { /* The transport is also closed when its tsnet forward is stopped. */ }
    }
  }

  func interrupt() {
    lock.lock()
    revision &+= 1
    interrupted = true
    let active = Array(sockets.values)
    lock.unlock()
    active.forEach { $0.close() }
  }

  private func newSocket(port: Int, token: Int) throws -> NkasIosAdbSocket {
    let socket = try NkasIosAdbSocket(port: port)
    let id = socket.id
    socket.onClose = { [weak self] in
      guard let self else { return }
      self.lock.lock()
      self.sockets.removeValue(forKey: id)
      self.lock.unlock()
    }
    lock.lock()
    guard revision == token, !interrupted else {
      lock.unlock()
      throw NkasIosAdbError.notConnected
    }
    sockets[id] = socket
    lock.unlock()
    do { try socket.connect(); return socket }
    catch { socket.close(); throw error }
  }

  private func transport() throws -> NkasIosAdbSocket {
    lock.lock()
    let current = interrupted ? nil : endpoint
    let serverPort = port
    let token = revision
    lock.unlock()
    guard let current else { throw NkasIosAdbError.notConnected }
    let socket = try newSocket(port: serverPort, token: token)
    do {
      try socket.request("host:transport:\(current.serial)")
      return socket
    } catch {
      socket.close()
      throw error
    }
  }

  private func open(_ service: String) throws -> NkasIosAdbStream {
    let socket = try transport()
    do {
      try socket.request(service)
      return NkasIosAdbStream(socket: socket, onClose: {})
    } catch {
      socket.close()
      throw error
    }
  }

  private func validatePath(_ path: String) throws {
    guard path.hasPrefix("/"), !path.contains("\0"), path.utf8.count <= 1024 else {
      throw NkasIosAdbError.invalidPath(path)
    }
  }

  private func syncHeader(_ id: String, _ value: UInt32) -> Data {
    var length = value.littleEndian
    return Data(id.utf8) + withUnsafeBytes(of: &length) { Data($0) }
  }

  private func syncFailure(_ stream: NkasIosAdbStream, length: UInt32) throws -> NkasIosAdbError {
    guard length <= 64 * 1024 else { return .protocolError("ADB 错误响应过大") }
    return .remote(String(decoding: try stream.readExactly(Int(length)), as: UTF8.self))
  }
}

final class NkasIosAdbStream {
  private let socket: NkasIosAdbSocket
  private let onClose: () -> Void
  private let lock = NSLock()
  private var closed = false

  fileprivate init(socket: NkasIosAdbSocket, onClose: @escaping () -> Void) {
    self.socket = socket
    self.onClose = onClose
  }

  func write(_ data: Data) throws { try socket.write(data) }

  func readExactly(_ count: Int, timeout: TimeInterval? = 15) throws -> Data {
    try socket.readExactly(count, timeout: timeout)
  }

  func readToClose(limit: Int = 8 * 1024 * 1024) throws -> Data {
    var result = Data()
    while let data = try socket.read(maxLength: 64 * 1024, timeout: nil) {
      guard result.count + data.count <= limit else { throw NkasIosAdbError.protocolError("ADB 输出超出限制") }
      result.append(data)
    }
    return result
  }

  func readChunk() throws -> Data? { try socket.read(maxLength: 64 * 1024, timeout: nil) }

  func close() {
    lock.lock()
    guard !closed else { lock.unlock(); return }
    closed = true
    lock.unlock()
    socket.close()
    onClose()
  }
}

private final class NkasIosAdbSocket {
  let id = UUID()
  var onClose: (() -> Void)?
  private let connection: NWConnection
  private let lock = NSLock()
  private var closed = false
  private static let queue = DispatchQueue(label: "com.megumiss.nkas.adb.socket", attributes: .concurrent)

  init(port: Int) throws {
    guard (1...65535).contains(port), let networkPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
      throw NkasIosAdbError.notConnected
    }
    connection = NWConnection(host: "127.0.0.1", port: networkPort, using: .tcp)
  }

  func connect(timeout: TimeInterval = 10) throws {
    lock.lock()
    let active = !closed
    lock.unlock()
    guard active else { throw NkasIosAdbError.notConnected }
    let result = NkasSocketResult<Void>()
    connection.stateUpdateHandler = { state in
      switch state {
      case .ready: result.finish(.success(()))
      case .failed(let error): result.finish(.failure(error))
      case .cancelled: result.finish(.failure(NkasIosAdbError.notConnected))
      default: break
      }
    }
    connection.start(queue: Self.queue)
    do { try result.wait(timeout: timeout) }
    catch { close(); throw error }
    connection.stateUpdateHandler = nil
  }

  func request(_ service: String, timeout: TimeInterval = 15) throws {
    let bytes = Data(service.utf8)
    guard !bytes.isEmpty, bytes.count <= 0xffff, !service.contains("\0") else {
      throw NkasIosAdbError.protocolError("无效的 ADB 服务请求")
    }
    try write(Data(String(format: "%04x", bytes.count).utf8) + bytes, timeout: timeout)
    let status = String(decoding: try readExactly(4, timeout: timeout), as: UTF8.self)
    if status == "FAIL" { throw NkasIosAdbError.remote(try readProtocolString(timeout: timeout)) }
    guard status == "OKAY" else { throw NkasIosAdbError.protocolError("无效的 ADB 服务响应") }
  }

  func readProtocolString(timeout: TimeInterval = 15) throws -> String {
    let header = String(decoding: try readExactly(4, timeout: timeout), as: UTF8.self)
    guard let length = Int(header, radix: 16), (0...0xffff).contains(length) else {
      throw NkasIosAdbError.protocolError("无效的 ADB 服务响应长度")
    }
    return String(decoding: try readExactly(length, timeout: timeout), as: UTF8.self)
  }

  func write(_ data: Data, timeout: TimeInterval = 15) throws {
    let result = NkasSocketResult<Void>()
    connection.send(content: data, completion: .contentProcessed { error in
      if let error { result.finish(.failure(error)) }
      else { result.finish(.success(())) }
    })
    do { try result.wait(timeout: timeout) }
    catch { close(); throw error }
  }

  func readExactly(_ count: Int, timeout: TimeInterval? = 15) throws -> Data {
    guard (0...32 * 1024 * 1024).contains(count) else { throw NkasIosAdbError.protocolError("ADB 数据长度无效") }
    var result = Data()
    while result.count < count {
      guard let chunk = try read(maxLength: count - result.count, timeout: timeout) else {
        throw NkasIosAdbError.connection("ADB 连接已断开")
      }
      result.append(chunk)
    }
    return result
  }

  func read(maxLength: Int, timeout: TimeInterval?) throws -> Data? {
    let result = NkasSocketResult<Data?>()
    connection.receive(minimumIncompleteLength: 1, maximumLength: maxLength) { data, _, _, error in
      if let error { result.finish(.failure(error)) }
      else { result.finish(.success(data?.isEmpty == false ? data : nil)) }
    }
    do { return try result.wait(timeout: timeout) }
    catch { close(); throw error }
  }

  func close() {
    lock.lock()
    guard !closed else { lock.unlock(); return }
    closed = true
    lock.unlock()
    connection.cancel()
    onClose?()
  }
}

private final class NkasSocketResult<Value> {
  private let lock = NSLock()
  private let done = DispatchSemaphore(value: 0)
  private var result: Result<Value, Error>?

  func finish(_ value: Result<Value, Error>) {
    lock.lock()
    guard result == nil else { lock.unlock(); return }
    result = value
    lock.unlock()
    done.signal()
  }

  func wait(timeout: TimeInterval?) throws -> Value {
    let deadline = timeout.map { DispatchTime.now() + $0 } ?? .distantFuture
    if done.wait(timeout: deadline) == .timedOut { throw NkasIosAdbError.connection("ADB 本地服务请求超时") }
    lock.lock()
    let value = result!
    lock.unlock()
    return try value.get()
  }
}

enum NkasIosAdbError: LocalizedError {
  case invalidEndpoint(String)
  case invalidPath(String)
  case connection(String)
  case notConnected
  case remote(String)
  case protocolError(String)

  var errorDescription: String? {
    switch self {
    case .invalidEndpoint(let value): return "无效的 ADB 地址：\(value)"
    case .invalidPath(let value): return "无效的 ADB 路径：\(value)"
    case .connection(let message), .protocolError(let message), .remote(let message): return message
    case .notConnected: return "ADB 尚未连接"
    }
  }
}

private extension Data {
  func uint32LE(at offset: Int) -> UInt32 {
    (0..<4).reduce(UInt32(0)) { $0 | UInt32(self[index(startIndex, offsetBy: offset + $1)]) << ($1 * 8) }
  }
}
