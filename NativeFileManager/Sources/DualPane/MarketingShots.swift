import AppKit
import ImageIO
import UniformTypeIdentifiers
import FileManagerCore

extension AppController {
    /// Opt-in product captures use synthetic files inside the explicitly supplied fixture directory.
    func runMarketingShots(at output:URL) {
        Task { @MainActor in
            do {
                let fm=FileManager.default
                let data=output.appendingPathComponent("Octo 演示/工作资料"),project=data.appendingPathComponent("设计项目"),docs=data.appendingPathComponent("产品文档"),photos=data.appendingPathComponent("摄影素材"),delivery=data.appendingPathComponent("交付物"),archive=data.appendingPathComponent("工作档案")
                for directory in [project,docs,photos,delivery,archive] {try fm.createDirectory(at:directory,withIntermediateDirectories:true)}
                let markdown="""
                # Octo 产品计划

                两个目录并排，常用位置按组整理。

                ## 本周交付
                - [x] 完成界面视觉方案
                - [x] 整理产品截图
                - [ ] 打包发布新版本

                ## 工作安排
                | 阶段 | 内容 |
                | --- | --- |
                | 设计 | 导航与文件列表 |
                | 开发 | 预览与快捷操作 |
                | 交付 | 安装包与使用说明 |

                > 文件留在原位，思路保持清楚。
                """
                try Data(markdown.utf8).write(to:docs.appendingPathComponent("产品计划.md"))
                try Data("{\n  \"project\": \"Octo\",\n  \"version\": \"0.6.0\",\n  \"layout\": {\n    \"panes\": 2,\n    \"groups\": true\n  },\n  \"preview\": [\"Markdown\", \"HTML\", \"JSON\", \"图片\"]\n}\n".utf8).write(to:docs.appendingPathComponent("项目配置.json"))
                try Data("<!doctype html><html lang=\"zh-CN\"><meta charset=\"utf-8\"><style>body{font:16px -apple-system;padding:24px;color:#273944}h1{font-size:32px;color:#d96242}.tag{display:inline-block;padding:8px 12px;background:#eaf1f5;border-radius:9px}li{margin:14px 0}</style><h1>工作，一目了然。</h1><p>把常用文件夹按组放好，让两个目录各自从容。</p><p class=\"tag\">Octo · 原生 Mac 工作台</p><h2>产品要点</h2><ul><li>双栏独立浏览目录</li><li>分组整理常用位置</li><li>在文件旁直接预览</li></ul></html>".utf8).write(to:docs.appendingPathComponent("产品介绍.html"))
                for name in ["会议记录.txt","数据清单.csv","环境配置.yaml","构建参数.toml"] {try Data("Octo 演示文件\n文件留在原位，常用位置按组整理。\n".utf8).write(to:docs.appendingPathComponent(name))}
                for name in ["01 设计源文件","02 交互原型","03 评审资料","04 字体与图标"] {try fm.createDirectory(at:project.appendingPathComponent(name),withIntermediateDirectories:true)}
                for name in ["设计说明.md","交付检查表.txt","资源清单.json"] {try Data((name.hasSuffix(".json") ? "{\"ready\":true}":"# 设计交付\n导航、分组、预览与文件操作。").utf8).write(to:project.appendingPathComponent(name))}
                for name in ["客户确认","发布文档","最终截图","历史版本"] {try fm.createDirectory(at:delivery.appendingPathComponent(name),withIntermediateDirectories:true)}
                for name in ["使用说明.md","版本记录.txt","交付清单.json"] {try Data((name.hasSuffix(".json") ? "{\"version\":\"0.6.0\"}":"# Octo 交付资料\n双栏分组工作台。").utf8).write(to:delivery.appendingPathComponent(name))}
                let names=["01 云海远山","02 海岸晨光","03 山谷微风","04 日落湖畔","05 林间清晨","06 远方的岛","07 群山入暮","08 湖面倒影","09 初夏原野","10 海边散步","11 山间小径","12 蓝色时刻"]
                for (index,name) in names.enumerated() {
                    let size=NSSize(width:1440,height:1000),image=NSImage(size:size)
                    image.lockFocus()
                    let skies:[(UInt32,UInt32)]=[(0xBCDDE5,0xF7E2C0),(0xA9D5DD,0xF3D9C2),(0xB8D4C7,0xF1E6C8),(0xF0B9A8,0xF6DFB6),(0xBCD6CB,0xEAF0D7),(0xB1D6E4,0xE3EBE0)]
                    let tones=skies[index%skies.count]
                    NSGradient(starting:Palette.color(tones.0),ending:Palette.color(tones.1))!.draw(in:NSRect(origin:.zero,size:size),angle:270)
                    Palette.color(0xFFF4D3).withAlphaComponent(0.8).setFill();NSBezierPath(ovalIn:NSRect(x:950-CGFloat(index%3)*170,y:640,width:135,height:135)).fill()
                    for layer in 0..<4 {
                        let mountain=NSBezierPath();mountain.move(to:NSPoint(x:0,y:0));mountain.line(to:NSPoint(x:0,y:330-CGFloat(layer*60)))
                        for step in 0...10 {
                            let x=CGFloat(step)*160
                            let y=CGFloat(350-layer*65)+sin(CGFloat(step)*0.9+CGFloat(index)*0.7+CGFloat(layer))*CGFloat(90-layer*10)
                            mountain.line(to:NSPoint(x:x,y:y))
                        }
                        mountain.line(to:NSPoint(x:1440,y:0));mountain.close()
                        let shades:[UInt32]=index%2 == 0 ? [0x9FBAB3,0x769E94,0x4F8075,0x315F57]:[0x9CB4C4,0x759CA8,0x4F7F90,0x315E75]
                        Palette.color(shades[layer]).setFill();mountain.fill()
                    }
                    image.unlockFocus()
                    let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
                    try bitmap.representation(using:.jpeg,properties:[.compressionFactor:0.9])!.write(to:photos.appendingPathComponent(name+".jpg"))
                }
                state=Workspace();state.skin = .native
                state.panes[0].groups=[FolderGroup(name:"项目",entries:[FolderEntry(path:project.path),FolderEntry(path:docs.path)]),FolderGroup(name:"素材",entries:[FolderEntry(path:photos.path),FolderEntry(path:archive.path)])]
                state.panes[1].groups=[FolderGroup(name:"交付",entries:[FolderEntry(path:delivery.path),FolderEntry(path:docs.path)]),FolderGroup(name:"归档",entries:[FolderEntry(path:archive.path),FolderEntry(path:photos.path)])]
                state.setFolderColor(.orange,enabled:true,at:project);state.setFolderColor(.blue,enabled:true,at:docs);state.setFolderColor(.green,enabled:true,at:delivery)
                applyAppearance();applyVisibility();panes.forEach{$0.reloadSidebar()};window.setContentSize(NSSize(width:1600,height:850));window.center()
                @MainActor func settle() async {try? await Task.sleep(nanoseconds:700_000_000);window.contentView?.layoutSubtreeIfNeeded();window.displayIfNeeded()}
                @MainActor func navigate(_ pane:PaneController,_ directory:URL,_ mode:Int) async {
                    pane.modeControl.selectedSegment=mode;pane.modeChanged();pane.navigate(to:directory);await pane.loadTask?.value;await settle()
                }
                @MainActor func open(_ pane:PaneController,_ file:URL) async throws {
                    guard let column=pane.columnControllers.last,let row=column.files.firstIndex(where:{$0.url.path == file.path}) else{throw UpdateError.invalid("截图文件未找到")}
                    column.table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)
                    if let task=pane.editor.imageTask {await task.value};if let task=pane.editor.imageNeighborTask {await task.value}
                    await settle();await settle()
                }
                @MainActor func capture(_ name:String) async throws {
                    messageTimer?.invalidate();operationStatusView.isHidden=true
                    window.setContentSize(NSSize(width:1600,height:850));await settle()
                    guard let view=window.contentView?.superview,let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{throw UpdateError.invalid("无法导出产品截图")}
                    view.cacheDisplay(in:view.bounds,to:bitmap)
                    try bitmap.representation(using:.jpeg,properties:[.compressionFactor:0.88])!.write(to:output.appendingPathComponent(name+".jpg"))
                }
                await navigate(panes[0],project,0);await navigate(panes[1],delivery,0)
                panes[0].list.selectRowIndexes(IndexSet(integer:4),byExtendingSelection:false);activePane=0;await settle();try await capture("octo-dual-groups")
                await navigate(panes[0],docs,1);await navigate(panes[1],docs,1)
                try await open(panes[0],docs.appendingPathComponent("产品计划.md"));try await open(panes[1],docs.appendingPathComponent("产品介绍.html"));await settle();try await capture("octo-document-preview")
                try await open(panes[0],docs.appendingPathComponent("项目配置.json"));panes[1].editor.modes.selectedSegment=2;panes[1].editor.changeDisplayMode();await settle();try await capture("octo-json-preview")
                await navigate(panes[1],photos,1);try await open(panes[1],photos.appendingPathComponent(names[3]+".jpg"));await settle();try await capture("octo-image-browsing")
                panes[1].editor.nextImage();await panes[1].editor.imageTask?.value;await settle()
                guard panes[1].editor.imageURL?.lastPathComponent == names[4]+".jpg" else{throw UpdateError.invalid("图片下一张切换失败")}
                panes[1].editor.showImageOverview();await panes[1].editor.gallery?.loadTask?.value;await settle();await settle();try await capture("octo-image-overview")
                await navigate(panes[0],docs,2);await navigate(panes[1],photos,2);await settle();await settle();try await capture("octo-icons")
                let imageTypes=(CGImageSourceCopyTypeIdentifiers() as! [String]).compactMap{UTType($0)}.flatMap{($0.tags[.filenameExtension] ?? [])}.sorted()
                let report:[String:Any]=["version":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "unknown","imageExtensions":Array(Set(imageTypes)).sorted(),"screenshots":["octo-dual-groups","octo-document-preview","octo-json-preview","octo-image-browsing","octo-image-overview","octo-icons"],"note":"真实应用界面，全部使用独立目录中的演示文件与原创示意图片。"]
                try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("capture-report.json"))
                print("MARKETING_SHOTS_PASS::"+output.path);NSApp.terminate(nil)
            } catch {print("MARKETING_SHOTS_FAIL::"+error.localizedDescription);exit(1)}
        }
    }
}
