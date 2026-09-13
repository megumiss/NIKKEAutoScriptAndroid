import Foundation

final class NkasIosAdbClient {
  private var input: InputStream?
  private var output: OutputStream?
  private var nextLocalId: UInt32 = 1
  private let lock = NSLock()
  private var keyPair: NkasIosAdbKeyPair?

  func connect(endpoint: String) throws {
    let parsed = try Endpoint(endpoint)
    close()

    var inputStream: InputStream?
    var outputStream: OutputStream?
    Stream.getStreamsToHost(withName: parsed.host, port: parsed.port, inputStream: &inputStream, outputStream: &outputStream)
    guard let inputStream, let outputStream else {
      throw NkasIosAdbError.connection("无法创建 ADB TCP 流")
    }
    inputStream.open()
    outputStream.open()
    self.input = inputStream
    self.output = outputStream

    keyPair = try NkasIosAdbKeyStore.loadOrCreate()
    try send(command: .cnxn, arg0: 0x01000000, arg1: 256 * 1024, payload: Data("host::features=shell_v2\0".utf8))
    var signatureSent = false
    while true {
      let packet = try readPacket()
      switch packet.command {
      case .cnxn:
        return
      case .auth:
        guard packet.arg0 == 1, let keyPair else {
          throw NkasIosAdbError.authentication
        }
        if !signatureSent {
          try send(command: .auth, arg0: 2, arg1: 0, payload: try keyPair.sign(packet.payload))
          signatureSent = true
        } else {
          try send(command: .auth, arg0: 3, arg1: 0, payload: keyPair.adbPublicKey)
        }
      default:
        continue
      }
    }
  }

  func shell(_ command: String) throws -> String {
    let stream = try open("shell:\(command)")
    let data = try stream.readToClose()
    return String(data: data, encoding: .utf8) ?? ""
  }

  func openLocalAbstract(_ name: String) throws -> NkasIosAdbStream {
    try open("localabstract:\(name)")
  }

  func push(_ data: Data, remotePath: String, mode: UInt32 = 0o644) throws {
    guard remotePath.hasPrefix("/") else { throw NkasIosAdbError.invalidPath(remotePath) }
    let stream = try open("sync:")
    defer { stream.close() }
    let path = Data("\(remotePath),\(mode)".utf8)
    try stream.writeSync(id: "SEND", length: UInt32(path.count))
    try stream.writeExactly(path)
    var offset = 0
    while offset < data.count {
      let count = min(64 * 1024, data.count - offset)
      try stream.writeSync(id: "DATA", length: UInt32(count))
      try stream.writeExactly(data.subdata(in: offset..<(offset + count)))
      offset += count
    }
    try stream.writeSync(id: "DONE", length: UInt32(Date().timeIntervalSince1970))
    try stream.expectSyncOkay(operation: "push")
  }

  func pull(remotePath: String) throws -> Data {
    guard remotePath.hasPrefix("/") else { throw NkasIosAdbError.invalidPath(remotePath) }
    let stream = try open("sync:")
    defer { stream.close() }
    let path = Data(remotePath.utf8)
    try stream.writeSync(id: "RECV", length: UInt32(path.count))
    try stream.writeExactly(path)
    var result = Data()
    while true {
      let id = try stream.readASCII(4)
      let length = try stream.readUInt32LE()
      switch id {
      case "DATA":
        guard length <= 16 * 1024 * 1024 else { throw NkasIosAdbError.protocolError("ADB pull 数据块过大") }
        result.append(try stream.readExactly(Int(length)))
      case "DONE":
        return result
      case "FAIL":
        let message = String(data: try stream.readExactly(Int(length)), encoding: .utf8) ?? "未知错误"
        throw NkasIosAdbError.remote(message)
      default:
        throw NkasIosAdbError.protocolError("ADB pull 返回未知同步命令：\(id)")
      }
    }
  }

  func close() {
    input?.close()
    output?.close()
    input = nil
    output = nil
  }

