import AppKit
import FileManagerCore

@MainActor final class ImageGallery: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    unowned let editor: DocumentEditor
    let collection = ImageGalleryCollection()
    let scroll = NSScrollView()
    var records: [FileRecord] = []
    var loadTask: Task<Void, Never>?
    var generation = UUID()
    init(editor:DocumentEditor) { self.editor=editor;super.init(nibName:nil,bundle:nil) }
    required init?(coder:NSCoder) { fatalError() }
    override func loadView() {
        view=NSView()
        let layout=NSCollectionViewFlowLayout();layout.itemSize=NSSize(width:112,height:120);layout.minimumInteritemSpacing=8;layout.minimumLineSpacing=10;layout.sectionInset=NSEdgeInsets(top:12,left:12,bottom:12,right:12)
        collection.collectionViewLayout=layout;collection.dataSource=self;collection.delegate=self;collection.isSelectable=true;collection.allowsMultipleSelection=false;collection.gallery=self
        collection.register(FileTile.self,forItemWithIdentifier:.init("image"));collection.setAccessibilityLabel("当前文件夹图片缩略图，双击或按回车预览")
        let click=NSClickGestureRecognizer(target:self,action:#selector(activateSelection));click.numberOfClicksRequired=2;collection.addGestureRecognizer(click)
        scroll.documentView=collection;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;pin(scroll,in:view)
        collection.backgroundColors=[editor.pane.palette.canvas];scroll.backgroundColor=editor.pane.palette.canvas
    }
    func loadImages(in directory:URL, selected:URL) {
        _=view;loadTask?.cancel();let token=UUID();generation=token
        loadTask=Task { @MainActor in
            do {
                let files=try await editor.pane.reader.contents(of:directory,showHidden:editor.pane.app.state.panes[editor.pane.index].showHidden)
                guard !Task.isCancelled,generation==token else{return}
                records=files.filter{!$0.directory && DocumentEditor.isImage($0.url)};collection.reloadData();collection.layoutSubtreeIfNeeded()
                if let index=records.firstIndex(where:{$0.url==selected.standardizedFileURL}) {
                    let path=IndexPath(item:index,section:0);collection.selectionIndexPaths=[path];collection.scrollToItems(at:[path],scrollPosition:.centeredVertically)
                }
                editor.info.stringValue="\(records.count) 张图片 · ←/→ 选择 · 回车或双击预览"
            } catch { if !Task.isCancelled { editor.info.stringValue=error.localizedDescription } }
        }
    }
    func clear() { loadTask?.cancel();generation=UUID();guard isViewLoaded else{return};collection.visibleItems().forEach{($0 as? FileTile)?.cancelThumbnail()};records=[];collection.reloadData() }
    func collectionView(_ collectionView:NSCollectionView,numberOfItemsInSection section:Int)->Int {records.count}
    func collectionView(_ collectionView:NSCollectionView,itemForRepresentedObjectAt indexPath:IndexPath)->NSCollectionViewItem {
        let item=collectionView.makeItem(withIdentifier:.init("image"),for:indexPath) as! FileTile
        item.configure(records[indexPath.item],palette:editor.pane.palette);return item
    }
    func collectionView(_ collectionView:NSCollectionView,didEndDisplaying item:NSCollectionViewItem,forRepresentedObjectAt indexPath:IndexPath) { (item as? FileTile)?.cancelThumbnail() }
    @objc func activateSelection() {
        guard let path=collection.selectionIndexPaths.first,records.indices.contains(path.item) else{return}
        editor.openGalleryImage(records[path.item].url)
    }
}

@MainActor final class ImageGalleryCollection:NSCollectionView {
    weak var gallery:ImageGallery?
    override func keyDown(with event:NSEvent) {
        if event.keyCode==36 || event.keyCode==76 {gallery?.activateSelection();return}
        super.keyDown(with:event)
    }
}
