import AppKit
import UniformTypeIdentifiers
import FileManagerCore

@MainActor final class FileApplicationItem:NSMenuItem {
    let application:URL?
    let files:[URL]
    weak var pane:PaneController?
    init(title:String,application:URL?,files:[URL],pane:PaneController) {
        self.application=application;self.files=files;self.pane=pane
        super.init(title:title,action:nil,keyEquivalent:"");target=self;action=#selector(openFiles)
        if let application {let icon=NSWorkspace.shared.icon(forFile:application.path);icon.size=NSSize(width:16,height:16);image=icon}
    }
    required init(coder:NSCoder){fatalError()}
    @objc func openFiles() {
        guard let pane else{return}
        if let application {pane.launchFiles(files,with:application);return}
        let panel=NSOpenPanel();panel.title="选择打开这些文件的应用";panel.allowedContentTypes=[.application];panel.directoryURL=URL(fileURLWithPath:"/Applications");panel.canChooseDirectories=false;panel.allowsMultipleSelection=false
        panel.beginSheetModal(for:pane.app.window) { [weak pane] result in
            guard result == .OK,let application=panel.url else{return}
            Task{@MainActor in pane?.launchFiles(self.files,with:application)}
        }
    }
}

@MainActor extension PaneController {
    func openWithMenu(urls:[URL])->NSMenuItem? {
        guard !urls.isEmpty,urls.allSatisfy({(try? FileRecord(url:$0).browsable) == false}) else{return nil}
        let menu=NSMenu(title:"打开方式")
        let applications=NSWorkspace.shared.urlsForApplications(toOpen:urls[0]).filter {app in
            urls.dropFirst().allSatisfy{NSWorkspace.shared.urlsForApplications(toOpen:$0).contains(app)}
        }
        let preferred=NSWorkspace.shared.urlForApplication(toOpen:urls[0])
        let defaultApp=urls.allSatisfy{NSWorkspace.shared.urlForApplication(toOpen:$0) == preferred} ? preferred:nil
        for application in applications {
            let name=FileManager.default.displayName(atPath:application.path)
            let title=name+(application == defaultApp ? "（默认）":"")
            menu.addItem(FileApplicationItem(title:title,application:application,files:urls,pane:self))
        }
        if !applications.isEmpty {menu.addItem(.separator())}
        menu.addItem(FileApplicationItem(title:"选择其他应用…",application:nil,files:urls,pane:self))
        let item=NSMenuItem(title:"打开方式",action:nil,keyEquivalent:"");item.submenu=menu;return item
    }
    func launchFiles(_ files:[URL],with application:URL) {
        let configuration=NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(files,withApplicationAt:application,configuration:configuration) { [weak self] _,error in
            if let error {Task{@MainActor in self?.app.showError(error)}}
        }
    }
}
