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
pub const ClearArgs = struct { filter_tags: []const []const u8, all: bool = false };

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
        var all = false;
        var tags: std.ArrayList([]const u8) = .empty;
        var i: usize = 1;
        while (i < argv.len) : (i += 1) {
            if (std.mem.eql(u8, argv[i], "--all")) {
                all = true;
            } else {
                const norm = try parse.normalizeFilterTag(arena, argv[i]);
                tags.append(arena, norm) catch return CliError.UsageError;
            }
        }
        return .{ .clear = .{ .filter_tags = tags.items, .all = all } };
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

fn itemHasTag(it: store.Item, tag: []const u8) bool {
    for (it.tags) |t| if (std.mem.eql(u8, t, tag)) return true;
    return false;
}

fn writeItemLine(writer: anytype, indent: []const u8, it: store.Item) !void {
    try writer.print("{s}{d}. {s}", .{ indent, it.id, it.text });
    for (it.tags) |tg| try writer.print(" #{s}", .{tg});
    try writer.writeAll("\n");
}

fn writeBreakdown(
    writer: anytype,
    items: []const store.Item,
    filter_tags: []const []const u8,
) !void {
    try writer.writeAll("#");
    try writer.writeAll(filter_tags[0]);
    var i: usize = 1;
    while (i < filter_tags.len) : (i += 1) {
        try writer.writeAll(" + #");
        try writer.writeAll(filter_tags[i]);
    }
    try writer.writeAll("\n");
    var printed_any = false;
    for (items) |it| {
        var all = true;
        for (filter_tags) |t| if (!itemHasTag(it, t)) {
            all = false;
            break;
        };
        if (all) {
            try writeItemLine(writer, "  ", it);
            printed_any = true;
        }
    }
    if (!printed_any) try writer.writeAll("  (none)\n");

    for (filter_tags) |t| {
        try writer.writeAll("\n#");
        try writer.writeAll(t);
        try writer.writeAll("\n");
        var any = false;
        for (items) |it| {
            if (!itemHasTag(it, t)) continue;
            var others = false;
            for (filter_tags) |o| {
                if (std.mem.eql(u8, o, t)) continue;
                if (itemHasTag(it, o)) {
                    others = true;
                    break;
                }
            }
            if (!others) {
                try writeItemLine(writer, "  ", it);
                any = true;
            }
        }
        if (!any) try writer.writeAll("  (none)\n");
    }
}

fn collectAllTags(arena: std.mem.Allocator, items: []const store.Item) ![][]const u8 {
    var set: std.ArrayList([]const u8) = .empty;
    for (items) |it| for (it.tags) |t| {
        var seen = false;
        for (set.items) |e| if (std.mem.eql(u8, e, t)) {
            seen = true;
            break;
        };
        if (!seen) try set.append(arena, t);
    };
    std.mem.sort([]const u8, set.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lt);
    return set.items;
}

fn writePerTagBlocks(
    writer: anytype,
    items: []const store.Item,
    tags_in_order: []const []const u8,
    leading_blank: bool,
) !void {
    var any_block = false;
    for (tags_in_order) |t| {
        const has_any = blk: {
            for (items) |it| if (itemHasTag(it, t)) break :blk true;
            break :blk false;
        };
        if (!has_any) continue;
        if (any_block or leading_blank) try writer.writeAll("\n");
        try writer.print("#{s}\n", .{t});
        for (items) |it| if (itemHasTag(it, t)) try writeItemLine(writer, "  ", it);
        any_block = true;
    }
}

fn writeUntaggedBlock(
    writer: anytype,
    items: []const store.Item,
    leading_blank: bool,
) !void {
    var has_any = false;
    for (items) |it| if (it.tags.len == 0) {
        has_any = true;
        break;
    };
    if (!has_any) return;
    if (leading_blank) try writer.writeAll("\n");
    try writer.writeAll("[untagged]\n");
    for (items) |it| if (it.tags.len == 0) try writeItemLine(writer, "  ", it);
}

