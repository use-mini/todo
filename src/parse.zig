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

fn isValidTagChar(ch: u8) bool {
    return (ch >= 'a' and ch <= 'z') or
        (ch >= 'A' and ch <= 'Z') or
        (ch >= '0' and ch <= '9') or
        ch == '_' or ch == '-';
}

fn validateAndLowercase(arena: std.mem.Allocator, raw: []const u8) ParseError![]u8 {
    if (raw.len == 0) return ParseError.InvalidTag;
    const out = arena.alloc(u8, raw.len) catch return ParseError.InvalidTag;
    for (raw, 0..) |ch, i| {
        if (!isValidTagChar(ch)) return ParseError.InvalidTag;
        out[i] = std.ascii.toLower(ch);
    }
    return out;
}

fn appendTag(list: *std.ArrayList([]const u8), arena: std.mem.Allocator, tag: []const u8) ParseError!void {
    for (list.items) |existing| {
        if (std.mem.eql(u8, existing, tag)) return;
    }
    list.append(arena, tag) catch return ParseError.InvalidTag;
}

fn trimAscii(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

pub fn parseAdd(arena: std.mem.Allocator, argv: []const []const u8) ParseError!Parsed {
    var end = argv.len;
    while (end > 0 and isTagToken(argv[end - 1])) : (end -= 1) {}

    var tags: std.ArrayList([]const u8) = .empty;
    var i: usize = end;
    while (i < argv.len) : (i += 1) {
        const norm = try validateAndLowercase(arena, argv[i][1..]);
        try appendTag(&tags, arena, norm);
    }

    var text_buf: std.ArrayList(u8) = .empty;
    var first = true;
    var j: usize = 0;
    while (j < end) : (j += 1) {
        if (!first) text_buf.append(arena, ' ') catch return ParseError.EmptyText;
        const tok = argv[j];
        if (tok.len >= 3 and tok[0] == '#' and tok[1] == '#' and tok[2] != '#') {
            const norm = try validateAndLowercase(arena, tok[2..]);
            try appendTag(&tags, arena, norm);
            text_buf.append(arena, '#') catch return ParseError.EmptyText;
            text_buf.appendSlice(arena, norm) catch return ParseError.EmptyText;
        } else {
            text_buf.appendSlice(arena, tok) catch return ParseError.EmptyText;
        }
        first = false;
    }

    const trimmed = trimAscii(text_buf.items);
    if (trimmed.len == 0) return ParseError.EmptyText;

    return .{
        .text = trimmed,
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

test "inline ##tag adds tag and rewrites to single #" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const argv = [_][]const u8{ "call", "the", "##doctor", "and", "schedule", "an", "appointment" };
    const out = try parseAdd(arena, &argv);

    try std.testing.expectEqualStrings("call the #doctor and schedule an appointment", out.text);
    try std.testing.expectEqual(@as(usize, 1), out.tags.len);
    try std.testing.expectEqualStrings("doctor", out.tags[0]);
}

test "tags are lowercased before storage" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const argv = [_][]const u8{ "call", "the", "lab", "#Urgent", "#MEDIC" };
    const out = try parseAdd(arena, &argv);

    try std.testing.expectEqualStrings("call the lab", out.text);
    try std.testing.expectEqual(@as(usize, 2), out.tags.len);
    try std.testing.expectEqualStrings("urgent", out.tags[0]);
    try std.testing.expectEqualStrings("medic", out.tags[1]);
}

test "invalid tag character is rejected" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const argv = [_][]const u8{ "fix", "#bad!tag" };
    const err = parseAdd(arena, &argv);
    try std.testing.expectError(ParseError.InvalidTag, err);
}

test "empty text after stripping tags is an error" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const argv = [_][]const u8{ "#urgent", "#backend" };
    const err = parseAdd(arena, &argv);
    try std.testing.expectError(ParseError.EmptyText, err);
}

test "whitespace-only text is treated as empty" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const argv = [_][]const u8{ "   ", "\t", "#urgent" };
    const err = parseAdd(arena, &argv);
    try std.testing.expectError(ParseError.EmptyText, err);
}

pub fn normalizeFilterTag(arena: std.mem.Allocator, raw: []const u8) ParseError![]u8 {
    const stripped = if (raw.len > 0 and raw[0] == '#') raw[1..] else raw;
    return try validateAndLowercase(arena, stripped);
}

test "normalizeFilterTag accepts with and without leading #" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const a = try normalizeFilterTag(arena, "Urgent");
    const b = try normalizeFilterTag(arena, "#urgent");
    try std.testing.expectEqualStrings("urgent", a);
    try std.testing.expectEqualStrings("urgent", b);
    try std.testing.expectError(ParseError.InvalidTag, normalizeFilterTag(arena, ""));
    try std.testing.expectError(ParseError.InvalidTag, normalizeFilterTag(arena, "#"));
    try std.testing.expectError(ParseError.InvalidTag, normalizeFilterTag(arena, "with space"));
}
