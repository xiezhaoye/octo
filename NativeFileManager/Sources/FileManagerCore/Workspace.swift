import Foundation

public enum Skin: String, Codable, CaseIterable {
    case native, dark, warm, monochrome
    public var title: String {
        switch self { case .native: return "原生浅色"; case .dark: return "深色工作台"; case .warm: return "温暖档案柜"; case .monochrome: return "黑白目录台" }
    }
}

public enum BrowseMode: String, Codable, CaseIterable { case list, columns, icons }
public enum DuplicateEntryPolicy: String, Codable { case relocate, reject }
public enum ConflictPolicy: String, Codable { case ask, keepBoth, skip, replace }
public enum SearchScope: String, Codable { case recursive, current, all }

public struct FolderEntry: Identifiable, Codable, Equatable {
    public var id: UUID
    public var path: String
    public var bookmark: Data?
    public init(path: String, id: UUID = UUID()) {
        self.id = id; self.path = URL(fileURLWithPath: path).standardizedFileURL.path
        self.bookmark = try? URL(fileURLWithPath: path).bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    public var url: URL { URL(fileURLWithPath: path) }
    public var name: String { url.lastPathComponent.isEmpty ? path : url.lastPathComponent }
    public var identity: String { url.resolvingSymlinksInPath().standardizedFileURL.path }
    public mutating func resolve() {
        guard let bookmark else { return }
        var stale = false
        if let resolved = try? URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale) {
            path = resolved.standardizedFileURL.path
            if stale { self.bookmark = try? resolved.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) }
        }
    }
}

public struct FolderGroup: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var entries: [FolderEntry]
    public var collapsed: Bool
    public init(name: String, entries: [FolderEntry] = [], id: UUID = UUID(), collapsed: Bool = false) {
        self.id = id; self.name = name; self.entries = entries; self.collapsed = collapsed
    }
}

public struct PaneState: Codable, Equatable {
    public var groups: [FolderGroup] = []
    public var directory: String
    public var mode: BrowseMode = .list
    public var showHidden = false
    public var hidden = false
    public var sidebarWidth: Double = 178
    public var sidebarCollapsed = false
    public init(directory: String = FileManager.default.homeDirectoryForCurrentUser.path) { self.directory = directory }
    private enum CodingKeys: String, CodingKey { case groups, directory, mode, showHidden, hidden, sidebarWidth, sidebarCollapsed }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        groups = try values.decodeIfPresent([FolderGroup].self, forKey: .groups) ?? []
        directory = try values.decodeIfPresent(String.self, forKey: .directory) ?? FileManager.default.homeDirectoryForCurrentUser.path
        mode = try values.decodeIfPresent(BrowseMode.self, forKey: .mode) ?? .list
        showHidden = try values.decodeIfPresent(Bool.self, forKey: .showHidden) ?? false
        hidden = try values.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        let width = try values.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? 178
        sidebarWidth = width.isFinite ? min(480, max(144, width)) : 178
        sidebarCollapsed = try values.decodeIfPresent(Bool.self, forKey: .sidebarCollapsed) ?? false
    }
}

public struct Workspace: Codable, Equatable {
    public var version = 1
    public var panes: [PaneState] = [PaneState(), PaneState()]
    public var skin: Skin = .native
    public var duplicatePolicy: DuplicateEntryPolicy = .relocate
    public var conflictPolicy: ConflictPolicy = .ask
    public var searchScope: SearchScope = .recursive
    public var commands: [CustomCommand] = []
    public var contextMenuOrder: [String]?
    public var contextCommandGroups:[String:String]?
    public var folderColors: [String:[FolderTagColor]]?
    public init() {}

    public mutating func normalize() {
        if panes.count != 2 { panes = Array(panes.prefix(2)); while panes.count < 2 { panes.append(PaneState()) } }
        if panes.allSatisfy(\.hidden) { panes[0].hidden = false }
        for p in panes.indices {
            var seen = Set<String>()
            for g in panes[p].groups.indices {
                for e in panes[p].groups[g].entries.indices { panes[p].groups[g].entries[e].resolve() }
                panes[p].groups[g].entries.removeAll { !seen.insert($0.identity).inserted }
            }
        }
    }

