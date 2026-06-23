import Foundation
import ResCore
#if canImport(Darwin)
import Darwin
#endif

/// Raw-mode terminal multiselect TUI. Renders to stderr, reads keys from
/// /dev/tty. ↑↓ or k/j to move, space toggles, Enter confirms, q/Esc cancels.
/// Live sessions are pre-checked. Returns the chosen session ids.
enum Picker {
    static func run(_ sessions: [Session]) -> [String] {
        guard !sessions.isEmpty else { return [] }

        // Open the controlling terminal explicitly so this works even when
        // stdin/stdout are redirected.
        let ttyFD = open("/dev/tty", O_RDWR)
        guard ttyFD >= 0 else {
            // No TTY available: fall back to pre-checked (live) selection.
            return sessions.filter { $0.live }.map { $0.id }
        }
        defer { close(ttyFD) }

        // Save & set raw mode.
        var orig = termios()
        guard tcgetattr(ttyFD, &orig) == 0 else {
            return sessions.filter { $0.live }.map { $0.id }
        }
        var raw = orig
        // cfmakeraw equivalent: disable canonical mode + echo.
        raw.c_lflag &= ~UInt(ICANON | ECHO | ISIG)
        raw.c_iflag &= ~UInt(IXON | ICRNL)
        tcsetattr(ttyFD, TCSANOW, &raw)
        defer {
            var restore = orig
            tcsetattr(ttyFD, TCSANOW, &restore)
            // Show cursor again.
            writeTTY(ttyFD, "\u{1B}[?25h")
        }

        var cursor = 0
        var checked = Set(sessions.enumerated().filter { $0.element.live }.map { $0.offset })

        writeTTY(ttyFD, "\u{1B}[?25l")  // hide cursor

        func render(initial: Bool) {
            var out = ""
            if !initial {
                // Move cursor up to the start of the previous render block.
                out += "\u{1B}[\(sessions.count + 2)A"
            }
            out += "\r\u{1B}[K"
            out += "  res — space to toggle, ↑/↓ move, enter to open, q to cancel\n"
            out += "\r\u{1B}[K\n"
            for (i, s) in sessions.enumerated() {
                out += "\r\u{1B}[K"
                let pointer = i == cursor ? "\u{1B}[36m>\u{1B}[0m" : " "
                let box = checked.contains(i) ? "[x]" : "[ ]"
                let glyph = statusGlyph(s)
                let g = glyph == " " ? " " : glyph
                let hint = "\u{1B}[2m\(s.project) · \(humanAge(s.age()))\u{1B}[0m"
                out += " \(pointer) \(box) \(g) \(s.title)  \(hint)\n"
            }
            writeTTY(ttyFD, out)
        }

        render(initial: true)

        var result: [String]? = nil
        var buf = [UInt8](repeating: 0, count: 8)

        loop: while true {
            let n = read(ttyFD, &buf, 1)
            if n <= 0 { break }
            let c = buf[0]
            switch c {
            case 0x1B:  // ESC — could be arrow sequence or bare escape
                // Peek for "[A"/"[B"
                let n2 = read(ttyFD, &buf, 1)
                if n2 <= 0 || buf[0] != 0x5B {  // not '['
                    // bare ESC -> cancel
                    result = []
                    break loop
                }
                let n3 = read(ttyFD, &buf, 1)
                if n3 <= 0 { break }
                switch buf[0] {
                case 0x41: cursor = (cursor - 1 + sessions.count) % sessions.count  // A up
                case 0x42: cursor = (cursor + 1) % sessions.count                    // B down
                default: break
                }
                render(initial: false)
            case 0x6B:  // k
                cursor = (cursor - 1 + sessions.count) % sessions.count
                render(initial: false)
            case 0x6A:  // j
                cursor = (cursor + 1) % sessions.count
                render(initial: false)
            case 0x20:  // space
                if checked.contains(cursor) { checked.remove(cursor) } else { checked.insert(cursor) }
                render(initial: false)
            case 0x0D, 0x0A:  // Enter
                result = checked.sorted().map { sessions[$0].id }
                break loop
            case 0x71, 0x03:  // q or Ctrl-C
                result = []
                break loop
            default:
                break
            }
        }

        writeTTY(ttyFD, "\n")
        return result ?? []
    }

    private static func writeTTY(_ fd: Int32, _ s: String) {
        let bytes = Array(s.utf8)
        bytes.withUnsafeBytes { _ = write(fd, $0.baseAddress, $0.count) }
    }
}
