import XCTest
import CryptoKit
@testable import FileManagerCore

final class AppReleaseTests:XCTestCase {
    func archive(extra:String? = nil,symlink:Bool=false) throws ->URL {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let files=root.appendingPathComponent("files"),binary=files.appendingPathComponent("Octo.app/Contents/MacOS/DualPane")
        try FileManager.default.createDirectory(at:binary.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data("fixture".utf8).write(to:binary)
        if symlink {try FileManager.default.createSymbolicLink(atPath:files.appendingPathComponent("Octo.app/link").path,withDestinationPath:"/tmp/outside")}
        if let extra {try Data("untrusted".utf8).write(to:files.appendingPathComponent(extra))}
        let zip=root.appendingPathComponent("fixture.zip"),process=Process()
        process.currentDirectoryURL=files;process.executableURL=URL(fileURLWithPath:"/usr/bin/zip");process.arguments=["-q","-r","-y",zip.path,"Octo.app"]+(extra.map{[$0]} ?? [])
        try process.run();process.waitUntilExit();XCTAssertEqual(process.terminationStatus,0)
        addTeardownBlock{try? FileManager.default.removeItem(at:root)};return zip
    }
    func release(_ url:URL,sha:String? = nil,download:String="https://octo-dl.xiezhaoye.site/Octo-0.6.0-macos-arm64.zip") throws ->AppRelease {
        let data=try Data(contentsOf:url)
        return AppRelease(version:"0.6.0",build:8,minimumSystemVersion:"14.0",architecture:"arm64",downloadURL:URL(string:download)!,sha256:sha ?? SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined(),bytes:Int64(data.count),notes:[])
    }
    func testNumericVersionsAndBuildsRejectDowngrades() throws {
        XCTAssertGreaterThan(try ReleaseVersion("10.0.0"),try ReleaseVersion("9.9.9"))
        XCTAssertEqual(try ReleaseVersion("14.0"),try ReleaseVersion("14.0.0"))
        XCTAssertThrowsError(try ReleaseVersion("1.2.beta"));XCTAssertThrowsError(try ReleaseVersion("1..2"));XCTAssertThrowsError(try ReleaseVersion("-1.2.3"))
        let value=try release(archive())
        XCTAssertTrue(try value.isNewer(than:"0.5.0",build:999))
        XCTAssertTrue(try value.isNewer(than:"0.6.0",build:7))
        XCTAssertFalse(try value.isNewer(than:"0.6.0",build:8))
        XCTAssertFalse(try value.isNewer(than:"0.7.0",build:1))
    }
    func testTrustedManifestAndChecksum() throws {
        let zip=try archive(),value=try release(zip)
        XCTAssertNoThrow(try value.validate());XCTAssertNoThrow(try value.verify(zip))
        XCTAssertThrowsError(try release(zip,sha:String(repeating:"0",count:64)).verify(zip))
        XCTAssertThrowsError(try release(zip,download:"http://octo-dl.xiezhaoye.site/Octo-0.6.0-macos-arm64.zip").validate())
        XCTAssertThrowsError(try release(zip,download:"https://example.com/Octo-0.6.0-macos-arm64.zip").validate())
        XCTAssertThrowsError(try release(zip,download:"https://octo-dl.xiezhaoye.site/other.zip").validate())
        XCTAssertFalse(AppRelease.allowed(URL(string:"https://user@octo-dl.xiezhaoye.site/file")!))
        XCTAssertFalse(AppRelease.allowed(URL(string:"https://octo-dl.xiezhaoye.site:444/file")!))
    }
    func testArchiveRejectsTraversalSymlinksAndOtherRoots() throws {
        XCTAssertThrowsError(try UpdateArchive.inspect(Data(contentsOf:archive(extra:"../escape.txt"))))
        XCTAssertThrowsError(try UpdateArchive.inspect(Data(contentsOf:archive(symlink:true))))
        XCTAssertThrowsError(try UpdateArchive.inspect(Data(contentsOf:archive(extra:"other.txt"))))
        XCTAssertThrowsError(try UpdateArchive.inspect(Data([0,1,2,3])))
    }
    func testExecutableArchitectureIsChecked() {
        XCTAssertTrue(AppRelease.supportsArm64Executable(Data([0xcf,0xfa,0xed,0xfe,0x0c,0,0,1])))
        XCTAssertFalse(AppRelease.supportsArm64Executable(Data([0xcf,0xfa,0xed,0xfe,0x07,0,0,1])))
        XCTAssertFalse(AppRelease.supportsArm64Executable(Data("#!/bin/sh".utf8)))
    }
    func testTruncatedAndForgedDirectoryFailClosed() throws {
        let zip=try archive();var data=try Data(contentsOf:zip)
        data.removeLast();XCTAssertThrowsError(try UpdateArchive.inspect(data))
        var forged=try Data(contentsOf:zip);forged[forged.count-6]=255
        XCTAssertThrowsError(try UpdateArchive.inspect(forged))
    }
}