  private func open(_ destination: String) throws -> NkasIosAdbStream {
    guard input != nil, output != nil else { throw NkasIosAdbError.notConnected }
    let localId = nextLocalId
    nextLocalId &+= 1
    try send(command: .open, arg0: localId, arg1: 0, payload: Data(destination.utf8) + Data([0]))
    while true {
      let packet = try readPacket()
      if packet.command == .okay && packet.arg0 == localId {
        return NkasIosAdbStream(client: self, localId: localId, remoteId: packet.arg1)
      }
      if packet.command == .clse && packet.arg0 == localId {
        throw NkasIosAdbError.rejected(destination)
      }
    }
  }

  fileprivate func write(localId: UInt32, remoteId: UInt32, data: Data) throws {
    try send(command: .wrte, arg0: localId, arg1: remoteId, payload: data)
    _ = try readPacket(expected: .okay)
  }

  fileprivate func readPacket(expected: Command? = nil) throws -> Packet {
    let header = try readExactly(24)
    let command = Command(rawValue: header.uint32LE(at: 0))
    let arg0 = header.uint32LE(at: 4)
    let arg1 = header.uint32LE(at: 8)
    let length = Int(header.uint32LE(at: 12))
    guard let command else { throw NkasIosAdbError.protocolError("未知 ADB 命令") }
    let payload = try readExactly(length)
    if let expected, command != expected { throw NkasIosAdbError.protocolError("ADB 响应不是预期类型") }
    return Packet(command: command, arg0: arg0, arg1: arg1, payload: payload)
  }

  private func send(command: Command, arg0: UInt32, arg1: UInt32, payload: Data) throws {
    var packet = Data()
    packet.append(contentsOf: command.rawValue.bytesLE)
    packet.append(contentsOf: arg0.bytesLE)
    packet.append(contentsOf: arg1.bytesLE)
    packet.append(contentsOf: UInt32(payload.count).bytesLE)
    packet.append(contentsOf: UInt32(payload.reduce(0) { $0 &+ UInt32($1) }).bytesLE)
    packet.append(contentsOf: (command.rawValue ^ 0xFFFFFFFF).bytesLE)
    packet.append(payload)
    try writeExactly(packet)
  }

  private func readExactly(_ count: Int) throws -> Data {
    var result = Data()
    result.reserveCapacity(count)
    while result.count < count {
      var buffer = [UInt8](repeating: 0, count: count - result.count)
      let read = input?.read(&buffer, maxLength: buffer.count) ?? -1
      if read <= 0 { throw NkasIosAdbError.connection("ADB 连接已断开") }
      result.append(contentsOf: buffer.prefix(read))
    }
    return result
  }

  private func writeExactly(_ data: Data) throws {
    lock.lock()
    defer { lock.unlock() }
    var offset = 0
    while offset < data.count {
      let written = data.withUnsafeBytes { raw in
        output?.write(raw.bindMemory(to: UInt8.self).baseAddress!.advanced(by: offset), maxLength: data.count - offset) ?? -1
      }
      if written <= 0 { throw NkasIosAdbError.connection("ADB 写入失败") }
      offset += written
    }
  }

  private struct Endpoint {
    let host: String
    let port: Int

    init(_ value: String) throws {
      let raw = value.hasPrefix("adb://") ? String(value.dropFirst(6)) : value
      guard let separator = raw.lastIndex(of: ":"), let port = Int(raw[raw.index(after: separator)...]), port > 0, port <= 65535 else {
        throw NkasIosAdbError.invalidEndpoint(value)
      }
      host = String(raw[..<separator])
      self.port = port
    }
  }

  fileprivate enum Command: UInt32 {
    case cnxn = 0x4E584E43
    case auth = 0x48545541
    case open = 0x4E45504F
    case okay = 0x59414B4F
    case clse = 0x45534C43
    case wrte = 0x45545257
  }

  fileprivate struct Packet {
    let command: Command
    let arg0: UInt32
    let arg1: UInt32
    let payload: Data
  }
}

final class NkasIosAdbStream {
  private weak var client: NkasIosAdbClient?
  private let localId: UInt32
  private let remoteId: UInt32
  private var closed = false
  private var pendingData = Data()

  fileprivate init(client: NkasIosAdbClient, localId: UInt32, remoteId: UInt32) {
    self.client = client
    self.localId = localId
    self.remoteId = remoteId
  }

