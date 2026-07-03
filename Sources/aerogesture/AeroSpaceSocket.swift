import Foundation

// AeroSpace 0.21+ socket wire protocol: version handshake + length-prefixed frames.
// Must match SOCKET_PROTOCOL_VERSION in AeroSpace/Sources/Common/model/clientServer.swift.
private let SOCKET_PROTOCOL_VERSION: UInt32 = 1

enum SwipeError: Error {
    case socketError(String)
    case commandFail(String)
    case unknown(String)
}

struct ClientRequest: Codable {
    let command: String
    let args: [String]
    let stdin: String
    let windowId: UInt32?
    let workspace: String?

    init(args: [String], stdin: String = "") {
        self.command = ""
        self.args = args
        self.stdin = stdin
        self.windowId = nil
        self.workspace = nil
    }
}

struct ServerAnswer: Codable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let serverVersionAndHash: String
}

final class AeroSpaceSocket {
    private var fd: Int32 = -1
    private let socketPath: String
    private let queue = DispatchQueue(label: "aerogesture.ipc", qos: .userInteractive)

    init() {
        self.socketPath = "/tmp/bobko.aerospace-\(NSUserName()).sock"
    }

    func connect() {
        if fd >= 0 {
            Darwin.close(fd)
        }
        fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            fputs("aerogesture: failed to create socket\n", stderr)
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
                let bound = sunPath.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                    strlcpy(dest, ptr, 104)
                }
                _ = bound
            }
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result < 0 {
            fputs("aerogesture: failed to connect to AeroSpace at \(socketPath): \(String(cString: strerror(errno)))\n", stderr)
            Darwin.close(fd)
            fd = -1
            return
        }

        // Protocol handshake: send our version, server replies with its version.
        guard writeUInt32(SOCKET_PROTOCOL_VERSION),
              let serverVersion = readUInt32(),
              serverVersion == SOCKET_PROTOCOL_VERSION else {
            fputs("aerogesture: AeroSpace socket handshake failed (protocol version mismatch — restart AeroSpace?)\n", stderr)
            Darwin.close(fd)
            fd = -1
            return
        }
    }

    // MARK: - Framing primitives (little-endian length prefix, native byte order)

    private func writeAll(_ data: Data) -> Bool {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress else { return true } // empty payload
            var total = 0
            while total < data.count {
                let n = Darwin.write(fd, base + total, data.count - total)
                if n <= 0 { return false }
                total += n
            }
            return true
        }
    }

    private func readExactly(_ count: Int) -> Data? {
        if count == 0 { return Data() }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: count)
        while data.count < count {
            let n = buf.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, count - data.count) }
            if n <= 0 { return nil }
            data.append(contentsOf: buf[0..<n])
        }
        return data
    }

    private func writeUInt32(_ value: UInt32) -> Bool {
        var v = value
        return withUnsafeBytes(of: &v) { writeAll(Data($0)) }
    }

    private func readUInt32() -> UInt32? {
        guard let d = readExactly(4) else { return nil }
        return d.withUnsafeBytes { $0.load(as: UInt32.self) }
    }

    func disconnect() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    @discardableResult
    func runCommand(_ args: [String], stdin: String = "", retry: Bool = false) -> Result<String, SwipeError> {
        guard fd >= 0 else {
            if retry {
                return .failure(.socketError("Not connected after reconnect"))
            }
            fputs("aerogesture: not connected, attempting to connect...\n", stderr)
            connect()
            return runCommand(args, stdin: stdin, retry: true)
        }

        do {
            let request = ClientRequest(args: args, stdin: stdin)
            let payload = try JSONEncoder().encode(request)

            // Write request: UInt32 length prefix + JSON payload
            guard writeUInt32(UInt32(payload.count)), writeAll(payload) else {
                throw SwipeError.socketError("write failed")
            }

            // Read response: UInt32 length prefix + JSON payload
            guard let len = readUInt32(), let responseData = readExactly(Int(len)) else {
                throw SwipeError.socketError("read failed")
            }

            let answer = try JSONDecoder().decode(ServerAnswer.self, from: responseData)
            if answer.exitCode != 0 {
                return .failure(.commandFail(answer.stderr))
            }
            return .success(answer.stdout)

        } catch is SwipeError {
            if retry {
                return .failure(.socketError("Socket error after reconnect"))
            }
            fputs("aerogesture: socket error, reconnecting...\n", stderr)
            connect()
            return runCommand(args, stdin: stdin, retry: true)
        } catch {
            if retry {
                return .failure(.socketError(error.localizedDescription))
            }
            fputs("aerogesture: socket error, reconnecting...\n", stderr)
            connect()
            return runCommand(args, stdin: stdin, retry: true)
        }
    }

    func switchWorkspace(direction: Direction, config: Config) {
        // Focus the workspace under the cursor first
        if let mouseWs = try? runCommand(["list-workspaces", "--monitor", "mouse", "--visible"]).get() {
            let trimmed = mouseWs.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                runCommand(["workspace", trimmed])
            }
        }

        var args = ["workspace", direction.value]
        var stdin = ""
        if config.workspace.wrapAround {
            args.append("--wrap-around")
        }
        if config.workspace.skipEmpty {
            let res = runCommand(["list-workspaces", "--monitor", "focused", "--empty", "no"])
            if let ws = try? res.get(), !ws.isEmpty {
                stdin = ws
                args.append("--stdin")
            }
        }
        let result = runCommand(args, stdin: stdin)
        if case .failure(let err) = result {
            fputs("aerogesture: workspace switch failed: \(err)\n", stderr)
        }
    }
}
