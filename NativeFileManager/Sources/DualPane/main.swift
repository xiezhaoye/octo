import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let controller = AppController()
    app.delegate = controller
    app.setActivationPolicy(.regular)
    withExtendedLifetime(controller) { app.run() }
}
