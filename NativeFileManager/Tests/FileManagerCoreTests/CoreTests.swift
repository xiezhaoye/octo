import XCTest
@testable import FileManagerCore

final class WorkspaceTests: XCTestCase {
    func fixture() -> Workspace {
        var s = Workspace(); s.panes[0].groups = [FolderGroup(name:"A",entries:[FolderEntry(path:"/tmp/left/123"),FolderEntry(path:"/tmp/left/健康")]),FolderGroup(name:"空组")]; s.panes[1].groups = [FolderGroup(name:"B")]; return s
    }
    func testEntryMoveOnlyChangesNavigationAndKeepsSourceGroup() throws {
        var s=fixture();let original=s.panes[0].groups[0].entries[0];let a=s.panes[0].groups[0].id,b=s.panes[1].groups[0].id
        try s.transferEntry(from:0,entryID:original.id,to:1,groupID:b,copy:false)
        XCTAssertEqual(s.panes[0].groups[0].id,a);XCTAssertFalse(s.panes[0].groups[0].entries.contains(original));XCTAssertEqual(s.panes[1].groups[0].entries[0].path,original.path)
    }
    func testOptionCopiesOnlyEntryAndUsesIndependentID() throws {
        var s=fixture();let original=s.panes[0].groups[0].entries[0]
        try s.transferEntry(from:0,entryID:original.id,to:1,groupID:s.panes[1].groups[0].id,copy:true)
        XCTAssertEqual(s.panes[0].groups[0].entries.count,2);XCTAssertEqual(s.panes[1].groups.count,1);XCTAssertEqual(s.panes[1].groups[0].entries.count,1);XCTAssertNotEqual(original.id,s.panes[1].groups[0].entries[0].id);XCTAssertEqual(original.path,s.panes[1].groups[0].entries[0].path)
    }
    func testDuplicateRelocatesWithinTargetPane() throws {
        var s=fixture();let original=s.panes[0].groups[0].entries[0];s.panes[1].groups[0].entries=[FolderEntry(path:original.path)];s.panes[1].groups.append(FolderGroup(name:"C"))
        try s.transferEntry(from:0,entryID:original.id,to:1,groupID:s.panes[1].groups[1].id,copy:true)
        XCTAssertTrue(s.panes[1].groups[0].entries.isEmpty);XCTAssertEqual(s.panes[1].groups[1].entries.count,1);XCTAssertEqual(s.panes[0].groups[0].entries.count,2)
    }
    func testRejectedTransferIsAtomic() throws {
        var s=fixture();s.duplicatePolicy = .reject;let original=s.panes[0].groups[0].entries[0];s.panes[1].groups[0].entries=[FolderEntry(path:original.path)];let before=s
        XCTAssertThrowsError(try s.transferEntry(from:0,entryID:original.id,to:1,groupID:s.panes[1].groups[0].id,copy:false));XCTAssertEqual(s,before)
    }
    func testGroupCopyPreservesOrderAndIsIndependent() throws {
        var s=fixture();let group=s.panes[0].groups[0];try s.transferGroup(from:0,groupID:group.id,to:1,copy:true)
        let copy=s.panes[1].groups.last!;XCTAssertEqual(copy.entries.map(\.path),group.entries.map(\.path));XCTAssertNotEqual(copy.id,group.id);XCTAssertNotEqual(copy.entries[0].id,group.entries[0].id)
    }
    func testSameGroupReorderAdjustsSourceIndex() throws {
        var s=fixture();let group=s.panes[0].groups[0];try s.transferEntry(from:0,entryID:group.entries[0].id,to:0,groupID:group.id,index:2,copy:false)
        XCTAssertEqual(s.panes[0].groups[0].entries.map(\.id),group.entries.reversed().map(\.id))
    }
    func testOnlyVisiblePaneCannotBeHidden() {var s=fixture();s.setPaneHidden(0,hidden:true);s.setPaneHidden(1,hidden:true);XCTAssertTrue(s.panes[0].hidden);XCTAssertFalse(s.panes[1].hidden)}
    func testRestoringPaneExpandsSidebarAndAllGroupsWithoutChangingOtherPane(){
        var s=fixture();s.panes[0].hidden=true;s.panes[0].sidebarCollapsed=true;s.panes[0].sidebarWidth=240
        for index in s.panes[0].groups.indices{s.panes[0].groups[index].collapsed=true}
        s.panes[1].sidebarCollapsed=true;let other=s.panes[1],directory=s.panes[0].directory
        s.restorePane(0)
        XCTAssertFalse(s.panes[0].hidden);XCTAssertFalse(s.panes[0].sidebarCollapsed);XCTAssertTrue(s.panes[0].groups.allSatisfy{!$0.collapsed});XCTAssertEqual(s.panes[0].sidebarWidth,240);XCTAssertEqual(s.panes[0].directory,directory);XCTAssertEqual(s.panes[1],other)
    }
    func testSerializationPreservesSkinAndGroups() throws {
        var s=fixture();s.skin = .warm;s.panes[0].mode = .columns;s.commands=[CustomCommand(name:"信息",script:"stat {path}")]
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:dir)}
        let store=WorkspaceStore(url:dir.appendingPathComponent("state.json"));try store.save(s);let read=try store.load();XCTAssertEqual(read.skin,.warm);XCTAssertEqual(read.panes[0].mode,.columns);XCTAssertEqual(read.commands,s.commands);XCTAssertEqual(read.panes[0].groups.map(\.name),s.panes[0].groups.map(\.name))
    }
    func testOldPaneConfigurationLoadsWithoutLosingGroups() throws {
        let original=fixture();let encoded=try JSONEncoder().encode(original)
        var json=try JSONSerialization.jsonObject(with:encoded) as! [String:Any]
        var panes=json["panes"] as! [[String:Any]]
        for index in panes.indices{panes[index].removeValue(forKey:"sidebarWidth");panes[index].removeValue(forKey:"sidebarCollapsed")}
        json["panes"]=panes
        let restored=try JSONDecoder().decode(Workspace.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertEqual(restored.panes[0].groups,original.panes[0].groups);XCTAssertEqual(restored.panes[0].sidebarWidth,178);XCTAssertFalse(restored.panes[0].sidebarCollapsed)
    }
    func testSidebarSizeAndCollapsePersistIndependently() throws {
        var original=fixture();original.panes[0].sidebarWidth=245;original.panes[0].sidebarCollapsed=true;original.panes[1].sidebarWidth=180
        let restored=try JSONDecoder().decode(Workspace.self,from:JSONEncoder().encode(original))
        XCTAssertEqual(restored.panes[0].sidebarWidth,245);XCTAssertTrue(restored.panes[0].sidebarCollapsed);XCTAssertFalse(restored.panes[1].sidebarCollapsed);XCTAssertEqual(restored.panes[1].sidebarWidth,180)
    }
    func testCommandSubstitutionCannotResubstituteFilename() {let p=URL(fileURLWithPath:"/tmp/a'{directory}$(touch nope)");let rendered=renderCommand("printf '%s' {path} {directory}",urls:[p],directory:URL(fileURLWithPath:"/tmp/root"));XCTAssertTrue(rendered.contains("{directory}"));XCTAssertTrue(rendered.contains("'\\''"));XCTAssertTrue(rendered.hasSuffix("'/tmp/root'"))}
}

