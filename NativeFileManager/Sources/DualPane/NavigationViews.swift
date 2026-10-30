import AppKit
import QuartzCore

@MainActor final class BreadcrumbBar: NSView {
    let stack = NSStackView()
    var onNavigate: ((URL) -> Void)?
    var copyButton: NSButton?
    var terminalButton: NSButton?
    var newFolderButton: NSButton?
    var newFileButton: NSButton?
    let creationSeparator = NSBox()
    private(set) var currentButton: NSButton?
    private var urls: [URL] = []
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stack.orientation = .horizontal; stack.alignment = .centerY; stack.spacing = 3
        pin(stack, in: self)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.init(200), for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }
    func setActions(copy:NSButton,terminal:NSButton,newFolder:NSButton,newFile:NSButton){
        copyButton=copy;terminalButton=terminal;newFolderButton=newFolder;newFileButton=newFile
        creationSeparator.boxType = .separator
        creationSeparator.widthAnchor.constraint(equalToConstant:1).isActive=true
        creationSeparator.heightAnchor.constraint(equalToConstant:17).isActive=true
    }
    func show(_ location: URL, palette: Palette) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        currentButton=nil
        var cursor = location; urls = []
        for _ in 0..<3 { urls.insert(cursor, at: 0); let parent = cursor.deletingLastPathComponent(); if parent == cursor { break }; cursor = parent }
        for (index, url) in urls.enumerated() {
            if index > 0 { let arrow = label("›", size: 13); arrow.textColor = palette.secondary; stack.addArrangedSubview(arrow) }
            let current = index == urls.count-1
            let name = url.lastPathComponent.isEmpty ? "磁盘" : url.lastPathComponent
            let button = NSButton(title: name, target: self, action: #selector(chosen(_:)))
            button.tag = index; button.isBordered = false; button.bezelStyle = .inline
            button.font = .systemFont(ofSize: 12, weight: current ? .semibold : .regular)
            button.attributedTitle = NSAttributedString(string: name, attributes: [.font:button.font!,.foregroundColor: current ? palette.text : palette.secondary])
            button.cell?.lineBreakMode = .byTruncatingMiddle; button.toolTip = url.path
            button.setContentCompressionResistancePriority(current ? .init(650) : .init(220), for: .horizontal)
            button.setAccessibilityLabel("前往 " + name); stack.addArrangedSubview(button)
            if current{currentButton=button}
        }
        if let copyButton{stack.addArrangedSubview(copyButton)}
        if let terminalButton{stack.addArrangedSubview(terminalButton)}
        if let newFolderButton,let newFileButton {
            stack.addArrangedSubview(creationSeparator);stack.setCustomSpacing(8,after:terminalButton ?? creationSeparator)
            stack.addArrangedSubview(newFolderButton);stack.addArrangedSubview(newFileButton)
        }
        let space = spacer(); stack.addArrangedSubview(space); toolTip = location.path
    }
    @objc private func chosen(_ sender: NSButton) { if urls.indices.contains(sender.tag) { onNavigate?(urls[sender.tag]) } }
}

@MainActor final class SidebarRail: NSButton {
    var palette = Palette.forSkin(.native) { didSet { updateColor(hover: false) } }
    private var tracking: NSTrackingArea?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect); title = ""; image = symbol("chevron.right"); isBordered = false; wantsLayer = true
        toolTip = "展开分组栏"; setAccessibilityLabel("展开分组栏")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited,.activeInActiveApp,.inVisibleRect], owner: self, userInfo: nil); addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { updateColor(hover: true) }
    override func mouseExited(with event: NSEvent) { updateColor(hover: false) }
    private func updateColor(hover: Bool) {
        guard let layer else { return }
        let color = (hover ? palette.selection : palette.sidebar).cgColor
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let old = layer.backgroundColor {
            let animation = CABasicAnimation(keyPath: "backgroundColor"); animation.fromValue = old; animation.toValue = color; animation.duration = 0.14
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut); layer.add(animation, forKey: "hover")
        }
        layer.backgroundColor = color; contentTintColor = hover ? palette.accent : palette.secondary
    }
}

