import Foundation
import TOMLKit

struct GestureConfig: Codable {
    var fingers: Int = 3
    var sensitivity: Double = 1.0
    var naturalDirection: Bool = true

    enum CodingKeys: String, CodingKey {
        case fingers
        case sensitivity
        case naturalDirection = "natural_direction"
    }
}

struct WorkspaceConfig: Codable {
    var wrapAround: Bool = false
    var skipEmpty: Bool = false

    enum CodingKeys: String, CodingKey {
        case wrapAround = "wrap_around"
        case skipEmpty = "skip_empty"
    }
}

struct Config: Codable {
    var gesture = GestureConfig()
    var workspace = WorkspaceConfig()

    /// Internal threshold used by gesture detection
    var internalThreshold: Float {
        Float(gesture.sensitivity) * 0.05
    }

    static let defaults = Config()

    static func resolvedPath(override: String?) -> URL {
        if let override = override {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/aerogesture/config.toml")
    }

    static func load(from path: URL) -> Config {
        guard let data = try? String(contentsOf: path, encoding: .utf8) else {
            return .defaults
        }
        do {
            let decoder = TOMLDecoder()
            return try decoder.decode(Config.self, from: data)
        } catch {
            fputs("aerogesture: warning: failed to parse config at \(path.path): \(error)\n", stderr)
            return .defaults
        }
    }

    enum CodingKeys: String, CodingKey {
        case gesture
        case workspace
    }
}
