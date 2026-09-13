import Foundation
import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {
  func testScrcpy41SessionAndFrameHeaders() throws {
    XCTAssertEqual(try NkasScrcpyVideoHeader(Data([0x80, 0, 0, 1, 0, 0, 4, 0x38, 0, 0, 7, 0x80])),
                   .size(1080, 1920))
    XCTAssertEqual(try NkasScrcpyVideoHeader(Data([0x40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5])),
                   .packet(length: 5, pts: 0, configuration: true, keyFrame: false))
    XCTAssertEqual(try NkasScrcpyVideoHeader(Data([0x20, 0, 0, 0, 0, 1, 2, 3, 0, 0, 0, 9])),
                   .packet(length: 9, pts: 66051, configuration: false, keyFrame: true))
  }

  func testMalformedVideoHeadersAreRejected() {
    XCTAssertThrowsError(try NkasScrcpyVideoHeader(Data(repeating: 0, count: 11)))
    XCTAssertThrowsError(try NkasScrcpyVideoHeader(Data(repeating: 0, count: 12)))
    XCTAssertThrowsError(try NkasScrcpyVideoHeader(Data([0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])))
    XCTAssertThrowsError(try NkasScrcpyVideoHeader(Data([0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 1])))
  }

  func testAnnexBSupportsMixedStartCodes() throws {
    let bytes = Data([0, 0, 0, 1, 0x67, 0x42, 0x10, 0, 0, 1, 0x68, 0xce])
    XCTAssertEqual(NkasAnnexB.units(bytes), [Data([0x67, 0x42, 0x10]), Data([0x68, 0xce])])
    XCTAssertEqual(try NkasAnnexB.lengthPrefixed(bytes),
                   Data([0, 0, 0, 3, 0x67, 0x42, 0x10, 0, 0, 0, 2, 0x68, 0xce]))
    XCTAssertThrowsError(try NkasAnnexB.lengthPrefixed(Data([0, 0, 1])))
  }

  func testKeycodePreservesAllBigEndianBits() throws {
    var output = Data()
    let control = NkasIosScrcpyControl { output = $0 }
    try control.keycode(action: 1, keycode: 0x01020304, repeatCount: 0x0100, metaState: 0x01020300)
    XCTAssertEqual(output, Data([0, 1, 1, 2, 3, 4, 0, 0, 1, 0, 1, 2, 3, 0]))
  }

  func testTouchCoordinatesAndPressureMatchWireFormat() throws {
    var output = Data()
    let control = NkasIosScrcpyControl { output = $0 }
    try control.touch(action: 2, pointerId: UInt64.max, x: 512, y: 255, width: 1920, height: 1080,
                      pressure: 0.5, actionButton: 0, buttons: 1)
    XCTAssertEqual(output, Data([2, 2, 255, 255, 255, 255, 255, 255, 255, 255,
                                 0, 0, 2, 0, 0, 0, 0, 255, 7, 128, 4, 56, 128, 0,
                                 0, 0, 0, 0, 0, 0, 0, 1]))
  }

  func testInvalidInputDoesNotWritePartialPackets() {
    let control = NkasIosScrcpyControl { _ in XCTFail("Invalid input wrote a packet") }
    XCTAssertThrowsError(try control.keycode(action: 0, keycode: -1, repeatCount: 0, metaState: 0))
    XCTAssertThrowsError(try control.touch(action: 0, pointerId: 0, x: 10, y: 0, width: 10, height: 10,
                                           pressure: 1, actionButton: 0, buttons: 0))
    XCTAssertThrowsError(try control.touch(action: 0, pointerId: 0, x: 0, y: 0, width: 10, height: 10,
                                           pressure: .nan, actionButton: 0, buttons: 0))
    XCTAssertThrowsError(try control.text(String(repeating: "文", count: 101)))
  }

  func testTextLengthCountsUtf8Bytes() throws {
    var output = Data()
    let control = NkasIosScrcpyControl { output = $0 }
    try control.text("文")
    XCTAssertEqual(output, Data([1, 0, 0, 0, 3, 0xe6, 0x96, 0x87]))
  }

  func testRemoteEndpointAcceptsIpv6AndMagicDns() throws {
    XCTAssertEqual(try NkasIosAdbEndpoint("adb://[fd7a:115c::1]:5555").serial, "[fd7a:115c::1]:5555")
    XCTAssertEqual(try NkasIosAdbEndpoint(" redroid.tailnet.ts.net:5555 ").host, "redroid.tailnet.ts.net")
    for value in [":5555", "host:0", "host:65536", "adb://host:5555/path", "fd7a::1:5555", "u@host:5555"] {
      XCTAssertThrowsError(try NkasIosAdbEndpoint(value), value)
    }
  }

  func testServerCommandUsesTheBundledProtocolAndCodec() {
    var options = NkasIosScrcpyOptions(video: true, control: true, maxSize: 1280, videoBitRate: 4_000_000)
    options.videoCodec = "h265"
    let command = NkasIosScrcpySession.buildCommand(remotePath: "/data/local/tmp/test.jar", scid: 42, options: options)
    XCTAssertTrue(command.contains("com.genymobile.scrcpy.Server 4.1"))
    XCTAssertTrue(command.contains("tunnel_forward=true"))
    XCTAssertTrue(command.contains("clipboard_autosync=false"))
    XCTAssertTrue(command.contains("video_codec=h265"))
    XCTAssertTrue(command.contains("audio=false"))
    XCTAssertTrue(command.contains("scid=2a"))
  }
}
