import Foundation

let version = "0.2.0"
let pidPath = "/tmp/aerogesture.pid"

// MARK: - CLI argument parsing

var configOverride: String? = nil
var args = CommandLine.arguments.dropFirst()

while let arg = args.first {
    switch arg {
    case "--version":
        print("aerogesture \(version)")
        exit(0)
    case "--reload":
        reloadRunningInstance()
        exit(0)
    case "--config":
        args = args.dropFirst()
        guard let path = args.first else {
            fputs("aerogesture: --config requires a path argument\n", stderr)
            exit(1)
        }
        configOverride = path
        args = args.dropFirst()
    case "--help", "-h":
        print("""
        Usage: aerogesture [options]

        Options:
          --config <path>  Override config file path
          --reload         Send SIGHUP to running instance
          --version        Print version and exit
          --help           Show this help
        """)
        exit(0)
    default:
        fputs("aerogesture: unknown option '\(arg)'\n", stderr)
        exit(1)
    }
}

// MARK: - Startup

checkAccessibilityPermissions()

let configPath = Config.resolvedPath(override: configOverride)
var config = Config.load(from: configPath)
fputs("aerogesture: loaded config from \(configPath.path)\n", stderr)

// Write PID file
writePID()

// Set up socket
let socket = AeroSpaceSocket()
socket.connect()

// Set up gesture detector
let detector = GestureDetector(config: config)
detector.onSwipe = { direction in
    socket.switchWorkspace(direction: direction, config: config)
}

// MARK: - Signal handling

let sighupSource = DispatchSource.makeSignalSource(signal: SIGHUP, queue: .main)
signal(SIGHUP, SIG_IGN)
sighupSource.setEventHandler {
    fputs("aerogesture: reloading config...\n", stderr)
    config = Config.load(from: configPath)
    detector.config = config
    detector.onSwipe = { direction in
        socket.switchWorkspace(direction: direction, config: config)
    }
    fputs("aerogesture: config reloaded\n", stderr)
}
sighupSource.resume()

func cleanShutdown() {
    fputs("aerogesture: shutting down...\n", stderr)
    detector.stop()
    socket.disconnect()
    removePID()
    exit(0)
}

let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
signal(SIGTERM, SIG_IGN)
sigtermSource.setEventHandler { cleanShutdown() }
sigtermSource.resume()

let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
signal(SIGINT, SIG_IGN)
sigintSource.setEventHandler { cleanShutdown() }
sigintSource.resume()

// Start gesture detection and run
detector.start()
fputs("aerogesture: running (PID \(ProcessInfo.processInfo.processIdentifier))\n", stderr)

CFRunLoopRun()

// MARK: - Helpers

func writePID() {
    let pid = "\(ProcessInfo.processInfo.processIdentifier)"
    try? pid.write(toFile: pidPath, atomically: true, encoding: .utf8)
}

func removePID() {
    try? FileManager.default.removeItem(atPath: pidPath)
}

func reloadRunningInstance() {
    guard let pidStr = try? String(contentsOfFile: pidPath, encoding: .utf8),
          let pid = Int32(pidStr.trimmingCharacters(in: .whitespacesAndNewlines))
    else {
        fputs("aerogesture: no running instance found (no PID file at \(pidPath))\n", stderr)
        exit(1)
    }
    if kill(pid, SIGHUP) == 0 {
        print("aerogesture: sent SIGHUP to PID \(pid)")
    } else {
        fputs("aerogesture: failed to signal PID \(pid): \(String(cString: strerror(errno)))\n", stderr)
        exit(1)
    }
}
