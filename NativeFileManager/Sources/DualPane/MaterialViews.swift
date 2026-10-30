import AppKit

@MainActor final class MaterialSurface:NSView {
    let effect=NSVisualEffectView()
    let tint=NSView()
    private var baseColor=NSColor.clear
    private var observer:NSObjectProtocol?
    private let notifications=NSWorkspace.shared.notificationCenter
    init(material:NSVisualEffectView.Material,blending:NSVisualEffectView.BlendingMode) {
        super.init(frame:.zero);wantsLayer=true
        effect.material=material;effect.blendingMode=blending;effect.state = .followsWindowActiveState
        pin(effect,in:self);tint.wantsLayer=true;pin(tint,in:self)
        observer=notifications.addObserver(forName:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil,queue:.main) { [weak self] _ in
            Task{@MainActor in guard let self else{return};self.apply(self.baseColor)}
        }
    }
    required init?(coder:NSCoder){fatalError()}
    deinit {if let observer {notifications.removeObserver(observer)}}
    func apply(_ color:NSColor) {
        baseColor=color
        let reduced=NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        effect.isHidden=reduced
        layer?.backgroundColor=(reduced ? color:.clear).cgColor
        tint.layer?.backgroundColor=color.withAlphaComponent(reduced ? 0:0.16).cgColor
    }
}

@MainActor final class GlassIconButton:NSButton {
    private var hovered=false
    override func updateTrackingAreas() {
        super.updateTrackingAreas();trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect:bounds,options:[.mouseEnteredAndExited,.activeInActiveApp,.inVisibleRect],owner:self,userInfo:nil))
    }
    override func mouseEntered(with event:NSEvent){hovered=true;needsDisplay=true}
    override func mouseExited(with event:NSEvent){hovered=false;needsDisplay=true}
    override func draw(_ dirtyRect:NSRect) {
        if hovered || isHighlighted {NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.12:0.06).setFill();NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:7,yRadius:7).fill()}
        super.draw(dirtyRect)
    }
}

@MainActor final class StableFolderImageView:NSImageView {
    override var allowsVibrancy:Bool {false}
    init(image:NSImage) {
        let size=NSSize(width:18,height:18)
        let fixed=NSImage(size:size,flipped:false) { rect in
            let scale=min(rect.width/max(1,image.size.width),rect.height/max(1,image.size.height))
            let drawing=NSRect(x:rect.midX-image.size.width*scale/2,y:rect.midY-image.size.height*scale/2,width:image.size.width*scale,height:image.size.height*scale)
            image.draw(in:drawing);return true
        }
        fixed.isTemplate=false
        super.init(frame:.zero);self.image=fixed
    }
    required init?(coder:NSCoder){fatalError()}
}
