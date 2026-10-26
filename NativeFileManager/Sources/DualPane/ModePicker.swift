import AppKit

/// Explicit image geometry avoids the baseline offset in large segmented cells.
@MainActor final class ModePicker: NSView {
    let buttons: [CenteredModeButton] = ["list.bullet", "rectangle.split.3x1", "square.grid.2x2"].map { CenteredModeButton(symbolName: $0) }
    weak var target: AnyObject?
    var action: Selector?
    var selectedSegment = 0 { didSet { updateButtons() } }
    var palette = Palette.forSkin(.native) { didSet { updateButtons() } }
    override var intrinsicContentSize: NSSize { NSSize(width:120,height:32) }
    override init(frame:NSRect) {
        super.init(frame:frame)
        for (i, button) in buttons.enumerated() {
            button.tag=i;button.target=self;button.action = #selector(choose(_:))
            button.toolTip=["列表","分栏","图标"][i];button.setAccessibilityLabel(button.toolTip!);addSubview(button)
        }
        setAccessibilityLabel("浏览模式");updateButtons()
    }
    required init?(coder:NSCoder){fatalError()}
    override func layout(){super.layout();for (i,b) in buttons.enumerated(){b.frame=NSRect(x:CGFloat(i)*40,y:(bounds.height-32)/2,width:38,height:32)}}
    @objc private func choose(_ sender:NSButton){selectedSegment=sender.tag;if let action{NSApp.sendAction(action,to:target,from:self)}}
    private func updateButtons(){for (i,b) in buttons.enumerated(){b.palette=palette;b.state=i == selectedSegment ? .on:.off;b.setAccessibilityValue(i == selectedSegment ? 1:0);b.needsDisplay=true}}
}

@MainActor final class CenteredModeButton: NSButton {
    var palette = Palette.forSkin(.native)
    private(set) var iconRect = NSRect.zero
    init(symbolName:String){super.init(frame:.zero);image=symbol(symbolName)?.withSymbolConfiguration(.init(pointSize:19,weight:.regular));isBordered=false;setButtonType(.toggle);focusRingType = .exterior}
    required init?(coder:NSCoder){fatalError()}
    override func draw(_ dirtyRect:NSRect){
        let rect=bounds.insetBy(dx:0.5,dy:0.5)
        let path=NSBezierPath(roundedRect:rect,xRadius:7,yRadius:7)
        (state == .on ? palette.selection : palette.canvas).setFill();path.fill()
        palette.line.setStroke();path.lineWidth=1;path.stroke()
        guard let image else{return}
        let alignment=image.alignmentRect
        let size=image.size
        let scale:CGFloat=min(1,min(24/max(1,alignment.width),24/max(1,alignment.height)))
        let drawing=NSRect(x:bounds.midX-alignment.midX*scale,y:bounds.midY-alignment.midY*scale,width:size.width*scale,height:size.height*scale)
        iconRect=NSRect(x:drawing.minX+alignment.minX*scale,y:drawing.minY+alignment.minY*scale,width:alignment.width*scale,height:alignment.height*scale)
        // Tint through a source-atop fill so selection never changes symbol placement.
        let tinted=NSImage(size:size,flipped:false){r in image.draw(in:r);self.palette.text.setFill();r.fill(using:.sourceAtop);return true}
        tinted.draw(in:drawing,from:.zero,operation:.sourceOver,fraction:isEnabled ? 1:0.45,respectFlipped:true,hints:nil)
    }
}
