import AppKit
import FileManagerCore

extension DocumentEditor {
    func loadImageNeighbors() {
        guard let imageURL else { return }
        if imageNeighbors.contains(imageURL) { updateImageNavigation(); return }
        let token = imageGeneration, directory = imageURL.deletingLastPathComponent()
        imageNeighborTask?.cancel()
        imageNeighborTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let files = try await pane.reader.contents(of: directory, showHidden: pane.app.state.panes[pane.index].showHidden)
                guard !Task.isCancelled, imageGeneration == token else { return }
                imageNeighbors = files.filter { !$0.directory && Self.isImage($0.url) }.map(\.url)
                updateImageNavigation()
            } catch { guard imageGeneration == token else { return }; updateImageNavigation(); info.stringValue = "无法读取同目录图片：" + error.localizedDescription }
        }
    }
    func updateImageNavigation() {
        guard let imageURL, !showingImageOverview else { return }
        let position = imageNeighbors.firstIndex(of: imageURL)
        imageCanvas.previous.isEnabled = position.map { $0 > 0 } ?? false
        imageCanvas.next.isEnabled = position.map { $0+1 < imageNeighbors.count } ?? false
        let counter = position.map { "\($0+1)/\(imageNeighbors.count) · " } ?? ""
        info.stringValue = counter + "↑ 缩略图总览 · ← 上一张 · → 下一张"
    }
    @objc func previousImage() { moveImage(by: -1) }
    @objc func nextImage() { moveImage(by: 1) }
    func moveImage(by offset: Int) {
        guard !showingImageOverview, let imageURL, let position = imageNeighbors.firstIndex(of: imageURL), imageNeighbors.indices.contains(position+offset) else { return }
        openGalleryImage(imageNeighbors[position+offset])
    }
    @objc func showImageOverview() { guard imageURL != nil, !showingImageOverview else { return }; toggleImageOverview() }
    func focusImagePreview() { guard imageURL != nil, !showingImageOverview else { return }; pane.app.activePane = pane.index; view.window?.makeFirstResponder(imageCanvas) }
}
