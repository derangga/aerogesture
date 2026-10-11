import Foundation

enum InstanceLockError: Error {
    case held
    case io(String)
}

/// flock on the PID file. The kernel drops the lock when the process dies, so a stale file is detectable.
final class InstanceLock {
    private let fd: Int32

    private init(fd: Int32) {
        self.fd = fd
    }

    /// Takes the lock and records our PID. The descriptor stays open for the life of the process.
    static func acquire(path: String) throws -> InstanceLock {
        // O_NOFOLLOW: /tmp is shared, never truncate through a symlink someone else planted
        let fd = open(path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o644)
        guard fd >= 0 else { throw InstanceLockError.io(String(cString: strerror(errno))) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw InstanceLockError.held
        }
        ftruncate(fd, 0)
        _ = "\(ProcessInfo.processInfo.processIdentifier)".withCString { write(fd, $0, strlen($0)) }
        return InstanceLock(fd: fd)
    }

    /// PID of the running instance, or nil when nobody holds the lock.
    static func runningPID(path: String) -> Int32? {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        if flock(fd, LOCK_SH | LOCK_NB) == 0 { return nil }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
