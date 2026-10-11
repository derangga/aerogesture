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
var initialConfig = Config.defaults
do {
    initialConfig = try Config.load(from: configPath)
    fputs("aerogesture: loaded config from \(configPath.path)\n", stderr)
} catch ConfigError.missing {
    fputs("aerogesture: no config at \(configPath.path), using defaults\n", stderr)
} catch {
    fputs("aerogesture: warning: \(error) in \(configPath.path), using defaults\n", stderr)
}

do {
    _ = try InstanceLock.acquire(path: pidPath)
} catch InstanceLockError.held {
    fputs("aerogesture: already running\n", stderr)
    exit(1)
} catch {
    fputs("aerogesture: cannot lock \(pidPath): \(error)\n", stderr)
    exit(1)
}

// A write to a closed AeroSpace socket must return EPIPE, not kill the daemon
signal(SIGPIPE, SIG_IGN)

// Set up socket
let socket = AeroSpaceSocket()
socket.connect()

// Set up gesture detector. Only the main queue touches detector.config.
let detector = GestureDetector(config: initialConfig)
detector.onSwipe = { direction in
    socket.requestSwitch(direction: direction, config: detector.config.workspace)
}

// MARK: - Signal handling

let sighupSource = DispatchSource.makeSignalSource(signal: SIGHUP, queue: .main)
signal(SIGHUP, SIG_IGN)
sighupSource.setEventHandler {
    fputs("aerogesture: reloading config...\n", stderr)
    do {
        detector.config = try Config.load(from: configPath)
        fputs("aerogesture: config reloaded\n", stderr)
    } catch {
        fputs("aerogesture: reload failed (\(error)), keeping current config\n", stderr)
    }
}
sighupSource.resume()

func cleanShutdown() {
    fputs("aerogesture: shutting down...\n", stderr)
    detector.stop()
    socket.disconnect()
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

func reloadRunningInstance() {
    guard let pid = InstanceLock.runningPID(path: pidPath) else {
        fputs("aerogesture: no running instance found (nothing holds \(pidPath))\n", stderr)
        exit(1)
    }
    if kill(pid, SIGHUP) == 0 {
        print("aerogesture: sent SIGHUP to PID \(pid)")
    } else {
        fputs("aerogesture: failed to signal PID \(pid): \(String(cString: strerror(errno)))\n", stderr)
        exit(1)
    }
}
