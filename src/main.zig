const std = @import("std");
const store = @import("store.zig");
const parse = @import("parse.zig");

pub const CliError = error{
    UsageError,
    InvalidTag,
    EmptyText,
    NotAnId,
};

pub const ListArgs = struct { quiet: bool, all: bool, filter_tags: []const []const u8 };
pub const AddArgs = struct { text: []const u8, tags: []const []const u8 };
pub const DoneArgs = struct { id: i64 };
pub const ClearArgs = struct { filter_tags: []const []const u8 };

pub const Command = union(enum) {
    list: ListArgs,
    add: AddArgs,
    done: DoneArgs,
    clear: ClearArgs,
};

pub fn classifyArgv(arena: std.mem.Allocator, argv: []const []const u8) (CliError || parse.ParseError)!Command {
    if (argv.len == 0) {
        return .{ .list = .{ .quiet = false, .all = false, .filter_tags = &.{} } };
    }

    if (std.mem.eql(u8, argv[0], "done")) {
        if (argv.len != 2) return CliError.UsageError;
        const id = std.fmt.parseInt(i64, argv[1], 10) catch return CliError.NotAnId;
        return .{ .done = .{ .id = id } };
    }

    if (std.mem.eql(u8, argv[0], "clear")) {
        var tags: std.ArrayList([]const u8) = .empty;
        var i: usize = 1;
        while (i < argv.len) : (i += 1) {
            const norm = try parse.normalizeFilterTag(arena, argv[i]);
            tags.append(arena, norm) catch return CliError.UsageError;
        }
        return .{ .clear = .{ .filter_tags = tags.items } };
    }

    var quiet = false;
    var all = false;
    var filter_tags: std.ArrayList([]const u8) = .empty;
    var explicit_tags: std.ArrayList([]const u8) = .empty;
    var positional: std.ArrayList([]const u8) = .empty;

    var i: usize = 0;
    while (i < argv.len) : (i += 1) {
        const a = argv[i];
        if (std.mem.eql(u8, a, "-q")) {
            quiet = true;
        } else if (std.mem.eql(u8, a, "--all")) {
            all = true;
        } else if (std.mem.eql(u8, a, "-l")) {
            i += 1;
            while (i < argv.len and !isFlag(argv[i])) : (i += 1) {
                const norm = try parse.normalizeFilterTag(arena, argv[i]);
                filter_tags.append(arena, norm) catch return CliError.UsageError;
            }
            if (filter_tags.items.len == 0) return CliError.UsageError;
            if (i < argv.len) i -= 1;
        } else if (std.mem.eql(u8, a, "-t")) {
            i += 1;
            if (i >= argv.len) return CliError.UsageError;
            const norm = try parse.normalizeFilterTag(arena, argv[i]);
            explicit_tags.append(arena, norm) catch return CliError.UsageError;
        } else {
            positional.append(arena, a) catch return CliError.UsageError;
        }
    }

    if (positional.items.len == 0) {
        return .{ .list = .{
            .quiet = quiet,
            .all = all,
            .filter_tags = filter_tags.items,
        } };
    }

    const parsed = try parse.parseAdd(arena, positional.items);
    var all_tags: std.ArrayList([]const u8) = .empty;
    for (explicit_tags.items) |t| {
        var seen = false;
        for (all_tags.items) |e| if (std.mem.eql(u8, e, t)) {
            seen = true;
            break;
        };
        if (!seen) all_tags.append(arena, t) catch return CliError.UsageError;
    }
    for (parsed.tags) |t| {
        var seen = false;
        for (all_tags.items) |e| if (std.mem.eql(u8, e, t)) {
            seen = true;
            break;
        };
        if (!seen) all_tags.append(arena, t) catch return CliError.UsageError;
    }
    return .{ .add = .{ .text = parsed.text, .tags = all_tags.items } };
}

fn isFlag(s: []const u8) bool {
    return s.len > 0 and s[0] == '-';
}

pub fn main(init: std.process.Init) !void {
    const stdout = std.Io.File.stdout();
    try stdout.writeStreamingAll(init.io, "todo (scaffold)\n");
}

test {
    std.testing.refAllDecls(@This());
    _ = store;
    _ = parse;
}

test "classifyArgv: bare invocation is plain list" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const cmd = try classifyArgv(arena, &[_][]const u8{});
    try std.testing.expect(cmd == .list);
    try std.testing.expect(!cmd.list.quiet);
    try std.testing.expect(!cmd.list.all);
    try std.testing.expectEqual(@as(usize, 0), cmd.list.filter_tags.len);
}

test "classifyArgv: -q sets quiet" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const cmd = try classifyArgv(arena, &[_][]const u8{"-q"});
    try std.testing.expect(cmd.list.quiet);
}

test "classifyArgv: --all sets all" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const cmd = try classifyArgv(arena, &[_][]const u8{"--all"});
    try std.testing.expect(cmd.list.all);
}

test "classifyArgv: -l consumes multiple tag values" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const cmd = try classifyArgv(arena, &[_][]const u8{ "-l", "urgent", "backend" });
    try std.testing.expectEqual(@as(usize, 2), cmd.list.filter_tags.len);
    try std.testing.expectEqualStrings("urgent", cmd.list.filter_tags[0]);
    try std.testing.expectEqualStrings("backend", cmd.list.filter_tags[1]);
}

test "classifyArgv: done <N>" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const cmd = try classifyArgv(arena, &[_][]const u8{ "done", "17" });
    try std.testing.expect(cmd == .done);
    try std.testing.expectEqual(@as(i64, 17), cmd.done.id);
}

test "classifyArgv: clear with no args" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const cmd = try classifyArgv(arena, &[_][]const u8{"clear"});
    try std.testing.expect(cmd == .clear);
    try std.testing.expectEqual(@as(usize, 0), cmd.clear.filter_tags.len);
}

test "classifyArgv: clear with #tag args" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const cmd = try classifyArgv(arena, &[_][]const u8{ "clear", "#urgent", "#backend" });
    try std.testing.expect(cmd == .clear);
    try std.testing.expectEqual(@as(usize, 2), cmd.clear.filter_tags.len);
    try std.testing.expectEqualStrings("urgent", cmd.clear.filter_tags[0]);
    try std.testing.expectEqualStrings("backend", cmd.clear.filter_tags[1]);
}

test "classifyArgv: add with trailing #tag" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const cmd = try classifyArgv(arena, &[_][]const u8{ "call", "the", "lab", "#medic" });
    try std.testing.expect(cmd == .add);
    try std.testing.expectEqualStrings("call the lab", cmd.add.text);
    try std.testing.expectEqual(@as(usize, 1), cmd.add.tags.len);
    try std.testing.expectEqualStrings("medic", cmd.add.tags[0]);
}

test "classifyArgv: add with -t and trailing #tag" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const cmd = try classifyArgv(arena, &[_][]const u8{ "-t", "urgent", "call", "the", "lab", "#medic" });
    try std.testing.expect(cmd == .add);
    try std.testing.expectEqualStrings("call the lab", cmd.add.text);
    try std.testing.expectEqual(@as(usize, 2), cmd.add.tags.len);
}
