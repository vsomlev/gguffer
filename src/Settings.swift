import AppKit

/// llama-server's --reasoning flag, plus the choice of not passing it at all.
enum Reasoning: String, CaseIterable {
    case unset
    case on
    case off
    case auto

    var title: String {
        switch self {
        case .unset: return "Don't pass the flag"
        case .on: return "Always on"
        case .off: return "Always off"
        case .auto: return "Auto (detect from template)"
        }
    }

    /// What this adds to the command line, if anything.
    var flag: String { self == .unset ? "" : "--reasoning \(rawValue)" }
}

/// The app's settings, remembered in UserDefaults.
enum Settings {
    private static let loadModelOnStartKey = "LoadModelOnStart"
    private static let reasoningKey = "Reasoning"
    private static let extraParametersKey = "ExtraParameters"

    /// Start llama-server as soon as a model is opened, without waiting for
    /// the Start button. Off by default.
    static var loadModelOnStart: Bool {
        get { UserDefaults.standard.bool(forKey: loadModelOnStartKey) }
        set { UserDefaults.standard.set(newValue, forKey: loadModelOnStartKey) }
    }

    /// Whether to pass --reasoning, and what to pass. Not passed by default.
    static var reasoning: Reasoning {
        get {
            UserDefaults.standard.string(forKey: reasoningKey)
                .flatMap(Reasoning.init(rawValue:)) ?? .unset
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: reasoningKey) }
    }

    /// Parameters added to every run, whatever the model.
    static var extraParameters: String {
        get { UserDefaults.standard.string(forKey: extraParametersKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: extraParametersKey) }
    }
}

/// A small settings window: the app's own behaviour, then what gets passed to
/// llama-server on every run.
final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {

    private let loadOnStartBox = NSButton(
        checkboxWithTitle: "Load model on start", target: nil, action: nil)
    private let reasoningPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let extraParametersField = NSTextField()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 310),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        super.init(window: window)

        loadOnStartBox.target = self
        loadOnStartBox.action = #selector(toggle(_:))

        reasoningPopUp.addItems(withTitles: Reasoning.allCases.map(\.title))
        reasoningPopUp.target = self
        reasoningPopUp.action = #selector(reasoningChanged(_:))

        extraParametersField.placeholderString = "e.g. --ctx-size 8192 --jinja"
        extraParametersField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        extraParametersField.delegate = self

        let reasoningRow = NSStackView(views: [
            NSTextField(labelWithString: "Reasoning:"), reasoningPopUp,
        ])
        reasoningRow.orientation = .horizontal
        reasoningRow.spacing = 8

        let stack = NSStackView(views: [
            loadOnStartBox,
            explanation(
                "Starts llama-server as soon as a model is opened — whether the app was "
                    + "launched with it or you picked it with Open Model."),
            sectionHeading("llama-server"),
            reasoningRow,
            explanation("Adds --reasoning on/off/auto to every run, or leaves it out."),
            NSTextField(labelWithString: "Extra parameters"),
            extraParametersField,
            explanation(
                "Added to every run. A model with its own parameters — from Start with "
                    + "Params… — gets those as well, after these, so they win."),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(18, after: stack.views[1])
        stack.setCustomSpacing(12, after: stack.views[2])
        stack.setCustomSpacing(14, after: stack.views[4])
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        refresh()

        guard let content = window.contentView else { return }
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ] + [extraParametersField].map {
            $0.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40)
        } + stack.views.filter { $0 is NSTextField && !$0.isKind(of: NSButton.self) }.map {
            $0.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor, constant: -40)
        })
        fitWindow(to: stack)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Sizes the window to whatever the settings actually need.
    private func fitWindow(to stack: NSStackView) {
        guard let window else { return }
        window.layoutIfNeeded()
        window.setContentSize(NSSize(width: window.frame.width, height: stack.fittingSize.height))
    }

    private func sectionHeading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func explanation(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    func present() {
        refresh()
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func refresh() {
        loadOnStartBox.state = Settings.loadModelOnStart ? .on : .off
        reasoningPopUp.selectItem(at: Reasoning.allCases.firstIndex(of: Settings.reasoning) ?? 0)
        extraParametersField.stringValue = Settings.extraParameters
    }

    @objc private func toggle(_ sender: NSButton) {
        Settings.loadModelOnStart = sender.state == .on
    }

    @objc private func reasoningChanged(_ sender: NSPopUpButton) {
        Settings.reasoning = Reasoning.allCases[sender.indexOfSelectedItem]
    }

    /// Saved as you type, so closing the window cannot lose an edit.
    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as AnyObject? === extraParametersField else { return }
        Settings.extraParameters = extraParametersField.stringValue
    }
}
