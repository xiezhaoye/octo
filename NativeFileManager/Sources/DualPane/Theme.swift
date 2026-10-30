import AppKit
import FileManagerCore

struct Palette {
    let canvas: NSColor, sidebar: NSColor, toolbar: NSColor, text: NSColor, secondary: NSColor, line: NSColor, accent: NSColor, selection: NSColor
    let dark: Bool
    static func color(_ hex: UInt32) -> NSColor { NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1) }
    static func forSkin(_ skin: Skin) -> Palette {
        func c(_ h: UInt32) -> NSColor { color(h) }
        switch skin {
        case .native: return Palette(canvas: c(0xFFFFFF), sidebar: c(0xF0F2F5), toolbar: c(0xF7F8FA), text: c(0x313840), secondary: c(0x77838F), line: c(0xDCE1E6), accent: c(0x527DA8), selection: c(0xDCE8F4), dark: false)
        case .dark: return Palette(canvas: c(0x282F35), sidebar: c(0x20262B), toolbar: c(0x232A30), text: c(0xE6EBEF), secondary: c(0xB1BDC6), line: c(0x414B53), accent: c(0x91B79E), selection: c(0x3D5047), dark: true)
        case .warm: return Palette(canvas: c(0xFCFBF8), sidebar: c(0xF2EFE8), toolbar: c(0xF7F4EE), text: c(0x49443E), secondary: c(0x897C6C), line: c(0xE3DDD3), accent: c(0x9B7658), selection: c(0xEADFD1), dark: false)
        case .monochrome: return Palette(canvas: c(0xFCFCFA), sidebar: c(0xF2F3EF), toolbar: c(0xF4F5F1), text: c(0x333B35), secondary: c(0x727E74), line: c(0xC7CFC8), accent: c(0x414B43), selection: c(0xDDE5DC), dark: false)
        }
    }
}

func symbol(_ name: String, _ description: String = "") -> NSImage? { NSImage(systemSymbolName: name, accessibilityDescription: description) }
func iconButton(_ image: String, _ tip: String, target: AnyObject?, action: Selector) -> NSButton {
    let b = GlassIconButton(image: symbol(image, tip) ?? NSImage(), target: target, action: action)
    b.bezelStyle = .texturedRounded; b.isBordered = false; b.toolTip = tip; b.setAccessibilityLabel(tip)
    b.widthAnchor.constraint(equalToConstant: 28).isActive = true
    b.heightAnchor.constraint(equalToConstant: 28).isActive = true
    return b
}
func label(_ value: String, size: CGFloat = 12, weight: NSFont.Weight = .regular) -> NSTextField {
    let text = NSTextField(labelWithString: value); text.font = .systemFont(ofSize: size, weight: weight)
    text.lineBreakMode = .byTruncatingMiddle; return text
}
func pin(_ child: NSView, in parent: NSView, inset: CGFloat = 0) {
    child.translatesAutoresizingMaskIntoConstraints = false; parent.addSubview(child)
    NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset), child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset), child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset), child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)])
}
func rowStack(_ views: [NSView], spacing: CGFloat = 6) -> NSStackView {
    let stack = NSStackView(views: views); stack.orientation = .horizontal; stack.distribution = .fill; stack.spacing = spacing; stack.alignment = .centerY
    return stack
}
func spacer() -> NSView { let v = NSView(); v.setContentHuggingPriority(.init(1), for: .horizontal); return v }

final class TintedRow: NSTableRowView {
    override var interiorBackgroundStyle:NSView.BackgroundStyle {.normal}
    var tint: NSColor = .selectedContentBackgroundColor
    override func drawSelection(in dirtyRect: NSRect) { tint.setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 4, yRadius: 4).fill() }
}

final class MenuOutline: NSOutlineView {
    var bottomPadding:CGFloat = 0
    override var frame:NSRect {
        get {super.frame}
        set {
            var value=newValue
            value.size.height=max(value.height,(numberOfRows > 0 ? rect(ofRow:numberOfRows-1).maxY : 0)+bottomPadding)
            super.frame=value
        }
    }
    override func setFrameSize(_ newSize:NSSize) {
        super.setFrameSize(NSSize(width:newSize.width,height:max(newSize.height,(numberOfRows > 0 ? rect(ofRow:numberOfRows-1).maxY : 0)+bottomPadding)))
    }
    var focused: (() -> Void)?
    var space: (() -> Void)?
    var enter: (() -> Void)?
    override func mouseDown(with event: NSEvent) { focused?(); super.mouseDown(with: event) }
    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " { space?(); return }
        if event.keyCode == 36 { enter?(); return }
        super.keyDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        focused?(); window?.makeFirstResponder(self); let r = row(at: convert(event.locationInWindow, from: nil))
        if r >= 0 && !selectedRowIndexes.contains(r) { selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false) } else if r < 0 { deselectAll(nil) }
        return super.menu(for: event)
    }
}
