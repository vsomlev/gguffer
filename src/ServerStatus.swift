import AppKit

/// What the window's status indicator is showing.
enum ServerStatus: Equatable {
    /// Nothing has been started yet.
    case notLoaded
    /// llama-server is up but has not reported the model as loaded.
    case loading
    /// The model finished loading and the server is listening, on the address
    /// it announced if we managed to read one out of its log.
    case running(URL?)
    /// The server is gone (or never started), with the reason for the tooltip.
    case stopped(String)

    var symbolName: String {
        switch self {
        case .notLoaded: return "questionmark.circle.fill"
        case .loading: return "arrow.triangle.2.circlepath"
        case .running: return "checkmark.circle.fill"
        case .stopped: return "xmark.octagon.fill"
        }
    }

    var tint: NSColor {
        switch self {
        case .notLoaded: return .secondaryLabelColor
        case .loading: return .systemYellow
        case .running: return .systemGreen
        case .stopped: return .systemRed
        }
    }

    /// The short label in the toolbar, with the port once we know it.
    var text: String {
        switch self {
        case .notLoaded: return "Not loaded"
        case .loading: return "Loading"
        case .running(let url):
            guard let port = url?.port else { return "Running" }
            return "Running (\(port))"
        case .stopped: return "Stopped"
        }
    }

    /// The longer story, shown on hover — including how a server exited.
    var detail: String {
        switch self {
        case .notLoaded: return "No model loaded yet"
        case .loading: return "llama-server is loading the model"
        case .running(let url):
            guard let url else { return "Model loaded, llama-server is listening" }
            return "Model loaded, listening on \(url.absoluteString)"
        case .stopped(let reason): return reason
        }
    }

    var spins: Bool { self == .loading }

    /// True once llama-server's log says the model is up and serving.
    ///
    /// Current builds print `llama_server: model loaded` followed by
    /// `llama_server: listening on http://…`; older ones print
    /// `main: server is listening on …`. Matching any of them keeps this
    /// working across llama.cpp versions.
    /// The address llama-server announced, if this output announces one.
    static func listeningURL(in output: String) -> URL? {
        for line in output.split(whereSeparator: \.isNewline) {
            guard let announcement = line.range(of: "listening on ", options: .caseInsensitive)
            else { continue }
            let rest = line[announcement.upperBound...]
            var address = String(rest.split(whereSeparator: \.isWhitespace).first ?? rest)
            if !address.contains("://") { address = "http://" + address }
            guard var components = URLComponents(string: address),
                let host = components.host, !host.isEmpty,
                // llama-server always announces a port; requiring one keeps a
                // model path that happens to contain the phrase out of here.
                let port = components.port, port > 0
            else { continue }
            // Hand the browser a full http(s) URL and nothing else: Safari
            // will not open a scheme-less "127.0.0.1:8080", and the log is
            // external input we should not follow into other schemes.
            let scheme = components.scheme?.lowercased() ?? ""
            guard scheme == "http" || scheme == "https" else { continue }
            // "every interface" is not something a browser can open.
            if ["0.0.0.0", "::", "[::]"].contains(components.host ?? "") {
                components.host = "127.0.0.1"
            }
            if let url = components.url { return url }
        }
        return nil
    }

    static func indicatesReady(_ output: String) -> Bool {
        let text = output.lowercased()
        return text.contains("model loaded")
            || text.contains("listening on")
            || text.contains("server is listening")
    }
}

/// A small coloured symbol that spins while the model is loading.
final class StatusIndicatorView: NSView {

    private static let rotationKey = "gguffer.spin"
    private let imageView = NSImageView()

    var status: ServerStatus = .notLoaded {
        didSet {
            guard status != oldValue else { return }
            apply()
        }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        addSubview(imageView)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 16),
            heightAnchor.constraint(equalToConstant: 16),
            imageView.widthAnchor.constraint(equalTo: widthAnchor),
            imageView.heightAnchor.constraint(equalTo: heightAnchor),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        apply()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        // Keep the layer rotating about its middle; AppKit resets this on layout.
        if let layer = imageView.layer {
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: imageView.bounds.midX, y: imageView.bounds.midY)
        }
    }

    private func apply() {
        imageView.image = NSImage(
            systemSymbolName: status.symbolName, accessibilityDescription: status.text)
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        imageView.contentTintColor = status.tint
        needsLayout = true
        status.spins ? startSpinning() : stopSpinning()
    }

    private func startSpinning() {
        guard let layer = imageView.layer, layer.animation(forKey: Self.rotationKey) == nil else {
            return
        }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -Double.pi * 2
        spin.duration = 1.4
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        layer.add(spin, forKey: Self.rotationKey)
    }

    private func stopSpinning() {
        imageView.layer?.removeAnimation(forKey: Self.rotationKey)
    }
}

extension NSImage {
    /// A copy with transparent space on its trailing edge — AppKit has no
    /// padding between a button's image and its title, so it goes in the image.
    func withTrailingPadding(_ padding: CGFloat) -> NSImage {
        let padded = NSImage(size: NSSize(width: size.width + padding, height: size.height))
        padded.lockFocus()
        draw(in: NSRect(origin: .zero, size: size))
        padded.unlockFocus()
        padded.isTemplate = isTemplate
        return padded
    }
}
