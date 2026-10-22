const std = @import("std");
const builtin = @import("builtin");

/// `std.debug.print`, except on iOS. Zig 0.17.0's std.debug.print pulls in
/// Io.Threaded's process-spawn code, which reads `NullFile.fd` — a field that
/// doesn't exist on iOS — so libwimg stops compiling for aarch64-ios. On iOS we
/// format into a stack buffer and write(2) to stderr (shows in the Xcode console).
pub fn print(comptime fmt: []const u8, args: anytype) void {
    if (builtin.os.tag == .ios) {
        var buf: [1024]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, fmt, args) catch &buf;
        _ = std.c.write(2, s.ptr, s.len);
    } else {
        std.debug.print(fmt, args);
    }
}
