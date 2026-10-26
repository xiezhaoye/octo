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
                try check(paneDivider.frame.width==4,"双屏具有明显分界")
                checks.append("名称、修改日期、大小双向排序，移除搜索和标题栏分栏按钮")
                let fileMenu=NSMenu();panes[0].menuNeedsUpdate(fileMenu);try check(fileMenu.items.contains(where:{$0.title=="展开所有文件夹"}) && fileMenu.items.contains(where:{$0.title=="收拢所有文件夹"}),"右键保留展开与收拢")
                panes[0].expandAll();await settle();try check(panes[0].list.numberOfRows>panes[0].records.count,"全部展开");panes[0].collapseAll();checks.append("右键保留列表全部展开和收拢")
                panes[0].toggleHidden();await settle();try check(panes[0].records.contains(where:{$0.hidden}),"显示隐藏项目");panes[0].toggleHidden();await settle();checks.append("显示隐藏文件切换")
                let entry=state.panes[0].groups[0].entries[0];try state.transferEntry(from:0,entryID:entry.id,to:1,groupID:state.panes[1].groups[0].id,copy:true);try check(fm.fileExists(atPath:source.path),"入口拖动不得改磁盘");panes.forEach{$0.reloadSidebar()};checks.append("Option 入口复制保持磁盘原位")
                settings=SettingsController(app:self)
                for (i,skin) in Skin.allCases.enumerated(){settings!.skinPopup.selectItem(at:i);settings!.skinChanged();await settle();try check(state.skin == skin,"皮肤切换");try capture("skin-"+skin.rawValue)}
                checks.append("设置中四套皮肤立即切换")
                settings?.showWindow(nil);await settle();try capture("settings",settings?.window?.contentView);settings?.close()
                preview([source.appendingPathComponent("体检说明.txt")]);await settle();try check(QLPreviewPanel.shared()?.isVisible == true,"快速预览窗口");QLPreviewPanel.shared()?.orderOut(nil);checks.append("原生 Quick Look 预览窗口")
                state.skin = .native;applyAppearance();try store.save(state);let saved=try store.load();try check(saved.panes[0].groups==state.panes[0].groups && saved.panes[0].sidebarWidth==212 && !saved.panes[0].sidebarCollapsed,"状态保存");checks.append("分组、侧栏宽度与收起状态保存和恢复")
                window.setContentSize(NSSize(width:1000,height:620));await settle();try capture("narrow-window");window.setContentSize(NSSize(width:1440,height:800));await settle();try check(paneSlots[0].frame.height>500,"窗口调整后分屏保持高度");try check(abs(paneSlots[0].frame.width+paneSlots[1].frame.width+4-window.contentView!.bounds.width)<2,"双屏宽度总和匹配窗口");
                for p in panes {try check(abs(p.view.frame.width-p.sidebarSplit.frame.width)<2 && abs(p.fileHost.frame.maxX-p.view.bounds.maxX)<2,"内部文件区匹配分屏：\(p.index) view=\(p.view.frame) split=\(p.sidebarSplit.frame) file=\(p.fileHost.frame)")};
                for p in panes{let mode=p.modeControl.convert(p.modeControl.bounds,to:p.toolbarView);try check(mode.maxX<p.toolbarView.bounds.width,"缩放恢复后浏览模式按钮保持可见：\(p.index) mode=\(mode) toolbar=\(p.toolbarView.bounds)")};try capture("native-final");try capture("titlebar",titleBrand)
                let report:[String:Any]=["passed":true,"checks":checks,"windowSize":[window.frame.width,window.frame.height],"note":"原生控件程序化验收；未执行用户文件操作，未模拟实体鼠标拖拽。"]
                try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("ui-verification.json"));print("UI_SMOKE_PASS::"+output.path);succeeded=true
            } catch { print("UI_SMOKE_FAIL::"+error.localizedDescription);try? Data(error.localizedDescription.utf8).write(to:output.appendingPathComponent("failure.txt")) }
            if succeeded{NSApp.terminate(nil)}else{exit(1)}
        }
    }
}
