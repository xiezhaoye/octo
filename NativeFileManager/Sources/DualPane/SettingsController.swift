import AppKit
import FileManagerCore

@MainActor final class SettingsController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    unowned let app: AppController
    let skinPopup = NSPopUpButton()
    let table = NSTableView()
    let sample = NSView()
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
        skinPopup.addItems(withTitles: Skin.allCases.map(\.title)); skinPopup.selectItem(at: Skin.allCases.firstIndex(of: app.state.skin) ?? 0); skinPopup.target = self; skinPopup.action = #selector(skinChanged); skinPopup.setAccessibilityLabel("更换皮肤")
        let skinRow = rowStack([label("界面皮肤",size:13), skinPopup, spacer()]); root.addArrangedSubview(skinRow)
        let explanation = label("切换后立即生效，分组、目录与分屏状态保持不变。",size:12); explanation.textColor = .secondaryLabelColor; root.addArrangedSubview(explanation)
        sample.wantsLayer = true; sample.layer?.cornerRadius = 7; sample.heightAnchor.constraint(equalToConstant: 52).isActive = true; let sampleText = label("个人资料    ›    健康                         文件与目录",size:13); pin(sampleText,in:sample,inset:14); root.addArrangedSubview(sample)
        let line = NSBox(); line.boxType = .separator; root.addArrangedSubview(line)
        root.addArrangedSubview(label("右键自定义命令", size: 15, weight: .semibold))
        let help = label("占位符：{path} 首个选中项目，{paths} 全部项目，{directory} 当前目录。",size:11); help.maximumNumberOfLines = 2; help.lineBreakMode = .byWordWrapping; root.addArrangedSubview(help)
        let c = NSTableColumn(identifier:.init("name")); c.title = "命令名称"; c.width = 180; table.addTableColumn(c)
        let script = NSTableColumn(identifier:.init("script")); script.title = "Shell 命令"; script.width = 330; table.addTableColumn(script); table.dataSource = self; table.delegate = self; table.rowHeight = 29; table.target = self; table.doubleAction = #selector(editCommand)
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true; root.addArrangedSubview(scroll)
        let add = NSButton(title:"添加命令…",target:self,action:#selector(addCommand)); let edit = NSButton(title:"编辑…",target:self,action:#selector(editCommand)); let remove = NSButton(title:"移除",target:self,action:#selector(removeCommand)); root.addArrangedSubview(rowStack([add,edit,remove,spacer()]))
        let foot = label("终端：支持默认终端；Termius 入口会复制目录路径后打开应用。",size:11); foot.textColor = .secondaryLabelColor; root.addArrangedSubview(foot)
        for view in root.arrangedSubviews { view.widthAnchor.constraint(equalTo: root.widthAnchor,constant:-48).isActive = true }
        root.wantsLayer = true; window?.contentView = root; applyTheme()
    }
    func applyTheme() { let p = Palette.forSkin(app.state.skin); window?.contentView?.layer?.backgroundColor = p.toolbar.cgColor; window?.backgroundColor = p.toolbar; sample.layer?.backgroundColor = p.sidebar.cgColor; (sample.subviews.first as? NSTextField)?.textColor = p.text; sample.layer?.borderColor = p.line.cgColor; sample.layer?.borderWidth = 1 }
    @objc func skinChanged() { let skin = Skin.allCases[skinPopup.indexOfSelectedItem]; app.update({$0.skin = skin},refreshSidebar:false); app.applyAppearance() }
    func numberOfRows(in tableView: NSTableView) -> Int { app.state.commands.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? { let command=app.state.commands[row]; let text=label(tableColumn?.identifier.rawValue == "name" ? command.name : command.script,size:12); text.toolTip=command.script; return text }
    @objc func addCommand() { edit(nil) }
    @objc func editCommand() { guard app.state.commands.indices.contains(table.selectedRow) else { return }; edit(app.state.commands[table.selectedRow]) }
    func edit(_ command: CustomCommand?) {
        let a = NSAlert(); a.messageText=command == nil ? "添加自定义命令" : "编辑自定义命令"; a.informativeText="使用 zsh 执行。路径占位符会自动进行 Shell 转义。"
        let name=NSTextField(string:command?.name ?? ""); name.placeholderString="例如：显示文件信息…"
        let script=NSTextField(string:command?.script ?? "stat {path}"); script.placeholderString="例如：stat {path}…"; script.font = .monospacedSystemFont(ofSize:12,weight:.regular)
        let folders=NSButton(checkboxWithTitle:"仅用于文件夹",target:nil,action:nil); folders.state=command?.foldersOnly == true ? .on:.off
        let stack=NSStackView(views:[label("命令名称"),name,label("Shell 命令"),script,folders]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing=8; stack.frame=NSRect(x:0,y:0,width:430,height:150); name.widthAnchor.constraint(equalToConstant:430).isActive=true; script.widthAnchor.constraint(equalToConstant:430).isActive=true
        name.setAccessibilityLabel("命令名称"); script.setAccessibilityLabel("Shell 命令"); a.accessoryView=stack; a.addButton(withTitle:"保存"); a.addButton(withTitle:"取消"); a.window.initialFirstResponder=name
        guard a.runModal() == .alertFirstButtonReturn else{return}
        let title=name.stringValue.trimmingCharacters(in:.whitespacesAndNewlines), code=script.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !title.isEmpty && !code.isEmpty else{app.message("名称和命令内容不能为空。");return}
        var updated=CustomCommand(name:title,script:code,foldersOnly:folders.state == .on); if let command{updated.id=command.id}
        app.update({state in if let i=state.commands.firstIndex(where:{$0.id==updated.id}){state.commands[i]=updated}else{state.commands.append(updated)}},refreshSidebar:false); table.reloadData()
    }
    @objc func removeCommand() { guard app.state.commands.indices.contains(table.selectedRow) else{return};let id=app.state.commands[table.selectedRow].id;app.update({$0.commands.removeAll{$0.id==id}},refreshSidebar:false);table.reloadData() }
}
