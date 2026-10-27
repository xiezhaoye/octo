import XCTest
@testable import FileManagerCore

final class TextDocumentTests: XCTestCase {
    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    func testCreationAndConflictDoNotOverwrite() throws {
        let directory = try temporaryDirectory()
        for kind in TextFileKind.allCases {
            let url = try kind.create(in: directory, name: "中文 " + kind.title)
            XCTAssertEqual(url.pathExtension, kind.fileExtension)
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), kind.initialContent)
            XCTAssertThrowsError(try kind.create(in: directory, name: url.lastPathComponent))
        }
        for name in ["", ".", "..", "../x", "a:b", "a\0b"] { XCTAssertThrowsError(try TextFileKind.text.create(in: directory, name: name)) }
    }
    func testUTF8BOMAndCRLFPreserved() throws {
        let url = try temporaryDirectory().appendingPathComponent("测试.md")
        try (Data([0xEF, 0xBB, 0xBF]) + Data("你好\r\n世界\r\n".utf8)).write(to: url)
        var document = try TextDocument(url: url)
        XCTAssertEqual(document.content, "你好\n世界\n")
        try document.save(document.content + "更新\n")
        XCTAssertEqual(try Data(contentsOf: url), Data([0xEF, 0xBB, 0xBF]) + Data("你好\r\n世界\r\n更新\r\n".utf8))
        XCTAssertFalse(document.hasExternalChanges())
    }
    func testUTF16AndSymlinkPreserved() throws {
        let directory = try temporaryDirectory(), url = directory.appendingPathComponent("source.txt"), link = directory.appendingPathComponent("link.txt")
        try (Data([0xFF, 0xFE]) + "中文\n".data(using: .utf16LittleEndian)!).write(to: url)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        var document = try TextDocument(url: link); try document.save("更新\n")
        XCTAssertEqual(try Data(contentsOf: url), Data([0xFF, 0xFE]) + "更新\n".data(using: .utf16LittleEndian)!)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), url.path)
    }
    func testExternalChangeAndDeletionRefuseSave() throws {
        let url = try TextFileKind.json.create(in: temporaryDirectory(), name: "配置")
        var document = try TextDocument(url: url)
        try Data("[]".utf8).write(to: url)
        XCTAssertTrue(document.hasExternalChanges()); XCTAssertThrowsError(try document.save("1"))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "[]")
        try FileManager.default.removeItem(at: url); XCTAssertThrowsError(try document.save("2"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testRejectBinaryAndLargeFileAndAllowEmpty() throws {
        let url = try TextFileKind.text.create(in: temporaryDirectory(), name: "空白")
        XCTAssertEqual(try TextDocument(url: url).content, "")
        try Data([0x61, 0, 0x62]).write(to: url); XCTAssertThrowsError(try TextDocument(url: url))
        try Data(repeating: 0x61, count: 8 * 1024 * 1024 + 1).write(to: url); XCTAssertThrowsError(try TextDocument(url: url))
        XCTAssertEqual(TextFileKind.identify(URL(fileURLWithPath: "TEST.MD")), .markdown)
        XCTAssertNil(TextFileKind.identify(URL(fileURLWithPath: "image.png")))
    }
}
