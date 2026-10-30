import AppKit
import QuickLookUI
import FileManagerCore
import Darwin

extension AppController {
    /// Opt-in verification uses only files under the explicitly supplied smoke directory.
    func runUISmoke(at output: URL) {
        Task { @MainActor in
            var succeeded=false
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: output, withIntermediateDirectories: true)
                for name in ["failure.txt","ui-verification.json"]{let old=output.appendingPathComponent(name);if fm.fileExists(atPath:old.path){try fm.removeItem(at:old)}}
                let source = output.appendingPathComponent("测试资料/个人/健康")
                let family = output.appendingPathComponent("测试资料/家庭/健康")
                let target = output.appendingPathComponent("测试归档")
                for url in [source, family, target, source.appendingPathComponent("检查影像")] { try fm.createDirectory(at: url, withIntermediateDirectories: true) }
                for (name, text) in [("健康计划.md", "# 健康计划\n每周记录运动与睡眠。"), ("体检说明.txt", "年度检查记录"), (".hidden.txt", "hidden")] { try Data(text.utf8).write(to: source.appendingPathComponent(name)) }
                try Data("子目录检索记录".utf8).write(to: source.appendingPathComponent("检查影像/健康报告.txt"))
                try fm.createDirectory(at:source.appendingPathComponent("检查影像/第一层/第二层/第三层/第四层"),withIntermediateDirectories:true)
                state = Workspace(); state.panes[0].groups = [FolderGroup(name: "个人资料", entries: [FolderEntry(path: source.path)]), FolderGroup(name: "家庭资料", entries: [FolderEntry(path: family.path)])]; state.panes[1].groups = [FolderGroup(name: "归档位置", entries: [FolderEntry(path: target.path)])]
                applyVisibility();panes.forEach { $0.reloadSidebar() }; panes[0].navigate(to: source); panes[1].navigate(to: target);window.setContentSize(NSSize(width:1440,height:800))
                @MainActor func settle() async { try? await Task.sleep(nanoseconds: 550_000_000); window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded() }
                func check(_ condition: Bool, _ name: String) throws { if !condition { throw NSError(domain:"UISmoke",code:1,userInfo:[NSLocalizedDescriptionKey:name]) } }
                @MainActor func capture(_ name: String, _ v: NSView? = nil) throws {
                    guard let v = v ?? window.contentView, let bitmap = v.bitmapImageRepForCachingDisplay(in:v.bounds) else { throw NSError(domain:"UISmoke",code:2) }
                    v.cacheDisplay(in:v.bounds,to:bitmap)
                    guard let data = bitmap.representation(using:.png,properties:[:]) else { throw NSError(domain:"UISmoke",code:3) }
                    try data.write(to:output.appendingPathComponent(name+".png"))
                }
                var checks: [String] = []
                await settle(); try check(panes[0].records.count == 3,"真实目录读取与隐藏项目过滤"); checks.append("真实目录读取，隐藏项目默认不可见")
                try capture("layout-first-pass")
                try check(operationStatusView.isHidden,"空闲时不能有常驻状态栏")
                let sidebar=panes[0].sidebar!
                let group=sidebar.items[0]
                sidebar.outline.selectRowIndexes(IndexSet(integer:sidebar.outline.row(forItem:group)),byExtendingSelection:false)
                NSApp.sendAction(sidebar.outline.action!,to:sidebar.outline.target,from:sidebar.outline);await settle()
                try check(!sidebar.outline.isItemExpanded(group) && state.panes[0].groups[0].collapsed,"点击分组标题收起并保存：expanded=\(sidebar.outline.isItemExpanded(group)) saved=\(state.panes[0].groups[0].collapsed) selected=\(sidebar.outline.selectedRow) clicked=\(sidebar.outline.clickedRow) action=\(String(describing:sidebar.outline.action))")
                NSApp.sendAction(sidebar.outline.action!,to:sidebar.outline.target,from:sidebar.outline);await settle();try check(sidebar.outline.isItemExpanded(group),"点击分组标题展开")
                try capture("group-selected")
                if let row=sidebar.outline.rowView(atRow:0,makeIfNecessary:true) as? GroupHeaderRow {try check(row.interiorBackgroundStyle == .normal && !row.isSelected,"分组点击不改变图标强调色")}
                checks.append("分组整行点击展开收起，图标不随选中变色")
                let before=sidebar.addGroupButton.convert(sidebar.addGroupButton.bounds,to:sidebar.view)
                state.panes[0].groups.append(FolderGroup(name:"新增测试组"));sidebar.reload();await settle()
                let after=sidebar.addGroupButton.convert(sidebar.addGroupButton.bounds,to:sidebar.view)
                try check(abs(before.minY-after.minY)<1 && after.minY<60,"新建分组固定在左下角")
                state.panes[0].groups.removeLast();sidebar.reload();checks.append("唯一新建分组按钮固定左下角")
                panes[0].resizeSidebar(to:212);await settle();try check(abs(panes[0].sidebarHost.frame.width-212)<2,"调节分组栏宽度")
                if let header=sidebar.outline.view(atColumn:0,row:0,makeIfNecessary:true) as? GroupHeaderContent {
                    header.layoutSubtreeIfNeeded()
                    try check(header.name.alignment == .left && header.name.frame.minX<5 && abs(header.plus.frame.maxX-header.bounds.maxX)<2,"分组名称靠左箭头，加号靠右")
                    try check(abs(header.name.frame.midY-header.bounds.midY)<1,"分组标题文字垂直居中")
                    let plusRight=header.convert(NSPoint(x:header.plus.frame.maxX,y:0),to:sidebar.view).x
                    try check(sidebar.view.bounds.maxX-plusRight<20,"加号靠近分组栏右边缘：gap=\(sidebar.view.bounds.maxX-plusRight)")
                    let required=(header.name.stringValue as NSString).size(withAttributes:[.font:header.name.font!]).width+4
                    try check(header.name.frame.width>=required,"短分组名应完整显示：outline=\(sidebar.outline.bounds) cell=\(header.frame) text=\(header.name.frame) required=\(required)")
                }else{throw NSError(domain:"UISmoke",code:6,userInfo:[NSLocalizedDescriptionKey:"未找到分组标题控件"])}
                let breadcrumb=panes[0].pathControl
                if let current=breadcrumb.currentButton,let copy=breadcrumb.copyButton,let terminal=breadcrumb.terminalButton{try check(copy.frame.minX-current.frame.maxX>=0 && copy.frame.minX-current.frame.maxX<14 && terminal.frame.minX-copy.frame.maxX<14,"路径快捷操作紧跟最后一级目录")}
                panes[0].toggleSidebar();await settle();try check(abs(panes[0].sidebarHost.frame.width-24)<2 && state.panes[0].sidebarCollapsed,"侧栏收起成竖条");try check(panes[0].sidebarSplit.dividerThickness==0 && abs(panes[0].fileHost.frame.minX-panes[0].sidebarHost.frame.maxX)<0.1,"收起侧栏不留多余分隔线或占位");try capture("sidebar-collapsed")
                panes[0].sidebarRail.performClick(nil);await settle();try check(!state.panes[0].sidebarCollapsed && abs(panes[0].sidebarHost.frame.width-212)<2,"点击竖条恢复宽度")
                try check(panes[0].toolbarView.isDescendant(of:panes[0].fileHost) && abs(panes[0].sidebarHost.frame.height-panes[0].view.bounds.height)<2,"分组栏顶到顶部，导航位于右侧")
                checks.append("分组栏调宽、竖条收起恢复、顶部对齐")
                try capture("native-list")
                for segment in 0..<3 { panes[0].modeControl.buttons[segment].performClick(nil);await settle();try check(state.panes[0].mode == BrowseMode.allCases[segment],"视图切换");try capture("mode-\(segment)") }
                for button in panes[0].modeControl.buttons {
                    button.displayIfNeeded()
                    try check(abs(button.iconRect.midX-button.bounds.midX)<0.1 && abs(button.iconRect.midY-button.bounds.midY)<0.1,"视图按钮图标水平垂直居中")
                }
                try capture("mode-picker",panes[0].modeControl)
                try check(OctoBrand.logo != nil,"透明 Dock 图标资源可读取")
                checks.append("三种视图点击切换，图标按外框水平垂直居中，Dock 资源可读取")
                panes[0].modeControl.selectedSegment=1;panes[0].modeChanged();await settle()
                for level in 0..<4 {
                    guard panes[0].columnControllers.indices.contains(level),let folder=panes[0].columnControllers[level].files.first(where:{$0.browsable}) else{throw NSError(domain:"UISmoke",code:4,userInfo:[NSLocalizedDescriptionKey:"多级分栏未生成"])}
                    panes[0].selectColumn(level,record:folder);await settle()
                }
                panes[0].layoutColumns(scrollToEnd:true);await settle()
                let clip=panes[0].columnsScroll.contentView
                try check(panes[0].columnStack.frame.width>clip.bounds.width && clip.bounds.minX>0,"超宽分栏自动横向滚动")
                try capture("columns-overflow")
                func wheel(_ x:Int32,_ y:Int32=0,shift:Bool=false)->NSEvent {
                    let cg=CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:2,wheel1:y,wheel2:x,wheel3:0)!
                    if shift{cg.flags = .maskShift};return NSEvent(cgEvent:cg)!
                }
                let end=clip.bounds.minX
                panes[0].columnControllers[0].scroll.scrollWheel(with:wheel(90))
                try check(clip.bounds.minX<end,"嵌套列表响应向左手势")
                let left=clip.bounds.minX
                panes[0].columnControllers[0].table.scrollWheel(with:wheel(-90))
                try check(clip.bounds.minX>left,"文件列表响应向右手势")
                panes[0].columnControllers[0].scroll.scrollWheel(with:wheel(0,90,shift:true))
                try check(clip.bounds.minX<end,"Shift 滚轮横向浏览")
                checks.append("分栏触控板横向事件、鼠标横向事件、Shift 滚轮路由")
                let navigationRoot=panes[0].columnControllers.first!, deepest=panes[0].currentURL, originalColumns=panes[0].columnControllers.map(\.url)
                panes[0].back();if let task=panes[0].navigationRestoreTask{await task.value};await settle()
                try check(panes[0].currentURL == deepest.deletingLastPathComponent() && panes[0].columnControllers.count == originalColumns.count-1,"后退恢复上次目录与完整分栏链")
                try check(panes[0].columnControllers.first === navigationRoot,"后退保留共同父目录列")
                panes[0].forward();if let task=panes[0].navigationRestoreTask{await task.value};await settle()
                try check(panes[0].currentURL == deepest && panes[0].columnControllers.map(\.url) == originalColumns,"前进恢复下一次目录与分栏链")
                panes[0].back();panes[0].forward();if let task=panes[0].navigationRestoreTask{await task.value};await settle()
                try check(panes[0].currentURL == deepest && panes[0].columnControllers.map(\.url) == originalColumns,"快速后退前进不覆盖尚未恢复的分栏历史")
                panes[0].up();await settle()
                try check(panes[0].currentURL == deepest.deletingLastPathComponent() && panes[0].columnControllers.count == originalColumns.count-1 && panes[0].columnControllers.first === navigationRoot,"上一级只收回最右子目录列")
                panes[0].back();if let task=panes[0].navigationRestoreTask{await task.value};await settle()
                try check(panes[0].currentURL == deepest && panes[0].columnControllers.count == originalColumns.count,"上一级也记录在历史中并可后退恢复")
                checks.append("后退、前进、上一级保留分栏层级、共同父列和目录历史")
                panes[0].navigate(to:source);await settle()
                for index in 0..<2 {
                    state.panes[index].sidebarCollapsed=true
                    for g in state.panes[index].groups.indices{state.panes[index].groups[g].collapsed=true}
                    let entries=state.panes[index].groups.map(\.entries)
                    collapse(index);await settle()
                    try check(panes[index].view.isHidden && abs(paneSlots[index].frame.width-48)<2,"分屏收起保留宽竖条")
                    try check(paneSlots[index].frame.height>500,"折叠竖条保持窗口高度");let rail=paneRestoreRails[index];let normal=rail.layer?.backgroundColor
                    rail.mouseEntered(with:wheel(0));try check(rail.layer?.backgroundColor != normal,"竖条悬停反馈");rail.mouseExited(with:wheel(0))
                    try capture("pane-collapsed-\(index)")
                    paneRestoreRails[index].performClick(nil);await settle()
                    try check(!state.panes[index].hidden && !state.panes[index].sidebarCollapsed && state.panes[index].groups.allSatisfy{!$0.collapsed},"恢复分屏默认展开分组栏及所有分组")
                    try check(entries == state.panes[index].groups.map(\.entries),"恢复保留入口")
                }
                checks.append("左右分屏各保留48点恢复竖条，点击全部展开导航分组")
                titleBrand.layoutSubtreeIfNeeded()
                try check(window.title == "Octo" && titleBrand.name.stringValue == "Octo" && titleBrand.logo.image != nil && titleBrand.logo.frame.maxX<titleBrand.name.frame.minX && abs(titleBrand.logo.frame.midY-titleBrand.name.frame.midY)<1,"透明 Logo 位于 Octo 名称前方且垂直居中")
                try check(titleBrand.logo.layer?.backgroundColor == nil,"标题 Logo 不添加背景色")
                if let bitmap=titleBrand.logo.bitmapImageRepForCachingDisplay(in:titleBrand.logo.bounds){
                    titleBrand.logo.cacheDisplay(in:titleBrand.logo.bounds,to:bitmap)
                    let hasOrange=(0..<bitmap.pixelsWide).contains{x in (0..<bitmap.pixelsHigh).contains{y in guard let c=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB) else{return false};return c.alphaComponent>0.5 && c.redComponent>0.6 && c.redComponent>c.greenComponent*1.4}}
                    try check(hasOrange,"标题 Logo 保留原图橙色，不被系统染灰")
                }

                if let zoom=window.standardWindowButton(.zoomButton),let frameView=window.contentView?.superview {
                    let brandRect=titleBrand.convert(titleBrand.bounds,to:frameView)
                    let zoomRect=zoom.convert(zoom.bounds,to:frameView)
                    try check(brandRect.minX>=zoomRect.maxX,"品牌显示在窗口按钮右侧")
                }
                checks.append("透明 Logo 与 Octo 名称位于窗口按钮右侧")
                panes[0].modeControl.selectedSegment=0;panes[0].modeChanged();await settle()
                let p=panes[0]
                for key in ["name","date","size"] {
                    try check(p.list.tableColumns.first{$0.identifier.rawValue==key}?.sortDescriptorPrototype != nil,"表头可点击排序")
                    for ascending in [true,false] {
                        p.list.sortDescriptors=[NSSortDescriptor(key:key,ascending:ascending)];await settle()
                        let items=p.nodes.map(\.record)
                        for pair in zip(items,items.dropFirst()) {
                            switch key {
                            case "size":let x=pair.0.directory ? -1:pair.0.size,y=pair.1.directory ? -1:pair.1.size;try check(ascending ? x<=y:x>=y,"大小排序")
                            case "date":let x=pair.0.modified ?? .distantPast,y=pair.1.modified ?? .distantPast;try check(ascending ? x<=y:x>=y,"修改日期排序")
                            default:let order=pair.0.name.localizedStandardCompare(pair.1.name);try check(ascending ? order != .orderedDescending:order != .orderedAscending,"名称排序")
                            }
                        }
                    }
                }
                try capture("sorted-size")
                p.expandAll();await settle()
                let expanded=(0..<p.list.numberOfRows).compactMap{p.list.item(atRow:$0) as? FileNode}.filter{p.list.isItemExpanded($0)}
                let selectedRow=max(0,p.list.numberOfRows-1);p.list.selectRowIndexes(IndexSet(integer:selectedRow),byExtendingSelection:false)
                let selected=Set(p.selectedURLs)
                p.list.sortDescriptors=[NSSortDescriptor(key:"name",ascending:false)];await settle()
                try check(Set(p.selectedURLs)==selected && expanded.allSatisfy{p.list.isItemExpanded($0)},"排序保留选中项与目录展开状态")
                p.collapseAll();p.list.sortDescriptors=[];p.reloadDirectory();await settle()
                try check(!p.toolbarView.subviews.contains{$0 is NSSearchField},"搜索入口已删除")
                try check(window.toolbar?.items.filter{$0.itemIdentifier.rawValue=="restore"}.isEmpty == true,"标题栏删除分栏图标")
                try check(paneDivider.frame.width==1,"双屏使用轻量细分界")
                checks.append("名称、修改日期、大小双向排序，移除搜索和标题栏分栏按钮")
                let fileMenu=NSMenu();panes[0].menuNeedsUpdate(fileMenu);try check(fileMenu.items.contains(where:{$0.title=="展开所有文件夹"}) && fileMenu.items.contains(where:{$0.title=="收拢所有文件夹"}),"右键保留展开与收拢")
                panes[0].expandAll();await settle();try check(panes[0].list.numberOfRows>panes[0].records.count,"全部展开");panes[0].collapseAll();checks.append("右键保留列表全部展开和收拢")
                panes[0].toggleHidden();await settle();try check(panes[0].records.contains(where:{$0.hidden}),"显示隐藏项目");panes[0].toggleHidden();await settle();checks.append("显示隐藏文件切换")
                let entry=state.panes[0].groups[0].entries[0];try state.transferEntry(from:0,entryID:entry.id,to:1,groupID:state.panes[1].groups[0].id,copy:true);try check(fm.fileExists(atPath:source.path),"入口拖动不得改磁盘");panes.forEach{$0.reloadSidebar()};checks.append("Option 入口复制保持磁盘原位")
                settings=SettingsController(app:self)
                try check(settings!.skinPopup.focusRingType == .none,"皮肤下拉框不显示默认蓝色焦点环")
                @MainActor func includesSample(_ view:NSView)->Bool { if let text=view as? NSTextField,text.stringValue.contains("文件与目录"){return true};return view.subviews.contains{includesSample($0)} }
                try check(!includesSample(settings!.window!.contentView!),"设置删除无实际功能的皮肤示例区域")
                try check(settings!.table.numberOfRows == BuiltinContextCommand.allCases.count+state.commands.count,"设置列出所有内置与自定义右键命令")
                for (i,skin) in Skin.allCases.enumerated(){settings!.skinPopup.selectItem(at:i);settings!.skinChanged();await settle();try check(state.skin == skin,"皮肤切换");try capture("skin-"+skin.rawValue)}
                checks.append("设置中四套皮肤立即切换")
                settings?.showWindow(nil);await settle();try capture("settings",settings?.window?.contentView);settings?.close()
                // Inline document workflow is exercised in the same native window.
                let documentPane = panes[0]
                documentPane.modeControl.selectedSegment = 1; documentPane.modeChanged()
                documentPane.navigate(to: source); await settle()
                guard let documentColumn = documentPane.columnControllers.first,
                      let markdownRow = documentColumn.files.firstIndex(where: { $0.name == "健康计划.md" }) else { throw NSError(domain:"UISmoke",code:7,userInfo:[NSLocalizedDescriptionKey:"缺少文档样例"]) }
                let windowCount = NSApp.windows.filter { $0.isVisible }.count
                documentColumn.table.selectRowIndexes(IndexSet(integer:markdownRow),byExtendingSelection:false)
                for _ in 0..<50 { if documentPane.editor.previewReady { break }; try await Task.sleep(nanoseconds:100_000_000) }
                await settle()
                let editor = documentPane.editor
                try check(editor.document?.url == source.appendingPathComponent("健康计划.md") && editor.view.superview === documentPane.columnStack,"分栏选择文档后在最右侧显示编辑区")
                try check(NSApp.windows.filter{$0.isVisible}.count == windowCount,"预览文档不新建窗口")
                try check(documentColumn.view.frame.minX >= documentPane.columnsScroll.contentView.bounds.minX-1,"常规双屏宽度下完整保留当前目录列")
                let markdownPreview = try await editor.web.evaluateJavaScript("document.querySelector('iframe').srcdoc") as? String ?? ""
                try check(markdownPreview.contains("<h1>健康计划</h1>"),"离线 Markdown 预览实际渲染标题")
                editor.modes.selectedSegment=2;editor.changeDisplayMode();await settle()
                editor.text.setSelectedRange(NSRange(location:(editor.text.string as NSString).length,length:0));editor.text.insertText("\n新增记录：中文输入。",replacementRange:editor.text.selectedRange())
                try check(editor.hasUnsavedChanges,"编辑后标记未保存")
                documentPane.reloadDirectory();if let task=documentPane.columnRefreshTask{await task.value};await settle()
                try check(editor.hasUnsavedChanges && editor.text.string.contains("新增记录"),"目录刷新保留未保存文档和列路径")
                try check(editor.save(),"保存文档")
                try check(try String(contentsOf:source.appendingPathComponent("健康计划.md"),encoding:.utf8).contains("新增记录"),"保存写入真实样例文件")
                try capture("document-markdown-split")
                guard let textRow = documentColumn.files.firstIndex(where:{$0.name == "体检说明.txt"}) else { throw NSError(domain:"UISmoke",code:8) }
                editor.text.insertText("未保存",replacementRange:editor.text.selectedRange())
                editor.unsavedDecision = { .alertThirdButtonReturn }
                documentColumn.table.selectRowIndexes(IndexSet(integer:textRow),byExtendingSelection:false)
                try check(editor.hasUnsavedChanges && documentColumn.table.selectedRow == markdownRow && editor.kind == .markdown,"取消离开后保留编辑内容和原选中项")
                editor.unsavedDecision = { .alertSecondButtonReturn }
                documentColumn.table.selectRowIndexes(IndexSet(integer:textRow),byExtendingSelection:false)
                editor.unsavedDecision=nil
                try check(!editor.hasUnsavedChanges && editor.kind == .text,"选择不保存后切换 TXT")
                let jsonURL=try TextFileKind.json.create(in:source,name:"测试配置")
                documentPane.revealCreatedDocument(jsonURL);await settle();await settle()
                try check(editor.kind == .json && editor.modes.selectedSegment == 1,"新建 JSON 后定位文件并进入编辑")
                editor.text.string="{\"项目\":[1,true,null],\"版本\":2}";editor.text.didChangeText();editor.formatJSON()
                try check(editor.text.string.contains("\n") && editor.hasUnsavedChanges,"JSON 格式化并标记修改")
                try check(editor.save(),"保存 JSON");editor.modes.selectedSegment=0;editor.changeDisplayMode();editor.renderPreview();await settle()
                let jsonPreview=try await editor.web.evaluateJavaScript("document.querySelector('iframe').srcdoc") as? String ?? ""
                try check(jsonPreview.contains("<details") && jsonPreview.contains("项目"),"JSON 树形预览")
                await settle();try capture("document-json-tree")
                let geometry:[String:String] = ["editor":NSStringFromRect(editor.view.frame),"body":NSStringFromRect(editor.body.frame),"web":NSStringFromRect(editor.web.frame),"columnStack":NSStringFromRect(documentPane.columnStack.frame),"clip":NSStringFromRect(documentPane.columnsScroll.contentView.bounds),"controls":NSStringFromRect(editor.controls.convert(editor.controls.bounds,to:documentPane.contentHost)),"viewport":NSStringFromRect(documentPane.contentHost.bounds)]
                try JSONSerialization.data(withJSONObject:geometry,options:.prettyPrinted).write(to:output.appendingPathComponent("document-geometry.json"))
                let htmlURL=try TextFileKind.html.create(in:source,name:"页面")
                try Data("<h1>页面预览</h1><script>document.body.innerHTML='BAD'</script><img src='https://example.invalid/tracker' onerror='alert(1)'>".utf8).write(to:htmlURL)
                documentPane.revealCreatedDocument(htmlURL);await settle();editor.modes.selectedSegment=0;editor.changeDisplayMode();editor.renderPreview();await settle()
                let htmlPreview=try await editor.web.evaluateJavaScript("document.querySelector('iframe').srcdoc") as? String ?? ""
                try check(htmlPreview.contains("页面预览") && !htmlPreview.contains("<script") && !htmlPreview.contains("onerror") && htmlPreview.contains("default-src 'none'"),"HTML 预览净化脚本、事件和网络加载")
                let inlineMenu=NSMenu();documentPane.menuNeedsUpdate(inlineMenu)
                try check(inlineMenu.items.first(where:{$0.title == "新建文件"})?.submenu?.items.count == 4,"右键提供四种文档新建入口")
                state.commands=[CustomCommand(name:"仅 Markdown",script:"cat {path}",target:.extensions,fileExtensions:["md"]),CustomCommand(name:"仅 HTML",script:"cat {path}",target:.extensions,fileExtensions:["html"])]
                documentPane.menuNeedsUpdate(inlineMenu)
                try check(inlineMenu.items.contains(where:{$0.title == "仅 HTML"}) && !inlineMenu.items.contains(where:{$0.title == "仅 Markdown"}),"右键命令按文件扩展名过滤")
                try check(Array(inlineMenu.items.prefix(3).map(\.title)) == ["复制完整路径","复制目录路径","在终端打开"],"右键菜单顶部依次为完整路径、目录路径、终端")
                editor.view.layoutSubtreeIfNeeded()
                let tabs=editor.modes.convert(editor.modes.bounds,to:editor.controls)
                try check(abs(tabs.midX-editor.controls.bounds.midX)<1,"预览编辑分屏标签严格居中")
                try check(editor.saveButton.superview === editor.controls && editor.saveButton.frame.minX < tabs.minX,"保存按钮位于同一行最左侧")
                try check(editor.reloadButton.title.isEmpty && editor.reloadButton.image != nil,"重新载入只显示刷新图标")
                let yamlURL=source.appendingPathComponent("配置.yaml")
                try Data("name: Octo\nitems:\n  - 中文\n".utf8).write(to:yamlURL)
                documentPane.revealCreatedDocument(yamlURL);await settle();await settle()
                try check(editor.kind == .text && editor.modes.isHidden && editor.sourceScroll.superview === editor.body && editor.web.superview == nil,"YAML 直接编辑且不显示预览分屏标签")
                let imageURL=source.appendingPathComponent("图片样例.png")
                if let tiff=OctoBrand.logo?.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let png=bitmap.representation(using:.png,properties:[:]) {try png.write(to:imageURL)}
                else {throw NSError(domain:"UISmoke",code:9,userInfo:[NSLocalizedDescriptionKey:"无法生成图片测试样例"])}
                documentPane.navigate(to:source);await settle()
                guard let imageColumn=documentPane.columnControllers.first,let imageRow=imageColumn.files.firstIndex(where:{$0.url == imageURL}) else {throw NSError(domain:"UISmoke",code:10)}
                imageColumn.table.selectRowIndexes(IndexSet(integer:imageRow),byExtendingSelection:false)
                if let task=editor.imageTask {await task.value};await settle()
                try check(editor.imageURL == imageURL && editor.imageView.image != nil && editor.imageCanvas.superview === editor.body && editor.imageView.superview === editor.imageCanvas,"图片在分栏右侧原生解码预览")
                try check(editor.modes.segmentCount == 1 && editor.modes.label(forSegment:0) == "预览" && editor.saveButton.isHidden,"图片仅显示可用的预览操作")
                try capture("document-image-preview")
                let galleryDirectory=source.appendingPathComponent("图片总览测试")
                try fm.createDirectory(at:galleryDirectory,withIntermediateDirectories:true)
                for index in 0..<300 {try fm.copyItem(at:imageURL,to:galleryDirectory.appendingPathComponent(String(format:"图片-%03d.png",index)))}
                documentPane.navigate(to:galleryDirectory);await settle()
                guard let galleryColumn=documentPane.columnControllers.first,let firstImage=galleryColumn.files.first else{throw NSError(domain:"UISmoke",code:11)}
                galleryColumn.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
                if let task=editor.imageTask{await task.value};editor.galleryButton.performClick(nil)
                if let task=editor.gallery?.loadTask{await task.value};await settle()
                guard let gallery=editor.gallery else{throw NSError(domain:"UISmoke",code:12)}
                try check(editor.showingImageOverview && gallery.records.count == 300,"按钮显示同文件夹300张图片总览")
                let visible=gallery.collection.visibleItems().count
                try check(visible>0 && visible<50,"仅创建可见缩略图项而非解码整个文件夹：\(visible)/300")
                try capture("image-gallery-300")
                let chosen=gallery.records[3].url;gallery.collection.selectionIndexPaths=[IndexPath(item:3,section:0)]
                let enter=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!
                gallery.collection.keyDown(with:enter)
                if let task=editor.imageTask{await task.value};await settle()
                try check(!editor.showingImageOverview && editor.imageURL == chosen && editor.imageView.image != nil && documentPane.columnSelection == [chosen],"总览激活选中图片后返回单张预览并同步目录选中项")
                if let task=editor.imageNeighborTask{await task.value}
                let siblings=editor.imageNeighbors
                try check(siblings.count == 300 && editor.imageCanvas.previous.isEnabled && editor.imageCanvas.next.isEnabled,"图片预览提供同目录前后浏览")
                try check(window.firstResponder === editor.imageCanvas,"单张预览获得局部方向键焦点")
                editor.imageCanvas.previous.performClick(nil);if let task=editor.imageTask{await task.value}
                try check(editor.imageURL == siblings[2] && documentPane.columnSelection == [siblings[2]],"浮动左箭头切换上一张并同步文件选择")
                activePane=1;editor.imageCanvas.next.performClick(nil);if let task=editor.imageTask{await task.value}
                try check(editor.imageURL == siblings[3] && activePane == documentPane.index,"浮动右箭头切换下一张并激活对应操作屏")
                @MainActor func imageKey(_ key:UInt16)->NSEvent {NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:key)!}
                editor.imageCanvas.keyDown(with:imageKey(124));if let task=editor.imageTask{await task.value}
                try check(editor.imageURL == siblings[4],"键盘右方向键浏览下一张")
                editor.imageCanvas.keyDown(with:imageKey(123));if let task=editor.imageTask{await task.value}
                try check(editor.imageURL == siblings[3],"键盘左方向键浏览上一张")
                try check(editor.info.stringValue.contains("↑") && editor.info.stringValue.contains("←") && editor.info.stringValue.contains("→"),"图片预览明确显示三个方向快捷键提示")
                let imageBounds=editor.imageView.convert(editor.imageView.bounds,to:editor.imageCanvas)
                try check(editor.imageCanvas.previous.frame.maxX <= imageBounds.minX && editor.imageCanvas.next.frame.minX >= imageBounds.maxX,"左右图标位于图片外侧，不覆盖图片")
                try check(!editor.imageCanvas.previous.isBordered && editor.imageCanvas.previous.superview === editor.imageCanvas,"图片箭头无圆形背景")
                try capture("image-floating-navigation")
                let columnsBeforeOverview=documentPane.columnControllers.map(\.url)
                editor.imageCanvas.overview.performClick(nil);if let task=gallery.loadTask{await task.value}
                try check(editor.showingImageOverview && gallery.records.count == 300 && documentPane.columnControllers.map(\.url) == columnsBeforeOverview,"浮动向上箭头显示总览且保留分栏")
                gallery.collection.selectionIndexPaths=[IndexPath(item:0,section:0)];gallery.collection.keyDown(with:enter);if let task=editor.imageTask{await task.value};if let task=editor.imageNeighborTask{await task.value}
                try check(editor.imageURL == siblings[0] && !editor.imageCanvas.previous.isEnabled && editor.imageCanvas.next.isEnabled,"第一张禁用上一张，不越界循环")
                editor.imageCanvas.keyDown(with:imageKey(126));if let task=gallery.loadTask{await task.value}
                try check(editor.showingImageOverview && gallery.records.count == 300,"键盘向上键与总览按钮效果一致")
                gallery.collection.selectionIndexPaths=[IndexPath(item:299,section:0)];gallery.collection.keyDown(with:enter);if let task=editor.imageTask{await task.value};if let task=editor.imageNeighborTask{await task.value}
                try check(!editor.imageCanvas.next.isEnabled && editor.imageCanvas.previous.isEnabled,"最后一张禁用下一张")
                checks.append("图片浮动上左右按钮、局部方向键、快捷键文字、目录选择同步及首尾边界")
                let imageOnly=DocumentEditor(pane:panes[1]);_ = imageOnly.open(firstImage.url);if let task=imageOnly.imageTask{await task.value}
                try check(!imageOnly.previewStarted && imageOnly.imageView.image != nil,"仅看图片不启动文档WebKit")
                imageOnly.clear()
                let metrics:[String:Any]=["folderImages":300,"visibleThumbnailItems":visible,"singlePreviewMaxPixelSize":ImagePreviewDecoding.maxPixelSize,"note":"仅统计应用侧可见项和位图边长限制，不代表系统解码器临时内存或整机进程内存。"]
                try JSONSerialization.data(withJSONObject:metrics,options:.prettyPrinted).write(to:output.appendingPathComponent("image-gallery-metrics.json"))
                checks.append("300图同目录缩略图总览、可见项加载、激活返回单图、选择同步及图片模式无WebKit")

                let mounts=Set(documentPane.contentHost.constraints.filter { ($0.firstItem as? NSView) === documentPane.columnsScroll || ($0.secondItem as? NSView) === documentPane.columnsScroll }.map(ObjectIdentifier.init))
                documentPane.installMode()
                let nextMounts=Set(documentPane.contentHost.constraints.filter { ($0.firstItem as? NSView) === documentPane.columnsScroll || ($0.secondItem as? NSView) === documentPane.columnsScroll }.map(ObjectIdentifier.init))
                try check(!mounts.isEmpty && mounts == nextMounts,"导航保持文件区域挂载约束，不移除重建")
                try check(documentPane.spinner.superview?.frame.width == 12,"加载指示器使用固定占位避免导航图标抖动")
                checks.append("单行居中文档工具栏、图标刷新、纯文本直接编辑、图片内联预览、右键路径菜单顺序、文件区域稳定挂载")
                documentPane.columnSelection=[];documentPane.menuDirectory=family
                try check(documentPane.creationDirectory == family,"空白菜单使用被右键点击的目录而非上次导航位置")
                documentPane.menuDirectory=nil
                documentPane.modeControl.selectedSegment=0;documentPane.modeChanged();await settle()
                try check(editor.document == nil && editor.imageURL == nil && editor.view.superview == nil,"离开分栏视图移除文档区域")
                checks.append("分栏内 Markdown/HTML/TXT/JSON 预览编辑、新建定位、保存、未保存取消保护、目录刷新保留、JSON 格式化、HTML 隔离、右键文件类型筛选")
                settings!.selectSection(.commands);settings!.table.reloadData()
                let customKey=ContextMenuOrder.key(for:state.commands[0])
                let customRow=settings!.menuKeys.firstIndex(of:customKey)!
                let dragBoard=NSPasteboard.withUniqueName()
                guard let writer=settings!.tableView(settings!.table,pasteboardWriterForRow:customRow) else{throw NSError(domain:"UISmoke",code:13)}
                dragBoard.writeObjects([writer])
                let drop=MenuDropFixture(pasteboard:dragBoard,source:settings!.table,window:settings!.window)
                try check(settings!.tableView(settings!.table,validateDrop:drop,proposedRow:0,proposedDropOperation:.above) == .move,"原生表格识别命令拖放载荷")
                try check(settings!.tableView(settings!.table,acceptDrop:drop,row:0,dropOperation:.above),"原生拖放回调接受排序")
                dragBoard.releaseGlobally()
                try check(settings!.menuKeys.first == customKey,"设置拖动排序同时支持自定义命令")
                settings!.moveMenuEntry(BuiltinContextCommand.newFile.rawValue,before:0)
                let orderedMenu=NSMenu();documentPane.menuNeedsUpdate(orderedMenu)
                try check(orderedMenu.items.first?.title == "新建文件","内置右键命令按设置顺序出现")
                try store.save(state);try check(try store.load().contextMenuOrder == state.contextMenuOrder,"右键菜单顺序持久保存")
                try capture("settings-menu-order",settings!.window?.contentView)
                checks.append("皮肤无默认焦点环、全部内置与自定义命令可排序、上下拖动顺序映射菜单并持久化")
                preview([source.appendingPathComponent("体检说明.txt")]);await settle();try check(QLPreviewPanel.shared()?.isVisible == true,"快速预览窗口");QLPreviewPanel.shared()?.orderOut(nil);checks.append("原生 Quick Look 预览窗口")
                state.skin = .native;applyAppearance();try store.save(state);let saved=try store.load();try check(saved.panes[0].groups==state.panes[0].groups && saved.panes[0].sidebarWidth==212 && !saved.panes[0].sidebarCollapsed,"状态保存");checks.append("分组、侧栏宽度与收起状态保存和恢复")
                window.setContentSize(NSSize(width:1000,height:620));await settle();try capture("narrow-window");window.setContentSize(NSSize(width:1440,height:800));await settle();try check(paneSlots[0].frame.height>500,"窗口调整后分屏保持高度");try check(abs(paneSlots[0].frame.width+paneSlots[1].frame.width+1-window.contentView!.bounds.width)<2,"双屏宽度总和匹配窗口");
                for p in panes {try check(abs(p.view.frame.width-p.sidebarSplit.frame.width)<2 && abs(p.fileHost.frame.maxX-p.view.bounds.maxX)<2,"内部文件区匹配分屏：\(p.index) view=\(p.view.frame) split=\(p.sidebarSplit.frame) file=\(p.fileHost.frame)")};
                for p in panes{let mode=p.modeControl.convert(p.modeControl.bounds,to:p.toolbarView);try check(mode.maxX<p.toolbarView.bounds.width,"缩放恢复后浏览模式按钮保持可见：\(p.index) mode=\(mode) toolbar=\(p.toolbarView.bounds)")};try capture("native-final");try capture("titlebar",titleBrand)
                // Folder tag verification touches only the isolated smoke fixture.
                let tagPane=panes[0],tagFolder=source.appendingPathComponent("颜色标签测试")
                try fm.createDirectory(at:tagFolder,withIntermediateDirectories:true)
                tagPane.modeControl.selectedSegment=1;tagPane.modeChanged()
                tagPane.navigate(to:source);await tagPane.loadTask?.value;await settle()
                guard let tagColumn=tagPane.columnControllers.first,let tagRow=tagColumn.files.firstIndex(where:{$0.url.path == tagFolder.path}) else {throw NSError(domain:"UISmoke",code:20)}
                tagColumn.table.selectRowIndexes(IndexSet(integer:tagRow),byExtendingSelection:false);await settle()
                let tagOriginalColumns=tagPane.columnControllers.map{ObjectIdentifier($0)}
                let tagMenu=NSMenu();tagColumn.menuNeedsUpdate(tagMenu)
                guard let tagItem=tagMenu.items.first(where:{$0.identifier?.rawValue == "folderTags"}),let palette=tagItem.submenu?.items.first?.view as? FolderTagPalette else {throw NSError(domain:"UISmoke",code:21)}
                try check(palette.swatches.count == 7,"文件夹右键显示七色选择器")
                let tagActivePane=activePane
                palette.swatches[1].performClick(nil);await settle()
                try check(activePane == tagActivePane,"更新标签不改变键盘操作所在的屏幕")
                try check(state.colors(for:tagFolder) == [.orange],"右键色块保存 Octo 独立橙色标签")
                try check(state.colors(for:tagColumn.files[tagRow].url) == [.orange],"分栏标签立即刷新")
                try check(tagPane.columnControllers.map{ObjectIdentifier($0)} == tagOriginalColumns && tagColumn.table.selectedRow == tagRow,"标签更新保留分栏和选中项")
                @MainActor func dots(in view:NSView)->[FolderTagDots] { (view as? FolderTagDots).map{[$0]} ?? view.subviews.flatMap{dots(in:$0)} }
                let tagCell=tagColumn.table.view(atColumn:0,row:tagRow,makeIfNecessary:true)!
                try check(dots(in:tagCell).contains{$0.colors == [.orange]},"分栏文件夹行显示鲜艳色点")
                tagColumn.menuNeedsUpdate(tagMenu)
                let selectedPalette=tagMenu.items.first(where:{$0.identifier?.rawValue == "folderTags"})!.submenu!.items[0].view as! FolderTagPalette
                try check(selectedPalette.swatches[1].selectedState == .on,"已添加颜色显示勾选")
                selectedPalette.swatches[4].performClick(nil);await settle()
                try check(Set(state.colors(for:tagFolder)) == Set([.orange,.blue]),"多色标签叠加")
                tagColumn.menuNeedsUpdate(tagMenu)
                let removalPalette=tagMenu.items.first(where:{$0.identifier?.rawValue == "folderTags"})!.submenu!.items[0].view as! FolderTagPalette
                removalPalette.swatches[1].performClick(nil);await settle()
                try check(state.colors(for:tagFolder) == [.blue],"再次点击移除对应颜色并保留其他颜色")
                tagPane.applyFolderTag(.orange,enabled:true,urls:[source]);await settle()
                let taggedSidebar=tagPane.sidebar!
                let entryRow=(0..<taggedSidebar.outline.numberOfRows).first{(taggedSidebar.outline.item(atRow:$0) as? SidebarItem)?.entry?.url.path == source.path}!
                let sidebarCell=taggedSidebar.outline.view(atColumn:0,row:entryRow,makeIfNecessary:true)!
                try check(dots(in:sidebarCell).contains{$0.colors == [.orange]},"侧栏文件夹同步 Octo 标签色点")
                taggedSidebar.outline.selectRowIndexes(IndexSet(integer:entryRow),byExtendingSelection:false)
                let sidebarMenu=NSMenu();taggedSidebar.menuNeedsUpdate(sidebarMenu)
                try check(sidebarMenu.items.contains{$0.title == "颜色标签"},"侧栏文件夹右键提供颜色标签")
                tagPane.modeControl.selectedSegment=0;tagPane.modeChanged();tagPane.navigate(to:source);await settle()
                guard let taggedNode=tagPane.nodes.first(where:{$0.record.url.path == tagFolder.path}) else {throw NSError(domain:"UISmoke",code:22)}
                let listCell=tagPane.outlineView(tagPane.list,viewFor:tagPane.list.tableColumns.first,item:taggedNode)!
                try check(dots(in:listCell).contains{$0.colors == [.blue]},"列表显示文件夹标签")
                tagPane.list.expandItem(taggedNode);await settle()
                let mixedPalette=FolderTagPalette(urls:[tagFolder,family],workspace:state,activate:{_,_ in})
                try check(mixedPalette.swatches[4].selectedState == .mixed,"多选文件夹显示部分已添加颜色")
                let tile=FileTile();tile.configure(try FileRecord(url:tagFolder),palette:tagPane.palette,colors:state.colors(for:tagFolder))
                try check(tile.tagDots.colors == [.blue],"图标视图显示标签")
                tagPane.list.selectRowIndexes(IndexSet(integer:tagPane.list.row(forItem:taggedNode)),byExtendingSelection:false)
                let finalTagMenu=NSMenu();tagPane.menuNeedsUpdate(finalTagMenu)
                let clear=finalTagMenu.items.first(where:{$0.identifier?.rawValue == "folderTags"})!.submenu!.items.last as! ClearFolderTagsMenuItem
                clear.activate();await settle()
                try check(tagPane.list.isItemExpanded(taggedNode),"移除标签保留列表已展开的文件夹")
                try check(state.colors(for:tagFolder).isEmpty,"移除全部内置标签同步清除文件夹颜色")
                tagPane.applyFolderTag(.orange,enabled:true,urls:[tagFolder]);await settle()
                try capture("folder-tags")
                // Put the real menu palette in a fixture panel for a reliable visual capture.
                let palettePanel=NSPanel(contentRect:NSRect(x:0,y:0,width:258,height:72),styleMask:[.titled],backing:.buffered,defer:false)
                palettePanel.isReleasedWhenClosed=false;palettePanel.contentView=FolderTagPalette(urls:[tagFolder],workspace:state,activate:{_,_ in})
                palettePanel.contentView?.wantsLayer=true;palettePanel.contentView?.layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor
                palettePanel.orderFront(nil);await settle();try capture("folder-tag-palette",palettePanel.contentView);palettePanel.orderOut(nil)
                let nativeTags=try URL(fileURLWithPath:tagFolder.path).resourceValues(forKeys:[.tagNamesKey]).tagNames ?? []
                try check(nativeTags.isEmpty,"Octo 标签不写入访达")
                try store.save(state);try check(try store.load().colors(for:tagFolder) == [.orange],"独立标签保存并恢复")
                checks.append("文件夹七色独立标签：右键添加叠加及移除、选中反馈、侧栏列表分栏图标同步、分栏与选中项保持")
                let pathBar=tagPane.pathControl
                try check(pathBar.newFolderButton?.action == #selector(PaneController.createCurrentFolder) && pathBar.newFileButton?.action == #selector(PaneController.showCurrentFileTypes(_:)),"路径栏提供新建文件夹和新建文件图标")
                try check(pathBar.creationSeparator.frame.minX > pathBar.terminalButton!.frame.minX && pathBar.newFolderButton!.frame.minX > pathBar.creationSeparator.frame.minX,"路径栏新建操作位于终端右侧并以竖线分隔")
                let typesMenu=tagPane.documentTypesMenu(in:source)
                try check(typesMenu.items.count == TextFileKind.allCases.count && typesMenu.items.allSatisfy{($0.representedObject as? [String:String])?["directory"] == source.path},"路径栏下拉列出全部文件类型且固定目标为当前目录")
                let crowded=output.appendingPathComponent("大量文件空白区")
                try fm.createDirectory(at:crowded,withIntermediateDirectories:true)
                for index in 0..<80 {try Data("sample".utf8).write(to:crowded.appendingPathComponent(String(format:"file-%03d.txt",index)))}
                tagPane.modeControl.selectedSegment=1;tagPane.modeChanged();tagPane.navigate(to:crowded);await tagPane.loadTask?.value;await settle()
                let crowdedColumn=tagPane.columnControllers[0],crowdedTable=tagPane.columnControllers[0].table
                let rowsBottom=crowdedTable.rect(ofRow:crowdedTable.numberOfRows-1).maxY
                try check(crowdedTable.bounds.height-rowsBottom >= 70,"长目录分栏在最后一项下保留可滚动空白区：bounds=\(crowdedTable.bounds) frame=\(crowdedTable.frame) rowsBottom=\(rowsBottom)")
                crowdedColumn.scroll.contentView.scroll(to:NSPoint(x:0,y:crowdedTable.bounds.height-crowdedColumn.scroll.contentView.bounds.height));await settle()
                let blank=NSPoint(x:30,y:rowsBottom+30)
                try check(crowdedTable.row(at:blank) == -1,"空白区不对应文件行")
                crowdedTable.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);await settle()
                let event=NSEvent.mouseEvent(with:.rightMouseDown,location:crowdedTable.convert(blank,to:nil),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
                _ = crowdedTable.menu(for:event);let blankMenu=NSMenu();crowdedColumn.menuNeedsUpdate(blankMenu)
                try check(tagPane.selectedURLs.isEmpty && tagPane.contextualDirectory.path == crowded.path && blankMenu.items.contains{$0.title == "新建文件"},"底部空白右键使用目录菜单，不选中文件")
                try capture("directory-bottom-blank")
                tagPane.modeControl.selectedSegment=0;tagPane.modeChanged();tagPane.navigate(to:crowded);await tagPane.loadTask?.value;await settle()
                let listBottom=tagPane.list.rect(ofRow:tagPane.list.numberOfRows-1).maxY
                try check(tagPane.list.bounds.height-listBottom >= 70,"长目录列表同样保留底部空白")
                checks.append("目录列表和分栏底部可滚动空白右键区、路径栏竖线和新建图标、文件类型下拉定位、图片箭头外置无圆圈")
                // This verification exercises real menu/AppKit state, and updates only an isolated app copy.
                let menuPane=panes[0]
                menuPane.navigate(to:source);await menuPane.loadTask?.value;await settle()
                if let row=menuPane.nodes.firstIndex(where:{$0.record.url.lastPathComponent == "体检说明.txt"}) {menuPane.list.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)}
                let groupedMenu=NSMenu();menuPane.menuNeedsUpdate(groupedMenu)
                try check(groupedMenu.items.filter(\.isSeparatorItem).count>=4 && groupedMenu.items.first?.isSeparatorItem == false && groupedMenu.items.last?.isSeparatorItem == false,"右键按用途分组且无首尾分隔线")
                guard let openWith=groupedMenu.items.first(where:{$0.identifier?.rawValue == "openWith"})?.submenu else {throw NSError(domain:"UISmoke",code:31)}
                try check(openWith.items.last?.title == "选择其他应用…" && openWith.items.contains{$0 is FileApplicationItem},"文件提供系统打开方式和选择其他应用")
                try check(openWith.items.compactMap{$0 as? FileApplicationItem}.allSatisfy{$0.files.map(\.path) == menuPane.selectedURLs.map(\.path)},"打开方式保留被右键点击的文件快照")
                let sidebarEntry=menuPane.sidebar.items.flatMap(\.children).first!
                let selectedSidebarRow=menuPane.sidebar.outline.row(forItem:sidebarEntry)
                menuPane.sidebar.outline.selectRowIndexes(IndexSet(integer:selectedSidebarRow),byExtendingSelection:false);await settle()
                let iconSidebarCell=menuPane.sidebar.outline.view(atColumn:0,row:selectedSidebarRow,makeIfNecessary:true) as! NSTableCellView
                try check(iconSidebarCell.imageView is StableFolderImageView && iconSidebarCell.imageView?.allowsVibrancy == false && iconSidebarCell.imageView?.image?.isTemplate == false,"选中文件夹图标不被系统改色或冲淡")
                if let row=menuPane.sidebar.outline.rowView(atRow:selectedSidebarRow,makeIfNecessary:true) {try check(row.interiorBackgroundStyle == .normal,"选中行保持图标原始对比度")}
                if let uncolored=menuPane.sidebar.items.flatMap(\.children).first(where:{state.colors(for:$0.entry!.url).isEmpty}) {
                    let row=menuPane.sidebar.outline.row(forItem:uncolored)
                    menuPane.sidebar.outline.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false);await settle()
                    let cell=menuPane.sidebar.outline.view(atColumn:0,row:row,makeIfNecessary:true) as! NSTableCellView
                    try check(cell.imageView is StableFolderImageView && cell.imageView?.image?.isTemplate == false,"未设置颜色的文件夹选中后也保留图标颜色")
                    try capture("sidebar-uncolored-selected")
                    menuPane.sidebar.outline.selectRowIndexes(IndexSet(integer:selectedSidebarRow),byExtendingSelection:false);await settle()
                }
                try check(menuPane.sidebar.material.effect.material == .sidebar && menuPane.headerMaterial.effect.material == .headerView,"侧栏与导航使用原生系统材质")
                try check(menuPane.sidebar.material.effect.isHidden == NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,"毛玻璃遵守降低透明度设置")
                try capture("glass-workspace")
                manageContextCommands()
                try check(settings!.selectedSection == .commands,"管理右键命令直接进入对应设置分类")
                try check(settings!.sectionButtons.count == 3,"设置按外观、右键菜单、关于与更新分类")
                for section in SettingsController.Section.allCases {
                    settings!.selectSection(section);await settle();try check(settings!.pages[section]?.superview === settings!.pageHost,"设置侧栏切换内容")
                    try check(abs(settings!.pageHost.frame.maxX+26-settings!.window!.contentView!.bounds.width+176)<2,"设置右侧内容占满可用宽度")
                    try capture("settings-"+String(describing:section),settings!.window?.contentView)
                }
                let updater=settings!.updater
                updater.checkRelease={throw UpdateError.invalid("测试网络不可用")};updater.checkForUpdates();await updater.task?.value
                try check(updater.status.stringValue.contains("检查失败") && updater.checkButton.isEnabled,"检查失败保留重试入口")
                updater.checkRelease={AppRelease(version:"99.0.0",build:999,minimumSystemVersion:"14.0",architecture:"arm64",downloadURL:URL(string:"https://octo-dl.xiezhaoye.site/Octo-99.0.0-macos-arm64.zip")!,sha256:String(repeating:"0",count:64),bytes:1,notes:["测试更新内容"])}
                updater.checkForUpdates();await updater.task?.value
                try check(!updater.installButton.isHidden && updater.status.stringValue.contains("99.0.0") && updater.notes.stringValue.contains("测试更新内容"),"新版本显示内容与下载入口")
                updater.checkRelease=nil;updater.checkForUpdates();await updater.task?.value
                try check(updater.status.stringValue.contains("最新版本") && updater.release == nil,"真实 HTTPS 更新服务返回当前版本")
                try capture("settings-updates-online",settings!.window?.contentView);settings!.close()
                let release=try await AppUpdateService.shared.check()
                let prepared=try await AppUpdateService.shared.prepare(release,progress:{_ in})
                let installedRoot=output.appendingPathComponent("更新安装隔离验证"),installed=installedRoot.appendingPathComponent("Octo.app")
                try fm.createDirectory(at:installedRoot,withIntermediateDirectories:true)
                let oldBinary=try Data(contentsOf:Bundle.main.executableURL!),newBinary=try Data(contentsOf:prepared.app.appendingPathComponent("Contents/MacOS/DualPane"))
                let currentBundle=Bundle.main.bundleURL
                try await Task.detached {
                    try AppUpdateInstaller.run("/usr/bin/ditto",[currentBundle.path,installed.path])
                    let helper=try AppUpdateInstaller.launch(prepared:prepared,current:installed,waitingFor:0,reopen:false)
                    helper.waitUntilExit()
                    guard helper.terminationStatus == 0 else{throw UpdateError.invalid("隔离更新助手失败")}
                }.value
                try check(try Data(contentsOf:installed.appendingPathComponent("Contents/MacOS/DualPane")) == newBinary,"真实安装包通过校验并替换隔离应用")
                let backups=try fm.contentsOfDirectory(at:installedRoot,includingPropertiesForKeys:nil).filter{$0.lastPathComponent.hasPrefix(".Octo-backup-")}
                try check(backups.count == 1 && Data(contentsOf:backups[0].appendingPathComponent("Contents/MacOS/DualPane")) == oldBinary,"安装保留上一应用备份")
                let failureWork=output.appendingPathComponent("更新失败隔离验证");try fm.createDirectory(at:failureWork,withIntermediateDirectories:true)
                let failureScript=failureWork.appendingPathComponent("install.sh");try Data(AppUpdateInstaller.helper.utf8).write(to:failureScript)
                let failedProcess=Process();failedProcess.executableURL=URL(fileURLWithPath:"/bin/sh");failedProcess.arguments=[failureScript.path,"0",installed.path,failureWork.appendingPathComponent("missing.app").path,failureWork.appendingPathComponent("backup.app").path,failureWork.path,"no"]
                try failedProcess.run();failedProcess.waitUntilExit()
                try check(failedProcess.terminationStatus != 0 && Data(contentsOf:installed.appendingPathComponent("Contents/MacOS/DualPane")) == newBinary,"缺失更新包不会移动或删除旧应用")
                var installations=0
                let dirtyEditor=panes[0].editor
                try check(dirtyEditor.open(source.appendingPathComponent("体检说明.txt")),"准备更新未保存保护测试")
                dirtyEditor.text.string += "\n未保存测试";dirtyEditor.textDidChange(Notification(name:NSText.didChangeNotification));dirtyEditor.unsavedDecision={.alertThirdButtonReturn}
                updateInstallAction={installations+=1}
                try check(applicationShouldTerminate(NSApp) == .terminateCancel && installations == 0 && updateInstallAction == nil,"未保存编辑取消退出时不启动安装助手")
                dirtyEditor.clear();dirtyEditor.unsavedDecision=nil
                updateInstallAction={installations+=1}
                try check(applicationShouldTerminate(NSApp) == .terminateNow && installations == 1,"保存及退出检查通过后才允许启动安装")
                checks.append("毛玻璃侧栏与导航、设置三分类、分组菜单和打开方式、图标选中稳定、真实在线版本检查与下载校验、隔离替换及备份、失败保留原应用、未保存取消保护")
                let report:[String:Any]=["passed":true,"checks":checks,"windowSize":[window.frame.width,window.frame.height],"note":"原生控件程序化验收；未执行用户文件操作，未模拟实体鼠标拖拽。"]
                try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("ui-verification.json"));print("UI_SMOKE_PASS::"+output.path);succeeded=true
            } catch { print("UI_SMOKE_FAIL::"+error.localizedDescription);try? Data(error.localizedDescription.utf8).write(to:output.appendingPathComponent("failure.txt")) }
            if succeeded{NSApp.terminate(nil)}else{exit(1)}
        }
    }
}