final class FileOperationTests: XCTestCase {
    var root:URL!
    override func setUpWithError() throws {root=FileManager.default.temporaryDirectory.appendingPathComponent("dualpane-test-"+UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)}
    override func tearDownWithError() throws {try FileManager.default.removeItem(at:root)}
    func file(_ name:String,_ text:String="original") throws -> URL {let url=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try Data(text.utf8).write(to:url);return url}
    func folder(_ name:String) throws -> URL {let url=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);return url}
    func testMoveRemovesSourceAfterSuccess() async throws {let source=try file("source/report.txt"),target=try folder("target");let op=FileOperator();let result=try await op.transfer(source,to:target,kind:.move,conflict:.ask);XCTAssertFalse(FileManager.default.fileExists(atPath:source.path));XCTAssertEqual(try String(contentsOf:result.destination,encoding:.utf8),"original")}
    func testCopyRetainsSource() async throws {let source=try file("source/report.txt"),target=try folder("target");let op=FileOperator();let result=try await op.transfer(source,to:target,kind:.copy,conflict:.ask);XCTAssertTrue(FileManager.default.fileExists(atPath:source.path));XCTAssertTrue(FileManager.default.fileExists(atPath:result.destination.path))}
    func testKeepBothAndSkipPreserveExistingData() async throws {let source=try file("source/report.txt","new"),target=try folder("target");let existing=try file("target/report.txt","old");let op=FileOperator();let skip=try await op.transfer(source,to:target,kind:.move,conflict:.skip);XCTAssertTrue(skip.skipped);let copy=try await op.transfer(source,to:target,kind:.copy,conflict:.keepBoth);XCTAssertNotEqual(copy.destination,existing);XCTAssertEqual(try String(contentsOf:existing,encoding:.utf8),"old");XCTAssertEqual(try String(contentsOf:copy.destination,encoding:.utf8),"new")}
    func testConflictDoesNotTouchEitherFile() async throws {let source=try file("source/report.txt","new"),target=try folder("target");let existing=try file("target/report.txt","old");do{_ = try await FileOperator().transfer(source,to:target,kind:.move,conflict:.ask);XCTFail()}catch{};XCTAssertEqual(try String(contentsOf:source,encoding:.utf8),"new");XCTAssertEqual(try String(contentsOf:existing,encoding:.utf8),"old")}
    func testFolderCannotMoveIntoItsDescendant() async throws {let source=try folder("source"),target=try folder("source/child");do{_ = try await FileOperator().transfer(source,to:target,kind:.move,conflict:.ask);XCTFail()}catch{};XCTAssertTrue(FileManager.default.fileExists(atPath:source.path))}
    func testFailedDestinationPreservesSource() async throws {let source=try file("source/report.txt");do{_ = try await FileOperator().transfer(source,to:root.appendingPathComponent("missing/deep"),kind:.move,conflict:.ask);XCTFail()}catch{};XCTAssertTrue(FileManager.default.fileExists(atPath:source.path))}
    func testRecursiveSearchAndHiddenFiltering() async throws {_ = try file("资料/child/健康报告.txt");_ = try file("资料/.hidden/健康记录.txt");let reader=DirectoryReader();let base=root.appendingPathComponent("资料");let visible=try await reader.search(in:base,query:"健康",showHidden:false);XCTAssertEqual(visible.count,1);let all=try await reader.search(in:base,query:"健康",showHidden:true);XCTAssertEqual(all.count,2)}
    func testReplacePreservesOldTargetInInjectedRecycleLocation() async throws {
        let source=try file("source/report.txt","new"),target=try folder("target"),recycle=try folder("recycle");_ = try file("target/report.txt","old")
        let op=FileOperator(recycle:{url in try FileManager.default.moveItem(at:url,to:recycle.appendingPathComponent(url.lastPathComponent))})
        let result=try await op.transfer(source,to:target,kind:.move,conflict:.replace)
        XCTAssertEqual(try String(contentsOf:result.destination,encoding:.utf8),"new");XCTAssertFalse(FileManager.default.fileExists(atPath:source.path));let backups=try FileManager.default.contentsOfDirectory(at:recycle,includingPropertiesForKeys:nil);XCTAssertEqual(backups.count,1);XCTAssertEqual(try String(contentsOf:backups[0],encoding:.utf8),"old")
    }
    func testRecycleFailureLeavesRecoverableBackupAndReportsIt() async throws {
        let source=try file("source/report.txt","new"),target=try folder("target");_ = try file("target/report.txt","old")
        let op=FileOperator(recycle:{_ in throw CocoaError(.fileWriteNoPermission)})
        let result=try await op.transfer(source,to:target,kind:.copy,conflict:.replace);XCTAssertNotNil(result.note)
        let backups=try FileManager.default.contentsOfDirectory(at:target,includingPropertiesForKeys:nil).filter{$0.lastPathComponent.hasPrefix(".dualpane-backup-")};XCTAssertEqual(backups.count,1);XCTAssertEqual(try String(contentsOf:backups[0],encoding:.utf8),"old")
    }
}
