import AppKit
import FileManagerCore

@MainActor final class AppUpdateController:NSViewController {
    unowned let app:AppController
    let status=label("点击“检查更新”获取最新版本。",size:13)
    let versionLabel=label("",size:15,weight:.semibold)
    let notes=label("",size:13)
    let progress=NSProgressIndicator()
    let checkButton=NSButton(title:"检查更新",target:nil,action:nil)
    let installButton=NSButton(title:"下载更新",target:nil,action:nil)
    var release:AppRelease?
    var prepared:PreparedAppUpdate?
    var task:Task<Void,Never>?
    var checkRelease:(() async throws ->AppRelease)?
    init(app:AppController){self.app=app;super.init(nibName:nil,bundle:nil)}
    required init?(coder:NSCoder){fatalError()}
    override func loadView() {
        let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "开发构建"
        let build=Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "—"
        versionLabel.stringValue="Octo \(version)（\(build)）"
        let icon=NSImageView(image:OctoBrand.logo ?? NSImage());icon.imageScaling = .scaleProportionallyUpOrDown;icon.widthAnchor.constraint(equalToConstant:60).isActive=true;icon.heightAnchor.constraint(equalToConstant:60).isActive=true
        let heading=rowStack([icon,versionLabel,spacer()],spacing:14)
        status.maximumNumberOfLines=3;status.lineBreakMode = .byWordWrapping;status.setAccessibilityLabel("更新状态")
        notes.maximumNumberOfLines=12;notes.lineBreakMode = .byWordWrapping;notes.textColor = .secondaryLabelColor
        progress.isIndeterminate=true;progress.style = .bar;progress.isHidden=true
        checkButton.target=self;checkButton.action=#selector(checkForUpdates)
        installButton.target=self;installButton.action=#selector(downloadOrInstall);installButton.isHidden=true
        let explanation=label("更新通过 Octo 下载服务提供，安装前校验文件完整性。\n安装并重启会先检查未保存的编辑，并保留工作区配置。",size:12);explanation.maximumNumberOfLines=3;explanation.lineBreakMode = .byWordWrapping;explanation.textColor = .secondaryLabelColor
        let stack=NSStackView(views:[heading,status,progress,notes,rowStack([checkButton,installButton,spacer()]),explanation,NSView()]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=18
        for child in stack.arrangedSubviews {child.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true}
        view=stack
    }
    func busy(_ enabled:Bool) {checkButton.isEnabled = !enabled;installButton.isEnabled = !enabled;progress.isHidden = !enabled;if enabled {progress.startAnimation(nil)}else{progress.stopAnimation(nil)}}
    @objc func checkForUpdates() {
        guard task == nil else{return};_ = view;if let prepared {try? FileManager.default.removeItem(at:prepared.directory)};release=nil;prepared=nil;installButton.isHidden=true;notes.stringValue="";busy(true);status.stringValue="正在检查更新…"
        task=Task { [weak self] in
            guard let self else{return};defer{busy(false);task=nil}
            do {
                let latest:AppRelease
                if let checkRelease {latest=try await checkRelease()}else{latest=try await AppUpdateService.shared.check()}
                let current=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.0.0"
                let build=Int(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "0") ?? 0
                if try latest.isNewer(than:current,build:build) {
                    release=latest;status.stringValue="发现新版本 \(latest.version)（\(latest.build)）";notes.stringValue=latest.notes.map{"• "+$0}.joined(separator:"\n");installButton.title="下载更新";installButton.isHidden=false
                } else {status.stringValue="当前已是最新版本（\(current)）。"}
            } catch {status.stringValue="检查失败：\(error.localizedDescription)。可稍后重试。"}
        }
    }
    @objc func downloadOrInstall() {
        if let prepared {
            app.updateInstallAction={try AppUpdateInstaller.launch(prepared:prepared,current:Bundle.main.bundleURL,waitingFor:ProcessInfo.processInfo.processIdentifier)}
            NSApp.terminate(nil)
            status.stringValue="安装已取消，更新包已保留。可再次点击“安装并重启”。"
            return
        }
        guard task == nil,let release else{return}
        busy(true);progress.isIndeterminate=false;progress.minValue=0;progress.maxValue=1;progress.doubleValue=0;status.stringValue="正在下载 \(release.version)…"
        task=Task { [weak self] in
            guard let self else{return};defer{busy(false);progress.isIndeterminate=true;task=nil}
            do {
                let candidate=try await AppUpdateService.shared.prepare(release) { [weak self] value in
                    Task{@MainActor in self?.progress.doubleValue=value}
                }
                prepared=candidate;status.stringValue="更新包已校验，安装后将重新打开 Octo。";installButton.title="安装并重启"
            } catch {status.stringValue="更新未安装：\(error.localizedDescription)。可重试。"}
        }
    }
}

struct PreparedAppUpdate:Sendable {let app:URL;let directory:URL}
private final class UpdateDownloadProgress:NSObject,URLSessionDownloadDelegate,@unchecked Sendable {
    let expected:Int64
    let changed:@Sendable(Double)->Void
    init(expected:Int64,changed:@escaping @Sendable(Double)->Void){self.expected=expected;self.changed=changed}
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didFinishDownloadingTo location:URL) {}
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didWriteData bytesWritten:Int64,totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64) {
        if totalBytesWritten>expected {downloadTask.cancel();return}
        changed(min(1,Double(totalBytesWritten)/Double(expected)))
    }
}

