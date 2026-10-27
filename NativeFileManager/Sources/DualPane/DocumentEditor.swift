import AppKit
import WebKit
import FileManagerCore
import ImageIO
import UniformTypeIdentifiers

/// One editor per pane. Source stays in AppKit; only sanitized previews enter WebKit.
@MainActor final class DocumentEditor: NSViewController, NSTextViewDelegate, WKNavigationDelegate {
    unowned let pane: PaneController
    var document: TextDocument?
    var kind: TextFileKind = .text
    let text = NSTextView()
    let sourceScroll = NSScrollView()
    let body = NSStackView()
    let info = label("", size: 11)
    let modes = NSSegmentedControl(labels: ["预览", "编辑", "分屏"], trackingMode: .selectOne, target: nil, action: nil)
    let saveButton = NSButton(title: "保存", target: nil, action: nil)
    let formatButton = NSButton(title: "格式化", target: nil, action: nil)
    let reloadButton = NSButton(image: symbol("arrow.clockwise") ?? NSImage(), target: nil, action: nil)
    let controls = NSView()
    let imageView = NSImageView()
    lazy var imageCanvas = ImagePreviewCanvas(editor: self, imageView: imageView)
    var imageNeighbors: [URL] = []
    var imageNeighborTask: Task<Void, Never>?
    var imageURL: URL?
    let galleryButton = NSButton(image:symbol("square.grid.2x2") ?? NSImage(),target:nil,action:nil)
    var gallery: ImageGallery?
    var showingImageOverview = false
    var imageRequest: ImageDecodeRequest?
    var previewStarted = false
    var imageTask: Task<Void, Never>?
    var imageGeneration = UUID()
    var fileURL: URL? { document?.url ?? imageURL?.resolvingSymlinksInPath() }
    static func supports(_ url: URL) -> Bool { TextFileKind.identify(url) != nil || isImage(url) }
    static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }
    lazy var web: WKWebView = {
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration); view.navigationDelegate = self
        view.setValue(false, forKey: "drawsBackground"); return view
    }()
    var previewReady = false
    var previewTimer: Timer?
    var checkTimer: Timer?
    var loading = false
    var unsavedDecision: (() -> NSApplication.ModalResponse)?
    var hasUnsavedChanges: Bool { document.map { text.string != $0.content } ?? false }
    init(pane: PaneController) { self.pane = pane; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() {
        view = NSView(); view.wantsLayer = true
        modes.selectedSegment = 0; modes.target = self; modes.action = #selector(changeDisplayMode)
        saveButton.target = self; saveButton.action = #selector(saveAction); saveButton.setAccessibilityLabel("保存文档（⌘S）")
        formatButton.target = self; formatButton.action = #selector(formatJSON)
        reloadButton.target = self; reloadButton.action = #selector(reloadDocument)
        reloadButton.title = ""; reloadButton.imagePosition = .imageOnly
        reloadButton.isBordered = false; reloadButton.toolTip = "重新载入"; reloadButton.setAccessibilityLabel("重新载入")
        reloadButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        galleryButton.title="";galleryButton.imagePosition = .imageOnly;galleryButton.isBordered=false;galleryButton.toolTip="查看同文件夹全部图片";galleryButton.setAccessibilityLabel("查看同文件夹全部图片");galleryButton.target=self;galleryButton.action = #selector(toggleImageOverview);galleryButton.widthAnchor.constraint(equalToConstant:28).isActive=true;galleryButton.isHidden=true
        let trailing = rowStack([formatButton, galleryButton, reloadButton], spacing: 4)
        for child in [saveButton, modes, trailing] { child.translatesAutoresizingMaskIntoConstraints = false; controls.addSubview(child) }
        NSLayoutConstraint.activate([
            saveButton.leadingAnchor.constraint(equalTo: controls.leadingAnchor, constant: 8),
            saveButton.centerYAnchor.constraint(equalTo: controls.centerYAnchor),
            modes.centerXAnchor.constraint(equalTo: controls.centerXAnchor), modes.centerYAnchor.constraint(equalTo: controls.centerYAnchor),
            trailing.trailingAnchor.constraint(equalTo: controls.trailingAnchor, constant: -8), trailing.centerYAnchor.constraint(equalTo: controls.centerYAnchor)
        ])
        imageView.imageScaling = .scaleProportionallyUpOrDown; imageView.setAccessibilityLabel("图片预览")
        text.isRichText = false; text.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        text.isAutomaticQuoteSubstitutionEnabled = false; text.isAutomaticDashSubstitutionEnabled = false; text.isAutomaticTextReplacementEnabled = false
        text.isContinuousSpellCheckingEnabled = false; text.allowsUndo = true; text.delegate = self
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true; text.textContainerInset = NSSize(width: 12, height: 12)
        text.setAccessibilityLabel("文档源码编辑器")
        sourceScroll.documentView = text; sourceScroll.hasVerticalScroller = true; sourceScroll.autohidesScrollers = true
        body.orientation = .horizontal; body.spacing = 1; body.distribution = .fillEqually; body.alignment = .top
        info.maximumNumberOfLines = 2; info.lineBreakMode = .byWordWrapping
        let footer = rowStack([info]); footer.edgeInsets = .init(top: 5, left: 12, bottom: 5, right: 12)
        let stack = NSStackView(views: [controls, body, footer]); stack.orientation = .vertical; stack.spacing = 1; stack.alignment = .leading
        for child in stack.arrangedSubviews { child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        controls.heightAnchor.constraint(equalToConstant: 36).isActive = true
        footer.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
        pin(stack, in: view); applyTheme(); changeDisplayMode()
    }
    func ensurePreviewLoaded() {
        guard !previewStarted else{return};previewStarted=true
        if let url = Bundle.module.url(forResource:"preview",withExtension:"html",subdirectory:"Editor") {web.loadFileURL(url,allowingReadAccessTo:url.deletingLastPathComponent())}
        else {info.stringValue="缺少预览资源，仍可编辑源码。"}
    }
    func applyTheme() {
        guard isViewLoaded else { return }; let palette = pane.palette
        view.layer?.backgroundColor = palette.toolbar.cgColor; info.textColor = palette.secondary
        text.backgroundColor = palette.canvas; text.textColor = palette.text; text.insertionPointColor = palette.text
        renderPreview()
    }
    @discardableResult func open(_ url: URL) -> Bool {
        _ = view
        if Self.isImage(url) ? imageURL == url.standardizedFileURL : document?.url == url.resolvingSymlinksInPath() { return true }
        guard prepareToLeave() else { return false }
        if Self.isImage(url) { openImage(url); return true }
        imageTask?.cancel(); imageURL = nil; imageView.image = nil
        do {
            let next = try TextDocument(url: url); document = next; kind = TextFileKind.identify(url) ?? .text
            loading = true; text.string = next.content; text.undoManager?.removeAllActions(); loading = false
            configureModes(); changeDisplayMode(); updateState(); renderPreview()
            checkTimer?.invalidate()
            checkTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in Task { @MainActor in self?.checkExternalChanges() } }
            return true
        } catch { pane.app.showError(error); return false }
    }
    func configureModes() {
        let image = imageURL != nil
        modes.isHidden = !image && kind == .text
        modes.segmentCount = image ? 1 : 3
        for (index, title) in (image ? ["预览"] : ["预览", "编辑", "分屏"]).enumerated() { modes.setLabel(title, forSegment: index) }
        modes.selectedSegment = !image && kind == .text ? 1 : 0
        galleryButton.isHidden = !image
        galleryButton.image=symbol("square.grid.2x2");galleryButton.toolTip="查看同文件夹全部图片";galleryButton.setAccessibilityLabel("查看同文件夹全部图片")
        saveButton.isHidden = image; formatButton.isHidden = image || kind != .json
    }
    func openImage(_ url: URL, neighbors: [URL] = []) {
        clear(); document = nil; imageURL = url.standardizedFileURL; imageNeighbors = neighbors; configureModes(); changeDisplayMode()
        info.stringValue = "正在读取图片… · ↑ 总览 · ← 上一张 · → 下一张"
        imageCanvas.previous.isEnabled = false; imageCanvas.next.isEnabled = false
        let token = UUID(); imageGeneration = token
        let request=ImageDecodeRequest();imageRequest=request
        loadImageNeighbors()
        imageTask = Task { @MainActor [weak self] in
            let decoded = await ImagePreviewDecoding.decode(url,request:request)
            guard let self, !Task.isCancelled, self.imageGeneration == token else { return }
            if let decoded { self.imageView.image = NSImage(cgImage: decoded, size: .zero); self.updateImageNavigation() }
            else { self.info.stringValue = "无法解码此图片，可使用外部应用打开。" }
        }
    }
    @objc func toggleImageOverview() {
        guard let imageURL else{return}
        pane.app.activePane = pane.index
        if showingImageOverview {openImage(imageURL);return}
        if gallery == nil {gallery=ImageGallery(editor:self)}
        imageRequest?.cancel();imageTask?.cancel();imageView.image=nil
        showingImageOverview=true;galleryButton.image=symbol("photo");galleryButton.toolTip="返回单张预览";galleryButton.setAccessibilityLabel("返回单张预览");changeDisplayMode();view.window?.makeFirstResponder(gallery!.collection)
        gallery!.loadImages(in:imageURL.deletingLastPathComponent(),selected:imageURL)
    }
    func openGalleryImage(_ url:URL) {
        pane.columnSelection=[url]
        for column in pane.columnControllers where column.url == url.deletingLastPathComponent() {
            if let row=column.files.firstIndex(where:{$0.url==url}) {column.restoringSelection=true;column.table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false);column.table.scrollRowToVisible(row);column.restoringSelection=false}
        }
        let neighbors = imageNeighbors.filter { $0.deletingLastPathComponent() == url.deletingLastPathComponent() }
        openImage(url, neighbors: neighbors);pane.rememberLocation();focusImagePreview()
    }
    func prepareToLeave() -> Bool {
        guard hasUnsavedChanges else { return true }
        let alert = NSAlert(); alert.messageText = "保存对“\(document!.url.lastPathComponent)”的修改？"
        alert.informativeText = "未保存的修改在离开后将丢失。"; alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "不保存"); alert.addButton(withTitle: "取消")
        switch unsavedDecision?() ?? alert.runModal() { case .alertFirstButtonReturn: return save(); case .alertSecondButtonReturn: loading = true; text.string = document!.content; loading = false; updateState(); return true; default: return false }
    }
    func clear() { imageNeighborTask?.cancel();imageNeighbors=[];imageRequest?.cancel();imageRequest=nil;imageTask?.cancel();gallery?.clear();showingImageOverview=false; imageURL = nil; imageView.image = nil; checkTimer?.invalidate(); checkTimer = nil; previewTimer?.invalidate(); document = nil; loading = true; text.string = ""; loading = false }
    @discardableResult func save() -> Bool {
        guard var document else { return true }
        do { try document.save(text.string); self.document = document; updateState(); pane.app.message("已保存“\(document.url.lastPathComponent)”"); return true }
        catch { pane.app.showError(error); return false }
    }
    @objc func saveAction() { _ = save() }
    @objc func reloadDocument() {
        if let imageURL { if showingImageOverview { gallery?.loadImages(in:imageURL.deletingLastPathComponent(),selected:imageURL) } else { openImage(imageURL) }; return }
        guard let url = document?.url, prepareToLeave() else { return }
        do { let next = try TextDocument(url: url); document = next; loading = true; text.string = next.content; text.undoManager?.removeAllActions(); loading = false; updateState(); renderPreview() }
        catch { pane.app.showError(error) }
    }
    @objc func changeDisplayMode() {
        body.arrangedSubviews.forEach { body.removeArrangedSubview($0); $0.removeFromSuperview() }
        if imageURL != nil {
            let content:NSView = showingImageOverview ? gallery!.view : imageCanvas
            body.addArrangedSubview(content);content.heightAnchor.constraint(equalTo:body.heightAnchor).isActive=true;focusImagePreview();return
        }
        let segment = kind == .text ? 1 : modes.selectedSegment
        if segment != 0 { body.addArrangedSubview(sourceScroll); sourceScroll.heightAnchor.constraint(equalTo: body.heightAnchor).isActive = true }
        if segment != 1 { ensurePreviewLoaded(); body.addArrangedSubview(web); web.heightAnchor.constraint(equalTo: body.heightAnchor).isActive = true }
        formatButton.isHidden = kind != .json
        if segment != 0 { view.window?.makeFirstResponder(text) }
    }
    func textDidBeginEditing(_ notification: Notification) { pane.app.activePane = pane.index }
    func textDidChange(_ notification: Notification) {
        guard !loading else { return }; updateState(); previewTimer?.invalidate()
        previewTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in Task { @MainActor in self?.renderPreview() } }
    }
    func updateState() {
        view.toolTip = fileURL?.path; saveButton.isEnabled = hasUnsavedChanges
        info.stringValue = hasUnsavedChanges ? "有未保存的修改 · ⌘S 保存" : "\(kind.title) · 已保存"
    }
    func checkExternalChanges() {
        guard view.window != nil, let document, document.hasExternalChanges() else { return }
        info.stringValue = "文件已被外部修改或删除；重新载入前请保留需要的内容。"
    }
    @objc func formatJSON() {
        do {
            let data = Data(text.string.utf8), value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            let pretty = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])
            if let string = String(data: pretty, encoding: .utf8), text.shouldChangeText(in: NSRange(location: 0, length: (text.string as NSString).length), replacementString: string + "\n") {
                text.replaceCharacters(in: NSRange(location: 0, length: (text.string as NSString).length), with: string + "\n"); text.didChangeText()
            }
        } catch { pane.app.showError(error) }
    }
    func renderPreview() {
        guard previewReady, document != nil else { return }
        web.callAsyncJavaScript("window.renderPreview(payload)", arguments: ["payload": ["content": text.string, "kind": kind.rawValue, "dark": pane.palette.dark]], in: nil, in: .page) { [weak self] result in
            if case .failure = result { self?.info.stringValue = "预览生成失败，仍可编辑和保存源码。" }
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { previewReady = true; renderPreview() }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = action.request.url
        if action.navigationType == .linkActivated {
            if let url, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel); return
        }
        let allowedFile = url?.isFileURL == true && url?.lastPathComponent == "preview.html"
        let allowedFrame = url?.scheme == "about" && action.targetFrame?.isMainFrame == false
        decisionHandler(allowedFile || allowedFrame ? .allow : .cancel)
    }
}
