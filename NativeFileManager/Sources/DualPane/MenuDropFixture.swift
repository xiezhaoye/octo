import AppKit

/// Opt-in native smoke tests exercise the same pasteboard/validation/drop callbacks as AppKit.
@MainActor final class MenuDropFixture: NSObject, @preconcurrency NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingDestinationWindow: NSWindow?
    let draggingSource: Any?
    let draggingSourceOperationMask: NSDragOperation = .move
    let draggingLocation = NSPoint.zero
    let draggedImageLocation = NSPoint.zero
    let draggedImage: NSImage? = nil
    let draggingSequenceNumber = 1
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    let springLoadingHighlight: NSSpringLoadingHighlight = .none
    init(pasteboard:NSPasteboard,source:NSTableView,window:NSWindow?) { draggingPasteboard=pasteboard;draggingSource=source;draggingDestinationWindow=window;super.init() }
    func slideDraggedImage(to screenPoint:NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination:URL)->[String]? {nil}
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts:NSDraggingItemEnumerationOptions,for view:NSView?,classes classArray:[AnyClass],searchOptions:[NSPasteboard.ReadingOptionKey:Any],using block:(NSDraggingItem,Int,UnsafeMutablePointer<ObjCBool>)->Void) {}
}
