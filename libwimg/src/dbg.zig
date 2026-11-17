const std = @import("std");

/// Debug output (FinTS traces). Plain `std.debug.print`: Zig 0.17.0 needed an
/// iOS-only workaround here (its print pulled in process-spawn code that didn't
/// compile for aarch64-ios); 0.17.1 fixed that.
pub fn print(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
}
