import AppKit

/// Keeps picture navigation local to the preview, leaving directory keyboard handling unchanged.
@MainActor final class ImagePreviewCanvas: NSView {
    weak var editor: DocumentEditor?
    let previous = NSButton(image: symbol("chevron.left") ?? NSImage(), target: nil, action: nil)
    let next = NSButton(image: symbol("chevron.right") ?? NSImage(), target: nil, action: nil)
    let overview = NSButton(image: symbol("arrow.up") ?? NSImage(), target: nil, action: nil)
    init(editor: DocumentEditor, imageView: NSImageView) {
        self.editor = editor; super.init(frame: .zero)
        pin(imageView, in: self, inset: 12)
        let left = floating(previous, title: "上一张图片（←）", action: #selector(DocumentEditor.previousImage))
        let right = floating(next, title: "下一张图片（→）", action: #selector(DocumentEditor.nextImage))
        let up = floating(overview, title: "当前文件夹图片总览（↑）", action: #selector(DocumentEditor.showImageOverview))
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), left.centerYAnchor.constraint(equalTo: centerYAnchor),
            right.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), right.centerYAnchor.constraint(equalTo: centerYAnchor),
            up.topAnchor.constraint(equalTo: topAnchor, constant: 12), up.centerXAnchor.constraint(equalTo: centerXAnchor)
        ])
        setAccessibilityLabel("图片预览：↑ 缩略图总览，← 上一张，→ 下一张")
    }
    required init?(coder: NSCoder) { fatalError() }
    func floating(_ button: NSButton, title: String, action: Selector) -> NSView {
        let background = NSVisualEffectView(); background.material = .hudWindow; background.blendingMode = .withinWindow; background.state = .active
        background.wantsLayer = true; background.layer?.cornerRadius = 18; background.layer?.masksToBounds = true
        button.title = ""; button.imagePosition = .imageOnly; button.isBordered = false; button.target = editor; button.action = action; button.toolTip = title; button.setAccessibilityLabel(title)
        button.image = button.image?.withSymbolConfiguration(.init(pointSize: 16, weight: .semibold))
        pin(button, in: background, inset: 2)
        background.translatesAutoresizingMaskIntoConstraints = false; addSubview(background)
        background.widthAnchor.constraint(equalToConstant: 36).isActive = true; background.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return background
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
