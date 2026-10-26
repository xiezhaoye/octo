import AppKit

enum OctoBrand {
    static let logo:NSImage? = {
        if let url=Bundle.main.url(forResource:"OctoDock",withExtension:"png"){return NSImage(contentsOf:url)}
        return Bundle.module.url(forResource:"OctoDock",withExtension:"png").flatMap{NSImage(contentsOf:$0)}
    }()
}

@MainActor final class TransparentLogoView:NSView {
    var image:NSImage? {didSet{needsDisplay=true}}
    override func draw(_ dirtyRect:NSRect){
        image?.draw(in:bounds,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
    }
}

@MainActor final class OctoTitleView:NSView {
    let logo=TransparentLogoView()
    let name=label("Octo",size:14,weight:.semibold)
    override var mouseDownCanMoveWindow:Bool{true}
    override init(frame:NSRect){
        super.init(frame:frame)
        logo.image=OctoBrand.logo
        logo.setAccessibilityLabel("Octo Logo");addSubview(logo);addSubview(name)
    }
    required init?(coder:NSCoder){fatalError()}
    override func layout(){
        super.layout()
        logo.frame=NSRect(x:6,y:(bounds.height-24)/2,width:24,height:24)
        let h=name.intrinsicContentSize.height
        name.frame=NSRect(x:36,y:(bounds.height-h)/2,width:54,height:h)
    }
}
