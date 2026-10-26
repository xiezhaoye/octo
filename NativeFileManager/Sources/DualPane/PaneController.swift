import AppKit
import QuickLookThumbnailing
import FileManagerCore
import Darwin

final class FileNode: NSObject {
    let record: FileRecord
    var children: [FileNode]?
    init(_ record: FileRecord) { self.record = record }
}

@MainActor final class PaneController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate, NSCollectionViewDataSource, NSCollectionViewDelegate {
    unowned let app: AppController
    let index: Int
    let reader = DirectoryReader()
    var currentURL: URL
    var records: [FileRecord] = []
    var nodes: [FileNode] = []
    var history: [URL] = []
    var historyIndex = -1
    var loadTask: Task<Void, Never>?
    var expandTask: Task<Void, Never>?
    var generation = UUID()
    var watch: DispatchSourceFileSystemObject?
    var watchTimer: Timer?
    var columnControllers: [DirectoryColumn] = []
    var columnSelection: [URL] = []
    var isLoading = false
    var sidebar: SidebarController!
    let list = MenuOutline()
    let listScroll = NSScrollView()
    let collection = FileCollectionView()
    let iconScroll = NSScrollView()
    let columnStack = NSStackView()
    let columnsScroll = ColumnCanvasScrollView()
    let contentHost = NSView()
    let pathControl = BreadcrumbBar()
    let sidebarSplit = SidebarSplitView()
    let sidebarHost = NSView()
    let fileHost = NSView()
    let sidebarRail = SidebarRail()
    let status = label("")
    let errorLabel = label("")
    let modeControl = ModePicker()
    let spinner = NSProgressIndicator()
    var hiddenButton: NSButton!
    var columnFrameObserver: NSObjectProtocol?
    var backButton: NSButton!
    var forwardButton: NSButton!
    var toolbarView: NSView!
    var navigationBackground: NSView!
    var selectedURLs: [URL] {
        if app.state.panes[index].mode == .list { return list.selectedRowIndexes.compactMap { (list.item(atRow: $0) as? FileNode)?.record.url } }
        if app.state.panes[index].mode == .icons { return collection.selectionIndexPaths.sorted().compactMap { records.indices.contains($0.item) ? records[$0.item].url : nil } }
        return columnSelection
    }
    var palette: Palette { Palette.forSkin(app.state.skin) }
    init(app: AppController, index: Int) { self.app = app; self.index = index; currentURL = URL(fileURLWithPath: app.state.panes[index].directory); super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    deinit { watch?.cancel(); loadTask?.cancel(); expandTask?.cancel(); if let columnFrameObserver { NotificationCenter.default.removeObserver(columnFrameObserver) } }
    override func loadView() {
        view = NSView(); view.wantsLayer = true
        backButton = iconButton("chevron.left", "后退", target: self, action: #selector(back))
        forwardButton = iconButton("chevron.right", "前进", target: self, action: #selector(forward))
        let up = iconButton("arrow.up", "上一级", target: self, action: #selector(up))
        modeControl.target=self;modeControl.action = #selector(modeChanged)
        hiddenButton = iconButton("eye.slash", "显示隐藏项目（⌘⇧.）", target: self, action: #selector(toggleHidden))
        let collapsePane = iconButton("rectangle.lefthalf.inset.filled", index == 0 ? "收起左屏" : "收起右屏", target: self, action: #selector(hidePane))
        for button in [backButton!,forwardButton!,up,hiddenButton!,collapsePane] { button.image = button.image?.withSymbolConfiguration(.init(pointSize:19,weight:.regular)) }
        spinner.widthAnchor.constraint(equalToConstant:12).isActive=true;spinner.heightAnchor.constraint(equalToConstant:12).isActive=true
        toolbarView = rowStack([backButton, forwardButton, up, spacer(), spinner, modeControl, hiddenButton, collapsePane], spacing: 3)
        (toolbarView as? NSStackView)?.edgeInsets = NSEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        toolbarView.heightAnchor.constraint(equalToConstant: 58).isActive = true
        sidebar = SidebarController(pane: self)
        setupList(); setupIcons(); setupColumns()
        pathControl.onNavigate = { [weak self] url in self?.navigate(to:url) }; pathControl.setAccessibilityLabel("当前目录路径")
        let copy = iconButton("doc.on.doc", "复制当前目录路径", target:self, action:#selector(copyCurrentPath))
        let terminal = iconButton("terminal", "在当前目录打开终端", target:self, action:#selector(openCurrentTerminal))
        pathControl.setActions(copy:copy,terminal:terminal)
        let pathRow = rowStack([pathControl], spacing: 3); pathRow.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 8); pathRow.heightAnchor.constraint(equalToConstant: 38).isActive = true
        let content = NSStackView(views: [toolbarView!,pathRow,contentHost]); content.orientation = .vertical; content.spacing = 1; content.alignment = .leading
        navigationBackground = content; content.wantsLayer = true
        for v in [toolbarView!,pathRow,contentHost] { v.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true }
        pin(content,in:fileHost)
        sidebarSplit.owner = self; sidebarSplit.addSubview(sidebarHost); sidebarSplit.addSubview(fileHost); pin(sidebarSplit,in:view)
        sidebarRail.target = self; sidebarRail.action = #selector(toggleSidebar)
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        errorLabel.maximumNumberOfLines = 4; errorLabel.alignment = .center; errorLabel.lineBreakMode = .byWordWrapping; errorLabel.isHidden = true
        let menu = NSMenu(); menu.delegate = self; list.menu = menu
        let iconMenu = NSMenu(); iconMenu.delegate = self; collection.menu = iconMenu
        list.focused = { [weak self] in guard let self else { return }; self.app.activePane = self.index }
        list.space = { [weak self] in self?.showFilePreview() }; list.enter = { [weak self] in self?.openSelection() }
        list.target = self; list.doubleAction = #selector(openSelection)
        collection.owner = self
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(openSelection)); doubleClick.numberOfClicksRequired = 2; collection.addGestureRecognizer(doubleClick)
        applyTheme(); installMode(); applySidebarState()
    }
    func navigationButton(_ image: String,_ tip: String,action:Selector) -> NSButton { let button = NSButton(image:symbol(image)?.withSymbolConfiguration(.init(pointSize:19,weight:.regular)) ?? NSImage(),target:self,action:action);button.isBordered = false;button.bezelStyle = .texturedRounded;button.toolTip=tip;button.setAccessibilityLabel(tip);button.widthAnchor.constraint(equalToConstant:30).isActive=true;button.heightAnchor.constraint(equalToConstant:32).isActive=true;return button }
    func applySidebarState() {
        let state = app.state.panes[index]; let child: NSView = state.sidebarCollapsed ? sidebarRail : sidebar.view
        if sidebarHost.subviews.first !== child { sidebarHost.subviews.forEach{$0.removeFromSuperview()};pin(child,in:sidebarHost) }
        sidebarSplit.desiredWidth = state.sidebarWidth;sidebarSplit.sidebarCollapsed=state.sidebarCollapsed;sidebarSplit.arrange();sidebarSplit.needsDisplay=true;sidebarRail.palette=palette
    }
    @objc func toggleSidebar() { app.activePane=index;app.update({$0.panes[index].sidebarCollapsed.toggle()},refreshSidebar:false);applySidebarState() }
    func rememberSidebarWidth(_ width:CGFloat) { app.update({$0.panes[index].sidebarWidth=Double(min(480,max(144,width)))},refreshSidebar:false) }
    func resizeSidebar(to width:CGFloat) { rememberSidebarWidth(width);applySidebarState() }
    func setupList() {
        list.dataSource = self; list.delegate = self; list.headerView = NSTableHeaderView(); list.rowHeight = 28; list.intercellSpacing = NSSize(width: 6, height: 0); list.allowsMultipleSelection = true; list.usesAlternatingRowBackgroundColors = true; list.indentationPerLevel = 16
        for (id, title, width) in [("name", "名称", CGFloat(270)), ("date", "修改日期", CGFloat(115)), ("size", "大小", CGFloat(65))] {
            let c = NSTableColumn(identifier: .init(id)); c.title = title; c.width = width; c.minWidth = id == "name" ? 120 : 55; c.resizingMask = id == "name" ? [.autoresizingMask, .userResizingMask] : .userResizingMask; c.sortDescriptorPrototype = NSSortDescriptor(key:id,ascending:true); list.addTableColumn(c)
        }
        list.outlineTableColumn = list.tableColumns[0]; list.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        list.registerForDraggedTypes([.fileURL]); list.setDraggingSourceOperationMask([.copy,.move], forLocal: true); list.setDraggingSourceOperationMask([.copy,.move], forLocal: false)
        list.autoresizingMask = [.width]; listScroll.documentView = list; listScroll.hasVerticalScroller = true; listScroll.hasHorizontalScroller = true; listScroll.autohidesScrollers = true
    }
    func setupIcons() {
        let layout = NSCollectionViewFlowLayout(); layout.itemSize = NSSize(width: 108, height: 112); layout.minimumInteritemSpacing = 12; layout.minimumLineSpacing = 14; layout.sectionInset = NSEdgeInsets(top: 18, left: 16, bottom: 18, right: 16)
        collection.collectionViewLayout = layout; collection.dataSource = self; collection.delegate = self; collection.isSelectable = true; collection.allowsMultipleSelection = true
        collection.register(FileTile.self, forItemWithIdentifier: .init("file")); collection.registerForDraggedTypes([.fileURL])
        collection.setDraggingSourceOperationMask([.copy,.move], forLocal: true); collection.setDraggingSourceOperationMask([.copy,.move], forLocal: false)
        iconScroll.documentView = collection; iconScroll.hasVerticalScroller = true; iconScroll.autohidesScrollers = true
    }
    func setupColumns() {
        columnsScroll.pane=self
        columnStack.orientation = .horizontal; columnStack.spacing = 1; columnStack.alignment = .top; columnStack.translatesAutoresizingMaskIntoConstraints = true
        columnsScroll.documentView = columnStack; columnsScroll.hasHorizontalScroller = true; columnsScroll.autohidesScrollers = true;columnsScroll.scrollerStyle = .legacy;columnsScroll.horizontalScrollElasticity = .allowed
        columnsScroll.contentView.postsFrameChangedNotifications=true
        columnFrameObserver=NotificationCenter.default.addObserver(forName:NSView.frameDidChangeNotification,object:columnsScroll.contentView,queue:.main){[weak self] _ in Task{@MainActor in self?.layoutColumns()}}
    }
    func applyTheme() {
        guard isViewLoaded else { return }; let p = palette
        view.layer?.backgroundColor = p.line.cgColor
        toolbarView?.wantsLayer = true;toolbarView?.layer?.backgroundColor = p.toolbar.cgColor
        contentHost.wantsLayer = true; contentHost.layer?.backgroundColor = p.canvas.cgColor
        navigationBackground.layer?.backgroundColor = p.toolbar.cgColor
        list.backgroundColor = p.canvas; iconScroll.backgroundColor = p.canvas; collection.backgroundColors = [p.canvas]; columnsScroll.backgroundColor = p.canvas; columnStack.wantsLayer = true; columnStack.layer?.backgroundColor = p.line.cgColor
        status.textColor = p.secondary; errorLabel.textColor = p.secondary
        hiddenButton.contentTintColor = app.state.panes[index].showHidden ? p.accent : p.secondary
        modeControl.palette = p
        pathControl.show(currentURL,palette:p);sidebarRail.palette=p
        sidebar.applyTheme(); list.reloadData(); collection.reloadData(); columnControllers.forEach { $0.applyTheme() }; updateFocus()
    }
    func updateFocus() {guard isViewLoaded else{return};view.setAccessibilityLabel("\(index == 0 ? "左屏" : "右屏")：\(currentURL.lastPathComponent)\(app.activePane == index ? "，当前操作屏" : "")")}
    func installMode() {
        contentHost.subviews.forEach { $0.removeFromSuperview() }
        let mode = app.state.panes[index].mode
        modeControl.selectedSegment = mode == .list ? 0 : mode == .columns ? 1 : 2
        if mode == .list { pin(listScroll, in: contentHost) }
        else if mode == .icons { pin(iconScroll, in: contentHost) }
        else { pin(columnsScroll, in: contentHost) }
        if !errorLabel.isHidden { errorLabel.translatesAutoresizingMaskIntoConstraints = false; contentHost.addSubview(errorLabel); NSLayoutConstraint.activate([errorLabel.centerXAnchor.constraint(equalTo: contentHost.centerXAnchor),errorLabel.centerYAnchor.constraint(equalTo: contentHost.centerYAnchor),errorLabel.widthAnchor.constraint(lessThanOrEqualTo: contentHost.widthAnchor,constant:-32)]) }
    }
    @objc func modeChanged() {
        app.activePane = index
        let mode: BrowseMode = modeControl.selectedSegment == 0 ? .list : modeControl.selectedSegment == 1 ? .columns : .icons
        app.update({ $0.panes[index].mode = mode }, refreshSidebar: false); installMode(); reloadDirectory()
    }
    @objc func hidePane() { app.collapse(index) }
    @objc func toggleHidden() { app.activePane = index; app.update({ $0.panes[index].showHidden.toggle() }, refreshSidebar: false); applyTheme(); reloadDirectory() }
    @objc func back() { guard historyIndex > 0 else { return }; historyIndex -= 1; navigate(to: history[historyIndex], recordHistory: false) }
    @objc func forward() { guard historyIndex+1 < history.count else { return }; historyIndex += 1; navigate(to: history[historyIndex], recordHistory: false) }
    @objc func up() { navigate(to: currentURL.deletingLastPathComponent()) }
    @objc func goToFolder() {
        guard let path = app.input("前往文件夹", initial: currentURL.path, detail: "可以输入完整路径或以 ~ 开头的路径。") else { return }
        navigate(to: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
    }
    func navigate(to url: URL, recordHistory: Bool = true, resetColumns: Bool = true) {
        app.activePane = index; currentURL = url.standardizedFileURL; expandTask?.cancel()
        records = []; nodes = []; list.reloadData(); collection.reloadData(); if resetColumns { columnSelection = [] }
        if recordHistory && history.last != currentURL { if historyIndex+1 < history.count { history.removeSubrange((historyIndex+1)..<history.count) }; history.append(currentURL); historyIndex = history.count-1 }
        if history.isEmpty { history = [currentURL]; historyIndex = 0 }
        pathControl.show(currentURL,palette:palette)
        backButton.isEnabled = historyIndex > 0; forwardButton.isEnabled = historyIndex+1 < history.count
        app.update({ $0.panes[index].directory = currentURL.path }, refreshSidebar: false)
        sidebar.selectCurrentDirectory(); installMode(); load(resetColumns: resetColumns); startWatching()
    }
    func reloadDirectory() { if !isViewLoaded { return }; load(resetColumns: true) }
    func load(resetColumns: Bool) {
        loadTask?.cancel(); let token = UUID(); generation = token; let url = currentURL; let hidden = app.state.panes[index].showHidden
        isLoading = true; spinner.startAnimation(nil); status.stringValue = "正在读取…"; errorLabel.isHidden = true
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.reader.contents(of: url, showHidden: hidden)
                guard !Task.isCancelled && self.generation == token else { return }
                self.records = result; self.nodes = self.sortedNodes(result.map(FileNode.init)); self.list.reloadData(); self.collection.reloadData(); self.spinner.stopAnimation(nil); self.isLoading = false
                self.status.stringValue = result.isEmpty ? "此文件夹为空" : "\(result.count) 个项目"
                self.errorLabel.isHidden = !result.isEmpty; self.errorLabel.stringValue = "此文件夹为空\n可拖入文件，或右键新建文件夹"
                self.installMode()
                if resetColumns && self.app.state.panes[self.index].mode == .columns { self.resetColumns(with: result, url: url) }
            } catch is CancellationError { }
            catch { guard self.generation == token else { return }; self.records = []; self.nodes = []; self.list.reloadData(); self.collection.reloadData(); self.resetColumns(with: [], url: url); self.spinner.stopAnimation(nil); self.isLoading = false; self.status.stringValue = "无法读取目录"; self.errorLabel.stringValue = "无法读取目录\n请检查路径和访问权限，或点击上一级"; self.errorLabel.isHidden = false; self.installMode(); self.app.message(error.localizedDescription) }
        }
    }
    func reloadSidebar() { guard isViewLoaded else { return }; sidebar.reload() }
    func startWatching() {
        watch?.cancel(); watch = nil; let fd = open(currentURL.path, O_EVTONLY); guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write,.rename,.delete], queue: .main)
        source.setEventHandler { [weak self] in guard let self else { return }; self.watchTimer?.invalidate(); self.watchTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in Task { @MainActor in self?.reloadDirectory() } } }
        source.setCancelHandler { close(fd) }; source.resume(); watch = source
    }
    func sortedNodes(_ items:[FileNode])->[FileNode] {
        guard let descriptor=list.sortDescriptors.first else{return items}
        return items.sorted {a,b in
            var order:ComparisonResult
            switch descriptor.key {
            case "date": order=(a.record.modified ?? .distantPast).compare(b.record.modified ?? .distantPast)
            case "size":
                let x=a.record.directory ? Int64(-1) : a.record.size, y=b.record.directory ? Int64(-1) : b.record.size
                order=x == y ? .orderedSame : x < y ? .orderedAscending : .orderedDescending
            default: order=a.record.name.localizedStandardCompare(b.record.name)
            }
            if order == .orderedSame {order=a.record.url.path.localizedStandardCompare(b.record.url.path)}
            return descriptor.ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }
    func outlineView(_ outlineView:NSOutlineView,sortDescriptorsDidChange oldDescriptors:[NSSortDescriptor]) {
        let selected=Set(selectedURLs)
        let expanded=(0..<list.numberOfRows).compactMap{list.item(atRow:$0) as? FileNode}.filter{list.isItemExpanded($0)}
        func sortTree(_ items:[FileNode])->[FileNode]{for n in items{if let children=n.children{n.children=sortTree(children)}};return sortedNodes(items)}
        nodes=sortTree(nodes);list.reloadData()
        for n in expanded{list.expandItem(n)}
        let rows=(0..<list.numberOfRows).filter{(list.item(atRow:$0) as? FileNode).map{selected.contains($0.record.url)} ?? false}
        list.selectRowIndexes(IndexSet(rows),byExtendingSelection:false)
    }
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { if let node = item as? FileNode { return node.children?.count ?? 0 }; return nodes.count }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { if let node = item as? FileNode { return node.children![index] }; return nodes[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { guard let n = item as? FileNode else { return false }; return n.record.browsable && !n.record.symbolicLink }
    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        guard let n = item as? FileNode, n.children == nil else { return true }
        let token = generation
        Task { do { let children = try await reader.contents(of: n.record.url, showHidden: app.state.panes[index].showHidden); guard token == generation else { return }; n.children = sortedNodes(children.map(FileNode.init)); list.reloadItem(n, reloadChildren: true); list.expandItem(n) } catch { app.showError(error) } }
        return false
    }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }; let r = node.record; let id = tableColumn?.identifier.rawValue ?? "name"
        if id == "name" {
            let cell = NSTableCellView(); let image = NSImageView(); image.image = NSWorkspace.shared.icon(forFile: r.url.path); image.widthAnchor.constraint(equalToConstant: 18).isActive = true; image.heightAnchor.constraint(equalToConstant: 18).isActive = true
            let text = label(r.name, size: 13); text.textColor = r.hidden ? palette.secondary : palette.text; text.toolTip = r.url.path; let stack = rowStack([image, text], spacing: 7); pin(stack, in: cell, inset: 2); cell.textField = text; cell.imageView = image; return cell
        }
        let text = label(id == "date" ? (r.modified.map { Self.dateFormatter.string(from: $0) } ?? "—") : (r.directory ? "—" : ByteCountFormatter.string(fromByteCount: r.size, countStyle: .file)), size: 11); text.textColor = palette.secondary; if id == "size" { text.alignment = .right }; return text
    }
    static let dateFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy/MM/dd HH:mm"; return f }()
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { let row = TintedRow(); row.tint = palette.selection; return row }
    func outlineViewSelectionDidChange(_ notification: Notification) { app.activePane = index; status.stringValue = "\(records.count) 个项目 · 已选 \(selectedURLs.count) 项" }
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? { (item as? FileNode)?.record.url as NSURL? }
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex childIndex: Int) -> NSDragOperation { info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly:true]) ? (NSEvent.modifierFlags.contains(.option) ? .copy : .move) : [] }
    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex: Int) -> Bool { let node = item as? FileNode; return acceptFiles(info, destination: node?.record.browsable == true ? node!.record.url : currentURL) }
    @discardableResult func acceptFiles(_ info: NSDraggingInfo, destination: URL) -> Bool { let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly:true]) as? [URL] ?? []; guard !urls.isEmpty else { return false }; app.performTransfer(urls, to: destination, copy: NSEvent.modifierFlags.contains(.option)); return true }
    @objc func expandAll() {
        expandTask?.cancel(); let token = generation; spinner.startAnimation(nil); status.stringValue = "正在展开目录… 再次点击收拢可停止"
        expandTask = Task { [weak self] in
            guard let self else { return }; var queue = self.nodes; var cursor = 0
            while cursor < queue.count && !Task.isCancelled && token == self.generation {
                let n = queue[cursor]; cursor += 1; if !n.record.browsable || n.record.symbolicLink { continue }
                do { if n.children == nil { n.children = self.sortedNodes(try await self.reader.contents(of: n.record.url, showHidden: self.app.state.panes[self.index].showHidden).map(FileNode.init)) }; guard !Task.isCancelled && token == self.generation else { break }; self.list.reloadItem(n, reloadChildren: true); self.list.expandItem(n); queue.append(contentsOf: n.children ?? []) } catch { self.app.message("部分目录无法展开：" + error.localizedDescription) }
                await Task.yield()
            }
            self.spinner.stopAnimation(nil); self.status.stringValue = "\(self.records.count) 个顶层项目 · 已显示 \(self.list.numberOfRows) 行"
        }
    }
    @objc func collapseAll() { expandTask?.cancel(); list.collapseItem(nil, collapseChildren: true); spinner.stopAnimation(nil); status.stringValue = "\(records.count) 个项目" }
    @objc func openSelection() { guard let url = selectedURLs.first else { return }; if let r = try? FileRecord(url: url), r.browsable { navigate(to: url) } else { NSWorkspace.shared.open(url) } }
    @objc func showFilePreview() { app.preview(selectedURLs) }
    func createFolder() { guard let name = app.input("新建文件夹", initial: "未命名文件夹") else { return }; Task { do { _ = try await app.fileOperator.createDirectory(in: currentURL, name: name); reloadDirectory() } catch { app.showError(error) } } }
    func renameSelection() { guard let url = selectedURLs.first, let name = app.input("重命名", initial: url.lastPathComponent) else { return }; Task { do { _ = try await app.fileOperator.rename(url, to: name); reloadDirectory(); app.update({ $0.normalize() }) } catch { app.showError(error) } } }
    func trashSelection() { let urls = selectedURLs; guard !urls.isEmpty, app.confirm("将 \(urls.count) 个项目移入废纸篓？", detail: "可从系统废纸篓恢复。", button: "移入废纸篓") else { return }; Task { do { try await app.fileOperator.trash(urls); reloadDirectory() } catch { app.showError(error) } } }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems(); app.activePane = index
        func item(_ title: String, _ action: Selector, target: AnyObject? = nil) { let i = NSMenuItem(title: title, action: action, keyEquivalent: ""); i.target = target ?? self; menu.addItem(i) }
        if !selectedURLs.isEmpty { item("打开", #selector(openSelection)); item("快速预览", #selector(showFilePreview)); item("复制完整路径", #selector(copyPath)); menu.addItem(.separator()); item("复制", #selector(AppController.copyFiles), target: app); item("重命名…", #selector(renameFromMenu)); item("移入废纸篓…", #selector(trashFromMenu)); menu.addItem(.separator()) }
        item("粘贴", #selector(AppController.pasteFiles), target: app); item("将剪贴板项目移到此处", #selector(AppController.moveFiles), target: app); item("新建文件夹…", #selector(newFolderFromMenu))
        if app.state.panes[index].mode == .list {menu.addItem(.separator());item("展开所有文件夹",#selector(expandAll));item("收拢所有文件夹",#selector(collapseAll))}
        menu.addItem(.separator()); item("在终端打开", #selector(openTerminal)); item("Termius：复制路径并打开", #selector(openTermius)); item(app.state.panes[index].showHidden ? "隐藏隐藏项目" : "显示隐藏项目", #selector(toggleHidden))
        if !app.state.commands.isEmpty { menu.addItem(.separator()); for c in app.state.commands { if c.foldersOnly && selectedURLs.contains(where: { (try? FileRecord(url: $0).browsable) != true }) { continue }; let i = NSMenuItem(title: c.name, action: #selector(runCommand(_:)), keyEquivalent: ""); i.target = self; i.representedObject = c.id; menu.addItem(i) } }
        menu.addItem(.separator()); item("管理自定义命令…", #selector(AppController.openSettings), target: app)
    }
    @objc func renameFromMenu() { renameSelection() }
    @objc func trashFromMenu() { trashSelection() }
    @objc func newFolderFromMenu() { createFolder() }
    @objc func copyPath() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(selectedURLs.map(\.path).joined(separator: "\n"), forType: .string); app.message("已复制完整路径") }
    @objc func copyCurrentPath(){app.activePane=index;NSPasteboard.general.clearContents();NSPasteboard.general.setString(currentURL.path,forType:.string);app.message("已复制当前目录路径")}
    @objc func openCurrentTerminal(){app.activePane=index;launchTerminal(at:currentURL)}
    var terminalDirectory: URL { if let url = selectedURLs.first { return (try? FileRecord(url: url).browsable) == true ? url : url.deletingLastPathComponent() }; return currentURL }
    @objc func openTerminal() {launchTerminal(at:terminalDirectory)}
    func launchTerminal(at directory:URL) { let configuration = NSWorkspace.OpenConfiguration(); NSWorkspace.shared.open([directory], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: configuration) { [weak self] _, error in if let error { DispatchQueue.main.async { self?.app.showError(error) } } } }
    @objc func openTermius() { let path = "/Applications/Termius.app"; guard FileManager.default.fileExists(atPath: path) else { app.message("未找到 Termius，请先安装或使用默认终端。"); return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(terminalDirectory.path, forType: .string); NSWorkspace.shared.open(URL(fileURLWithPath: path)); app.message("目录路径已复制，已打开 Termius。") }
    @objc func runCommand(_ sender: NSMenuItem) { guard let id = sender.representedObject as? UUID, let command = app.state.commands.first(where: { $0.id == id }) else { return }; let script = renderCommand(command.script, urls: selectedURLs, directory: currentURL); app.message("正在执行：" + command.name); let dir = currentURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/zsh"); p.arguments = ["-lc", script]; p.currentDirectoryURL = dir; let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
            do { try p.run(); var data = Data(); var truncated = false; while true { let chunk = pipe.fileHandleForReading.readData(ofLength: 65536); if chunk.isEmpty { break }; let remaining = max(0, 2_000_000-data.count); data.append(chunk.prefix(remaining)); if chunk.count > remaining { truncated = true } }; p.waitUntilExit(); var output = String(decoding: data, as: UTF8.self); if truncated { output += "\n输出超过 2 MB，后续内容未显示。" }; DispatchQueue.main.async { guard let self else { return }; self.app.message("\(command.name)：退出码 \(p.terminationStatus)"); CommandOutput.show(title: command.name, output: output.isEmpty ? "命令已结束，没有输出。" : output); self.reloadDirectory() } } catch { DispatchQueue.main.async { self?.app.showError(error) } }
        }
    }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { records.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem { let item = collectionView.makeItem(withIdentifier: .init("file"), for: indexPath) as! FileTile; item.configure(records[indexPath.item], palette: palette); return item }
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { app.activePane = index; status.stringValue = "\(records.count) 个项目 · 已选 \(selectedURLs.count) 项" }
    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool { true }
    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? { records[indexPath.item].url as NSURL }
    func resetColumns(with files: [FileRecord], url: URL) { columnControllers.forEach { $0.view.removeFromSuperview() }; columnControllers = []; addColumn(files, url: url) }
    func addColumn(_ files: [FileRecord], url: URL) {
        let column = DirectoryColumn(pane: self, files: files, url: url, position: columnControllers.count); columnControllers.append(column); columnStack.addArrangedSubview(column.view); column.view.widthAnchor.constraint(equalToConstant: 230).isActive = true; column.view.heightAnchor.constraint(equalTo: columnStack.heightAnchor).isActive = true
        layoutColumns();DispatchQueue.main.async {[weak self] in self?.layoutColumns(scrollToEnd:true)}
    }
    func layoutColumns(scrollToEnd:Bool=false){
        let clip=columnsScroll.contentView;let width=max(clip.bounds.width,CGFloat(columnControllers.count)*230+CGFloat(max(0,columnControllers.count-1)))
        let size=NSSize(width:width,height:clip.bounds.height)
        if columnStack.frame.size != size {columnStack.setFrameSize(size)}
        columnStack.layoutSubtreeIfNeeded();let maximum=max(0,width-clip.bounds.width)
        let x=scrollToEnd ? maximum : min(clip.bounds.origin.x,maximum)
        clip.scroll(to:NSPoint(x:x,y:0));columnsScroll.reflectScrolledClipView(clip)
    }
    @discardableResult func routeColumnScroll(_ event:NSEvent)->Bool{
        guard app.state.panes[index].mode == .columns else{return false}
        let shifted=event.modifierFlags.contains(.shift)
        let dx=shifted && abs(event.scrollingDeltaY)>abs(event.scrollingDeltaX) ? event.scrollingDeltaY : event.scrollingDeltaX
        guard abs(dx)>0.001,shifted || abs(event.scrollingDeltaX)>abs(event.scrollingDeltaY) else{return false}
        let clip=columnsScroll.contentView;let maximum=max(0,columnStack.frame.width-clip.bounds.width)
        let scale:CGFloat=event.hasPreciseScrollingDeltas ? 1 : 12
        let next=min(maximum,max(0,clip.bounds.minX-dx*scale))
        clip.scroll(to:NSPoint(x:next,y:0));columnsScroll.reflectScrolledClipView(clip);return true
    }
    func selectColumn(_ position: Int, record: FileRecord) {
        app.activePane = index; columnSelection = [record.url]
        while columnControllers.count > position+1 { columnControllers.removeLast().view.removeFromSuperview() }
        layoutColumns()
        guard record.browsable else { return }
        navigate(to: record.url, resetColumns: false)
        let selected = record.url
        Task { do { let files = try await reader.contents(of: selected, showHidden: app.state.panes[index].showHidden); guard currentURL == selected, app.state.panes[index].mode == .columns else { return }; addColumn(files, url: selected) } catch { app.showError(error) } }
    }
}
