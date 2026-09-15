import AppKit

/// The single gguffer window: a unified toolbar carrying the model name, the
/// server's status and the start/stop button, over a parameters field and the
/// server's log.
final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation,
    NSToolbarDelegate
{

    private let server = ServerController()
    private var model: URL
    private var binary: String?
    private var savedParams = ""
    private var isConfirming = false
    private var pendingShutdown: ((Bool) -> Void)?

    private let modelLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let statusIcon = StatusIndicatorView()
    private let runButton = NSButton(title: "Start", target: nil, action: nil)
    private let browserButton = NSButton(title: "", target: nil, action: nil)
    private let logView = LogView(frame: .zero)

    var isRunning: Bool { server.isRunning }

    /// Everything that follows the model on the command line: the reasoning
    /// flag, the parameters set for every run, then this model's own — last, so
    /// that llama-server's last-wins parsing lets them override the rest.
    private var launchParameters: String {
        [Settings.reasoning.flag, Settings.extraParameters, savedParams]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// What Start with Params… shows: this model's own parameters, or the
    /// every-run ones when the model has none of its own.
    private var promptParameters: String {
        savedParams.isEmpty ? Settings.extraParameters : savedParams
    }

    /// Where the running server said it is listening, once it has said so.
    private var listeningURL: URL? {
        if case .running(let url) = status { return url }
        return nil
    }

    private var status: ServerStatus = .notLoaded {
        didSet {
            statusIcon.status = status
            statusLabel.stringValue = status.text
            statusItemView.toolTip = status.detail
            browserButton.isEnabled = listeningURL != nil
        }
    }

    private lazy var statusItemView: NSView = {
        let container = NSView()
        for view in [statusIcon, statusLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            statusIcon.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            // An SF Symbol image reserves descender space below the glyph, so
            // centring the image box leaves the glyph riding high — measured at
            // 3pt for this symbol size against a 12pt label.
            statusIcon.centerYAnchor.constraint(
                equalTo: statusLabel.centerYAnchor, constant: Self.iconNudge),
            statusLabel.leadingAnchor.constraint(equalTo: statusIcon.trailingAnchor, constant: 5),
            statusLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusLabel.topAnchor.constraint(equalTo: container.topAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }()

    private static let iconNudge: CGFloat = 3

    init(model: URL) {
        self.model = model

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.minSize = NSSize(width: 560, height: 320)
        window.setFrameAutosaveName("GgufferMainWindow")
        super.init(window: window)

        window.delegate = self
        buildToolbar()
        buildLayout()
        wireServer()
        binary = ServerController.resolveBinary()
        load(model: model)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Toolbar

    private func buildToolbar() {
        modelLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        modelLabel.lineBreakMode = .byTruncatingMiddle
        modelLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor

        browserButton.bezelStyle = .rounded
        browserButton.controlSize = .large
        browserButton.imagePosition = .imageLeading
        browserButton.title = "llama-ui"
        browserButton.image = NSImage(
            systemSymbolName: "globe", accessibilityDescription: "Open llama-ui")?
            .withTrailingPadding(6)
        browserButton.toolTip = "Open llama-server's chat interface in your browser"
        browserButton.target = self
        browserButton.action = #selector(openInBrowser(_:))
        browserButton.isEnabled = false

        runButton.bezelStyle = .rounded
        runButton.controlSize = .large
        runButton.imagePosition = .imageLeading
        runButton.target = self
        runButton.action = #selector(toggleServer(_:))
        runButton.keyEquivalent = "\r"

        let toolbar = NSToolbar(identifier: "GgufferToolbar")
        toolbar.delegate = self
        // Items are custom views with their own labels; the toolbar's own label
        // row would only add empty space under them.
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        if #available(macOS 15.0, *) {
            // Drop "Icon and Text" etc. from the toolbar's context menu, so the
            // display mode cannot be changed out from under the layout.
            toolbar.allowsDisplayModeCustomization = false
        }

        window?.toolbar = toolbar
        window?.toolbarStyle = .unified
        // The toolbar is the title bar: only the traffic lights remain of it.
        window?.titleVisibility = .hidden
        // A unified toolbar draws a hairline under itself that
        // titlebarSeparatorStyle does not remove on current macOS; a
        // transparent titlebar does, and blends the toolbar into the content.
        window?.titlebarAppearsTransparent = true
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.model, .status, .flexibleSpace, .browser, .run]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.isBordered = false
        switch identifier {
        case .model:
            item.view = modelLabel
            item.visibilityPriority = .high
        case .status:
            item.view = statusItemView
            item.visibilityPriority = .high
        case .browser:
            item.view = browserButton
            item.visibilityPriority = .high
        case .run:
            item.view = runButton
            item.visibilityPriority = .high
        default:
            return nil
        }
        return item
    }

    // MARK: - Layout

    private func buildLayout() {
        // The log is the whole window below the toolbar, edge to edge.
        guard let content = window?.contentView else { return }
        logView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(logView)
        NSLayoutConstraint.activate([
            logView.topAnchor.constraint(equalTo: content.topAnchor),
            logView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            logView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            logView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    private func wireServer() {
        server.onOutput = { [weak self] text in
            guard let self else { return }
            self.logView.append(text)
            self.readStatus(from: text)
        }
        server.onExit = { [weak self] status, reason in self?.serverExited(status, reason) }
    }

    /// Promotes the status as llama-server announces its progress. The address
    /// may arrive in a later chunk than "model loaded", so a running server
    /// without one keeps watching for it.
    private func readStatus(from output: String) {
        switch status {
        case .loading:
            if let url = ServerStatus.listeningURL(in: output) {
                status = .running(url)
            } else if ServerStatus.indicatesReady(output) {
                status = .running(nil)
            }
        case .running(let known) where known == nil:
            if let url = ServerStatus.listeningURL(in: output) { status = .running(url) }
        default:
            break
        }
    }

    // MARK: - Model

    func load(model: URL) {
        self.model = model
        savedParams = Config.params(for: model)
        modelLabel.stringValue = model.lastPathComponent
        modelLabel.toolTip = model.path
        window?.title = model.lastPathComponent
        logView.clear()

        if binary == nil {
            status = .stopped("llama-server not found")
            runButton.isEnabled = false
            logView.append(
                "llama-server was not found on your PATH.\n"
                    + "Install llama.cpp (brew install llama.cpp), then reopen this model.\n",
                isNote: true)
        } else {
            setIdle(status: .notLoaded)
            if Settings.loadModelOnStart {
                // Let the window finish appearing before the log starts filling.
                DispatchQueue.main.async { [weak self] in self?.startServer() }
            }
        }
    }

    // MARK: - Actions

    @objc func toggleServer(_ sender: Any?) {
        guard !server.isRunning else {
            stopServer()
            return
        }
        // Option-clicking Start asks for parameters first, like the menu item.
        if isOptionHeld, sender as AnyObject? === runButton {
            startWithParameters(sender)
        } else {
            startServer()
        }
    }

    private var isOptionHeld: Bool {
        NSApp.currentEvent?.modifierFlags.contains(.option) ?? false
    }

    /// Asks for this run's parameters, prefilled with whatever is saved for the
    /// model, and starts with them.
    @objc func startWithParameters(_ sender: Any?) {
        guard !server.isRunning, binary != nil else { return }

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.placeholderString = "extra llama-server parameters (optional)"
        field.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        field.stringValue = promptParameters

        let alert = NSAlert()
        alert.messageText = "Start \(model.lastPathComponent) with parameters"
        alert.informativeText =
            "Extra llama-server parameters. Changing them here saves them for this model; "
            + "leaving them alone keeps using what Settings provides."
        alert.accessoryView = field
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field

        let respond: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.startServer(parameters: field.stringValue)
        }
        if let window {
            alert.beginSheetModal(for: window, completionHandler: respond)
        } else {
            respond(alert.runModal())
        }
    }

    /// Starts the server. `parameters` comes from the Start with Params… dialog;
    /// anything the user actually changed there becomes this model's own.
    private func startServer(parameters: String? = nil) {
        guard let binary, !server.isRunning else { return }

        if let parameters, parameters != promptParameters {
            do {
                try Config.save(parameters, for: model)
                savedParams = parameters.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                presentWarning(
                    "Could not save parameters",
                    "\(Config.fileName) in \(model.deletingLastPathComponent().path) "
                        + "could not be written: \(error.localizedDescription)")
            }
        }

        let params = launchParameters
        let command = ServerController.command(binary: binary, model: model, params: params)
        logView.append((logView.text.isEmpty ? "" : "\n") + "$ \(command)\n", isNote: true)

        do {
            try server.start(binary: binary, model: model, params: params)
        } catch {
            logView.append("Failed to launch: \(error.localizedDescription)\n", isNote: true)
            setIdle(status: .stopped("Launch failed"))
            return
        }

        setRunButton(title: "Stop", symbol: "stop.fill", isDefault: false)
        status = .loading
    }

    private func stopServer() {
        guard server.isRunning else { return }
        runButton.isEnabled = false
        server.stop()
    }

    private func serverExited(_ status: Int32, _ reason: Process.TerminationReason) {
        let note: String
        switch (reason, status) {
        case (.uncaughtSignal, _): note = "llama-server stopped"
        case (_, 0): note = "llama-server exited"
        default: note = "llama-server exited with status \(status)"
        }
        logView.append("— \(note) —\n", isNote: true)
        setIdle(status: .stopped(note))

        if let shutdown = pendingShutdown {
            pendingShutdown = nil
            shutdown(true)
        }
    }

    private func setIdle(status: ServerStatus) {
        runButton.isEnabled = true
        setRunButton(title: "Start", symbol: "play.fill", isDefault: true)
        self.status = status
    }

    private func setRunButton(title: String, symbol: String, isDefault: Bool) {
        runButton.title = title
        runButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withTrailingPadding(6)
        // Return starts the server, but never stops one by accident.
        runButton.keyEquivalent = isDefault ? "\r" : ""
    }

    @objc func openInBrowser(_ sender: Any?) {
        guard let url = listeningURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func copyCommand(_ sender: Any?) {
        guard let binary else { return }
        let command = ServerController.command(
            binary: binary, model: model, params: launchParameters)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    // MARK: - Shutdown confirmation

    /// Calls `completion(true)` once nothing is running — asking first, and
    /// waiting for a clean shutdown, if the server is live.
    func confirmStop(
        question: String = "Stop llama-server and quit?",
        verb: String = "Stop and Quit",
        completion: @escaping (Bool) -> Void
    ) {
        guard server.isRunning else {
            completion(true)
            return
        }
        guard !isConfirming else {
            completion(false)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = question
        alert.informativeText =
            "\(model.lastPathComponent) is still running. It will be shut down."
        alert.addButton(withTitle: verb)
        alert.addButton(withTitle: "Cancel")

        isConfirming = true
        let respond: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            self.isConfirming = false
            guard response == .alertFirstButtonReturn else {
                completion(false)
                return
            }
            self.pendingShutdown = completion
            self.stopServer()
        }

        if let window {
            alert.beginSheetModal(for: window, completionHandler: respond)
        } else {
            respond(alert.runModal())
        }
    }

    private func presentWarning(_ message: String, _ detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        if let window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    // MARK: - NSMenuItemValidation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copyCommand):
            // Nothing to copy until we know where llama-server is.
            return binary != nil
        case #selector(toggleServer(_:)):
            // One item, following the button between Start and Stop.
            menuItem.title = runButton.title
            return runButton.isEnabled
        case #selector(openInBrowser(_:)):
            return listeningURL != nil
        case #selector(startWithParameters(_:)):
            return !server.isRunning && binary != nil
        default:
            return true
        }
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard server.isRunning else { return true }
        confirmStop { if $0 { sender.close() } }
        return false
    }
}

extension NSToolbarItem.Identifier {
    static let model = NSToolbarItem.Identifier("model")
    static let status = NSToolbarItem.Identifier("status")
    static let browser = NSToolbarItem.Identifier("browser")
    static let run = NSToolbarItem.Identifier("run")
}
