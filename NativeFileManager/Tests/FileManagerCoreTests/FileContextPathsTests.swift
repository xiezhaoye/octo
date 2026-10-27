import XCTest
@testable import FileManagerCore

final class FileContextPathsTests: XCTestCase {
    func testFilePathsIncludeFilenameButDirectoryPathsDeduplicateParents() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try TextFileKind.text.create(in: folder, name: "中文 空格"), second = try TextFileKind.json.create(in: folder, name: "配置")
        XCTAssertEqual(FileContextPaths.fullPaths(for: [first, second], directory: folder), [first.path, second.path])
        XCTAssertEqual(FileContextPaths.directoryPaths(for: [first, second], directory: folder), [folder.path])
        XCTAssertEqual(FileContextPaths.directoryPaths(for: [folder], directory: folder.deletingLastPathComponent()), [folder.path])
        XCTAssertEqual(FileContextPaths.fullPaths(for: [], directory: folder), [folder.path])
        XCTAssertEqual(FileContextPaths.directoryPaths(for: [], directory: folder), [folder.path])
    }
}
