import Foundation

/// POSIX shell single-quote, matching Python's `shlex.quote`.
/// Empty string -> '' ; safe tokens pass through unquoted; otherwise wrap in
/// single quotes, escaping embedded single quotes as '"'"'.
public func shellQuote(_ s: String) -> String {
    if s.isEmpty { return "''" }
    // shlex's _find_unsafe: anything not in this set is "safe".
    let safe = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@%_-+=:,./")
    if s.unicodeScalars.allSatisfy({ safe.contains($0) }) {
        return s
    }
    let escaped = s.replacingOccurrences(of: "'", with: "'\"'\"'")
    return "'\(escaped)'"
}