actor AppUpdateService {
    static let shared=AppUpdateService()
    static let feedURL=URL(string:"https://octo-dl.xiezhaoye.site/latest.json")!
    func check() async throws ->AppRelease {
        var request=URLRequest(url:Self.feedURL,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:20)
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        let (data,response)=try await URLSession.shared.data(for:request)
        guard let http=response as? HTTPURLResponse,http.statusCode==200,let final=response.url,AppRelease.allowed(final),data.count<128*1024 else{throw UpdateError.invalid("更新服务暂时不可用")}
        let release=try JSONDecoder().decode(AppRelease.self,from:data);try release.validate();return release
    }
    func prepare(_ release:AppRelease,progress:@escaping @Sendable(Double)->Void) async throws ->PreparedAppUpdate {
        try release.validate()
        #if !arch(arm64)
        throw UpdateError.invalid("当前更新包仅适用于 Apple Silicon")
        #endif
        let os=ProcessInfo.processInfo.operatingSystemVersion
        guard try ReleaseVersion("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)") >= ReleaseVersion(release.minimumSystemVersion) else{throw UpdateError.invalid("新版本需要 macOS \(release.minimumSystemVersion) 或以上")}
        let fm=FileManager.default
        let directory=fm.temporaryDirectory.appendingPathComponent("Octo-update-"+UUID().uuidString)
        try fm.createDirectory(at:directory,withIntermediateDirectories:true)
        var success=false
        defer{if !success {try? fm.removeItem(at:directory)}}
        let delegate=UpdateDownloadProgress(expected:release.bytes,changed:progress)
        var request=URLRequest(url:release.downloadURL,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:180)
        request.setValue("identity",forHTTPHeaderField:"Accept-Encoding")
        let (temporary,response)=try await URLSession.shared.download(for:request,delegate:delegate)
        defer{try? fm.removeItem(at:temporary)}
        guard let http=response as? HTTPURLResponse,http.statusCode==200,let final=response.url,AppRelease.allowed(final) else{throw UpdateError.invalid("安装包下载失败")}
        let archive=directory.appendingPathComponent("update.zip");try fm.moveItem(at:temporary,to:archive)
        try release.verify(archive)
        let extracted=directory.appendingPathComponent("extracted");try fm.createDirectory(at:extracted,withIntermediateDirectories:true)
        try AppUpdateInstaller.run("/usr/bin/ditto",["-x","-k",archive.path,extracted.path])
        let candidate=extracted.appendingPathComponent("Octo.app")
        guard let bundle=Bundle(url:candidate),bundle.bundleIdentifier == "com.xiezhaoye.dualpane",
              bundle.object(forInfoDictionaryKey:"CFBundleExecutable") as? String == "DualPane",
              bundle.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String == release.version,
              bundle.object(forInfoDictionaryKey:"CFBundleVersion") as? String == String(release.build),
              let minimum=bundle.object(forInfoDictionaryKey:"LSMinimumSystemVersion") as? String,
              try ReleaseVersion("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)") >= ReleaseVersion(minimum) else{throw UpdateError.invalid("安装包身份、版本或系统要求不匹配")}
        guard AppRelease.supportsArm64Executable(try Data(contentsOf:candidate.appendingPathComponent("Contents/MacOS/DualPane"),options:.mappedIfSafe)) else{throw UpdateError.invalid("安装包不包含 Apple Silicon 可执行程序")}
        try AppUpdateInstaller.run("/usr/bin/codesign",["--verify","--deep","--strict",candidate.path])
        success=true;return PreparedAppUpdate(app:candidate,directory:directory)
    }
}

