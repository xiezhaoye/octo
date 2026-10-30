import XCTest
@testable import FileManagerCore

final class FolderTagsTests:XCTestCase {
    func testIndependentColorsStackAndRoundTrip() throws {
        let url=URL(fileURLWithPath:"/tmp/octo-colors-example")
        var workspace=Workspace()
        for color in FolderTagColor.allCases {workspace.setFolderColor(color,enabled:true,at:url)}
        XCTAssertEqual(Set(workspace.colors(for:url)),Set(FolderTagColor.allCases))
        workspace.setFolderColor(.red,enabled:true,at:url)
        XCTAssertEqual(workspace.colors(for:url).filter{$0 == .red}.count,1)
        let restored=try JSONDecoder().decode(Workspace.self,from:JSONEncoder().encode(workspace))
        XCTAssertEqual(restored.colors(for:url),workspace.colors(for:url))
        workspace.setFolderColor(.red,enabled:false,at:url)
        XCTAssertFalse(workspace.colors(for:url).contains(.red));XCTAssertEqual(workspace.colors(for:url).count,6)
    }
    func testWorkspaceColorsDoNotReadOrChangeFinderTags() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:url)}
        try (url as NSURL).setResourceValue(["已有访达标签"],forKey:.tagNamesKey)
        try (url as NSURL).setResourceValue(6,forKey:.labelNumberKey)
        let before=try URL(fileURLWithPath:url.path).resourceValues(forKeys:[.tagNamesKey,.labelNumberKey])
        var workspace=Workspace();XCTAssertTrue(workspace.colors(for:url).isEmpty)
        workspace.setFolderColor(.blue,enabled:true,at:url)
        XCTAssertEqual(workspace.colors(for:url),[.blue])
        workspace.setFolderColor(nil,enabled:false,at:url)
        let after=try URL(fileURLWithPath:url.path).resourceValues(forKeys:[.tagNamesKey,.labelNumberKey])
        XCTAssertEqual(before.tagNames,after.tagNames);XCTAssertEqual(before.labelNumber,after.labelNumber)
    }
    func testOldWorkspaceLoadsWithoutColorField() throws {
        var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(Workspace())) as! [String:Any]
        object.removeValue(forKey:"folderColors")
        let restored=try JSONDecoder().decode(Workspace.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertNil(restored.folderColors)
    }
    func testSeparateWorkspacesAndNormalizedFolderPaths() {
        let url=URL(fileURLWithPath:"/tmp/octo-colors/child/../folder")
        var first=Workspace(),second=Workspace()
        first.setFolderColor(.yellow,enabled:true,at:url)
        XCTAssertEqual(first.colors(for:URL(fileURLWithPath:"/tmp/octo-colors/folder")),[.yellow])
        XCTAssertTrue(second.colors(for:url).isEmpty)
        second.setFolderColor(.green,enabled:true,at:url)
        first.setFolderColor(nil,enabled:false,at:url)
        XCTAssertTrue(first.colors(for:url).isEmpty);XCTAssertEqual(second.colors(for:url),[.green])
    }
}
