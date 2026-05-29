const std = @import("std");

pub const ParseError = error{
    EmptyText,
    InvalidTag,
};

pub const Parsed = struct {
    text: []const u8,
    tags: []const []const u8,
};

fn isTagToken(tok: []const u8) bool {
    if (tok.len < 2) return false;
    if (tok[0] != '#') return false;
    if (tok[1] == '#') return false;
    return true;
}

pub fn parseAdd(arena: std.mem.Allocator, argv: []const []const u8) ParseError!Parsed {
    var end = argv.len;
    while (end > 0 and isTagToken(argv[end - 1])) : (end -= 1) {}

    var tags: std.ArrayList([]const u8) = .empty;
    var i: usize = end;
    while (i < argv.len) : (i += 1) {
        const raw = argv[i][1..];
        const dup = arena.dupe(u8, raw) catch return ParseError.EmptyText;
        tags.append(arena, dup) catch return ParseError.EmptyText;
    }

    var text_buf: std.ArrayList(u8) = .empty;
    var first = true;
    var j: usize = 0;
    while (j < end) : (j += 1) {
        if (!first) text_buf.append(arena, ' ') catch return ParseError.EmptyText;
        text_buf.appendSlice(arena, argv[j]) catch return ParseError.EmptyText;
        first = false;
    }

    if (text_buf.items.len == 0) return ParseError.EmptyText;

    return .{
        .text = text_buf.items,
        .tags = tags.items,
    };
}

test "trailing #tag extracted, text stripped" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const argv = [_][]const u8{ "call", "and", "schedule", "an", "appointment", "#medic" };
    const out = try parseAdd(arena, &argv);

    try std.testing.expectEqualStrings("call and schedule an appointment", out.text);
    try std.testing.expectEqual(@as(usize, 1), out.tags.len);
    try std.testing.expectEqualStrings("medic", out.tags[0]);
}

test "bare middle #word stays literal, no tags" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const argv = [_][]const u8{ "call", "the", "#doctor", "and", "schedule", "an", "appointment" };
    const out = try parseAdd(arena, &argv);

    try std.testing.expectEqualStrings("call the #doctor and schedule an appointment", out.text);
    try std.testing.expectEqual(@as(usize, 0), out.tags.len);
}
