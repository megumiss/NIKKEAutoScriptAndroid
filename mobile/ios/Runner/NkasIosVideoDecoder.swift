import CoreMedia
import Foundation
import VideoToolbox

final class NkasIosVideoDecoder {
  private let onFrame: (CVPixelBuffer) -> Void
  private var decompressionSession: VTDecompressionSession?
  private var formatDescription: CMVideoFormatDescription?
  private var width = 0
  private var height = 0

  init(onFrame: @escaping (CVPixelBuffer) -> Void) {
    self.onFrame = onFrame
  }

  func configure(_ data: Data, width: Int, height: Int) throws {
    let parameterSets = annexBParameterSets(data)
    guard parameterSets.count >= 2 else { throw NkasIosVideoError.invalidConfiguration }
    self.width = width
    self.height = height
    var description: CMVideoFormatDescription?
    let status = parameterSets[0].withUnsafeBytes { spsRaw in
      parameterSets[1].withUnsafeBytes { ppsRaw in
        var pointers: [UnsafePointer<UInt8>?] = [
          spsRaw.baseAddress!.assumingMemoryBound(to: UInt8.self),
          ppsRaw.baseAddress!.assumingMemoryBound(to: UInt8.self),
        ]
        var sizes = [parameterSets[0].count, parameterSets[1].count]
        return CMVideoFormatDescriptionCreateFromH264ParameterSets(
          allocator: kCFAllocatorDefault,
          parameterSetCount: 2,
          parameterSetPointers: &pointers,
          parameterSetSizes: &sizes,
          nalUnitHeaderLength: 4,
          formatDescriptionOut: &description
        )
      }
    }
    guard status == noErr else { throw NkasIosVideoError.videoToolbox(status) }
    guard let description else { throw NkasIosVideoError.invalidConfiguration }
    formatDescription = description
    decompressionSession?.invalidate()
    var callback = VTDecompressionOutputCallbackRecord(
      decompressionOutputCallback: { refCon, _, status, _, imageBuffer, _, _ in
        guard status == noErr, let refCon, let imageBuffer = imageBuffer as? CVPixelBuffer else { return }
        Unmanaged<NkasIosVideoDecoder>.fromOpaque(refCon).takeUnretainedValue().onFrame(imageBuffer)
      },
      decompressionOutputRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    )
    var session: VTDecompressionSession?
    let status = VTDecompressionSessionCreate(
      allocator: kCFAllocatorDefault,
      formatDescription: description,
      decoderSpecification: nil,
      imageBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelBufferWidthKey: width,
        kCVPixelBufferHeightKey: height,
      ] as CFDictionary,
      outputCallback: &callback,
      decompressionSessionOut: &session
    )
    guard status == noErr, let session else { throw NkasIosVideoError.videoToolbox(status) }
    decompressionSession = session
  }

  func decode(_ data: Data, ptsUs: UInt64) throws {
    guard let session, let formatDescription else { throw NkasIosVideoError.notConfigured }
    let avcc = annexBToAvcc(data)
    var blockBuffer: CMBlockBuffer?
    let blockStatus = CMBlockBufferCreateWithMemoryBlock(
      allocator: kCFAllocatorDefault,
      memoryBlock: nil,
      blockLength: avcc.count,
      blockAllocator: kCFAllocatorDefault,
      customBlockSource: nil,
      offsetToData: 0,
      dataLength: avcc.count,
      flags: 0,
      blockBufferOut: &blockBuffer
    )
    guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else { throw NkasIosVideoError.videoToolbox(blockStatus) }
    let copyStatus = avcc.withUnsafeBytes { raw in
      CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: avcc.count)
    }
    guard copyStatus == kCMBlockBufferNoErr else { throw NkasIosVideoError.videoToolbox(copyStatus) }
    var timing = CMSampleTimingInfo(
      duration: CMTime.invalid,
      presentationTimeStamp: CMTime(value: CMTimeValue(ptsUs), timescale: 1_000_000),
      decodeTimeStamp: .invalid
    )
    var sampleBuffer: CMSampleBuffer?
    let sampleStatus = CMSampleBufferCreateReady(
      allocator: kCFAllocatorDefault,
      dataBuffer: blockBuffer,
      formatDescription: formatDescription,
      sampleCount: 1,
      sampleTimingEntryCount: 1,
      sampleTimingArray: &timing,
      sampleSizeEntryCount: 1,
      sampleSizeArray: [avcc.count],
      sampleBufferOut: &sampleBuffer
    )
    guard sampleStatus == noErr, let sampleBuffer else { throw NkasIosVideoError.videoToolbox(sampleStatus) }
    var flags = VTDecodeInfoFlags()
    let status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sampleBuffer, flags: [], frameOptions: nil, infoFlagsOut: &flags)
    guard status == noErr || status == kVTVideoDecoderMalfunctionErr else { throw NkasIosVideoError.videoToolbox(status) }
  }

  func close() {
    decompressionSession?.invalidate()
    decompressionSession = nil
    formatDescription = nil
  }

  private func annexBParameterSets(_ data: Data) -> [Data] {
    annexBNals(data).filter { guard let first = $0.first else { return false }; return first & 0x1f == 7 || first & 0x1f == 8 }
  }

  private func annexBToAvcc(_ data: Data) -> Data {
    var output = Data()
    for nal in annexBNals(data) {
      var length = UInt32(nal.count).bigEndian
      withUnsafeBytes(of: &length) { output.append(contentsOf: $0) }
      output.append(nal)
    }
    return output.isEmpty ? data : output
  }

  private func annexBNals(_ data: Data) -> [Data] {
    let bytes = [UInt8](data)
    var starts: [Int] = []
    var index = 0
    while index + 3 < bytes.count {
      if bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 1 { starts.append(index); index += 3 }
      else if index + 4 < bytes.count, bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 0, bytes[index + 3] == 1 { starts.append(index); index += 4 }
      else { index += 1 }
    }
    return starts.enumerated().compactMap { offset, start in
      let prefix = bytes[start + 2] == 1 ? 3 : 4
      let end = offset + 1 < starts.count ? starts[offset + 1] : bytes.count
      guard end > start + prefix else { return nil }
      return Data(bytes[(start + prefix)..<end])
    }
  }
}

enum NkasIosVideoError: LocalizedError {
  case invalidConfiguration
  case notConfigured
  case videoToolbox(OSStatus)

  var errorDescription: String? {
    switch self {
    case .invalidConfiguration: return "scrcpy 视频配置包无效"
    case .notConfigured: return "scrcpy 视频解码器尚未配置"
    case .videoToolbox(let status): return "VideoToolbox 解码失败：\(status)"
    }
  }
}