/// The helper starts only after applicationShouldTerminate has approved saving/exit.
/// All paths are arguments, never interpolated into shell code. A same-volume staged
/// replacement retains the old app until the new app is in place.
enum AppUpdateInstaller {
    static func run(_ tool:String,_ arguments:[String]) throws {
        let process=Process();process.executableURL=URL(fileURLWithPath:tool);process.arguments=arguments
        let pipe=Pipe();process.standardError=pipe;process.standardOutput=FileHandle.nullDevice
        try process.run();let data=pipe.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
        guard process.terminationStatus==0 else{throw UpdateError.invalid(String(data:data,encoding:.utf8) ?? "更新准备失败")}
    }
    static let helper="""
    set -eu
    PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
    pid="$1"; current="$2"; staged="$3"; backup="$4"; work="$5"; reopen="$6"
    count=0
    while [ "$pid" -gt 0 ] && kill -0 "$pid" 2>/dev/null; do
      count=$((count + 1)); [ "$count" -lt 120 ] || exit 2
      sleep 1
    done
    [ -d "$current" ] && [ -d "$staged" ] && [ ! -e "$backup" ] || exit 3
    /bin/mv "$current" "$backup"
    if /bin/mv "$staged" "$current"; then
      if [ "$reopen" = "yes" ]; then
        if ! /usr/bin/open -n "$current"; then
          /bin/mv "$current" "$staged"
          /bin/mv "$backup" "$current"
          /usr/bin/open -n "$current" || true
          exit 4
        fi
      fi
      /bin/rm -rf "$work"
    else
      /bin/mv "$backup" "$current"
      if [ "$reopen" = "yes" ]; then /usr/bin/open -n "$current" || true; fi
      exit 5
    fi
    """
    @discardableResult static func launch(prepared:PreparedAppUpdate,current:URL,waitingFor pid:Int32,reopen:Bool=true) throws ->Process {
        let fm=FileManager.default,parent=current.deletingLastPathComponent()
        guard current.pathExtension == "app",fm.isWritableFile(atPath:parent.path),!current.path.contains("/AppTranslocation/") else{throw UpdateError.invalid("此位置无法安装更新，请先将 Octo 移到可写的应用程序目录")}
        let token=UUID().uuidString,staged=parent.appendingPathComponent(".Octo-update-"+token+".app"),backup=parent.appendingPathComponent(".Octo-backup-"+token+".app")
        try run("/usr/bin/ditto",[prepared.app.path,staged.path])
        do {
            try run("/usr/bin/codesign",["--verify","--deep","--strict",staged.path])
            let script=prepared.directory.appendingPathComponent("install.sh");try Data(helper.utf8).write(to:script,options:.atomic)
            let log=prepared.directory.appendingPathComponent("install.log");fm.createFile(atPath:log.path,contents:nil)
            let process=Process();process.executableURL=URL(fileURLWithPath:"/bin/sh");process.arguments=[script.path,String(pid),current.path,staged.path,backup.path,prepared.directory.path,reopen ? "yes":"no"]
            let handle=try FileHandle(forWritingTo:log);process.standardOutput=handle;process.standardError=handle
            try process.run();try? handle.close();return process
        } catch {try? fm.removeItem(at:staged);throw error}
    }
}
