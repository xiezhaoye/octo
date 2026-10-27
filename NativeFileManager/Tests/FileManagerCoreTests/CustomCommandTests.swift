import XCTest
@testable import FileManagerCore

final class CustomCommandTests: XCTestCase {
    func testLegacyMigrationAndRoundtrip() throws {
        let id = UUID()
        let bytes = Data("{\"id\":\"\(id)\",\"name\":\"旧命令\",\"script\":\"ls\",\"foldersOnly\":true}".utf8)
        let command = try JSONDecoder().decode(CustomCommand.self, from: bytes)
        XCTAssertEqual(command.target, .folders); XCTAssertTrue(command.foldersOnly)
        let updated = CustomCommand(name: "文本", script: "cat {paths}", target: .extensions, fileExtensions: [".MD", "txt", "JSON", "md"])
        XCTAssertEqual(updated.fileExtensions, ["json", "md", "txt"])
        XCTAssertEqual(try JSONDecoder().decode(CustomCommand.self, from: JSONEncoder().encode(updated)), updated)
        XCTAssertEqual(CustomCommand.normalizeExtensions("*.md，TXT; .json html\nyml"), ["html", "json", "md", "txt", "yml"])
    }
    func testTargetsAndMixedSelections() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let md = try TextFileKind.markdown.create(in: directory, name: "一.MD"), txt = try TextFileKind.text.create(in: directory, name: "二")
        let restricted = CustomCommand(name: "md", script: "cat", target: .extensions, fileExtensions: ["md"])
        XCTAssertTrue(restricted.applies(to: [md], directory: directory))
        XCTAssertFalse(restricted.applies(to: [md, txt], directory: directory))
        XCTAssertFalse(restricted.applies(to: [], directory: directory))
        XCTAssertFalse(restricted.applies(to: [directory], directory: directory))
        XCTAssertTrue(CustomCommand(name: "folder", script: "ls", foldersOnly: true).applies(to: [], directory: directory))
        XCTAssertTrue(CustomCommand(name: "files", script: "cat", target: .files).applies(to: [md, txt], directory: directory))
        XCTAssertFalse(CustomCommand(name: "files", script: "cat", target: .files).applies(to: [md, directory], directory: directory))
    }
}