fn renderList(
    arena: std.mem.Allocator,
    writer: anytype,
    s: *store.Store,
    cmd: ListArgs,
) !void {
    const items = if (cmd.filter_tags.len == 0)
        try s.listActive(arena)
    else
        try s.listActiveByTags(arena, cmd.filter_tags);

    if (items.len == 0) {
        if (cmd.quiet) return;
        if (cmd.filter_tags.len == 0) {
            try writer.writeAll("no todos\n");
        } else {
            try writer.writeAll("no todos matching ");
            for (cmd.filter_tags, 0..) |t, i| {
                if (i != 0) try writer.writeAll(" or ");
                try writer.print("#{s}", .{t});
            }
            try writer.writeAll("\n");
        }
        return;
    }

    if (cmd.all and cmd.filter_tags.len == 0) {
        const tags = try collectAllTags(arena, items);
        try writePerTagBlocks(writer, items, tags, false);
        try writeUntaggedBlock(writer, items, true);
        return;
    }

    if (cmd.filter_tags.len >= 2) {
        try writeBreakdown(writer, items, cmd.filter_tags);
        if (cmd.all) {
            try writer.writeAll("\n");
            try writePerTagBlocks(writer, items, cmd.filter_tags, false);
        }
        return;
    }

    if (cmd.filter_tags.len == 1) {
        for (items) |it| try writeItemLine(writer, "", it);
        if (cmd.all) try writePerTagBlocks(writer, items, cmd.filter_tags, true);
        return;
    }

    for (items) |it| try writeItemLine(writer, "", it);
}

fn todoPath(arena: std.mem.Allocator, env: *std.process.Environ.Map) ![]const u8 {
    if (env.get("TODO_FILE")) |p| return arena.dupe(u8, p);
    if (env.get("XDG_DATA_HOME")) |x|
        return std.fs.path.join(arena, &.{ x, "todo", "todo.sqlite" });
    const home = env.get("HOME") orelse return error.NoHome;
    return std.fs.path.join(arena, &.{ home, ".local", "share", "todo", "todo.sqlite" });
}

fn runAdd(s: *store.Store, cmd: AddArgs) !void {
    _ = try s.add(cmd.text, cmd.tags);
}

fn runDone(s: *store.Store, cmd: DoneArgs, err_writer: anytype) !void {
    s.markCompleted(cmd.id) catch |err| switch (err) {
        store.StoreError.NotFound => {
            var buf: [128]u8 = undefined;
            const msg = try std.fmt.bufPrint(&buf, "no todo with id {d}\n", .{cmd.id});
            try err_writer.writeAll(msg);
            return;
        },
        store.StoreError.AlreadyDone => {
            var buf: [128]u8 = undefined;
            const msg = try std.fmt.bufPrint(&buf, "todo {d} already done\n", .{cmd.id});
            try err_writer.writeAll(msg);
            return;
        },
        else => return err,
    };
}

fn runClear(s: *store.Store, cmd: ClearArgs) !void {
    if (cmd.filter_tags.len == 0 and !cmd.all) return;
    if (cmd.filter_tags.len == 0) {
        _ = try s.clearActive();
    } else {
        _ = try s.clearActiveByTags(cmd.filter_tags);
    }
}

fn ensureParentDir(io: std.Io, path: []const u8) !void {
    const dir = std.fs.path.dirname(path) orelse return;
    std.Io.Dir.cwd().createDirPath(io, dir) catch {};
}

pub fn main(init: std.process.Init) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try init.minimal.args.toSlice(arena);
    var argv_list: std.ArrayList([]const u8) = .empty;
    if (args.len > 1) for (args[1..]) |a| try argv_list.append(arena, a);

    const stdout = std.Io.File.stdout();
    const stderr = std.Io.File.stderr();

    const cmd = classifyArgv(arena, argv_list.items) catch |e| {
        switch (e) {
            error.UsageError, error.NotAnId => try stderr.writeStreamingAll(init.io, "usage error\n"),
            error.InvalidTag => try stderr.writeStreamingAll(init.io, "invalid tag: use [A-Za-z0-9_-]\n"),
            error.EmptyText => try stderr.writeStreamingAll(init.io, "cannot add an empty todo\n"),
        }
        std.process.exit(1);
    };

    const path_raw = try todoPath(arena, init.environ_map);
    const path = try arena.dupeZ(u8, path_raw);
    try ensureParentDir(init.io, path);

    var s = store.Store.open(path) catch {
        try stderr.writeStreamingAll(init.io, "could not open todo database\n");
        std.process.exit(2);
    };
    defer s.close();
    s.initSchema() catch {
        try stderr.writeStreamingAll(init.io, "could not initialize todo database\n");
        std.process.exit(2);
    };

    switch (cmd) {
        .list => |l| {
            var aw = std.Io.Writer.Allocating.init(arena);
            defer aw.deinit();
            try renderList(arena, &aw.writer, &s, l);
            const buf = aw.toArrayList();
            try stdout.writeStreamingAll(init.io, buf.items);
        },
        .add => |a| try runAdd(&s, a),
        .done => |d| {
            var ew = std.Io.Writer.Allocating.init(arena);
            defer ew.deinit();
            try runDone(&s, d, &ew.writer);
            const ebuf = ew.toArrayList();
            if (ebuf.items.len > 0)
                try stderr.writeStreamingAll(init.io, ebuf.items);
        },
        .clear => |c| try runClear(&s, c),
    }
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

