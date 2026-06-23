import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// True if the process is currently running. Lets adapters reject stale
/// "running" records left behind by a crash or reboot.
///
/// `kill(pid, 0)` returns 0 if we can signal it, or sets errno to EPERM if the
/// process exists but isn't ownable by us. Either means alive. pid <= 0 -> false.
public func pidAlive(_ pid: Int) -> Bool {
    if pid <= 0 { return false }
    let rc = kill(pid_t(pid), 0)
    if rc == 0 { return true }
    return errno == EPERM
}
