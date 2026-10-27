import AppKit
import FileManagerCore

@MainActor final class SettingsController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    unowned let app: AppController
    let skinPopup = NSPopUpButton()
    let table = NSTableView()
    let editButton = NSButton(title:"编辑…",target:nil,action:nil)
    let removeButton = NSButton(title:"移除",target:nil,action:nil)
    let menuDragType = NSPasteboard.PasteboardType("com.xiezhaoye.octo.menu-order")
    var menuKeys: [String] { ContextMenuOrder.keys(saved:app.state.contextMenuOrder,commands:app.state.commands) }
    var selectedCustomCommand: CustomCommand? { guard menuKeys.indices.contains(table.selectedRow) else { return nil }; let key=menuKeys[table.selectedRow]; return app.state.commands.first{ContextMenuOrder.key(for:$0)==key} }
    init(app: AppController) {
        self.app = app
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 630, height: 550), styleMask: [.titled,.closable], backing: .buffered, defer: false); window.title = "设置"; window.isReleasedWhenClosed = false
        super.init(window: window)
        build(); window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    func build() {
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 14; root.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        root.addArrangedSubview(label("更换皮肤", size: 15, weight: .semibold))
        skinPopup.focusRingType = .none
        skinPopup.addItems(withTitles: Skin.allCases.map(\.title)); skinPopup.selectItem(at: Skin.allCases.firstIndex(of: app.state.skin) ?? 0); skinPopup.target = self; skinPopup.action = #selector(skinChanged); skinPopup.setAccessibilityLabel("更换皮肤")
        let skinRow = rowStack([label("界面皮肤",size:13), skinPopup, spacer()]); root.addArrangedSubview(skinRow)
        let explanation = label("切换后立即生效，分组、目录与分屏状态保持不变。",size:12); explanation.textColor = .secondaryLabelColor; root.addArrangedSubview(explanation)
        let line = NSBox(); line.boxType = .separator; root.addArrangedSubview(line)
        root.addArrangedSubview(label("右键命令与排序", size: 15, weight: .semibold))
        let help = label("拖动整行调整右键菜单顺序。内置命令可排序；自定义命令可编辑和移除。",size:11); help.maximumNumberOfLines = 2; help.lineBreakMode = .byWordWrapping; root.addArrangedSubview(help)
        let c = NSTableColumn(identifier:.init("name")); c.title = "命令名称"; c.width = 180; table.addTableColumn(c)
        let script = NSTableColumn(identifier:.init("script")); script.title = "类型／Shell 命令"; script.width = 330; table.addTableColumn(script); table.dataSource = self; table.delegate = self; table.rowHeight = 29; table.target = self; table.doubleAction = #selector(editCommand); table.registerForDraggedTypes([menuDragType]); table.setDraggingSourceOperationMask(.move, forLocal:true); table.allowsMultipleSelection = false; table.verticalMotionCanBeginDrag = true
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true; root.addArrangedSubview(scroll)
        let add = NSButton(title:"添加命令…",target:self,action:#selector(addCommand)); editButton.target=self;editButton.action = #selector(editCommand);removeButton.target=self;removeButton.action = #selector(removeCommand);root.addArrangedSubview(rowStack([add,editButton,removeButton,spacer()]))
        let foot = label("终端：支持默认终端；Termius 入口会复制目录路径后打开应用。",size:11); foot.textColor = .secondaryLabelColor; root.addArrangedSubview(foot)
        for view in root.arrangedSubviews { view.widthAnchor.constraint(equalTo: root.widthAnchor,constant:-48).isActive = true }
        root.wantsLayer = true; window?.contentView = root; window?.initialFirstResponder = table; tableViewSelectionDidChange(Notification(name:NSTableView.selectionDidChangeNotification)); applyTheme()
    }
    func applyTheme() { let p = Palette.forSkin(app.state.skin); window?.contentView?.layer?.backgroundColor = p.toolbar.cgColor; window?.backgroundColor = p.toolbar }
    @objc func skinChanged() { let skin = Skin.allCases[skinPopup.indexOfSelectedItem]; app.update({$0.skin = skin},refreshSidebar:false); app.applyAppearance() }
    func numberOfRows(in tableView: NSTableView) -> Int { menuKeys.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard menuKeys.indices.contains(row) else { return nil }; let key=menuKeys[row]
        let builtin=BuiltinContextCommand(rawValue:key), custom=app.state.commands.first{ContextMenuOrder.key(for:$0)==key}
        let value=tableColumn?.identifier.rawValue == "name" ? (builtin?.title ?? custom?.name ?? "") : (builtin != nil ? "内置命令 · 可拖动排序" : custom?.script ?? "")
        let text=label(value,size:12);text.toolTip=value;return text
    }
    func tableViewSelectionDidChange(_ notification: Notification) { let custom=selectedCustomCommand != nil;editButton.isEnabled=custom;removeButton.isEnabled=custom }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard menuKeys.indices.contains(row) else { return nil };let item=NSPasteboardItem();item.setString(menuKeys[row],forType:menuDragType);return item
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        guard let key=info.draggingPasteboard.string(forType:menuDragType),menuKeys.contains(key) else{return []}
        table.setDropRow(row,dropOperation:.above);return .move
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let key=info.draggingPasteboard.string(forType:menuDragType),menuKeys.contains(key) else{return false}
        moveMenuEntry(key,before:row);return true
    }
    func moveMenuEntry(_ key:String,before row:Int) {
        let ordered=ContextMenuOrder.moving(key,in:menuKeys,before:row)
        app.update({$0.contextMenuOrder=ordered},refreshSidebar:false);table.reloadData()
        if let position=ordered.firstIndex(of:key){table.selectRowIndexes(IndexSet(integer:position),byExtendingSelection:false)}
    }
    @objc func addCommand() { edit(nil) }
    @objc func editCommand() { guard let command=selectedCustomCommand else{return};edit(command) }
    func edit(_ command: CustomCommand?) {
        let a = NSAlert(); a.messageText=command == nil ? "添加自定义命令" : "编辑自定义命令"; a.informativeText="使用 zsh 执行。路径占位符会自动进行 Shell 转义。"
        let name=NSTextField(string:command?.name ?? ""); name.placeholderString="例如：显示文件信息…"
        let script=NSTextField(string:command?.script ?? "stat {path}"); script.placeholderString="例如：stat {path}…"; script.font = .monospacedSystemFont(ofSize:12,weight:.regular)
        let scope=NSPopUpButton(); scope.addItems(withTitles:CommandTarget.allCases.map(\.title)); scope.selectItem(at:CommandTarget.allCases.firstIndex(of:command?.target ?? .all) ?? 0)
        let extensions=NSTextField(string:command?.fileExtensions.joined(separator:", ") ?? ""); extensions.placeholderString="md, markdown, txt, json, html, htm"
        scope.setAccessibilityLabel("适用对象"); extensions.setAccessibilityLabel("适用文件扩展名")
        let stack=NSStackView(views:[label("命令名称"),name,label("Shell 命令"),script,label("适用对象"),scope,label("文件扩展名（选择“指定文件类型”时生效）"),extensions]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing=8; stack.frame=NSRect(x:0,y:0,width:430,height:250); name.widthAnchor.constraint(equalToConstant:430).isActive=true; script.widthAnchor.constraint(equalToConstant:430).isActive=true
        name.setAccessibilityLabel("命令名称"); script.setAccessibilityLabel("Shell 命令"); a.accessoryView=stack; a.addButton(withTitle:"保存"); a.addButton(withTitle:"取消"); a.window.initialFirstResponder=name
        guard a.runModal() == .alertFirstButtonReturn else{return}
        let title=name.stringValue.trimmingCharacters(in:.whitespacesAndNewlines), code=script.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !title.isEmpty && !code.isEmpty else{app.message("名称和命令内容不能为空。");return}
        let target=CommandTarget.allCases[scope.indexOfSelectedItem]
        let types=CustomCommand.normalizeExtensions(extensions.stringValue)
        guard target != .extensions || !types.isEmpty else{app.message("请填写至少一种文件扩展名，例如 md, txt, json, html。");return}
        var updated=CustomCommand(name:title,script:code,target:target,fileExtensions:types); if let command{updated.id=command.id}
        app.update({state in if let i=state.commands.firstIndex(where:{$0.id==updated.id}){state.commands[i]=updated}else{state.commands.append(updated)}},refreshSidebar:false); table.reloadData()
    }
    @objc func removeCommand() { guard let command=selectedCustomCommand else{return};app.update({$0.commands.removeAll{$0.id==command.id}},refreshSidebar:false);table.reloadData();tableViewSelectionDidChange(Notification(name:NSTableView.selectionDidChangeNotification)) }
}