test "classifyArgv: clear with no args does not set all flag" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const cmd = try classifyArgv(arena, &[_][]const u8{"clear"});
    try std.testing.expect(cmd == .clear);
    try std.testing.expectEqual(@as(usize, 0), cmd.clear.filter_tags.len);
    try std.testing.expect(!cmd.clear.all);
}

test "classifyArgv: clear --all sets all flag" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const cmd = try classifyArgv(arena, &[_][]const u8{ "clear", "--all" });
    try std.testing.expect(cmd == .clear);
    try std.testing.expectEqual(@as(usize, 0), cmd.clear.filter_tags.len);
    try std.testing.expect(cmd.clear.all);
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

test "renderList: empty active set, no -q, prints 'no todos'" {
    var s = try store.Store.open(":memory:");
    defer s.close();
    try s.initSchema();

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    try renderList(arena, &aw.writer, &s, .{ .quiet = false, .all = false, .filter_tags = &.{} });
    var buf = aw.toArrayList();
    defer buf.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("no todos\n", buf.items);
}

test "renderList: empty active set, -q, prints nothing" {
    var s = try store.Store.open(":memory:");
    defer s.close();
    try s.initSchema();

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    try renderList(arena, &aw.writer, &s, .{ .quiet = true, .all = false, .filter_tags = &.{} });
    var buf = aw.toArrayList();
    defer buf.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("", buf.items);
}

test "renderList: flat list shows id, text, tags" {
    var s = try store.Store.open(":memory:");
    defer s.close();
    try s.initSchema();
    _ = try s.add("first", &[_][]const u8{"urgent"});
    _ = try s.add("second", &.{});

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    try renderList(arena, &aw.writer, &s, .{ .quiet = false, .all = false, .filter_tags = &.{} });
    var buf = aw.toArrayList();
    defer buf.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("1. first #urgent\n2. second\n", buf.items);
}

test "runAdd: inserts item and it appears in listActive" {
    var s = try store.Store.open(":memory:");
    defer s.close();
    try s.initSchema();
    try runAdd(&s, .{ .text = "buy milk", .tags = &.{"errand"} });
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const items = try s.listActive(arena);
    try std.testing.expectEqual(@as(usize, 1), items.len);
    try std.testing.expectEqualStrings("buy milk", items[0].text);
}

test "runDone: marks existing active todo as done" {
    var s = try store.Store.open(":memory:");
    defer s.close();
    try s.initSchema();
    const id = try s.add("do laundry", &.{});
    var ew = std.Io.Writer.Allocating.init(std.testing.allocator);
    try runDone(&s, .{ .id = id }, &ew.writer);
    var buf = ew.toArrayList();
    defer buf.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("", buf.items);
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const items = try s.listActive(arena_state.allocator());
    try std.testing.expectEqual(@as(usize, 0), items.len);
}

test "runDone: unknown id prints warning" {
    var s = try store.Store.open(":memory:");
    defer s.close();
    try s.initSchema();
    var ew = std.Io.Writer.Allocating.init(std.testing.allocator);
    try runDone(&s, .{ .id = 999 }, &ew.writer);
    var buf = ew.toArrayList();
    defer buf.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("no todo with id 999\n", buf.items);
}

test "runDone: already done prints warning" {
    var s = try store.Store.open(":memory:");
    defer s.close();
    try s.initSchema();
    const id = try s.add("do laundry", &.{});
    try s.markCompleted(id);
    var ew = std.Io.Writer.Allocating.init(std.testing.allocator);
    try runDone(&s, .{ .id = id }, &ew.writer);
    var buf = ew.toArrayList();
    defer buf.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.startsWith(u8, buf.items, "todo "));
    try std.testing.expect(std.mem.endsWith(u8, buf.items, "already done\n"));
}

test "runClear: --all clears all active todos" {
    var s = try store.Store.open(":memory:");
    defer s.close();
    try s.initSchema();
    _ = try s.add("task one", &.{});
    _ = try s.add("task two", &.{"work"});
    try runClear(&s, .{ .filter_tags = &.{}, .all = true });
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const items = try s.listActive(arena_state.allocator());
    try std.testing.expectEqual(@as(usize, 0), items.len);
}

