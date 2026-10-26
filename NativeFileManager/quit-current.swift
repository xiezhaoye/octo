import AppKit

// Request a normal quit so the running app can save its workspace or refuse
// termination while a file operation is in progress. Never force-kill it.
MainActor.assumeIsolated {
    let apps=NSRunningApplication.runningApplications(withBundleIdentifier:"com.xiezhaoye.dualpane")
    for app in apps{_ = app.terminate()}
    let deadline=Date().addingTimeInterval(6)
    while apps.contains(where:{!$0.isTerminated}) && Date()<deadline{RunLoop.current.run(until:Date().addingTimeInterval(0.05))}
    if apps.contains(where:{!$0.isTerminated}){print("APP_RESTART_BLOCKED：旧版仍在运行，可能正在操作文件；未强制退出。");exit(2)}
    print("APP_QUIT_OK：旧版已正常退出，工作区由应用自行保存。")
}
