const std = @import("std");
const opts = @import("e2e_opts");

fn mkdb(buf: []u8) []const u8 {
    var n: u64 = undefined;
    _ = std.os.linux.getrandom(@ptrCast(&n), @sizeOf(u64), 0);
    return std.fmt.bufPrint(buf, "/tmp/todo_e2e_{x}.sqlite", .{n}) catch unreachable;
}

fn invoke(
    allocator: std.mem.Allocator,
    io: std.Io,
    db: []const u8,
    args: []const []const u8,
) !std.process.RunResult {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, opts.todo_bin);
    for (args) |a| try argv.append(allocator, a);

    var env = std.process.Environ.Map.init(allocator);
    defer env.deinit();
    try env.put("TODO_FILE", db);

    return std.process.run(allocator, io, .{
        .argv = argv.items,
        .environ_map = &env,
    });
}

test "add then list shows item" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var buf: [128]u8 = undefined;
    const db = mkdb(&buf);

    var r = try invoke(allocator, io, db, &.{ "install", "linux" });
    allocator.free(r.stdout);
    allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);

    r = try invoke(allocator, io, db, &.{});
    defer allocator.free(r.stdout);
    defer allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);
    try std.testing.expect(std.mem.indexOf(u8, r.stdout, "install linux") != null);
}

// bug1: items added with trailing #tag should appear in the --all grouped view
test "bug1: --all groups items added with trailing #tag" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var buf: [128]u8 = undefined;
    const db = mkdb(&buf);

    var r = try invoke(allocator, io, db, &.{ "aaa", "@prog" });
    allocator.free(r.stdout);
    allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);

    r = try invoke(allocator, io, db, &.{"--all"});
    defer allocator.free(r.stdout);
    defer allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);

    try std.testing.expect(std.mem.indexOf(u8, r.stdout, "@prog") != null);
    try std.testing.expect(std.mem.indexOf(u8, r.stdout, "aaa") != null);
}

// bug1b: items added with -t should also appear in the --all grouped view
test "bug1b: --all groups items added with -t flag" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var buf: [128]u8 = undefined;
    const db = mkdb(&buf);

    var r = try invoke(allocator, io, db, &.{ "-t", "prog", "aaa" });
    allocator.free(r.stdout);
    allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);

    r = try invoke(allocator, io, db, &.{"--all"});
    defer allocator.free(r.stdout);
    defer allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);

    try std.testing.expect(std.mem.indexOf(u8, r.stdout, "@prog") != null);
    try std.testing.expect(std.mem.indexOf(u8, r.stdout, "aaa") != null);
}

// bug2: clear #tag must only remove items with that tag, not everything
test "bug2: clear #tag only removes items with that tag" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var buf: [128]u8 = undefined;
    const db = mkdb(&buf);

    var r = try invoke(allocator, io, db, &.{ "buy milk", "@prog" });
    allocator.free(r.stdout);
    allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);

    r = try invoke(allocator, io, db, &.{"call mom"});
    allocator.free(r.stdout);
    allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);

    r = try invoke(allocator, io, db, &.{ "clear", "@prog" });
    allocator.free(r.stdout);
    allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);

    r = try invoke(allocator, io, db, &.{});
    defer allocator.free(r.stdout);
    defer allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);

    try std.testing.expect(std.mem.indexOf(u8, r.stdout, "call mom") != null);
    try std.testing.expect(std.mem.indexOf(u8, r.stdout, "buy milk") == null);
}

// bug3: a single quoted arg containing ##word should tag the item
test "bug3: inline ##tag in a single quoted arg tags the item" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var buf: [128]u8 = undefined;
    const db = mkdb(&buf);

    // Simulates: todo "call ##doctor for refill"
    var r = try invoke(allocator, io, db, &.{"call @@doctor for refill"});
    allocator.free(r.stdout);
    allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);

    // -l doctor must find the item
    r = try invoke(allocator, io, db, &.{ "-l", "doctor" });
    defer allocator.free(r.stdout);
    defer allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);
    try std.testing.expect(std.mem.indexOf(u8, r.stdout, "call") != null);
}

