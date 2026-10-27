import XCTest
@testable import FileManagerCore

final class ContextMenuOrderTests: XCTestCase {
    func testBuiltinAndCustomOrderMergesMissingAndRejectsStaleKeys() throws {
        let command = CustomCommand(name:"命令",script:"stat {path}")
        let key = ContextMenuOrder.key(for: command)
        let defaults = ContextMenuOrder.keys(saved:nil,commands:[command])
        XCTAssertEqual(Array(defaults.prefix(3)),["copyPath","copyDirectoryPath","openTerminal"])
        let moved = ContextMenuOrder.moving(key,in:defaults,before:0)
        XCTAssertEqual(moved.first,key);XCTAssertEqual(Set(moved),Set(defaults));XCTAssertEqual(moved.count,defaults.count)
        let restored = ContextMenuOrder.keys(saved:[key,key,"unknown","trash"],commands:[command])
        XCTAssertEqual(Array(restored.prefix(2)),[key,"trash"]);XCTAssertEqual(restored.count,defaults.count)
        XCTAssertFalse(ContextMenuOrder.keys(saved:moved,commands:[]).contains(key))
        XCTAssertEqual(ContextMenuOrder.moving("copyPath",in:["copyPath","trash","paste"],before:3),["trash","paste","copyPath"])
    }
    func testOrderRoundTripAndOldWorkspaceLoads() throws {
        var state=Workspace();state.contextMenuOrder=["newFile","copyPath"]
        XCTAssertEqual(try JSONDecoder().decode(Workspace.self,from:JSONEncoder().encode(state)).contextMenuOrder,state.contextMenuOrder)
        var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(state)) as! [String:Any];object.removeValue(forKey:"contextMenuOrder")
        XCTAssertNil(try JSONDecoder().decode(Workspace.self,from:JSONSerialization.data(withJSONObject:object)).contextMenuOrder)
    }
}
