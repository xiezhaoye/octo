import AppKit
import FileManagerCore

extension PaneController {
    var contextualDirectory: URL { menuDirectory ?? currentURL }
    var creationDirectory: URL {
        if let url = selectedURLs.first, selectedURLs.count == 1, (try? FileRecord(url: url).browsable) == true { return url }
        return contextualDirectory
    }
    func addNewDocumentMenu(to menu: NSMenu) {
        let parent = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
        let submenu = documentTypesMenu()
        parent.submenu = submenu; menu.addItem(parent)
    }
    func documentTypesMenu(in directory:URL? = nil) -> NSMenu {
        let submenu = NSMenu()
        for kind in TextFileKind.allCases {
            let item = NSMenuItem(title: kind.title + "…", action: #selector(createDocument(_:)), keyEquivalent: "")
            item.target = self
            if let directory {item.representedObject=["kind":kind.rawValue,"directory":directory.path]}
            else {item.representedObject=kind.rawValue}
            submenu.addItem(item)
        }
        return submenu
    }
    @objc func createCurrentFolder() {app.activePane=index;createFolder(in:currentURL)}
    @objc func showCurrentFileTypes(_ sender:NSButton) {
        app.activePane=index
        documentTypesMenu(in:currentURL).popUp(positioning:nil,at:NSPoint(x:0,y:0),in:sender)
    }
    @objc func createDocument(_ sender: NSMenuItem) {
        let parameters=sender.representedObject as? [String:String]
        let raw=parameters?["kind"] ?? (sender.representedObject as? String) ?? ""
        guard let kind = TextFileKind(rawValue: raw),
              let name = app.input("新建 " + kind.title, initial: "未命名." + kind.fileExtension) else { return }
        let directory = parameters?["directory"].map{URL(fileURLWithPath:$0)} ?? creationDirectory
        guard editor.prepareToLeave() else { return }
        do { let url = try kind.create(in: directory, name: name); revealCreatedDocument(url) }
        catch { app.showError(error) }
    }
    func revealCreatedDocument(_ url: URL) {
        navigate(to: url.deletingLastPathComponent())
        Task { @MainActor in
            if let task = loadTask { await task.value }
            guard currentURL == url.deletingLastPathComponent() else { return }
            if app.state.panes[index].mode == .columns,
               let column = columnControllers.last,
               let row = column.files.firstIndex(where: { $0.url == url }) {
                column.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                column.table.scrollRowToVisible(row)
                if editor.document != nil { editor.modes.selectedSegment = 1; editor.changeDisplayMode() }
            } else if app.state.panes[index].mode == .list {
                if let row = nodes.firstIndex(where: { $0.record.url == url }) { list.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
            } else if let row = records.firstIndex(where: { $0.url == url }) { collection.selectionIndexPaths = [IndexPath(item: row, section: 0)] }
        }
    }
    func removeDocumentPreview(clear: Bool = true) {
        if editor.isViewLoaded { editor.view.removeFromSuperview() }
        if clear { editor.clear() }
    }
    func showDocumentPreview(_ url: URL) -> Bool {
        guard app.state.panes[index].mode == .columns, DocumentEditor.supports(url), editor.open(url) else { return false }
        if editor.view.superview == nil {
            columnStack.addArrangedSubview(editor.view)
            editorWidth?.isActive = false
            editorWidth = editor.view.widthAnchor.constraint(equalToConstant: 460); editorWidth?.isActive = true
            editor.view.heightAnchor.constraint(equalTo: columnStack.heightAnchor).isActive = true
        }
        rememberLocation(); layoutColumns(scrollToEnd: true); editor.focusImagePreview(); return true
    }
    /// Directory changes refresh each existing column in place, preserving the path and editor buffer.
    func refreshColumns() {
        columnRefreshTask?.cancel()
        let snapshot = columnControllers
        columnRefreshTask = Task { @MainActor in
            for column in snapshot {
                do {
                    let files = try await reader.contents(of: column.url, showHidden: app.state.panes[index].showHidden)
                    guard !Task.isCancelled, columnControllers.contains(where: { $0 === column }) else { return }
                    let selected = Set(column.table.selectedRowIndexes.compactMap { column.files.indices.contains($0) ? column.files[$0].url : nil })
                    column.restoringSelection = true; column.files = files; column.table.reloadData()
                    column.table.selectRowIndexes(IndexSet(files.indices.filter { selected.contains(files[$0].url) }), byExtendingSelection: false)
                    column.restoringSelection = false
                } catch { if !Task.isCancelled { app.message(error.localizedDescription) } }
            }
            editor.checkExternalChanges()
        }
    }
}
