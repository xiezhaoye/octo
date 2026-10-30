import AppKit
import FileManagerCore

extension FolderTagColor {
    var displayColor: NSColor {
        let rgb: UInt32
        switch self {
        case .red: rgb=0xFF453A; case .orange: rgb=0xFF9F0A; case .yellow: rgb=0xFFD60A
        case .green: rgb=0x30D158; case .blue: rgb=0x0A84FF; case .purple: rgb=0xBF5AF2; case .gray: rgb=0x8E8E93
        }
        return NSColor(srgbRed:CGFloat((rgb>>16)&255)/255,green:CGFloat((rgb>>8)&255)/255,blue:CGFloat(rgb&255)/255,alpha:1)
    }
}

@MainActor func taggedFolderIcon(_ record: FileRecord, colors:[FolderTagColor]) -> NSImage {
    guard record.browsable,let color=colors.first,
          let image=NSImage(systemSymbolName:"folder.fill",accessibilityDescription:"\(color.title)文件夹") else {
        return NSWorkspace.shared.icon(forFile:record.url.path)
    }
    return image.withSymbolConfiguration(.init(paletteColors:[color.displayColor])) ?? image
}

@MainActor final class FolderTagDots: NSView {
    private(set) var colors: [FolderTagColor] = []
    init(_ colors:[FolderTagColor] = []) { super.init(frame:.zero);configure(colors) }
    required init?(coder:NSCoder) { fatalError() }
    func configure(_ colors:[FolderTagColor]) {
        self.colors=colors;isHidden=colors.isEmpty;toolTip=colors.map(\.title).joined(separator:"、")
        setAccessibilityElement(!colors.isEmpty);setAccessibilityLabel("颜色标签："+(toolTip ?? ""))
        invalidateIntrinsicContentSize();needsDisplay=true
    }
    override var intrinsicContentSize:NSSize { NSSize(width:colors.isEmpty ? 0 : CGFloat(colors.count*12),height:14) }
    override func draw(_ dirtyRect:NSRect) {
        for (index,color) in colors.enumerated() {
            let circle=NSBezierPath(ovalIn:NSRect(x:CGFloat(index*12)+1,y:(bounds.height-9)/2,width:9,height:9))
            color.displayColor.setFill();circle.fill()
        }
    }
}

@MainActor final class FolderTagSwatch: NSButton {
    let color:FolderTagColor
    let selectedState:NSControl.StateValue
    var invoke:(()->Void)?
    var hover:((Bool)->Void)?
    private var hovered=false
    init(color:FolderTagColor,state:NSControl.StateValue) {
        self.color=color;selectedState=state;super.init(frame:NSRect(x:0,y:0,width:34,height:36))
        isBordered=false;title="";target=self;action=#selector(activate)
        toolTip=(state == .on ? "移除" : "添加")+"“\(color.title)”"
        setAccessibilityLabel(toolTip!);setAccessibilityValue(state.rawValue)
    }
    required init?(coder:NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect:bounds,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil))
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event:NSEvent) { hovered=true;hover?(true);needsDisplay=true }
    override func mouseExited(with event:NSEvent) { hovered=false;hover?(false);needsDisplay=true }
    @objc func activate() { invoke?() }
    override func draw(_ dirtyRect:NSRect) {
        let rect=NSRect(x:5,y:6,width:24,height:24)
        color.displayColor.setFill();let path=NSBezierPath(ovalIn:rect);path.fill()
        let mark=selectedState == .on ? "✓" : selectedState == .mixed ? "−" : hovered ? "+":""
        let ink:NSColor = color == .yellow || color == .green ? .black : .white
        let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:17,weight:.semibold),.foregroundColor:ink]
        let size=(mark as NSString).size(withAttributes:attributes)
        (mark as NSString).draw(at:NSPoint(x:rect.midX-size.width/2,y:rect.midY-size.height/2),withAttributes:attributes)
    }
}

