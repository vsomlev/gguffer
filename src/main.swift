import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowController: MainWindowController?
    private lazy var settingsController = SettingsWindowController()
    private var pendingModel: URL?
    private var didFinishLaunching = false

    // MARK: - Launching

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: \.isFileURL) else { return }
        if didFinishLaunching {
            present(model: url)
        } else {
            pendingModel = url
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        NSApp.activate(ignoringOtherApps: true)

        if let pendingModel {
            self.pendingModel = nil
            present(model: pendingModel)
            return
        }
        // Nothing was opened with us — but let a file event still in flight land first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.windowController == nil else { return }
            self.chooseModel(orQuit: true)
        }
    }

    // MARK: - Model selection

    @objc func showSettings(_ sender: Any?) {
        settingsController.present()
    }

    @objc func openDocument(_ sender: Any?) {
        chooseModel(orQuit: false)
    }

    private func chooseModel(orQuit: Bool) {
        let panel = NSOpenPanel()
        panel.message = "Choose a GGUF model:"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let type = UTType(filenameExtension: "gguf") {
            panel.allowedContentTypes = [type]
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            if orQuit { NSApp.terminate(nil) }
            return
        }
        present(model: url)
    }

    private func present(model: URL) {
        guard let controller = windowController else {
            let controller = MainWindowController(model: model)
            windowController = controller
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            // Settings must not keep the app alive once the main window goes.
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: controller.window, queue: .main
            ) { [weak self] _ in
                self?.settingsController.close()
            }
            return
        }

        controller.confirmStop(
            question: "Stop llama-server and open another model?", verb: "Stop and Open"
        ) { proceed in
            guard proceed else { return }
            controller.load(model: model)
            controller.window?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Quitting

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller = windowController, controller.isRunning else { return .terminateNow }
        controller.confirmStop { proceed in
            NSApp.reply(toApplicationShouldTerminate: proceed)
        }
        return .terminateLater
    }
}

// MARK: - Menu

private func makeMainMenu() -> NSMenu {
    let mainMenu = NSMenu()

    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(
        withTitle: "About gguffer", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
        keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addItem(
        withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
    appMenu.addItem(.separator())
    appMenu.addItem(
        withTitle: "Hide gguffer", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    appMenu.addItem(.separator())
    appMenu.addItem(
        withTitle: "Quit gguffer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    mainMenu.addItem(appItem)

    let fileItem = NSMenuItem()
    let fileMenu = NSMenu(title: "File")
    fileMenu.addItem(
        withTitle: "Open Model…", action: #selector(AppDelegate.openDocument(_:)), keyEquivalent: "o")
    fileMenu.addItem(.separator())
    fileMenu.addItem(
        withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    fileItem.submenu = fileMenu
    mainMenu.addItem(fileItem)

    // Just the text-editing essentials: AppKit routes ⌘X/⌘C/⌘V/⌘A through
    // these menu items, so without them those keys do nothing anywhere in the
    // app — including pasting flags into the parameters dialog.
    let editItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(
        withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = editMenu
    mainMenu.addItem(editItem)

    let serverItem = NSMenuItem()
    let serverMenu = NSMenu(title: "Server")
    serverMenu.addItem(
        withTitle: "Start", action: #selector(MainWindowController.toggleServer(_:)),
        keyEquivalent: "s")
    let startWithParamsItem = serverMenu.addItem(
        withTitle: "Start with Params…",
        action: #selector(MainWindowController.startWithParameters(_:)), keyEquivalent: "s")
    startWithParamsItem.keyEquivalentModifierMask = [.command, .option]
    serverMenu.addItem(.separator())
    serverMenu.addItem(
        withTitle: "Open llama-ui", action: #selector(MainWindowController.openInBrowser(_:)),
        keyEquivalent: "l")
    serverMenu.addItem(.separator())
    let copyCommandItem = serverMenu.addItem(
        withTitle: "Copy Command", action: #selector(MainWindowController.copyCommand(_:)),
        keyEquivalent: "c")
    copyCommandItem.keyEquivalentModifierMask = [.command, .option]
    serverItem.submenu = serverMenu
    mainMenu.addItem(serverItem)

    return mainMenu
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.mainMenu = makeMainMenu()
application.setActivationPolicy(.regular)
application.run()
