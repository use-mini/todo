const std = @import("std");
const Io = std.Io;
const store = @import("store.zig");
const parse = @import("parse.zig");

pub fn main(init: std.process.Init) !void {
    const stdout = Io.File.stdout();
    try stdout.writeStreamingAll(init.io, "todo (scaffold)\n");
}

test "scaffold compiles" {
    try std.testing.expect(true);
}

test {
    std.testing.refAllDecls(@This());
    _ = store;
    _ = parse;
}