  func write(_ data: Data) throws {
    guard !closed, let client else { throw NkasIosAdbError.notConnected }
    try client.write(localId: localId, remoteId: remoteId, data: data)
  }

  func readToClose() throws -> Data {
    guard let client else { throw NkasIosAdbError.notConnected }
    var output = Data()
    while !closed {
      let packet = try client.readPacket()
      guard packet.arg0 == remoteId else { continue }
      switch packet.command {
      case .wrte:
        output.append(packet.payload)
        try client.write(localId: localId, remoteId: remoteId, data: Data())
      case .clse:
        closed = true
      default:
        break
      }
    }
    return output
  }

  func close() {
    closed = true
  }

  fileprivate func writeSync(id: String, length: UInt32) throws {
    guard id.utf8.count == 4 else { throw NkasIosAdbError.protocolError("同步命令长度无效") }
    try writeExactly(Data(id.utf8))
    try writeExactly(length.bytesLEData)
  }

  fileprivate func expectSyncOkay(operation: String) throws {
    let id = try readASCII(4)
    let length = try readUInt32LE()
    guard id == "OKAY" else {
      let message = String(data: try readExactly(Int(length)), encoding: .utf8) ?? id
      throw NkasIosAdbError.remote("ADB \(operation) 失败：\(message)")
    }
    if length > 0 { _ = try readExactly(Int(length)) }
  }

  fileprivate func readASCII(_ count: Int) throws -> String {
    String(data: try readExactly(count), encoding: .ascii) ?? ""
  }

  fileprivate func readUInt32LE() throws -> UInt32 {
    try readExactly(4).uint32LE(at: 0)
  }

  fileprivate func readExactly(_ count: Int) throws -> Data {
    guard let client else { throw NkasIosAdbError.notConnected }
    var result = Data()
    while result.count < count {
      if !pendingData.isEmpty {
        let needed = count - result.count
        let take = min(needed, pendingData.count)
        result.append(pendingData.prefix(take))
        pendingData.removeFirst(take)
        continue
      }
      let packet = try client.readPacket()
      guard packet.command == .wrte, packet.arg0 == remoteId else {
        if packet.command == .clse { closed = true }
        continue
      }
      pendingData.append(packet.payload)
      try client.send(command: .okay, arg0: localId, arg1: remoteId, payload: Data())
    }
    return result.prefix(count)
  }

  fileprivate func writeExactly(_ data: Data) throws {
    var offset = 0
    while offset < data.count {
      let count = min(64 * 1024, data.count - offset)
      try write(data.subdata(in: offset..<(offset + count)))
      offset += count
    }
  }
}

enum NkasIosAdbError: LocalizedError {
  case invalidEndpoint(String)
  case invalidPath(String)
  case connection(String)
  case authentication
  case notConnected
  case rejected(String)
  case remote(String)
  case protocolError(String)

  var errorDescription: String? {
    switch self {
    case .invalidEndpoint(let value): return "无效的 ADB 地址：\(value)"
    case .invalidPath(let value): return "无效的 ADB 路径：\(value)"
    case .connection(let message), .protocolError(let message), .remote(let message): return message
    case .authentication: return "iOS ADB 需要设备认证，当前密钥后端尚未接入"
    case .notConnected: return "ADB 尚未连接"
    case .rejected(let destination): return "ADB 服务被设备拒绝：\(destination)"
    }
  }
}

private extension UInt32 {
  var bytesLE: [UInt8] {
    [UInt8(self & 0xff), UInt8((self >> 8) & 0xff), UInt8((self >> 16) & 0xff), UInt8((self >> 24) & 0xff)]
  }

  var bytesLEData: Data { Data(bytesLE) }
}

private extension Data {
  func uint32LE(at offset: Int) -> UInt32 {
    UInt32(self[index(startIndex, offsetBy: offset)]) |
      UInt32(self[index(startIndex, offsetBy: offset + 1)]) << 8 |
      UInt32(self[index(startIndex, offsetBy: offset + 2)]) << 16 |
      UInt32(self[index(startIndex, offsetBy: offset + 3)]) << 24
  }
}
