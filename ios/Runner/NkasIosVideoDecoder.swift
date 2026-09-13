import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

final class NkasIosVideoDecoder {
  private let codecId: UInt32
  private let onFrame: (CVPixelBuffer) -> Void
  private let onError: (Error) -> Void
  private var decompressionSession: VTDecompressionSession?
  private var formatDescription: CMVideoFormatDescription?
  private var parameterSets: [Int: Data] = [:]

  init(codecId: UInt32, onFrame: @escaping (CVPixelBuffer) -> Void, onError: @escaping (Error) -> Void) throws {
    guard codecId == 0x68323634 || codecId == 0x68323635 else { throw NkasIosVideoError.unsupportedCodec }
    self.codecId = codecId
    self.onFrame = onFrame
    self.onError = onError
  }

  func configure(_ data: Data, width: Int, height: Int) throws {
    let h264 = codecId == 0x68323634
    let required = h264 ? [7, 8] : [32, 33, 34]
    for unit in NkasAnnexB.units(data) {
      guard let first = unit.first else { continue }
      let type = h264 ? Int(first & 0x1f) : Int((first >> 1) & 0x3f)
      if required.contains(type) { parameterSets[type] = unit }
    }
    guard required.allSatisfy({ parameterSets[$0] != nil }) else { return }
    let storage = required.map { parameterSets[$0]! as NSData }
    let pointers = storage.map { $0.bytes.assumingMemoryBound(to: UInt8.self) }
    let sizes = storage.map { $0.length }
    var description: CMVideoFormatDescription?
    let formatStatus = withExtendedLifetime(storage) { pointers.withUnsafeBufferPointer { pointers in
      sizes.withUnsafeBufferPointer { sizes in
        if h264 {
          return CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator: kCFAllocatorDefault, parameterSetCount: required.count,
            parameterSetPointers: pointers.baseAddress!, parameterSetSizes: sizes.baseAddress!,
            nalUnitHeaderLength: 4, formatDescriptionOut: &description
          )
        }
        return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
          allocator: kCFAllocatorDefault, parameterSetCount: required.count,
          parameterSetPointers: pointers.baseAddress!, parameterSetSizes: sizes.baseAddress!,
          nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &description
        )
      }
    } }
    guard formatStatus == noErr, let description else { throw NkasIosVideoError.videoToolbox(formatStatus) }
    closeSession()
    var callback = VTDecompressionOutputCallbackRecord(
      decompressionOutputCallback: { refCon, _, status, _, imageBuffer, _, _ in
        guard let refCon else { return }
        let decoder = Unmanaged<NkasIosVideoDecoder>.fromOpaque(refCon).takeUnretainedValue()
        guard status == noErr else { decoder.onError(NkasIosVideoError.videoToolbox(status)); return }
        if let imageBuffer { decoder.onFrame(imageBuffer) }
      },
      decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
    )
    var session: VTDecompressionSession?
    let sessionStatus = VTDecompressionSessionCreate(
      allocator: kCFAllocatorDefault, formatDescription: description, decoderSpecification: nil,
      imageBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelBufferWidthKey: width,
        kCVPixelBufferHeightKey: height,
        kCVPixelBufferIOSurfacePropertiesKey: [:],
        kCVPixelBufferMetalCompatibilityKey: true,
      ] as CFDictionary,
      outputCallback: &callback, decompressionSessionOut: &session
    )
    guard sessionStatus == noErr, let session else { throw NkasIosVideoError.videoToolbox(sessionStatus) }
    formatDescription = description
    decompressionSession = session
  }

  func decode(_ data: Data, ptsUs: UInt64) throws {
    guard let session = decompressionSession, let formatDescription else { throw NkasIosVideoError.notConfigured }
    let avcc = try NkasAnnexB.lengthPrefixed(data)
    var blockBuffer: CMBlockBuffer?
    let blockStatus = CMBlockBufferCreateWithMemoryBlock(
      allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: avcc.count,
      blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
      dataLength: avcc.count, flags: 0, blockBufferOut: &blockBuffer
    )
    guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else { throw NkasIosVideoError.videoToolbox(blockStatus) }
    let copyStatus = avcc.withUnsafeBytes { raw in
      CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: blockBuffer,
                                    offsetIntoDestination: 0, dataLength: avcc.count)
    }
    guard copyStatus == kCMBlockBufferNoErr else { throw NkasIosVideoError.videoToolbox(copyStatus) }
    var timing = CMSampleTimingInfo(duration: .invalid,
                                    presentationTimeStamp: CMTime(value: Int64(ptsUs), timescale: 1_000_000),
                                    decodeTimeStamp: .invalid)
    var sampleSize = avcc.count
    var sampleBuffer: CMSampleBuffer?
    let sampleStatus = CMSampleBufferCreateReady(
      allocator: kCFAllocatorDefault, dataBuffer: blockBuffer, formatDescription: formatDescription,
      sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
      sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sampleBuffer
    )
    guard sampleStatus == noErr, let sampleBuffer else { throw NkasIosVideoError.videoToolbox(sampleStatus) }
    var flags = VTDecodeInfoFlags()
    let decodeStatus = VTDecompressionSessionDecodeFrame(
      session, sampleBuffer: sampleBuffer, flags: [], frameRefcon: nil, infoFlagsOut: &flags
    )
    guard decodeStatus == noErr else { throw NkasIosVideoError.videoToolbox(decodeStatus) }
    let waitStatus = VTDecompressionSessionWaitForAsynchronousFrames(session)
    guard waitStatus == noErr else { throw NkasIosVideoError.videoToolbox(waitStatus) }
  }

  func close() {
    closeSession()
    parameterSets.removeAll()
  }

  private func closeSession() {
    if let session = decompressionSession {
      VTDecompressionSessionWaitForAsynchronousFrames(session)
      VTDecompressionSessionInvalidate(session)
    }
    decompressionSession = nil
    formatDescription = nil
  }
}

enum NkasIosVideoError: LocalizedError {
  case invalidConfiguration
  case notConfigured
  case unsupportedCodec
  case videoToolbox(OSStatus)

  var errorDescription: String? {
    switch self {
    case .invalidConfiguration: return "scrcpy 视频配置包无效"
    case .notConfigured: return "scrcpy 视频解码器尚未配置"
    case .unsupportedCodec: return "设备未提供 H.264/H.265 视频"
    case .videoToolbox(let status): return "VideoToolbox 解码失败：\(status)"
    }
  }
}
