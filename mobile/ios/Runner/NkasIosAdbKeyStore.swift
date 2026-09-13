import Foundation
import Security

struct NkasIosAdbKeyPair {
  let privateKey: SecKey
  let publicKeyData: Data

  var adbPublicKey: Data {
    NkasIosAdbKeyStore.encodeAdbPublicKey(publicKeyData)
  }

  func sign(_ token: Data) throws -> Data {
    var error: Unmanaged<CFError>?
    guard let signature = SecKeyCreateSignature(
      privateKey,
      .rsaSignatureMessagePKCS1v15SHA1,
      token as CFData,
      &error
    ) as Data? else {
      throw NkasIosAdbError.authentication
    }
    return signature
  }
}

enum NkasIosAdbKeyStore {
  private static let tag = Data("com.megumiss.nkas.mobile.adbkey".utf8)

  static func loadOrCreate() throws -> NkasIosAdbKeyPair {
    if let data = loadPrivateKey(), let pair = makePair(privateData: data) {
      return pair
    }
    var error: Unmanaged<CFError>?
    guard let privateKey = SecKeyCreateRandomKey([
      kSecAttrKeyType: kSecAttrKeyTypeRSA,
      kSecAttrKeySizeInBits: 2048,
    ] as CFDictionary, &error),
    let privateData = SecKeyCopyExternalRepresentation(privateKey, &error) as Data?,
    let pair = makePair(privateData: privateData) else {
      throw NkasIosAdbError.authentication
    }
    savePrivateKey(privateData)
    return pair
  }

  private static func makePair(privateData: Data) -> NkasIosAdbKeyPair? {
    guard let privateKey = SecKeyCreateWithData(privateData as CFData, [
      kSecAttrKeyType: kSecAttrKeyTypeRSA,
      kSecAttrKeyClass: kSecAttrKeyClassPrivate,
    ] as CFDictionary, nil),
    let publicKey = SecKeyCopyPublicKey(privateKey),
    let publicData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
      return nil
    }
    return NkasIosAdbKeyPair(privateKey: privateKey, publicKeyData: publicData)
  }

  private static func loadPrivateKey() -> Data? {
    let query: [CFString: Any] = [
      kSecClass: kSecClassKey,
      kSecAttrKeyType: kSecAttrKeyTypeRSA,
      kSecAttrApplicationTag: tag,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
    return result as? Data
  }

  private static func savePrivateKey(_ data: Data) {
    SecItemDelete([
      kSecClass: kSecClassKey,
      kSecAttrApplicationTag: tag,
    ] as CFDictionary)
    SecItemAdd([
      kSecClass: kSecClassKey,
      kSecAttrKeyType: kSecAttrKeyTypeRSA,
      kSecAttrKeyClass: kSecAttrKeyClassPrivate,
      kSecAttrApplicationTag: tag,
      kSecValueData: data,
    ] as CFDictionary, nil)
  }

  static func encodeAdbPublicKey(_ der: Data) -> Data {
    var parser = DerParser(der)
    _ = parser.readTag(0x30)
    let modulus = parser.readInteger()
    let exponentData = parser.readInteger()
    var exponent: UInt32 = 0
    for byte in exponentData { exponent = (exponent << 8) | UInt32(byte) }

    let size = 256
    let paddedModulus = pad(modulus, to: size)
    let modulusLE = littleEndianWords(paddedModulus)
    let rrLE = littleEndianWords(pad(moduloPowerOfTwo(modulus, bits: size * 16), to: size))
    let low = UInt64(modulus.suffix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
    let inverse = modularInverse(low == 0 ? 1 : low)
    let n0inv = UInt32((0x1_0000_0000 - inverse) & 0xffff_ffff)

    var body = Data()
    body.append(contentsOf: UInt32(64).bytesLE)
    body.append(contentsOf: n0inv.bytesLE)
    body.append(modulusLE)
    body.append(rrLE)
    body.append(contentsOf: exponent.bytesLE)
    return Data((body.base64EncodedString() + " nkas-mobile\0").utf8)
  }

  private static func pad(_ value: Data, to size: Int) -> Data {
    let trimmed = value.drop(while: { $0 == 0 })
    var result = Data(repeating: 0, count: max(0, size - trimmed.count))
    result.append(trimmed)
    return result
  }

  private static func littleEndianWords(_ value: Data) -> Data {
    var result = Data(repeating: 0, count: value.count)
    for word in 0..<(value.count / 4) {
      let source = value.count - (word + 1) * 4
      result[word * 4] = value[source + 3]
      result[word * 4 + 1] = value[source + 2]
      result[word * 4 + 2] = value[source + 1]
      result[word * 4 + 3] = value[source]
    }
    return result
  }

  private static func moduloPowerOfTwo(_ modulus: Data, bits: Int) -> Data {
    var value = Data(repeating: 0, count: modulus.count + 1)
    value[value.count - 1] = 1
    for _ in 0..<bits {
      value = shiftLeft(value)
      if compare(value, modulus) >= 0 { value = subtract(value, modulus) }
    }
    return value.suffix(modulus.count)
  }

  private static func shiftLeft(_ input: Data) -> Data {
    var output = Data(repeating: 0, count: input.count)
    var carry: UInt8 = 0
    for index in stride(from: input.count - 1, through: 0, by: -1) {
      let byte = input[index]
      output[index] = (byte << 1) | carry
      carry = byte & 0x80 == 0 ? 0 : 1
    }
    return output
  }

  private static func compare(_ left: Data, _ right: Data) -> Int {
    let padded = Data(repeating: 0, count: max(0, left.count - right.count)) + right
    for index in 0..<left.count where left[index] != padded[index] {
      return left[index] < padded[index] ? -1 : 1
    }
    return 0
  }

  private static func subtract(_ left: Data, _ right: Data) -> Data {
    let padded = Data(repeating: 0, count: max(0, left.count - right.count)) + right
    var result = Data(repeating: 0, count: left.count)
    var borrow = 0
    for index in stride(from: left.count - 1, through: 0, by: -1) {
      let value = Int(left[index]) - Int(padded[index]) - borrow
      result[index] = UInt8(value >= 0 ? value : value + 256)
      borrow = value >= 0 ? 0 : 1
    }
    return result
  }

  private static func modularInverse(_ value: UInt64) -> UInt64 {
    var result: UInt64 = 1
    for _ in 0..<32 { result = result &* (2 &- value &* result) }
    return result
  }
}

private struct DerParser {
  let data: Data
  var offset = 0

  init(_ data: Data) { self.data = data }

  mutating func readTag(_ expected: UInt8) -> Int {
    precondition(data[offset] == expected)
    offset += 1
    return readLength()
  }

  mutating func readInteger() -> Data {
    precondition(data[offset] == 0x02)
    offset += 1
    let length = readLength()
    let value = data.subdata(in: offset..<(offset + length))
    offset += length
    return Data(value.drop(while: { $0 == 0 }))
  }

  mutating private func readLength() -> Int {
    let first = data[offset]
    offset += 1
    if first & 0x80 == 0 { return Int(first) }
    let count = Int(first & 0x7f)
    var length = 0
    for _ in 0..<count {
      length = (length << 8) | Int(data[offset])
      offset += 1
    }
    return length
  }
}

private extension UInt32 {
  var bytesLE: [UInt8] {
    [UInt8(self & 0xff), UInt8((self >> 8) & 0xff), UInt8((self >> 16) & 0xff), UInt8((self >> 24) & 0xff)]
  }
}
