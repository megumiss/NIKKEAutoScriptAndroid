import Foundation

final class NkasIosScrcpyControl {
  private let stream: NkasIosAdbStream
  private let lock = NSLock()

  init(stream: NkasIosAdbStream) { self.stream = stream }

  func back(action: Int) throws {
    try send(Data([4, UInt8(action & 0xff)]))
  }

  func text(_ value: String) throws {
    let bytes = Data(value.utf8)
    guard bytes.count <= 1 << 20 else { throw NkasIosAdbError.protocolError("scrcpy 文本过长") }
    var data = Data([1])
    data.append(contentsOf: UInt32(bytes.count).bigEndianBytes)
    data.append(bytes)
    try send(data)
  }

  func keycode(action: Int, keycode: Int, repeatCount: Int, metaState: Int) throws {
    var data = Data([0, UInt8(action & 0xff)])
    data.append(contentsOf: UInt32(keycode).bigEndianBytes)
    data.append(contentsOf: UInt32(repeatCount).bigEndianBytes)
    data.append(contentsOf: UInt32(metaState).bigEndianBytes)
    try send(data)
  }

  func touch(action: Int, pointerId: UInt64, x: Int, y: Int, width: Int, height: Int, pressure: Double, actionButton: Int, buttons: Int) throws {
    guard width > 0, width <= 0xffff, height > 0, height <= 0xffff else {
      throw NkasIosAdbError.protocolError("scrcpy 屏幕尺寸无效")
    }
    var data = Data([2, UInt8(action & 0xff)])
    data.append(contentsOf: pointerId.bigEndianBytes)
    data.append(contentsOf: UInt32(x).bigEndianBytes)
    data.append(contentsOf: UInt32(y).bigEndianBytes)
    data.append(contentsOf: UInt16(width).bigEndianBytes)
    data.append(contentsOf: UInt16(height).bigEndianBytes)
    let encodedPressure = pressure >= 1 ? UInt16.max : UInt16(max(0, pressure) * 65536)
    data.append(contentsOf: encodedPressure.bigEndianBytes)
    data.append(contentsOf: UInt32(actionButton).bigEndianBytes)
    data.append(contentsOf: UInt32(buttons).bigEndianBytes)
    try send(data)
  }

  private func send(_ data: Data) throws {
    lock.lock()
    defer { lock.unlock() }
    try stream.write(data)
  }
}

private extension UInt16 {
  var bigEndianBytes: [UInt8] { [UInt8(self >> 8), UInt8(self & 0xff)] }
}

private extension UInt32 {
  var bigEndianBytes: [UInt8] {
    [UInt8(self >> 24), UInt8(self >> 16), UInt8(self >> 8), UInt8(self & 0xff)]
  }
}

private extension UInt64 {
  var bigEndianBytes: [UInt8] {
    [UInt8(self >> 56), UInt8(self >> 48), UInt8(self >> 40), UInt8(self >> 32), UInt8(self >> 24), UInt8(self >> 16), UInt8(self >> 8), UInt8(self & 0xff)]
  }
}
