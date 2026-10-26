import AppKit
import FileManagerCore

private let sidebarDragType = NSPasteboard.PasteboardType("com.xiezhaoye.dualpane.sidebar")
private struct SidebarDrag: Codable { let pane: Int; let id: UUID; let group: Bool }
final class SidebarItem: NSObject {
    let groupID: UUID
    let entry: FolderEntry?
    var children: [SidebarItem] = []
    init(group: FolderGroup) { groupID = group.id; entry = nil; super.init(); children = group.entries.map { SidebarItem(group: group.id, entry: $0) } }
    init(group: UUID, entry: FolderEntry) { groupID = group; self.entry = entry }
}

@MainActor final class SidebarController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    unowned let pane: PaneController
    let outline = MenuOutline()
    var items: [SidebarItem] = []
    var reloading = false
    let addGroupButton=NSButton()
    var collapseSidebarButton: NSButton!
    let emptyHint = label("还没有分组\n点击下方 ＋ 创建分组", size: 12)
    var selectedGroup: UUID? {
        if let item = outline.item(atRow: outline.selectedRow) as? SidebarItem { return item.groupID }
        return pane.app.state.panes[pane.index].groups.first?.id
    }
    init(pane: PaneController) { self.pane = pane; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() {
        view = NSView(); view.wantsLayer = true
        let column = NSTableColumn(identifier: .init("folder")); column.resizingMask = .autoresizingMask; outline.addTableColumn(column); outline.outlineTableColumn = column; outline.headerView = nil; outline.style = .plain; outline.dataSource = self; outline.delegate = self; outline.rowHeight = 30; outline.indentationPerLevel = 14; outline.intercellSpacing = NSSize(width: 0, height: 2); outline.selectionHighlightStyle = .regular
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outline.target = self; outline.action = #selector(rowClicked); outline.autoresizingMask = [.width]
        outline.registerForDraggedTypes([sidebarDragType, .fileURL]); outline.setDraggingSourceOperationMask([.copy,.move], forLocal: true); outline.setDraggingSourceOperationMask([], forLocal: false)
        outline.focused = { [weak self] in guard let self else { return }; self.pane.app.activePane = self.pane.index }
        let menu = NSMenu(); menu.delegate = self; outline.menu = menu
        let scroll = NSScrollView(); scroll.documentView = outline; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        collapseSidebarButton = iconButton("sidebar.left", "收起分组栏", target: pane, action: #selector(PaneController.toggleSidebar))
        addGroupButton.title="＋ 新建分组";addGroupButton.target=self;addGroupButton.action = #selector(newGroup);addGroupButton.isBordered=false;addGroupButton.font = .systemFont(ofSize:13,weight:.medium);addGroupButton.setAccessibilityIdentifier("add-group-button-\(pane.index)")
        let bottom = rowStack([addGroupButton,spacer(),collapseSidebarButton!], spacing: 4); bottom.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 6); bottom.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let stack = NSStackView(views: [scroll, bottom]); stack.orientation = .vertical; stack.spacing = 0; stack.alignment = .leading; scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true; bottom.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true; pin(stack, in: view)
        reload(); applyTheme()
    }
    func applyTheme() { guard isViewLoaded else { return }; view.layer?.backgroundColor = pane.palette.sidebar.cgColor; outline.backgroundColor = pane.palette.sidebar; outline.enclosingScrollView?.backgroundColor = pane.palette.sidebar; emptyHint.textColor = pane.palette.secondary; outline.reloadData() }
    func reload() {
        guard isViewLoaded else { return }; reloading = true
        let groups = pane.app.state.panes[pane.index].groups; items = groups.map(SidebarItem.init); outline.reloadData()
        for (i, group) in groups.enumerated() where !group.collapsed { outline.expandItem(items[i]) }
        reloading = false; selectCurrentDirectory()
        if groups.isEmpty { outline.toolTip = "点击新建分组，再点击分组标题右侧的 ＋ 添加文件夹。" }
        else { outline.toolTip = "拖动排序；跨屏拖动入口或分组；按住 Option 复制配置。" }
    }
    func selectCurrentDirectory() {
        guard isViewLoaded else { return }; for r in 0..<outline.numberOfRows {
            if let item = outline.item(atRow: r) as? SidebarItem, item.entry?.path == pane.currentURL.path { reloading = true; outline.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false); reloading = false; return }
        }
    }
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { item == nil ? items.count : ((item as? SidebarItem)?.children.count ?? 0) }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { if let item = item as? SidebarItem { return item.children[index] }; return items[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { guard let item = item as? SidebarItem else { return false }; return item.entry == nil }
    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool { true }
    func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item:Any)->Bool{true}
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { item is SidebarItem }
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat { guard let item = item as? SidebarItem else { return 80 }; return item.entry == nil ? 38 : 30 }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? SidebarItem else { return nil }
        if let entry = item.entry {
            let image = NSImageView(image: symbol("folder") ?? NSImage()); image.contentTintColor = pane.palette.accent; image.widthAnchor.constraint(equalToConstant: 17).isActive = true; image.heightAnchor.constraint(equalToConstant: 17).isActive = true
            let text = label(entry.name, size: 13); text.textColor = pane.palette.text; text.toolTip = entry.path
            let cell = NSTableCellView(); pin(rowStack([image,text], spacing: 6), in: cell, inset: 2); cell.textField = text; cell.imageView = image; cell.toolTip = entry.path; return cell
        }
        let name = pane.app.state.panes[pane.index].groups.first(where: { $0.id == item.groupID })?.name ?? ""
        return GroupHeaderContent(name:name,groupID:item.groupID,outline:outline,palette:pane.palette,target:self,action:#selector(addToGroup(_:)))
    }
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {if let item = item as? SidebarItem, item.entry == nil { let row = GroupHeaderRow(); row.color = pane.palette.groupHeader; return row }; let r = TintedRow(); r.tint = pane.palette.selection; return r }
    @objc func rowClicked() { let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow;guard let item = outline.item(atRow:row) as? SidebarItem, item.entry == nil else { return }; toggleGroup(item.groupID) }
    func toggleGroup(_ id: UUID) { guard let item = items.first(where:{$0.groupID == id}) else { return }; if outline.isItemExpanded(item) { outline.collapseItem(item) } else { outline.expandItem(item) };outline.reloadItem(item) }
    func outlineViewSelectionDidChange(_ notification: Notification) { guard !reloading, let item = outline.item(atRow: outline.selectedRow) as? SidebarItem, let entry = item.entry else { return }; pane.navigate(to: entry.url) }
    func outlineViewItemDidCollapse(_ notification: Notification) { saveCollapsed(notification, true) }
    func outlineViewItemDidExpand(_ notification: Notification) { saveCollapsed(notification, false) }
    func saveCollapsed(_ n: Notification, _ collapsed: Bool) {
        guard !reloading, let item = n.userInfo?["NSObject"] as? SidebarItem else { return }
        pane.app.update({ state in if let g = state.panes[pane.index].groups.firstIndex(where: { $0.id == item.groupID }) { state.panes[pane.index].groups[g].collapsed = collapsed } }, refreshSidebar: false)
    }
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let item = item as? SidebarItem else { return nil }; let payload = SidebarDrag(pane: pane.index, id: item.entry?.id ?? item.groupID, group: item.entry == nil)
        let p = NSPasteboardItem(); p.setData(try! JSONEncoder().encode(payload), forType: sidebarDragType); return p
    }
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex childIndex: Int) -> NSDragOperation {
        if let data = info.draggingPasteboard.data(forType: sidebarDragType), let payload = try? JSONDecoder().decode(SidebarDrag.self, from: data) {
            let target = item as? SidebarItem
            if payload.group {
                if let target, target.entry != nil { return [] }
                if let target, let position = items.firstIndex(where: { $0.groupID == target.groupID }) { outlineView.setDropItem(nil, dropChildIndex: position) }
            }
            else if target?.entry != nil || target == nil { return [] }
            return NSEvent.modifierFlags.contains(.option) && payload.pane != pane.index ? .copy : .move
        }
        if (item as? SidebarItem)?.entry == nil && item != nil && info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly:true]) { return .copy }
        return []
    }
    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex: Int) -> Bool {
        let target = item as? SidebarItem; let copy = NSEvent.modifierFlags.contains(.option)
        if let data = info.draggingPasteboard.data(forType: sidebarDragType), let payload = try? JSONDecoder().decode(SidebarDrag.self, from: data) {
            let succeeded = pane.app.update { state in
                if payload.group { let position = target.flatMap { t in state.panes[pane.index].groups.firstIndex(where: { $0.id == t.groupID }) } ?? (childIndex < 0 ? nil : childIndex); try state.transferGroup(from: payload.pane, groupID: payload.id, to: pane.index, index: position, copy: copy) }
                else if let target { try state.transferEntry(from: payload.pane, entryID: payload.id, to: pane.index, groupID: target.groupID, index: childIndex < 0 ? nil : childIndex, copy: copy) }
            }
            if succeeded { pane.app.message(copy ? "已复制导航配置，磁盘文件保持原位。" : "已移动导航配置，磁盘文件保持原位。") }
            return succeeded
        }
        guard let target else { return false }
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly:true]) as? [URL] ?? []
        pane.app.update { state in for url in urls where (try? FileRecord(url: url).browsable) == true { try state.addEntry(FolderEntry(path: url.path), pane: pane.index, group: target.groupID) } }
        return true
    }
    @objc func newGroup() {
        guard let name = pane.app.input("新建分组", detail: "分组只整理文件夹入口，不创建磁盘目录。") else { return }
        pane.app.update { $0.panes[pane.index].groups.append(FolderGroup(name: name)) }
    }
    @objc func addToGroup(_ sender: NSButton) { guard let raw = sender.identifier?.rawValue, let group = UUID(uuidString:raw) else { return }; chooseFolders(group:group) }
    @objc func addFolders() {
        if selectedGroup == nil { newGroup() }; guard let group = selectedGroup else { return }
        chooseFolders(group:group)
    }
    func chooseFolders(group: UUID) {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true; panel.prompt = "添加入口"; panel.directoryURL = pane.currentURL
        panel.beginSheetModal(for: pane.app.window) { [weak self] result in guard let self, result == .OK else { return }; self.pane.app.update { state in for url in panel.urls { try state.addEntry(FolderEntry(path: url.path), pane: self.pane.index, group: group) } } }
    }
    @objc func addCurrentFolder() { if selectedGroup == nil { newGroup() }; guard let group = selectedGroup else { return }; pane.app.update { try $0.addEntry(FolderEntry(path: pane.currentURL.path), pane: pane.index, group: group) } }
    @objc func renameGroup() {
        guard let group = selectedGroup, let old = pane.app.state.panes[pane.index].groups.first(where: { $0.id == group }), let name = pane.app.input("重命名分组", initial: old.name) else { return }
        pane.app.update { state in if let i = state.panes[pane.index].groups.firstIndex(where: { $0.id == group }) { state.panes[pane.index].groups[i].name = name } }
    }
    @objc func copyEntryPath() { guard let entry = (outline.item(atRow: outline.selectedRow) as? SidebarItem)?.entry else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.path,forType:.string); pane.app.message("已复制完整路径") }
    @objc func removeItem() {
        guard let item = outline.item(atRow: outline.selectedRow) as? SidebarItem else { return }
        if let entry = item.entry { pane.app.update { state in for i in state.panes[pane.index].groups.indices { state.panes[pane.index].groups[i].entries.removeAll { $0.id == entry.id } } } }
        else if pane.app.confirm("删除这个分组？", detail: "仅移除分组及导航入口，磁盘文件夹保持不变。", button: "删除分组") { pane.app.update { $0.panes[pane.index].groups.removeAll { $0.id == item.groupID } } }
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ action: Selector) { let i = NSMenuItem(title: title, action: action, keyEquivalent: ""); i.target = self; menu.addItem(i) }
        add("新建分组…", #selector(newGroup)); add("添加文件夹入口…", #selector(addFolders)); add("将当前目录加入此组", #selector(addCurrentFolder))
        if let item = outline.item(atRow: outline.selectedRow) as? SidebarItem { menu.addItem(.separator()); if item.entry == nil { add("重命名分组…", #selector(renameGroup)); add("删除分组…", #selector(removeItem)) } else { add("复制完整路径", #selector(copyEntryPath)); let terminal = NSMenuItem(title:"在终端打开",action:#selector(PaneController.openTerminal),keyEquivalent:""); terminal.target = pane; menu.addItem(terminal); add("移除文件夹入口", #selector(removeItem)) } }
    }
}
