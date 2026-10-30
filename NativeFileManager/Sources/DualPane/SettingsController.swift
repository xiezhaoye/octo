import AppKit
import FileManagerCore

@MainActor final class SettingsController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    unowned let app: AppController
    let skinPopup = NSPopUpButton()
    let table = NSTableView()
    let editButton = NSButton(title:"编辑…",target:nil,action:nil)
    let removeButton = NSButton(title:"移除",target:nil,action:nil)
    let menuDragType = NSPasteboard.PasteboardType("com.xiezhaoye.octo.menu-order")
    var menuKeys: [String] { ContextMenuOrder.groupedKeys(saved:app.state.contextMenuOrder,commands:app.state.commands,groups:app.state.contextCommandGroups) }
    var selectedCustomCommand: CustomCommand? { guard menuKeys.indices.contains(table.selectedRow) else { return nil }; let key=menuKeys[table.selectedRow]; return app.state.commands.first{ContextMenuOrder.key(for:$0)==key} }
    init(app: AppController) {
        self.app = app
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 580), styleMask: [.titled,.closable,.resizable], backing: .buffered, defer: false); window.title = "设置";window.minSize=NSSize(width:780,height:540);window.titlebarAppearsTransparent=true; window.isReleasedWhenClosed = false
        super.init(window: window)
        build(); window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    enum Section:String,CaseIterable {case appearance="外观",commands="右键菜单",updates="关于与更新"}
    let pageHost=NSView()
    let navigation=NSStackView()
    var pages:[Section:NSView]=[:]
    var sectionButtons:[Section:NSButton]=[:]
    private(set) var selectedSection:Section = .appearance
    lazy var updater=AppUpdateController(app:app)
    func page(_ title:String)->NSStackView {
        let stack=NSStackView();stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=16
        stack.addArrangedSubview(label(title,size:21,weight:.semibold))
        return stack
    }
    func build() {
        let appearance=page("外观")
        skinPopup.focusRingType = .none
        skinPopup.addItems(withTitles:Skin.allCases.map(\.title));skinPopup.selectItem(at:Skin.allCases.firstIndex(of:app.state.skin) ?? 0)
        skinPopup.target=self;skinPopup.action=#selector(skinChanged);skinPopup.setAccessibilityLabel("界面外观")
        appearance.addArrangedSubview(rowStack([label("界面皮肤",size:13),skinPopup,spacer()]))
        let help=label("侧栏与导航使用系统磨砂材质，文件和文档区域保持清晰。\n系统启用“降低透明度”时，自动使用实色背景。",size:13);help.maximumNumberOfLines=3;help.lineBreakMode = .byWordWrapping;help.textColor = .secondaryLabelColor
        appearance.addArrangedSubview(help);appearance.addArrangedSubview(NSView())
        let commands=page("右键菜单")
        let explanation=label("菜单按用途分组。拖动可调整组内顺序；拖到另一分组的命令前，可移动到该组。",size:12);explanation.maximumNumberOfLines=2;explanation.lineBreakMode = .byWordWrapping;commands.addArrangedSubview(explanation)
        for (id,title,width) in [("name","命令名称",190.0),("group","分组",120.0),("script","类型／Shell 命令",220.0)] {
            let column=NSTableColumn(identifier:.init(id));column.title=title;column.width=width;table.addTableColumn(column)
        }
        table.dataSource=self;table.delegate=self;table.rowHeight=31;table.target=self;table.doubleAction=#selector(editCommand)
        table.registerForDraggedTypes([menuDragType]);table.setDraggingSourceOperationMask(.move,forLocal:true);table.verticalMotionCanBeginDrag=true;table.allowsMultipleSelection=false
        let scroll=NSScrollView();scroll.documentView=table;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:260).isActive=true;commands.addArrangedSubview(scroll)
        editButton.target=self;editButton.action=#selector(editCommand);removeButton.target=self;removeButton.action=#selector(removeCommand)
        commands.addArrangedSubview(rowStack([NSButton(title:"添加命令…",target:self,action:#selector(addCommand)),editButton,removeButton,spacer()]))
        let foot=label("内置命令可排序；自定义命令支持按文件类型筛选、编辑和移除。",size:11);foot.textColor = .secondaryLabelColor;commands.addArrangedSubview(foot)
        let updates=page("关于与更新");updates.addArrangedSubview(updater.view)
        pages=[.appearance:appearance,.commands:commands,.updates:updates]
        for content in pages.values.compactMap({$0 as? NSStackView}) {
            for child in content.arrangedSubviews {child.widthAnchor.constraint(equalTo:content.widthAnchor).isActive=true}
        }
        navigation.orientation = .vertical;navigation.alignment = .leading;navigation.spacing=6;navigation.edgeInsets=NSEdgeInsets(top:22,left:12,bottom:18,right:12)
        let symbols=["paintpalette","line.3.horizontal.decrease","arrow.down.circle"]
        for (index,section) in Section.allCases.enumerated() {
            let button=NSButton(title:section.rawValue,target:self,action:#selector(sectionClicked(_:)));button.image=symbol(symbols[index]);button.imagePosition = .imageLeading;button.alignment = .left;button.isBordered=false;button.tag=index;button.wantsLayer=true;button.layer?.cornerRadius=8
            button.heightAnchor.constraint(equalToConstant:36).isActive=true;button.widthAnchor.constraint(equalToConstant:152).isActive=true
            button.setAccessibilityLabel(section.rawValue);sectionButtons[section]=button;navigation.addArrangedSubview(button)
        }
        navigation.addArrangedSubview(NSView())
        let sidebar=MaterialSurface(material:.sidebar,blending:.behindWindow);pin(navigation,in:sidebar);sidebar.widthAnchor.constraint(equalToConstant:176).isActive=true
        let content=NSView();content.wantsLayer=true;pin(pageHost,in:content,inset:26)
        let root=NSStackView(views:[sidebar,content]);root.orientation = .horizontal;root.distribution = .fill;root.spacing=0;root.alignment = .top
        content.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-176).isActive=true
        sidebar.heightAnchor.constraint(equalTo:root.heightAnchor).isActive=true;content.heightAnchor.constraint(equalTo:root.heightAnchor).isActive=true
        window?.contentView=root;table.reloadData();selectSection(.appearance)
        tableViewSelectionDidChange(Notification(name:NSTableView.selectionDidChangeNotification));sidebar.apply(Palette.forSkin(app.state.skin).sidebar);applyTheme()
    }
    @objc func sectionClicked(_ sender:NSButton){selectSection(Section.allCases[sender.tag])}
    func selectSection(_ section:Section) {
        selectedSection=section;pageHost.subviews.forEach{$0.removeFromSuperview()}
        if let page=pages[section] {pin(page,in:pageHost)}
        for (key,button) in sectionButtons {button.layer?.backgroundColor=(key == section ? Palette.forSkin(app.state.skin).selection:NSColor.clear).cgColor;button.setAccessibilityValue(key == section ? 1:0)}
        window?.initialFirstResponder=section == .commands ? table:sectionButtons[section]
    }
    func applyTheme() {
        let p=Palette.forSkin(app.state.skin);window?.backgroundColor=p.canvas;pageHost.superview?.layer?.backgroundColor=p.canvas.cgColor
        if let sidebar=navigation.superview as? MaterialSurface {sidebar.apply(p.sidebar)}
        for (key,button) in sectionButtons {button.layer?.backgroundColor=(key == selectedSection ? p.selection:NSColor.clear).cgColor}
    }
    @objc func skinChanged() { let skin = Skin.allCases[skinPopup.indexOfSelectedItem]; app.update({$0.skin = skin},refreshSidebar:false); app.applyAppearance() }
    func numberOfRows(in tableView: NSTableView) -> Int { menuKeys.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard menuKeys.indices.contains(row) else { return nil }; let key=menuKeys[row]
        let builtin=BuiltinContextCommand(rawValue:key), custom=app.state.commands.first{ContextMenuOrder.key(for:$0)==key}
        let value:String
        if tableColumn?.identifier.rawValue == "group" {value=ContextCommandGroup.group(for:key,overrides:app.state.contextCommandGroups).title}
        else {value=tableColumn?.identifier.rawValue == "name" ? (builtin?.title ?? custom?.name ?? "") : (builtin != nil ? "内置命令 · 可拖动排序" : custom?.script ?? "")}
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
        let original=menuKeys
        let destination=original.indices.contains(row) ? original[row]:original.last ?? key
        let group=ContextCommandGroup.group(for:destination,overrides:app.state.contextCommandGroups)
        let ordered=ContextMenuOrder.moving(key,in:original,before:row)
        app.update({state in
            if state.contextCommandGroups == nil {state.contextCommandGroups=[:]}
            state.contextCommandGroups?[key]=group.rawValue;state.contextMenuOrder=ordered
        },refreshSidebar:false);table.reloadData()
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
