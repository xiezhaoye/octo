import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers
import FileManagerCore

@MainActor final class FileTile: NSCollectionViewItem {
    let image = NSImageView()
    let name = label("", size: 12)
    let tagDots = FolderTagDots()
    var path: String?
    var palette = Palette.forSkin(.native)
    var thumbnail: QLThumbnailGenerator.Request?
    override func loadView() {
        view = NSView(); view.wantsLayer = true; view.layer?.cornerRadius = 6
        image.imageScaling = .scaleProportionallyUpOrDown; image.widthAnchor.constraint(equalToConstant: 58).isActive = true; image.heightAnchor.constraint(equalToConstant: 58).isActive = true
        name.alignment = .center; name.maximumNumberOfLines = 2; name.lineBreakMode = .byTruncatingMiddle
        let stack = NSStackView(views: [image,name]); stack.orientation = .vertical; stack.spacing = 7; stack.alignment = .centerX; pin(stack, in: view, inset: 6); textField = name; imageView = image
        view.addSubview(tagDots);tagDots.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([tagDots.centerXAnchor.constraint(equalTo:image.centerXAnchor),tagDots.bottomAnchor.constraint(equalTo:image.bottomAnchor,constant:3)])
    }
    override var isSelected: Bool { didSet { view.layer?.backgroundColor = (isSelected ? palette.selection : .clear).cgColor } }
    func configure(_ record: FileRecord, palette: Palette, colors:[FolderTagColor] = []) {
        _ = view; self.palette = palette; path = record.url.path; name.stringValue = record.name; name.textColor = palette.text; view.toolTip = record.url.path; image.image = taggedFolderIcon(record,colors:colors); tagDots.configure(colors)
        view.layer?.backgroundColor = (isSelected ? palette.selection : .clear).cgColor
        if let thumbnail { QLThumbnailGenerator.shared.cancel(thumbnail) }
        guard !record.directory, let type = UTType(filenameExtension: record.url.pathExtension), type.conforms(to: .image) || type.conforms(to: .pdf) else { return }
        let request = QLThumbnailGenerator.Request(fileAt: record.url, size: NSSize(width: 80, height: 80), scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        thumbnail = request
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in DispatchQueue.main.async { guard let self, self.path == record.url.path, let representation else { return }; self.image.image = representation.nsImage } }
    }
    func cancelThumbnail() { if let thumbnail { QLThumbnailGenerator.shared.cancel(thumbnail) }; thumbnail = nil }
    override func prepareForReuse() { super.prepareForReuse(); if let thumbnail { QLThumbnailGenerator.shared.cancel(thumbnail) }; thumbnail = nil; path = nil }
}

@MainActor final class FileCollectionView: NSCollectionView {
    weak var owner: PaneController?
    override func mouseDown(with event: NSEvent) { if let owner { owner.app.activePane = owner.index; owner.menuDirectory = nil }; super.mouseDown(with: event) }
    override func keyDown(with event: NSEvent) { if event.charactersIgnoringModifiers == " " { owner?.showFilePreview(); return }; if event.keyCode == 36 { owner?.openSelection(); return }; super.keyDown(with: event) }
    override func menu(for event: NSEvent) -> NSMenu? { window?.makeFirstResponder(self); if let owner { owner.app.activePane = owner.index }; let point = convert(event.locationInWindow, from: nil); if let index = indexPathForItem(at: point) { if !selectionIndexPaths.contains(index) { selectionIndexPaths = [index] } } else { selectionIndexPaths = [] }; if let owner { owner.menuDirectory = nil }; return super.menu(for: event) }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly:true]) ? (NSEvent.modifierFlags.contains(.option) ? .copy : .move) : [] }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { guard let owner else { return false }; let point = convert(sender.draggingLocation, from: nil); var target = owner.currentURL; if let i = indexPathForItem(at: point), owner.records.indices.contains(i.item), owner.records[i.item].browsable { target = owner.records[i.item].url }; return owner.acceptFiles(sender, destination: target) }
}

