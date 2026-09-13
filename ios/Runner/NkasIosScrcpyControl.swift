import Foundation

final class NkasIosScrcpyControl {
  private let writer: (Data) throws -> Void
  private let lock = NSLock()

  init(write: @escaping (Data) throws -> Void) { writer = write }
  convenience init(stream: NkasIosAdbStream) { self.init(write: stream.write) }

  func back(action: Int) throws {
    guard (0...1).contains(action) else { throw invalidArguments() }
    try send(Data([4, UInt8(action)]))
  }

  func text(_ value: String) throws {
    let bytes = Data(value.utf8)
    guard bytes.count <= 300 else { throw NkasIosAdbError.protocolError("输入文本不能超过 300 个 UTF-8 字节") }
    var data = Data([1])
    data.appendBigEndian(UInt32(bytes.count))
    data.append(bytes)
    try send(data)
  }

  func keycode(action: Int, keycode: Int, repeatCount: Int, metaState: Int) throws {
    guard (0...1).contains(action), let code = UInt32(exactly: keycode),
          let repeats = UInt32(exactly: repeatCount), let meta = UInt32(exactly: metaState) else {
      throw invalidArguments()
    }
    var data = Data([0, UInt8(action)])
    data.appendBigEndian(code)
    data.appendBigEndian(repeats)
    data.appendBigEndian(meta)
    try send(data)
  }

  func touch(action: Int, pointerId: UInt64, x: Int, y: Int, width: Int, height: Int,
             pressure: Double, actionButton: Int, buttons: Int) throws {
    guard (1...65535).contains(width), (1...65535).contains(height),
          (0..<width).contains(x), (0..<height).contains(y), (0...255).contains(action),
          pressure.isFinite, let actionButton = UInt32(exactly: actionButton),
          let buttons = UInt32(exactly: buttons) else {
      throw invalidArguments()
    }
    var data = Data([2, UInt8(action)])
    data.appendBigEndian(pointerId)
    data.appendBigEndian(UInt32(x))
    data.appendBigEndian(UInt32(y))
    data.appendBigEndian(UInt16(width))
    data.appendBigEndian(UInt16(height))
    let normalized = min(1, max(0, pressure))
    let encoded = normalized >= 1 ? UInt16.max : UInt16(min(65534, (normalized * 65536).rounded()))
    data.appendBigEndian(encoded)
    data.appendBigEndian(actionButton)
    data.appendBigEndian(buttons)
    try send(data)
  }

  private func send(_ data: Data) throws {
    lock.lock()
    defer { lock.unlock() }
    try writer(data)
  }

  private func invalidArguments() -> NkasIosAdbError {
    .protocolError("scrcpy 输入参数无效")
  }
}
