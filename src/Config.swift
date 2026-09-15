import Foundation

/// Per-folder parameter storage: a hidden `.gguffer.json` next to the model,
/// keyed by bare filename, with a hand-editable "*" folder-wide fallback.
enum Config {
    static let fileName = ".gguffer.json"

    static func url(for model: URL) -> URL {
        model.deletingLastPathComponent().appendingPathComponent(fileName)
    }

    private static func load(_ url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any]
        else { return [:] }
        return dict.compactMapValues { $0 as? String }
    }

    /// Saved parameters for this model: its own entry, else the folder's "*", else "".
    static func params(for model: URL) -> String {
        let config = load(url(for: model))
        return config[model.lastPathComponent] ?? config["*"] ?? ""
    }

    /// Stores `params` for this model. An empty string removes the entry, and
    /// removing the last entry deletes the file. Other keys are preserved.
    static func save(_ params: String, for model: URL) throws {
        let path = url(for: model)
        var config = load(path)
        let key = model.lastPathComponent
        let trimmed = params.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            config.removeValue(forKey: key)
        } else {
            config[key] = trimmed
        }

        guard !config.isEmpty else {
            if FileManager.default.fileExists(atPath: path.path) {
                try FileManager.default.removeItem(at: path)
            }
            return
        }

        var data = try JSONSerialization.data(
            withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        data.append(contentsOf: [0x0A])
        try data.write(to: path, options: .atomic)
    }
}
