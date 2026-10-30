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
    func testGroupingAndCrossGroupOrderPersist() throws {
        let command=CustomCommand(name:"示例",script:"pwd"),key=ContextMenuOrder.key(for:command)
        var state=Workspace();state.commands=[command]
        let grouped=ContextMenuOrder.groupedKeys(saved:nil,commands:state.commands,groups:nil)
        XCTAssertEqual(Array(grouped.prefix(3)),["copyPath","copyDirectoryPath","openTerminal"])
        let groups=grouped.map{ContextCommandGroup.group(for:$0)}
        for group in ContextCommandGroup.allCases {
            let positions=groups.indices.filter{groups[$0] == group}
            if let first=positions.first,let last=positions.last {XCTAssertEqual(last-first+1,positions.count)}
        }
        state.contextCommandGroups=[key:ContextCommandGroup.paths.rawValue]
        state.contextMenuOrder=ContextMenuOrder.moving(key,in:grouped,before:0)
        let restored=try JSONDecoder().decode(Workspace.self,from:JSONEncoder().encode(state))
        XCTAssertEqual(ContextMenuOrder.groupedKeys(saved:restored.contextMenuOrder,commands:restored.commands,groups:restored.contextCommandGroups).first,key)
        XCTAssertEqual(ContextCommandGroup.group(for:"openWith"),.opening)
    }

}
