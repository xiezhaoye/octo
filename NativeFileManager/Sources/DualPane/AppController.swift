import AppKit
import QuickLookUI
import FileManagerCore

@MainActor final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate, NSToolbarDelegate, @preconcurrency QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var state = Workspace()
    var store: WorkspaceStore!
    var window: NSWindow!
    var panes: [PaneController] = []
    var paneSlots:[NSView]=[]
    var paneRestoreRails:[SidebarRail]=[]
    var collapsedPaneWidths:[NSLayoutConstraint]=[]
    var equalPaneWidths:NSLayoutConstraint!
    var titleBrand:OctoTitleView!
    var activePane = 0 { didSet { panes.forEach { $0.updateFocus() } } }
    let fileOperator = FileOperator()
    var settings: SettingsController?
    var previewURLs: [URL] = []
    var saveTimer: Timer?
    var operationTask: Task<Void, Never>?
    var stopRemaining = false
    var operationLabel = label("")
    var operationSpinner = NSProgressIndicator()
    var operationStatusView: NSView!
    var messageTimer: Timer?
    var cancelButton: NSButton!
    let paneDivider=NSView()
    var undoTransfers: [(from: URL, to: URL)] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        let config: URL
        if let i = args.firstIndex(of: "--state-dir"), i + 1 < args.count { config = URL(fileURLWithPath: args[i+1]).appendingPathComponent("workspace.json") }
        else { config = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DualPane/workspace.json") }
        store = WorkspaceStore(url: config)
        do { state = try store.load() }
        catch {
            let a = NSAlert(); a.messageText = "无法读取上次的工作区"; a.informativeText = "原配置将保留为备份。\n" + error.localizedDescription
            a.addButton(withTitle: "使用默认配置"); a.addButton(withTitle: "退出")
            if a.runModal() != .alertFirstButtonReturn { NSApp.terminate(nil); return }
            let backup = config.deletingLastPathComponent().appendingPathComponent("workspace-backup-\(Int(Date().timeIntervalSince1970)).json")
            do { try FileManager.default.copyItem(at: config, to: backup) } catch { showError(error); NSApp.terminate(nil); return }
        }
        buildMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 860), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Octo"; window.minSize = NSSize(width: 1000, height: 560)
        window.delegate = self
        window.setFrameAutosaveName("DualPaneMainWindow"); window.center(); window.toolbarStyle = .unifiedCompact
        let toolbar = NSToolbar(identifier: "MainToolbar"); toolbar.delegate = self; toolbar.displayMode = .iconAndLabel; window.toolbar = toolbar
        window.titleVisibility = .hidden
        let titleAccessory=NSTitlebarAccessoryViewController();titleAccessory.layoutAttribute = .left
        titleBrand=OctoTitleView(frame:NSRect(x:0,y:0,width:96,height:30));titleAccessory.view=titleBrand;window.addTitlebarAccessoryViewController(titleAccessory)
        NSApp.applicationIconImage=OctoBrand.logo
        let root = NSStackView(); root.orientation = .vertical; root.distribution = .fill; root.spacing = 0; root.alignment = .leading
        root.wantsLayer = true
        let paneStack = NSStackView(); paneStack.orientation = .horizontal; paneStack.distribution = .fill; paneStack.spacing = 0
        for i in 0..<2 {
            let p=PaneController(app:self,index:i);panes.append(p)
            if i == 1{paneDivider.wantsLayer=true;paneDivider.widthAnchor.constraint(equalToConstant:4).isActive=true;paneStack.addArrangedSubview(paneDivider);paneDivider.heightAnchor.constraint(equalTo:paneStack.heightAnchor).isActive=true}
            let slot=NSView();paneSlots.append(slot);paneStack.addArrangedSubview(slot)
            slot.heightAnchor.constraint(equalTo:paneStack.heightAnchor).isActive=true
            let rail=SidebarRail();rail.image=symbol(i == 0 ? "chevron.right" : "chevron.left");rail.tag=i;rail.target=self;rail.action = #selector(restorePaneFromRail(_:));rail.toolTip=i == 0 ? "展开左屏" : "展开右屏";rail.setAccessibilityLabel(rail.toolTip!);rail.setAccessibilityIdentifier("restore-pane-\(i)");paneRestoreRails.append(rail)
            collapsedPaneWidths.append(slot.widthAnchor.constraint(equalToConstant:48))
        }
        equalPaneWidths=paneSlots[0].widthAnchor.constraint(equalTo:paneSlots[1].widthAnchor)
        operationSpinner.style = .spinning; operationSpinner.controlSize = .small; operationSpinner.isDisplayedWhenStopped = false
        cancelButton = NSButton(title: "取消剩余", target: self, action: #selector(cancelTransfers)); cancelButton.bezelStyle = .inline; cancelButton.isHidden = true
        let status = rowStack([operationSpinner, operationLabel, spacer(), cancelButton], spacing: 8); status.edgeInsets = NSEdgeInsets(top: 2, left: 12, bottom: 2, right: 12); status.heightAnchor.constraint(equalToConstant: 24).isActive = true
        operationStatusView=status;status.isHidden=true;root.detachesHiddenViews=true
        root.addArrangedSubview(paneStack); root.addArrangedSubview(status)
        paneStack.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true; status.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        window.contentView = root
        applyAppearance(); applyVisibility()
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        panes.forEach { $0.navigate(to: URL(fileURLWithPath: state.panes[$0.index].directory), recordHistory: false) }
        if let i = args.firstIndex(of: "--ui-smoke"), i+1 < args.count, args.contains("--state-dir") { runUISmoke(at: URL(fileURLWithPath: args[i+1])) }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { panes.allSatisfy { $0.editor.prepareToLeave() } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { if !flag { window.makeKeyAndOrderFront(nil) }; return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if operationTask != nil { let a = NSAlert(); a.messageText = "文件操作尚未完成"; a.informativeText = "请等待当前操作结束，或先取消剩余项目。"; a.addButton(withTitle: "继续等待"); a.runModal(); return .terminateCancel }
        guard panes.allSatisfy({ $0.editor.prepareToLeave() }) else { return .terminateCancel }; do { try store.save(state) } catch { showError(error); return .terminateCancel }; return .terminateNow
    }
    @discardableResult func update(_ body: (inout Workspace) throws -> Void, refreshSidebar: Bool = true) -> Bool {
        do { var draft = state; try body(&draft); state = draft; saveSoon(); if refreshSidebar { panes.forEach { $0.reloadSidebar() } }; return true }
        catch { showError(error); return false }
    }
    func saveSoon() {
        saveTimer?.invalidate(); saveTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            Task { @MainActor in guard let self else { return }; do { try self.store.save(self.state) } catch { self.showError(error) } }
        }
    }
    func applyAppearance() {
        let p = Palette.forSkin(state.skin); NSApp.appearance = NSAppearance(named: p.dark ? .darkAqua : .aqua)
        window?.backgroundColor = p.line; operationLabel.textColor = p.secondary
        window?.contentView?.layer?.backgroundColor = p.toolbar.cgColor
        panes.forEach { $0.applyTheme() }; settings?.applyTheme()
        paneRestoreRails.forEach{$0.palette=p};titleBrand?.name.textColor=p.text;paneDivider.layer?.backgroundColor=p.secondary.withAlphaComponent(0.55).cgColor
    }
    func applyVisibility() {
        equalPaneWidths.isActive=false
        for i in 0..<2{
            let hidden=state.panes[i].hidden;let child:NSView=hidden ? paneRestoreRails[i] : panes[i].view
            if paneSlots[i].subviews.first !== child{paneSlots[i].subviews.forEach{$0.removeFromSuperview()};pin(child,in:paneSlots[i])}
            panes[i].view.isHidden=hidden;collapsedPaneWidths[i].isActive=hidden
        }
        equalPaneWidths.isActive=state.panes.allSatisfy{!$0.hidden}
    }
    func collapse(_ index: Int) { update({ $0.setPaneHidden(index, hidden: true) }, refreshSidebar: false); applyVisibility(); if state.panes[index].hidden { activePane = 1-index } }
    @objc func restorePaneFromRail(_ sender:NSButton){restorePane(sender.tag)}
    func restorePane(_ index:Int){update({$0.restorePane(index)});panes[index].applySidebarState();applyVisibility();activePane=index}
    @objc func restoreBoth() {update({state in for i in state.panes.indices where state.panes[i].hidden{state.restorePane(i)}});panes.forEach{$0.applySidebarState()};applyVisibility()}
    @objc func openSettings() { if settings == nil { settings = SettingsController(app: self) }; settings?.showWindow(nil); settings?.window?.makeKeyAndOrderFront(nil) }
    func showError(_ error: Error) { let a = NSAlert(error: error); if let window, window.isVisible { a.beginSheetModal(for: window) } else { a.runModal() } }
    func message(_ text: String) { operationLabel.stringValue = text;operationStatusView?.isHidden=false;messageTimer?.invalidate();if operationTask == nil {messageTimer=Timer.scheduledTimer(withTimeInterval:4,repeats:false){[weak self] _ in Task{@MainActor in if self?.operationTask == nil {self?.operationLabel.stringValue="";self?.operationStatusView?.isHidden=true}}}} }
    func input(_ title: String, initial: String = "", detail: String = "") -> String? {
        let a = NSAlert(); a.messageText = title; a.informativeText = detail
        let field = NSTextField(string: initial); field.frame = NSRect(x: 0, y: 0, width: 340, height: 25); a.accessoryView = field
        a.addButton(withTitle: "确定"); a.addButton(withTitle: "取消"); a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return nil }; let result = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); return result.isEmpty ? nil : result
    }
    func confirm(_ title: String, detail: String, button: String = "确定") -> Bool { let a = NSAlert(); a.messageText = title; a.informativeText = detail; a.addButton(withTitle: button); a.addButton(withTitle: "取消"); return a.runModal() == .alertFirstButtonReturn }
    func performTransfer(_ urls: [URL], to directory: URL, copy: Bool, recordUndo: Bool = true) {
        guard operationTask == nil else { message("请先等待当前文件操作完成。"); return }
        let sources = urls.filter { candidate in !urls.contains { $0 != candidate && candidate.path.hasPrefix($0.path + "/") } }
        guard !sources.isEmpty else { return }
        stopRemaining = false; operationSpinner.startAnimation(nil); cancelButton.isHidden = false
        messageTimer?.invalidate();operationStatusView.isHidden=false
        operationTask = Task { [weak self] in
            guard let self else { return }; var completed = 0; var skipped = 0; var failures: [String] = []; var notes: [String] = []
            for (i, source) in sources.enumerated() {
                if self.stopRemaining { break }
                self.operationLabel.stringValue = "\(copy ? "复制" : "移动") \(i+1)/\(sources.count)：\(source.lastPathComponent)"
                var policy = self.state.conflictPolicy
                let target = directory.appendingPathComponent(source.lastPathComponent)
                if FileManager.default.fileExists(atPath: target.path), policy == .ask {
                    let a = NSAlert(); a.messageText = "已存在“\(source.lastPathComponent)”"; a.informativeText = "选择如何处理同名项目。替换文件夹会替换整个目标文件夹，不合并内容。"
                    a.addButton(withTitle: "保留两者"); a.addButton(withTitle: "跳过"); a.addButton(withTitle: "替换"); a.addButton(withTitle: "取消剩余")
                    switch a.runModal() { case .alertFirstButtonReturn: policy = .keepBoth; case .alertSecondButtonReturn: policy = .skip; case .alertThirdButtonReturn: policy = .replace; default: self.stopRemaining = true; continue }
                }
                do {
                    let result = try await self.fileOperator.transfer(source, to: directory, kind: copy ? .copy : .move, conflict: policy)
                    if result.skipped { skipped += 1 } else { completed += 1 }
                    if let note = result.note { notes.append(note) }
                    if recordUndo && result.moved && policy != .replace { self.undoTransfers.append((result.destination, result.source)) }
                } catch { failures.append("\(source.lastPathComponent)：\(error.localizedDescription)") }
            }
            self.operationTask = nil; self.operationSpinner.stopAnimation(nil); self.cancelButton.isHidden = true
            self.update({ $0.normalize() }); self.panes.forEach { $0.reloadDirectory() }
            self.message("\(self.stopRemaining ? "已停止。" : "")完成 \(completed) 项，跳过 \(skipped) 项\(failures.isEmpty ? "" : "，失败 \(failures.count) 项")")
            if !failures.isEmpty || !notes.isEmpty { let a = NSAlert(); a.messageText = failures.isEmpty ? "文件操作说明" : "部分项目未完成"; a.informativeText = (failures + notes).prefix(12).joined(separator: "\n"); a.beginSheetModal(for: self.window, completionHandler: nil) }
        }
    }
    @objc func cancelTransfers() { stopRemaining = true; cancelButton.isEnabled = false; operationLabel.stringValue = "正在完成当前项目，随后停止…"; DispatchQueue.main.asyncAfter(deadline: .now()+0.3) { self.cancelButton.isEnabled = true } }
    @objc func copyFiles() { if let editor = NSApp.keyWindow?.firstResponder as? NSTextView { editor.copy(nil); return }; let urls = panes[activePane].selectedURLs; guard !urls.isEmpty else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(urls as [NSURL]); message("已复制 \(urls.count) 个项目") }
    @objc func pasteFiles() { paste(move: false) }
    @objc func moveFiles() { paste(move: true) }
    func paste(move: Bool) { if let editor = NSApp.keyWindow?.firstResponder as? NSTextView { editor.paste(nil); return }; let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []; performTransfer(urls, to: panes[activePane].currentURL, copy: !move) }
    @objc func undoMove() { if let editor = NSApp.keyWindow?.firstResponder as? NSTextView { editor.undoManager?.undo(); return }; guard let move = undoTransfers.popLast() else { message("没有可撤销的移动。"); return }; if FileManager.default.fileExists(atPath: move.to.path) { undoTransfers.append(move); message("原位置已有同名项目，无法自动撤销。"); return }; performTransfer([move.from], to: move.to.deletingLastPathComponent(), copy: false, recordUndo: false) }
    @objc func previewSelection() { panes[activePane].showFilePreview() }
    @objc func saveDocument() { _ = panes[activePane].editor.save() }
    func preview(_ urls: [URL]) { guard !urls.isEmpty else { return }; previewURLs = urls; guard let panel = QLPreviewPanel.shared() else { return }; panel.updateController(); panel.makeKeyAndOrderFront(nil); panel.reloadData() }
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = self; panel.delegate = self }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil; panel.delegate = nil }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { previewURLs[index] as NSURL }
    @objc func newFolder() { panes[activePane].createFolder() }
    @objc func renameSelection() { panes[activePane].renameSelection() }
    @objc func trashSelection() { if let editor = NSApp.keyWindow?.firstResponder as? NSTextView { editor.deleteToBeginningOfLine(nil); return }; panes[activePane].trashSelection() }
    @objc func goToFolder() { panes[activePane].goToFolder() }
    @objc func refresh() { panes[activePane].reloadDirectory() }
    @objc func toggleHidden() { panes[activePane].toggleHidden() }
    func buildMenu() {
        let main = NSMenu(); NSApp.mainMenu = main
        func submenu(_ title: String) -> NSMenu { let item = NSMenuItem(); main.addItem(item); let menu = NSMenu(title: title); item.submenu = menu; return menu }
        func add(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String, _ mods: NSEvent.ModifierFlags = [.command]) { let i = NSMenuItem(title: title, action: action, keyEquivalent: key); i.keyEquivalentModifierMask = mods; i.target = self; menu.addItem(i) }
        let app = submenu("Octo"); add(app, "设置…", #selector(openSettings), ","); app.addItem(.separator()); add(app, "退出", #selector(NSApplication.terminate(_:)), "q"); app.items.last?.target = NSApp
        let file = submenu("文件"); add(file, "保存文档", #selector(saveDocument), "s"); add(file, "新建文件夹…", #selector(newFolder), "n", [.command,.shift]); add(file, "重命名…", #selector(renameSelection), ""); add(file, "快速预览", #selector(previewSelection), ""); add(file, "移入废纸篓", #selector(trashSelection), "\u{8}"); file.addItem(.separator()); add(file, "关闭窗口", #selector(NSWindow.performClose(_:)), "w"); file.items.last?.target = nil
        let edit = submenu("编辑"); add(edit, "剪切", #selector(NSText.cut(_:)), "x"); edit.items.last?.target = nil; add(edit, "撤销移动", #selector(undoMove), "z"); edit.addItem(.separator()); add(edit, "复制文件", #selector(copyFiles), "c"); add(edit, "粘贴文件", #selector(pasteFiles), "v"); add(edit, "将项目移到此处", #selector(moveFiles), "v", [.command,.option]); add(edit, "全选", #selector(NSResponder.selectAll(_:)), "a"); edit.items.last?.target = nil
        let view = submenu("显示"); add(view, "显示双屏", #selector(restoreBoth), "2"); add(view, "显示／隐藏隐藏项目", #selector(toggleHidden), ".", [.command,.shift]); add(view, "刷新", #selector(refresh), "r")
        let go = submenu("前往"); add(go, "前往文件夹…", #selector(goToFolder), "g", [.command,.shift])
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, .init("settings")] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, .init("settings")] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id); item.target = self
        guard id.rawValue == "settings" else{return nil}
        item.label="设置";item.action = #selector(openSettings)
        let button=NSButton(image:symbol("gearshape")?.withSymbolConfiguration(.init(pointSize:14,weight:.regular)) ?? NSImage(),target:self,action:#selector(openSettings))
        button.isBordered=false;button.toolTip="设置";button.setAccessibilityLabel("设置");button.widthAnchor.constraint(equalToConstant:24).isActive=true;button.heightAnchor.constraint(equalToConstant:24).isActive=true;item.view=button
        return item
    }
}
