const std = @import("std");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const stdout = Io.File.stdout();
    try stdout.writeStreamingAll(init.io, "todo (scaffold)\n");
}

test "scaffold compiles" {
    try std.testing.expect(true);
}
