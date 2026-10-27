import AppKit
import FileManagerCore

struct PaneLocation {
    let directory: URL
    let columns: [URL]
    let selection: [URL]
}

extension PaneController {
    func rememberLocation() {
        guard !restoringLocation, history.indices.contains(historyIndex), history[historyIndex].directory == currentURL else { return }
        history[historyIndex] = PaneLocation(directory: currentURL, columns: columnControllers.map(\.url), selection: columnSelection)
    }
    @objc func back() { restoreHistory(at: historyIndex-1) }
    @objc func forward() { restoreHistory(at: historyIndex+1) }
    @objc func up() {
        let parent = currentURL.deletingLastPathComponent()
        guard parent != currentURL, editor.prepareToLeave() else { return }
        rememberLocation()
        if app.state.panes[index].mode == .columns, let position = columnControllers.firstIndex(where: { $0.url == parent }) {
            let child = currentURL; removeDocumentPreview()
            while columnControllers.count > position+1 { columnControllers.removeLast().view.removeFromSuperview() }
            columnSelection = [child]; navigate(to: parent, resetColumns: false); rememberLocation(); layoutColumns(scrollToEnd: true)
        } else { navigate(to: parent) }
    }
    func restoreHistory(at position: Int) {
        guard history.indices.contains(position), editor.prepareToLeave() else { return }
        rememberLocation(); let location = history[position]; historyIndex = position
        if app.state.panes[index].mode != .columns { navigate(to: location.directory, recordHistory: false); return }
        removeDocumentPreview(); navigate(to: location.directory, recordHistory: false, resetColumns: false)
        let paths = location.columns.isEmpty ? [location.directory] : location.columns
        var common = 0
        while common < min(paths.count, columnControllers.count), paths[common] == columnControllers[common].url { common += 1 }
        while columnControllers.count > common { columnControllers.removeLast().view.removeFromSuperview() }
        let token = generation, directoryLoad = loadTask
        restoringLocation = true
        navigationRestoreTask = Task { @MainActor in
            defer { if generation == token {restoringLocation=false} }
            for path in paths.dropFirst(common) {
                do {
                    let files: [FileRecord]
                    if path == location.directory { await directoryLoad?.value; guard lastLoadSucceeded else { return }; files = records }
                    else { files = try await reader.contents(of: path, showHidden: app.state.panes[index].showHidden) }
                    guard !Task.isCancelled, generation == token else { return }
                    addColumn(files, url: path)
                } catch { if !Task.isCancelled { app.showError(error) }; return }
            }
            guard !Task.isCancelled, generation == token else { return }
            columnSelection = location.selection
            for (offset, column) in columnControllers.enumerated() {
                let selected = offset+1 < paths.count ? [paths[offset+1]] : location.selection
                column.restoringSelection = true
                column.table.selectRowIndexes(IndexSet(column.files.indices.filter { selected.contains(column.files[$0].url) }), byExtendingSelection: false)
                column.restoringSelection = false
            }
            if location.selection.count == 1, let url = location.selection.first, (try? FileRecord(url:url).directory) == false, DocumentEditor.supports(url) { _ = showDocumentPreview(url) }
            restoringLocation=false;rememberLocation(); layoutColumns(scrollToEnd: true)
        }
    }
}