@MainActor final class SidebarSplitView: NSSplitView, NSSplitViewDelegate {
    weak var owner: PaneController?
    var desiredWidth: CGFloat = 178
    var sidebarCollapsed = false
    var applying = false
    private var userDragging = false
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect); isVertical = true; dividerStyle = .thin; delegate = self
    }
    required init?(coder: NSCoder) { fatalError() }
    override var dividerThickness:CGFloat{sidebarCollapsed ? 0:super.dividerThickness}
    override func drawDivider(in rect:NSRect){if !sidebarCollapsed{super.drawDivider(in:rect)}}
    override func resizeSubviews(withOldSize oldSize: NSSize) { if userDragging, !sidebarCollapsed, let width = subviews.first?.frame.width {desiredWidth=width};arrange() }
    override func mouseDown(with event:NSEvent){userDragging=true;super.mouseDown(with:event);userDragging=false;if !sidebarCollapsed,let width=subviews.first?.frame.width{desiredWidth=width;owner?.rememberSidebarWidth(width)}}
    func arrange() {
        guard subviews.count == 2 else { return }; applying = true
        if bounds.width<=0 || bounds.height<=0 {subviews.forEach{$0.frame = .zero};applying=false;return}
        let width = sidebarCollapsed ? 24 : min(max(144, desiredWidth), max(144, bounds.width-320))
        subviews[0].frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        subviews[1].frame = NSRect(x: width+dividerThickness, y: 0, width: max(0,bounds.width-width-dividerThickness), height: bounds.height)
        applying = false
    }
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat { sidebarCollapsed ? 24 : 144 }
    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat { sidebarCollapsed ? 24 : max(144,min(480,bounds.width-320)) }
    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool { view !== subviews.first }
    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !applying, !sidebarCollapsed, userDragging, let width = subviews.first?.frame.width else { return }
        desiredWidth = width; owner?.rememberSidebarWidth(width)
    }
}

@MainActor final class GroupHeaderRow: NSTableRowView {
    var color = NSColor.controlAccentColor
    override func drawBackground(in dirtyRect: NSRect) { color.setFill(); NSBezierPath(rect:bounds).fill() }
    override func drawSelection(in dirtyRect: NSRect) { drawBackground(in: dirtyRect) }
    override var interiorBackgroundStyle:NSView.BackgroundStyle{.normal}
    override var isSelected:Bool{get{false}set{}}
}

@MainActor final class GroupHeaderContent: NSView {
    let name: NSTextField
    let plus = NSButton()
    weak var outline: NSOutlineView?
    init(name:String,groupID:UUID,outline:NSOutlineView,palette:Palette,target:AnyObject,action:Selector){
        self.name=label(name,size:14,weight:.semibold);self.outline=outline;super.init(frame:.zero)
        self.name.textColor = palette.text;self.name.alignment = .left;self.name.toolTip=name;self.name.identifier = .init("group-title")
        plus.image=symbol("plus");(plus.cell as? NSButtonCell)?.highlightsBy=[];(plus.cell as? NSButtonCell)?.showsStateBy=[];plus.isBordered=false;plus.contentTintColor = palette.secondary;plus.target=target;plus.action=action;plus.identifier = .init(groupID.uuidString);plus.toolTip="添加文件夹到“\(name)”";plus.setAccessibilityLabel(plus.toolTip!);plus.setAccessibilityIdentifier("group-add-\(groupID)")
        addSubview(self.name);addSubview(plus)
    }
    required init?(coder:NSCoder){fatalError()}
    override func layout(){
        super.layout()
        plus.frame=NSRect(x:max(0,bounds.width-28),y:(bounds.height-28)/2,width:28,height:28)
        let h=ceil(name.intrinsicContentSize.height)
        name.frame=NSRect(x:2,y:(bounds.height-h)/2,width:max(0,plus.frame.minX-10),height:h)
    }
}

extension Palette {
    var groupHeader: NSColor {
        NSColor.clear
    }
}
