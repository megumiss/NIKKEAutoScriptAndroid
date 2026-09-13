import Foundation

enum NkasScrcpyVideoHeader: Equatable {
  case size(Int, Int)
  case packet(length: Int, pts: UInt64, configuration: Bool, keyFrame: Bool)

  init(_ data: Data) throws {
    guard data.count == 12 else { throw NkasIosAdbError.protocolError("scrcpy 帧头长度无效") }
    let flags = data.bigEndianInteger(at: 0, count: 8)
    if flags & (1 << 63) != 0 {
      let width = Int(data.bigEndianInteger(at: 4, count: 4))
      let height = Int(data.bigEndianInteger(at: 8, count: 4))
      guard (1...65535).contains(width), (1...65535).contains(height) else {
        throw NkasIosAdbError.protocolError("scrcpy 视频尺寸无效")
      }
      self = .size(width, height)
    } else {
      let length = Int(data.bigEndianInteger(at: 8, count: 4))
      guard (1...32 * 1024 * 1024).contains(length) else {
        throw NkasIosAdbError.protocolError("scrcpy 视频帧长度无效")
      }
      self = .packet(length: length, pts: flags & ((1 << 61) - 1),
                     configuration: flags & (1 << 62) != 0, keyFrame: flags & (1 << 61) != 0)
    }
  }
}

enum NkasAnnexB {
  static func units(_ data: Data) -> [Data] {
    let bytes = [UInt8](data)
    var starts: [(offset: Int, prefix: Int)] = []
    var index = 0
    while index + 3 <= bytes.count {
      if bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 1 {
        starts.append((index, 3))
        index += 3
      } else if index + 4 <= bytes.count, bytes[index] == 0, bytes[index + 1] == 0,
                bytes[index + 2] == 0, bytes[index + 3] == 1 {
        starts.append((index, 4))
        index += 4
      } else {
        index += 1
      }
    }
    return starts.enumerated().compactMap { position, start in
      let end = position + 1 < starts.count ? starts[position + 1].offset : bytes.count
      guard start.offset + start.prefix < end else { return nil }
      return Data(bytes[(start.offset + start.prefix)..<end])
    }
  }

  static func lengthPrefixed(_ data: Data) throws -> Data {
    let units = units(data)
    guard !units.isEmpty else { throw NkasIosAdbError.protocolError("scrcpy NAL 数据无效") }
    var result = Data()
    for unit in units {
      result.appendBigEndian(UInt32(unit.count))
      result.append(unit)
    }
    return result
  }
}

extension Data {
  mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
    var encoded = value.bigEndian
    Swift.withUnsafeBytes(of: &encoded) { append(contentsOf: $0) }
  }

  func bigEndianInteger(at offset: Int, count: Int) -> UInt64 {
    (0..<count).reduce(UInt64(0)) { ($0 << 8) | UInt64(self[index(startIndex, offsetBy: offset + $1)]) }
  }
}