    public mutating func addEntry(_ entry: FolderEntry, pane: Int, group: UUID, at index: Int? = nil) throws {
        guard panes.indices.contains(pane), let target = panes[pane].groups.firstIndex(where: { $0.id == group }) else { throw WorkspaceError.invalidTarget }
        let duplicate = panes[pane].groups.contains { $0.entries.contains { $0.identity == entry.identity } }
        if duplicate && duplicatePolicy == .reject { throw WorkspaceError.duplicate(entry.name) }
        for g in panes[pane].groups.indices { panes[pane].groups[g].entries.removeAll { $0.identity == entry.identity } }
        let insertion = min(max(0, index ?? panes[pane].groups[target].entries.count), panes[pane].groups[target].entries.count)
        panes[pane].groups[target].entries.insert(entry, at: insertion)
    }

    public mutating func transferEntry(from sourcePane: Int, entryID: UUID, to targetPane: Int, groupID: UUID, index: Int? = nil, copy: Bool) throws {
        guard panes.indices.contains(sourcePane), panes.indices.contains(targetPane),
              let sourceGroup = panes[sourcePane].groups.firstIndex(where: { $0.entries.contains(where: { $0.id == entryID }) }),
              let sourceIndex = panes[sourcePane].groups[sourceGroup].entries.firstIndex(where: { $0.id == entryID }) else { throw WorkspaceError.invalidTarget }
        let original = panes[sourcePane].groups[sourceGroup].entries[sourceIndex]
        var draft = self
        // Same-pane rearrangement is a move, because each folder has one group per pane.
        if !copy || sourcePane == targetPane { draft.panes[sourcePane].groups[sourceGroup].entries.remove(at: sourceIndex) }
        var entry = original
        if copy && sourcePane != targetPane { entry.id = UUID() }
        var insertion = index
        if sourcePane == targetPane && panes[sourcePane].groups[sourceGroup].id == groupID, let index, index > sourceIndex { insertion = index - 1 }
        try draft.addEntry(entry, pane: targetPane, group: groupID, at: insertion)
        self = draft
    }

    public mutating func transferGroup(from sourcePane: Int, groupID: UUID, to targetPane: Int, index: Int? = nil, copy: Bool) throws {
        guard panes.indices.contains(sourcePane), panes.indices.contains(targetPane), let sourceIndex = panes[sourcePane].groups.firstIndex(where: { $0.id == groupID }) else { throw WorkspaceError.invalidTarget }
        var draft = self
        var group = draft.panes[sourcePane].groups[sourceIndex]
        if sourcePane == targetPane {
            draft.panes[sourcePane].groups.remove(at: sourceIndex)
        } else {
            let identities = Set(group.entries.map(\.identity))
            let duplicates = draft.panes[targetPane].groups.flatMap(\.entries).filter { identities.contains($0.identity) }
            if !duplicates.isEmpty && duplicatePolicy == .reject { throw WorkspaceError.duplicate(duplicates[0].name) }
            for g in draft.panes[targetPane].groups.indices { draft.panes[targetPane].groups[g].entries.removeAll { identities.contains($0.identity) } }
            if copy { group.id = UUID(); for e in group.entries.indices { group.entries[e].id = UUID() } }
            else { draft.panes[sourcePane].groups.remove(at: sourceIndex) }
        }
        var proposed = index ?? draft.panes[targetPane].groups.count
        if sourcePane == targetPane, let index, index > sourceIndex { proposed = index - 1 }
        let insertion = min(max(0, proposed), draft.panes[targetPane].groups.count)
        draft.panes[targetPane].groups.insert(group, at: insertion)
        self = draft
    }

    public mutating func setPaneHidden(_ index: Int, hidden: Bool) {
        guard panes.indices.contains(index) else { return }
        if hidden && panes.enumerated().allSatisfy({ $0.offset == index || $0.element.hidden }) { return }
        panes[index].hidden = hidden
    }
    public mutating func restorePane(_ index:Int){
        guard panes.indices.contains(index) else{return}
        panes[index].hidden=false;panes[index].sidebarCollapsed=false
        for group in panes[index].groups.indices{panes[index].groups[group].collapsed=false}
    }
}

public enum WorkspaceError: LocalizedError {
    case invalidTarget, duplicate(String)
    public var errorDescription: String? {
        switch self { case .invalidTarget: return "拖放目标已失效，请重新选择分组。"; case .duplicate(let name): return "目标屏已包含“\(name)”入口。请先移除已有入口，或在设置中允许转移归属。" }
    }
}

public final class WorkspaceStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> Workspace {
        guard FileManager.default.fileExists(atPath: url.path) else { return Workspace() }
        var state = try JSONDecoder().decode(Workspace.self, from: Data(contentsOf: url))
        state.normalize(); return state
    }
    public func save(_ state: Workspace) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}
