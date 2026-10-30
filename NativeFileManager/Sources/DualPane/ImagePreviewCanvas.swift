import AppKit

/// Keeps picture navigation local to the preview, leaving directory keyboard handling unchanged.
@MainActor final class ImagePreviewCanvas: NSView {
    weak var editor: DocumentEditor?
    let previous = NSButton(image: symbol("chevron.left") ?? NSImage(), target: nil, action: nil)
    let next = NSButton(image: symbol("chevron.right") ?? NSImage(), target: nil, action: nil)
    let overview = NSButton(image: symbol("arrow.up") ?? NSImage(), target: nil, action: nil)
    init(editor: DocumentEditor, imageView: NSImageView) {
        self.editor = editor; super.init(frame: .zero)
        imageView.translatesAutoresizingMaskIntoConstraints=false;addSubview(imageView)
        configure(previous,title:"上一张图片（←）",action:#selector(DocumentEditor.previousImage))
        configure(next,title:"下一张图片（→）",action:#selector(DocumentEditor.nextImage))
        configure(overview,title:"当前文件夹图片总览（↑）",action:#selector(DocumentEditor.showImageOverview))
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo:leadingAnchor,constant:44),imageView.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-44),
            imageView.topAnchor.constraint(equalTo:topAnchor,constant:44),imageView.bottomAnchor.constraint(equalTo:bottomAnchor,constant:-12),
            previous.leadingAnchor.constraint(equalTo:leadingAnchor,constant:6),previous.centerYAnchor.constraint(equalTo:imageView.centerYAnchor),
            next.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-6),next.centerYAnchor.constraint(equalTo:imageView.centerYAnchor),
            overview.topAnchor.constraint(equalTo:topAnchor,constant:6),overview.centerXAnchor.constraint(equalTo:centerXAnchor)
        ])
        setAccessibilityLabel("图片预览：↑ 缩略图总览，← 上一张，→ 下一张")
    }
    required init?(coder: NSCoder) { fatalError() }
    func configure(_ button:NSButton,title:String,action:Selector) {
        button.title="";button.imagePosition = .imageOnly;button.isBordered=false;button.target=editor;button.action=action
        button.toolTip=title;button.setAccessibilityLabel(title)
        button.image=button.image?.withSymbolConfiguration(.init(pointSize:18,weight:.medium))
        button.translatesAutoresizingMaskIntoConstraints=false;addSubview(button)
        button.widthAnchor.constraint(equalToConstant:32).isActive=true;button.heightAnchor.constraint(equalToConstant:32).isActive=true
    }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        if let editor { editor.pane.app.activePane = editor.pane.index }; window?.makeFirstResponder(self); super.mouseDown(with: event)
    }
    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 123: editor?.previousImage()
        case 124: editor?.nextImage()
        case 126: editor?.showImageOverview()
        default: super.keyDown(with: event)
        }
    }
}