@MainActor final class FolderTagPalette:NSView {
    let hint=label("点击添加或移除颜色标签",size:12)
    let swatches:[FolderTagSwatch]
    init(urls:[URL],workspace:Workspace,activate:@escaping (FolderTagColor?,Bool)->Void) {
        let tags=urls.map{workspace.colors(for:$0)}
        swatches=FolderTagColor.allCases.map { color in
            let count=tags.filter{ $0.contains(color) }.count
            return FolderTagSwatch(color:color,state:count == urls.count ? .on:count == 0 ? .off:.mixed)
        }
        super.init(frame:NSRect(x:0,y:0,width:258,height:72))
        hint.alignment = .center;hint.textColor = .secondaryLabelColor
        hint.frame=NSRect(x:8,y:8,width:242,height:20);addSubview(hint)
        for (index,button) in swatches.enumerated() {
            button.frame.origin=NSPoint(x:10+CGFloat(index*34),y:30);addSubview(button)
            button.hover={ [weak self,weak button] inside in self?.hint.stringValue=inside ? button?.toolTip ?? "" : "点击添加或移除颜色标签" }
            button.invoke={ [weak self,weak button] in guard let button else {return};self?.enclosingMenuItem?.menu?.cancelTracking();activate(button.color,button.selectedState != .on) }
        }
    }
    required init?(coder:NSCoder) { fatalError() }
}

@MainActor final class ClearFolderTagsMenuItem:NSMenuItem {
    var invoke:(()->Void)?
    init(action:@escaping ()->Void) {super.init(title:"移除内置颜色标签",action:nil,keyEquivalent:"");invoke=action;target=self;self.action=#selector(activate)}
    required init(coder:NSCoder) {fatalError()}
    @objc func activate() {invoke?()}
}

@MainActor func folderTagMenu(urls:[URL],workspace:Workspace,activate:@escaping (FolderTagColor?,Bool)->Void) -> NSMenuItem? {
    guard !urls.isEmpty,urls.allSatisfy({(try? FileRecord(url:$0).browsable) == true}) else {return nil}
    let item=NSMenuItem(title:"颜色标签",action:nil,keyEquivalent:"")
    let menu=NSMenu(title:"颜色标签");menu.autoenablesItems=false
    let palette=NSMenuItem();palette.view=FolderTagPalette(urls:urls,workspace:workspace,activate:activate);menu.addItem(palette)
    menu.addItem(.separator());let clear=ClearFolderTagsMenuItem {activate(nil,false)}
    clear.isEnabled=urls.contains{!workspace.colors(for:$0).isEmpty}
    menu.addItem(clear);item.submenu=menu;return item
}

@MainActor extension PaneController {
    func applyFolderTag(_ color:FolderTagColor?,enabled:Bool,urls:[URL]) {
        guard app.update({state in
            for url in urls {state.setFolderColor(color,enabled:enabled,at:url)}
        },refreshSidebar:false) else {return}
        let activePane=app.activePane
        for pane in app.panes {pane.refreshFolderTags(urls)}
        app.activePane=activePane
    }
    func refreshFolderTags(_ urls:[URL]) {
        guard isViewLoaded else {return}
        let selection=list.selectedRowIndexes;list.reloadData();list.selectRowIndexes(selection,byExtendingSelection:false)
        let icons=collection.selectionIndexPaths;collection.reloadData();collection.selectionIndexPaths=icons
        for column in columnControllers {
            let selection=column.table.selectedRowIndexes;column.restoringSelection=true
            column.table.reloadData();column.table.selectRowIndexes(selection,byExtendingSelection:false)
            column.restoringSelection=false
        }
        let sidebarSelection=sidebar.outline.selectedRowIndexes
        sidebar.reloading=true;sidebar.outline.reloadData();sidebar.outline.selectRowIndexes(sidebarSelection,byExtendingSelection:false);sidebar.reloading=false
    }
}