@MainActor final class DirectoryColumn: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    unowned let pane: PaneController
    var files: [FileRecord]
    var restoringSelection = false
    let url: URL
    let position: Int
    var widthConstraint: NSLayoutConstraint?
    let table = ColumnTable()
    let scroll = ColumnContentScrollView()
    let heading = label("", size: 11, weight: .medium)
    init(pane: PaneController, files: [FileRecord], url: URL, position: Int) { self.pane = pane; self.files = files; self.url = url; self.position = position; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() {
        view = NSView(); view.wantsLayer = true; heading.stringValue = url.lastPathComponent; heading.toolTip = url.path
        let head = NSView(); pin(heading, in: head, inset: 7); head.heightAnchor.constraint(equalToConstant: 31).isActive = true
        let c = NSTableColumn(identifier: .init("name")); c.resizingMask = .autoresizingMask; table.addTableColumn(c); table.headerView = nil; table.dataSource = self; table.delegate = self; table.rowHeight = 29; table.target = self; table.doubleAction = #selector(open); table.owner = self; table.allowsMultipleSelection = true
        table.registerForDraggedTypes([.fileURL]); table.setDraggingSourceOperationMask([.copy,.move], forLocal: true); table.setDraggingSourceOperationMask([.copy,.move], forLocal: false)
        let menu = NSMenu(); menu.delegate = self; table.menu = menu
        scroll.pane=pane;scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let stack = NSStackView(views: [head,scroll]); stack.orientation = .vertical; stack.spacing = 0; stack.alignment = .leading; head.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true; scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true; pin(stack, in: view); applyTheme()
    }
    func applyTheme() { guard isViewLoaded else { return }; view.layer?.backgroundColor = pane.palette.toolbar.cgColor; table.backgroundColor = pane.palette.canvas; heading.textColor = pane.palette.secondary; table.reloadData() }
    func numberOfRows(in tableView: NSTableView) -> Int { files.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? { let r = files[row]; let icon = NSImageView(image: taggedFolderIcon(r,colors:pane.app.state.colors(for:r.url))); icon.widthAnchor.constraint(equalToConstant: 18).isActive = true; icon.heightAnchor.constraint(equalToConstant: 18).isActive = true; let text = label(r.name, size: 13); text.textColor = pane.palette.text; text.toolTip = r.url.path; let views: [NSView] = r.browsable ? [icon,text,spacer(),FolderTagDots(pane.app.state.colors(for:r.url)),NSImageView(image:symbol("chevron.right") ?? NSImage())] : [icon,text]; return rowStack(views, spacing: 6) }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { let r = TintedRow(); r.tint = pane.palette.selection; return r }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !restoringSelection else { return }
        pane.app.activePane = pane.index
        let previous = pane.columnSelection
        let selection = table.selectedRowIndexes.map { files[$0].url }
        let accepted: Bool
        if table.selectedRowIndexes.count == 1, table.selectedRow >= 0 { accepted = pane.selectColumn(position, record: files[table.selectedRow]) }
        else { accepted = pane.editor.prepareToLeave(); if accepted { pane.columnSelection = selection; pane.menuDirectory = nil; pane.removeDocumentPreview(); if pane.currentURL != url { pane.navigate(to: url, resetColumns: false) }; while pane.columnControllers.count > position+1 { pane.columnControllers.removeLast().view.removeFromSuperview() }; pane.layoutColumns() } }
        if !accepted { restoringSelection = true; table.selectRowIndexes(IndexSet(files.indices.filter { previous.contains(files[$0].url) }), byExtendingSelection: false); restoringSelection = false }
    }
    @objc func open() { pane.openSelection() }
    func menuNeedsUpdate(_ menu: NSMenu) { pane.menuDirectory = url; pane.columnSelection = table.selectedRowIndexes.map { files[$0].url }; pane.menuNeedsUpdate(menu) }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? { files[row].url as NSURL }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation { info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly:true]) ? (NSEvent.modifierFlags.contains(.option) ? .copy : .move) : [] }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool { pane.acceptFiles(info, destination: dropOperation == .on && files.indices.contains(row) && files[row].browsable ? files[row].url : url) }
}

@MainActor final class ColumnTable: NSTableView {
    weak var owner: DirectoryColumn?
    override var frame:NSRect {
        get {super.frame}
        set {
            var value=newValue
            value.size.height=max(value.height,(numberOfRows > 0 ? rect(ofRow:numberOfRows-1).maxY : 0)+72)
            super.frame=value
        }
    }
    override func setFrameSize(_ newSize:NSSize) {
        super.setFrameSize(NSSize(width:newSize.width,height:max(newSize.height,(numberOfRows > 0 ? rect(ofRow:numberOfRows-1).maxY : 0)+72)))
    }
    override func scrollWheel(with event:NSEvent){if owner?.pane.routeColumnScroll(event)==true{return};super.scrollWheel(with:event)}
    override func keyDown(with event: NSEvent) { if event.charactersIgnoringModifiers == " " { owner?.pane.showFilePreview(); return }; super.keyDown(with: event) }
    override func menu(for event: NSEvent) -> NSMenu? { window?.makeFirstResponder(self); let row = self.row(at: convert(event.locationInWindow, from: nil)); if row >= 0 && !selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) } else if row < 0 { deselectAll(nil) }; return super.menu(for: event) }
}

@MainActor final class ColumnContentScrollView:NSScrollView{
    weak var pane:PaneController?
    override func scrollWheel(with event:NSEvent){if pane?.routeColumnScroll(event)==true{return};super.scrollWheel(with:event)}
}
@MainActor final class ColumnCanvasScrollView:NSScrollView{
    weak var pane:PaneController?
    override func scrollWheel(with event:NSEvent){if pane?.routeColumnScroll(event)==true{return};super.scrollWheel(with:event)}
}

@MainActor enum CommandOutput {
    static var windows: [NSWindow] = []
    static func show(title: String, output: String) { let window = CommandWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 440), styleMask: [.titled,.closable,.resizable], backing: .buffered, defer: false); window.title = "命令输出 · " + title; window.isReleasedWhenClosed = false; let scroll = NSScrollView(); scroll.hasVerticalScroller = true; let text = NSTextView(); text.isEditable = false; text.font = .monospacedSystemFont(ofSize: 12, weight: .regular); text.string = String(output.prefix(2_000_000)); text.isVerticallyResizable = true; text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true; scroll.documentView = text; window.contentView = scroll; window.center(); window.makeKeyAndOrderFront(nil); windows.append(window) }
}

@MainActor final class CommandWindow: NSWindow {
    override func close() { super.close(); CommandOutput.windows.removeAll { $0 === self } }
}
