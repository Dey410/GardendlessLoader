import Foundation
import GardendlessResource
import XCTest

final class ResourceMIMETests: XCTestCase {
  func testAudioExtensionsKeepTheirNativeContainerMIME() {
    XCTAssertEqual(ResourceMIME.type(for: "audio/song.AAC"), "audio/aac")
    XCTAssertEqual(ResourceMIME.type(for: "audio/song.m4a"), "audio/mp4")
    XCTAssertEqual(ResourceMIME.type(for: "audio/song.mp3"), "audio/mpeg")
  }

  func testMp3PathWithAdtsHeaderUsesAacMime() {
    for header: [UInt8] in [[0xff, 0xf1, 0x50, 0x80], [0xff, 0xf9, 0x50, 0x80]] {
      XCTAssertEqual(ResourceMIME.detectAudioType(path: "audio/legacy.mp3", header: Data(header)), "audio/aac")
    }
  }

  func testMp3AndShortHeadersAreNotMisclassifiedAsAac() {
    for header: [UInt8] in [[], [0xff], [0xff, 0xfb], [0xff, 0xf3], [0, 0xf1]] {
      XCTAssertEqual(ResourceMIME.detectAudioType(path: "audio/song.mp3", header: Data(header)), "audio/mpeg")
    }
  }

  func testMp3PathWithM4AHeaderKeepsMp4Mime() {
    for brand in ["ftypM4A", "ftypisom", "ftypmp42"] {
      let header = Data([0, 0, 0, 24] + Array(brand.utf8) + [0, 0, 0, 0])
      XCTAssertEqual(ResourceMIME.detectAudioType(path: "audio/song.mp3", header: header), "audio/mp4")
    }
  }
}