test "runClear: clears only matching tagged todos" {
    var s = try store.Store.open(":memory:");
    defer s.close();
    try s.initSchema();
    _ = try s.add("task one", &.{"work"});
    _ = try s.add("task two", &.{"personal"});
    try runClear(&s, .{ .filter_tags = &.{"work"} });
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const items = try s.listActive(arena_state.allocator());
    try std.testing.expectEqual(@as(usize, 1), items.len);
    try std.testing.expectEqualStrings("task two", items[0].text);
}

test "runClear: no filter and no --all is a no-op, prevents accidental deletion" {
    var s = try store.Store.open(":memory:");
    defer s.close();
    try s.initSchema();
    _ = try s.add("task one", &.{"work"});
    _ = try s.add("task two", &.{});
    try runClear(&s, .{ .filter_tags = &.{}, .all = false });
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const items = try s.listActive(arena_state.allocator());
    try std.testing.expectEqual(@as(usize, 2), items.len);
}

test "runClear: empty store with --all is a no-op" {
    var s = try store.Store.open(":memory:");
    defer s.close();
    try s.initSchema();
    try runClear(&s, .{ .filter_tags = &.{}, .all = true });
}

test "renderList: single -l shows a flat list with no header" {
    var s = try store.Store.open(":memory:");
    defer s.close();
    try s.initSchema();
    _ = try s.add("a", &[_][]const u8{"urgent"});
    _ = try s.add("b", &[_][]const u8{"backend"});

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    try renderList(arena, &aw.writer, &s, .{
        .quiet = false,
        .all = false,
        .filter_tags = &[_][]const u8{"urgent"},
    });
    var buf = aw.toArrayList();
    defer buf.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("1. a #urgent\n", buf.items);
}

test "renderList: two -l tags produce breakdown sections" {
    var s = try store.Store.open(":memory:");
    defer s.close();
    try s.initSchema();
    _ = try s.add("a", &[_][]const u8{"urgent"});
    _ = try s.add("b", &[_][]const u8{ "urgent", "backend" });
    _ = try s.add("c", &[_][]const u8{"backend"});

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    try renderList(arena, &aw.writer, &s, .{
        .quiet = false,
        .all = false,
        .filter_tags = &[_][]const u8{ "urgent", "backend" },
    });
    var buf = aw.toArrayList();
    defer buf.deinit(std.testing.allocator);

    const expected =
        "#urgent + #backend\n" ++
        "  2. b #backend #urgent\n" ++
        "\n" ++
        "#urgent\n" ++
        "  1. a #urgent\n" ++
        "\n" ++
        "#backend\n" ++
        "  3. c #backend\n";
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "renderList: --all with no filter, items grouped by tag with [untagged]" {
    var s = try store.Store.open(":memory:");
    defer s.close();
    try s.initSchema();
    _ = try s.add("a", &[_][]const u8{"urgent"});
    _ = try s.add("b", &[_][]const u8{ "urgent", "backend" });
    _ = try s.add("c", &.{});

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    try renderList(arena, &aw.writer, &s, .{
        .quiet = false,
        .all = true,
        .filter_tags = &.{},
    });
    var buf = aw.toArrayList();
    defer buf.deinit(std.testing.allocator);

    const expected =
        "#backend\n" ++
        "  2. b #backend #urgent\n" ++
        "\n" ++
        "#urgent\n" ++
        "  1. a #urgent\n" ++
        "  2. b #backend #urgent\n" ++
        "\n" ++
        "[untagged]\n" ++
        "  3. c\n";
    try std.testing.expectEqualStrings(expected, buf.items);
}

test "renderList: --all with single -l appends per-tag block" {
    var s = try store.Store.open(":memory:");
    defer s.close();
    try s.initSchema();
    _ = try s.add("a", &[_][]const u8{"urgent"});

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    try renderList(arena, &aw.writer, &s, .{
        .quiet = false,
        .all = true,
        .filter_tags = &[_][]const u8{"urgent"},
    });
    var buf = aw.toArrayList();
    defer buf.deinit(std.testing.allocator);

    const expected =
        "1. a #urgent\n" ++
        "\n" ++
        "#urgent\n" ++
        "  1. a #urgent\n";
    try std.testing.expectEqualStrings(expected, buf.items);
}
