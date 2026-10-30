import AppKit
import FileManagerCore

extension PaneController {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems(); app.activePane = index
        var previousGroup:ContextCommandGroup?
        func append(_ item:NSMenuItem,key:String) {
            let group=ContextCommandGroup.group(for:key,overrides:app.state.contextCommandGroups)
            if let previousGroup,previousGroup != group {menu.addItem(.separator())}
            menu.addItem(item);previousGroup=group
        }
        for key in ContextMenuOrder.groupedKeys(saved: app.state.contextMenuOrder, commands: app.state.commands,groups:app.state.contextCommandGroups) {
            if let builtin = BuiltinContextCommand(rawValue: key) {
                guard let item = contextMenuItem(builtin) else { continue }
                item.identifier = .init(key); append(item,key:key)
            } else if let command = app.state.commands.first(where: { ContextMenuOrder.key(for: $0) == key }), command.applies(to: selectedURLs, directory: contextualDirectory) {
                let item = NSMenuItem(title: command.name, action: #selector(runCommand(_:)), keyEquivalent: "")
                item.identifier = .init(key); item.target = self; item.representedObject = command.id; append(item,key:key)
            }
        }
    }
    func contextMenuItem(_ command: BuiltinContextCommand) -> NSMenuItem? {
        let hasSelection = !selectedURLs.isEmpty
        switch command {
        case .open, .openWith, .preview, .copy, .rename, .trash: guard hasSelection else { return nil }
        case .expandAll, .collapseAll: guard app.state.panes[index].mode == .list else { return nil }
        default: break
        }
        if command == .openWith {return openWithMenu(urls:selectedURLs)}
        if command == .folderTags {
            let urls = hasSelection ? selectedURLs : [contextualDirectory]
            return folderTagMenu(urls:urls,workspace:app.state) { [weak self] color,enabled in self?.applyFolderTag(color,enabled:enabled,urls:urls) }
        }
        if command == .newFile {
            let temporary = NSMenu(); addNewDocumentMenu(to: temporary)
            let item = temporary.items[0]; temporary.removeItem(item); return item
        }
        let action: Selector
        var target: AnyObject = self
        switch command {
        case .copyPath: action = #selector(copyPath)
        case .copyDirectoryPath: action = #selector(copyDirectoryPath)
        case .openTerminal: action = #selector(openTerminal)
        case .open: action = #selector(openSelection)
        case .preview: action = #selector(showFilePreview)
        case .copy: action = #selector(AppController.copyFiles); target = app
        case .rename: action = #selector(renameFromMenu)
        case .trash: action = #selector(trashFromMenu)
        case .paste: action = #selector(AppController.pasteFiles); target = app
        case .moveHere: action = #selector(AppController.moveFiles); target = app
        case .newFolder: action = #selector(newFolderFromMenu)
        case .expandAll: action = #selector(expandAll)
        case .collapseAll: action = #selector(collapseAll)
        case .termius: action = #selector(openTermius)
        case .toggleHidden: action = #selector(toggleHidden)
        case .manageCommands: action = #selector(AppController.manageContextCommands); target = app
        case .newFile, .folderTags, .openWith: return nil
        }
        let title = command == .toggleHidden ? (app.state.panes[index].showHidden ? "隐藏隐藏项目" : "显示隐藏项目") : command.title
        let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = target; return item
    }
}
