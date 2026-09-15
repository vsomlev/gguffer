import Foundation

/// Runs llama-server as a child process and streams its output.
///
/// The child is launched as `zsh -lc 'exec llama-server …'`: the login shell
/// supplies the same PATH and quoting rules you'd get by typing the command
/// yourself, and `exec` replaces the shell so the PID we hold is the server's.
final class ServerController {

    /// Emitted on the main queue as output arrives.
    var onOutput: ((String) -> Void)?
    /// Emitted on the main queue when the child exits.
    var onExit: ((Int32, Process.TerminationReason) -> Void)?

    private var process: Process?
    private var pipe: Pipe?
    private var stopWorkItems: [DispatchWorkItem] = []

    /// Serialises all output buffering off the main thread; delivering from a
    /// single queue also keeps output and the exit notice in order.
    private let ioQueue = DispatchQueue(label: "com.vee.gguffer.output")
    private var buffer = Data()

    var isRunning: Bool { process?.isRunning ?? false }

    /// Absolute path to llama-server, resolved through a login shell.
    static func resolveBinary() -> String? {
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/bin/zsh")
        probe.arguments = ["-lc", "command -v llama-server"]
        let out = Pipe()
        probe.standardOutput = out
        probe.standardError = FileHandle.nullDevice
        do {
            try probe.run()
        } catch {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        probe.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (probe.terminationStatus == 0 && !path.isEmpty) ? path : nil
    }

    /// The exact shell command that will be run — also what "Copy command" copies.
    static func command(binary: String, model: URL, params: String) -> String {
        var command = "\(shellQuote(binary)) -m \(shellQuote(model.path))"
        let params = params.trimmingCharacters(in: .whitespacesAndNewlines)
        if !params.isEmpty { command += " " + params }
        return command
    }

    static func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func start(binary: String, model: URL, params: String) throws {
        precondition(!isRunning)
        cancelPendingStops()
        ioQueue.sync { buffer.removeAll() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "exec " + Self.command(binary: binary, model: model, params: params)]
        process.currentDirectoryURL = model.deletingLastPathComponent()

        // One pipe for both streams keeps stdout and stderr interleaved in order.
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.ioQueue.async { self?.consume(data) }
        }

        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = nil
            self.ioQueue.async {
                self.drainRemainder(handle)
                DispatchQueue.main.async {
                    guard self.process === process else { return }
                    self.pipe = nil
                    self.process = nil
                    self.cancelPendingStops()
                    self.onExit?(process.terminationStatus, process.terminationReason)
                }
            }
        }

        self.process = process
        self.pipe = pipe
        try process.run()
    }

    /// Asks the server to shut down: SIGINT, escalating to SIGTERM then SIGKILL.
    func stop() {
        guard let process, process.isRunning else { return }
        let pid = process.processIdentifier
        kill(pid, SIGINT)
        schedule(after: 4) { kill(pid, SIGTERM) }
        schedule(after: 7) { kill(pid, SIGKILL) }
    }

    private func schedule(after seconds: TimeInterval, _ body: @escaping () -> Void) {
        let item = DispatchWorkItem { [weak self] in
            guard let self, let process = self.process, process.isRunning else { return }
            body()
        }
        stopWorkItems.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func cancelPendingStops() {
        stopWorkItems.forEach { $0.cancel() }
        stopWorkItems.removeAll()
    }

    // MARK: - Output buffering

    /// Emits complete lines only. Splitting on LF/CR is UTF-8 safe (continuation
    /// bytes are all >= 0x80), so multi-byte characters never straddle a chunk.
    private func consume(_ data: Data) {
        buffer.append(data)
        guard let cut = buffer.lastIndex(where: { $0 == 0x0A || $0 == 0x0D }) else { return }
        let ready = buffer[..<(cut + 1)]
        buffer = Data(buffer[(cut + 1)...])
        emit(Data(ready))
    }

    private func drainRemainder(_ handle: FileHandle) {
        let data = (try? handle.readToEnd()) ?? nil
        if let data, !data.isEmpty { buffer.append(data) }
        guard !buffer.isEmpty else { return }
        let remainder = buffer
        buffer.removeAll()
        emit(remainder)
    }

    private func emit(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        DispatchQueue.main.async { [weak self] in self?.onOutput?(text) }
    }
}