// bug4: ##word among multiple args should keep all surrounding words in the text
test "bug4: ##tag among multiple args preserves all words in text" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var buf: [128]u8 = undefined;
    const db = mkdb(&buf);

    // Simulates: todo call ##doctor fore refill  (4 separate args)
    var r = try invoke(allocator, io, db, &.{ "call", "@@doctor", "fore", "refill" });
    allocator.free(r.stdout);
    allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);

    r = try invoke(allocator, io, db, &.{});
    defer allocator.free(r.stdout);
    defer allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);

    // "fore" and "refill" must survive — not just "call"
    try std.testing.expect(std.mem.indexOf(u8, r.stdout, "fore") != null);
    try std.testing.expect(std.mem.indexOf(u8, r.stdout, "refill") != null);
    // item must be tagged with doctor
    try std.testing.expect(std.mem.indexOf(u8, r.stdout, "doctor") != null);
}

test "color: set and unset tag color" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var buf: [128]u8 = undefined;
    const db = mkdb(&buf);

    // add a tagged item
    var r = try invoke(allocator, io, db, &.{ "buy milk", "@urgent" });
    allocator.free(r.stdout);
    allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);

    // set color
    r = try invoke(allocator, io, db, &.{ "color", "@urgent", "#ff5500" });
    allocator.free(r.stdout);
    allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);

    // tags shows the hex value
    r = try invoke(allocator, io, db, &.{"tags"});
    defer allocator.free(r.stdout);
    defer allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);
    try std.testing.expect(std.mem.indexOf(u8, r.stdout, "#ff5500") != null);
    try std.testing.expect(std.mem.indexOf(u8, r.stdout, "urgent") != null);
}

test "tags: shows counts by state" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var buf: [128]u8 = undefined;
    const db = mkdb(&buf);

    var r = try invoke(allocator, io, db, &.{ "task a", "@work" });
    allocator.free(r.stdout);
    allocator.free(r.stderr);
    r = try invoke(allocator, io, db, &.{ "task b", "@work" });
    allocator.free(r.stdout);
    allocator.free(r.stderr);

    // mark one done
    r = try invoke(allocator, io, db, &.{ "done", "1" });
    allocator.free(r.stdout);
    allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);

    r = try invoke(allocator, io, db, &.{"tags"});
    defer allocator.free(r.stdout);
    defer allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);
    try std.testing.expect(std.mem.indexOf(u8, r.stdout, "active") != null);
    try std.testing.expect(std.mem.indexOf(u8, r.stdout, "done") != null);
    try std.testing.expect(std.mem.indexOf(u8, r.stdout, "cleared") != null);
}

test "tag: add and remove tags on an item" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var buf: [128]u8 = undefined;
    const db = mkdb(&buf);

    var r = try invoke(allocator, io, db, &.{ "fix bug", "@backend" });
    allocator.free(r.stdout);
    allocator.free(r.stderr);

    // add urgent, remove backend
    r = try invoke(allocator, io, db, &.{ "tag", "1", "+@urgent", "-@backend" });
    allocator.free(r.stdout);
    allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);

    r = try invoke(allocator, io, db, &.{});
    defer allocator.free(r.stdout);
    defer allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);
    try std.testing.expect(std.mem.indexOf(u8, r.stdout, "urgent") != null);
    try std.testing.expect(std.mem.indexOf(u8, r.stdout, "backend") == null);
}

test "clear <id>: clears a single item by id" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var buf: [128]u8 = undefined;
    const db = mkdb(&buf);

    var r = try invoke(allocator, io, db, &.{"keep me"});
    allocator.free(r.stdout);
    allocator.free(r.stderr);
    r = try invoke(allocator, io, db, &.{"delete me"});
    allocator.free(r.stdout);
    allocator.free(r.stderr);

    r = try invoke(allocator, io, db, &.{ "clear", "2" });
    allocator.free(r.stdout);
    allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);

    r = try invoke(allocator, io, db, &.{});
    defer allocator.free(r.stdout);
    defer allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);
    try std.testing.expect(std.mem.indexOf(u8, r.stdout, "keep me") != null);
    try std.testing.expect(std.mem.indexOf(u8, r.stdout, "delete me") == null);
}

test "done <id> note: stores note without error" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var buf: [128]u8 = undefined;
    const db = mkdb(&buf);

    var r = try invoke(allocator, io, db, &.{"ship feature"});
    allocator.free(r.stdout);
    allocator.free(r.stderr);

    r = try invoke(allocator, io, db, &.{ "done", "1", "deployed", "to", "prod" });
    defer allocator.free(r.stdout);
    defer allocator.free(r.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, r.term);
    try std.testing.expectEqualStrings("", r.stderr);
}
