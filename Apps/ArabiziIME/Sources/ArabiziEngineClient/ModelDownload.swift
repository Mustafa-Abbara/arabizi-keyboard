import Foundation

/// Whether the engine has its model, or how far the installer's download of it has got. The installer
/// (harfi-setup.sh) registers the keyboard first, so Harfi converts on its rules while the model downloads into
/// ~/Library/Caches/Harfi in parts, and puts the model inside the engine service once the download is checked.
public enum ModelDownload: Equatable, Sendable {
    case ready
    /// Parts arriving now; `fraction` of the model's size is there.
    case downloading(fraction: Double)
    /// No model and no download going on: the installer was closed before it finished.
    case stopped(fraction: Double)

    /// A part written less than this long ago means the download is still going.
    static let active: TimeInterval = 90

    /// - Parameters:
    ///   - app: the installed ArabiziIME.app.
    ///   - cache: the folder the installer downloads into.
    public static func state(app: URL, cache: URL, now: Date = Date()) -> ModelDownload {
        let resources = app.appending(path: "Contents/XPCServices/ArabiziEngineXPC.xpc/Contents/Resources")
        let files = FileManager.default
        if let inside = try? files.contentsOfDirectory(atPath: resources.path), inside.contains(where: { $0.hasSuffix(".gguf") }) {
            return .ready
        }
        guard let info = try? String(contentsOf: app.appending(path: "Contents/Resources/model-download.txt"), encoding: .utf8),
              let asset = value("MODEL_ASSET", in: info), let size = value("MODEL_SIZE", in: info).flatMap(Double.init),
              size > 0
        else { return .ready }  // a build without a model to download (rules only, or a developer's own)
        var bytes = 0.0
        var newest = Date.distantPast
        for name in (try? files.contentsOfDirectory(atPath: cache.path)) ?? [] where name.hasPrefix(asset + ".part") {
            guard let attributes = try? files.attributesOfItem(atPath: cache.appending(path: name).path) else { continue }
            if name != asset + ".part" { bytes += (attributes[.size] as? NSNumber)?.doubleValue ?? 0 }
            newest = max(newest, attributes[.modificationDate] as? Date ?? .distantPast)
        }
        let fraction = min(1, bytes / size)
        return now.timeIntervalSince(newest) < active ? .downloading(fraction: fraction) : .stopped(fraction: fraction)
    }

    /// A `KEY="value"` line of model-download.txt.
    static func value(_ key: String, in text: String) -> String? {
        for line in text.split(separator: "\n") where line.hasPrefix(key + "=") {
            return line.dropFirst(key.count + 1).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        }
        return nil
    }
}
