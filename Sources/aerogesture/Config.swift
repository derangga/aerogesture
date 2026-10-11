import Foundation
import TOMLKit

enum ConfigError: Error, CustomStringConvertible {
    case missing
    case parse(Error)
    case invalid(field: String, reason: String)

    var description: String {
        switch self {
        case .missing: "no config file"
        case .parse(let error): "failed to parse: \(error)"
        case .invalid(let field, let reason): "invalid \(field): \(reason)"
        }
    }
}

struct GestureConfig: Codable {
    var fingers: Int = 3
    var sensitivity: Double = 1.0
    var naturalDirection: Bool = true

    enum CodingKeys: String, CodingKey {
        case fingers
        case sensitivity
        case naturalDirection = "natural_direction"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GestureConfig()
        fingers = try c.decodeIfPresent(Int.self, forKey: .fingers) ?? d.fingers
        // TOMLKit does not decode an integer such as `sensitivity = 2` as a Double
        if let whole = try? c.decode(Int.self, forKey: .sensitivity) {
            sensitivity = Double(whole)
        } else {
            sensitivity = try c.decodeIfPresent(Double.self, forKey: .sensitivity) ?? d.sensitivity
        }
        naturalDirection = try c.decodeIfPresent(Bool.self, forKey: .naturalDirection) ?? d.naturalDirection
    }
}

struct WorkspaceConfig: Codable {
    var wrapAround: Bool = false
    var skipEmpty: Bool = false

    enum CodingKeys: String, CodingKey {
        case wrapAround = "wrap_around"
        case skipEmpty = "skip_empty"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WorkspaceConfig()
        wrapAround = try c.decodeIfPresent(Bool.self, forKey: .wrapAround) ?? d.wrapAround
        skipEmpty = try c.decodeIfPresent(Bool.self, forKey: .skipEmpty) ?? d.skipEmpty
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

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        gesture = try c.decodeIfPresent(GestureConfig.self, forKey: .gesture) ?? d.gesture
        workspace = try c.decodeIfPresent(WorkspaceConfig.self, forKey: .workspace) ?? d.workspace
    }

    static func resolvedPath(override: String?) -> URL {
        if let override = override {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/aerogesture/config.toml")
    }

    static func load(from path: URL) throws -> Config {
        guard let text = try? String(contentsOf: path, encoding: .utf8) else {
            throw ConfigError.missing
        }
        return try parse(text)
    }

    static func parse(_ text: String) throws -> Config {
        let config: Config
        do {
            config = try TOMLDecoder().decode(Config.self, from: text)
        } catch {
            throw ConfigError.parse(error)
        }
        try config.validate()
        return config
    }

    func validate() throws {
        guard (3...5).contains(gesture.fingers) else {
            throw ConfigError.invalid(field: "gesture.fingers", reason: "must be 3 to 5, got \(gesture.fingers)")
        }
        guard gesture.sensitivity.isFinite, gesture.sensitivity > 0 else {
            throw ConfigError.invalid(field: "gesture.sensitivity", reason: "must be greater than 0, got \(gesture.sensitivity)")
        }
    }

    enum CodingKeys: String, CodingKey {
        case gesture
        case workspace
    }
}
