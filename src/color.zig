const std = @import("std");

pub const Color = struct { r: u8, g: u8, b: u8 };
pub const TagColor = struct { tag: []const u8, color: Color };
pub const ParseError = error{InvalidColor};

pub const ColorMap = struct {
    entries: []const TagColor,

    pub fn get(self: ColorMap, tag: []const u8) ?Color {
        for (self.entries) |e| {
            if (std.mem.eql(u8, e.tag, tag)) return e.color;
        }
        return null;
    }
};

pub fn parseHex(s: []const u8) ParseError!Color {
    if (s.len != 7 or s[0] != '#') return ParseError.InvalidColor;
    const r = std.fmt.parseInt(u8, s[1..3], 16) catch return ParseError.InvalidColor;
    const g = std.fmt.parseInt(u8, s[3..5], 16) catch return ParseError.InvalidColor;
    const b = std.fmt.parseInt(u8, s[5..7], 16) catch return ParseError.InvalidColor;
    return Color{ .r = r, .g = g, .b = b };
}

pub fn writeTagColored(writer: anytype, color_map: ColorMap, tag: []const u8) !void {
    if (color_map.get(tag)) |c| {
        try writer.print("\x1b[38;2;{d};{d};{d}m@{s}\x1b[0m", .{ c.r, c.g, c.b, tag });
    } else {
        try writer.print("@{s}", .{tag});
    }
}

test "parseHex: valid #rrggbb" {
    const c = try parseHex("#ff5500");
    try std.testing.expectEqual(@as(u8, 255), c.r);
    try std.testing.expectEqual(@as(u8, 85), c.g);
    try std.testing.expectEqual(@as(u8, 0), c.b);
}

test "parseHex: wrong length rejects" {
    try std.testing.expectError(ParseError.InvalidColor, parseHex("#ff550"));
    try std.testing.expectError(ParseError.InvalidColor, parseHex("ff5500"));
    try std.testing.expectError(ParseError.InvalidColor, parseHex("#ff55001"));
}

test "parseHex: invalid hex digits rejected" {
    try std.testing.expectError(ParseError.InvalidColor, parseHex("#gggggg"));
}

test "parseHex: uppercase hex accepted" {
    const c = try parseHex("#FF5500");
    try std.testing.expectEqual(@as(u8, 255), c.r);
}

test "ColorMap.get: returns color for known tag" {
    const entries = [_]TagColor{.{ .tag = "urgent", .color = .{ .r = 255, .g = 0, .b = 0 } }};
    const cm = ColorMap{ .entries = &entries };
    const col = cm.get("urgent");
    try std.testing.expect(col != null);
    try std.testing.expectEqual(@as(u8, 255), col.?.r);
}

test "ColorMap.get: returns null for unknown tag" {
    const cm = ColorMap{ .entries = &.{} };
    try std.testing.expect(cm.get("missing") == null);
}

test "writeTagColored: no entry writes plain @tag" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    const cm = ColorMap{ .entries = &.{} };
    try writeTagColored(&aw.writer, cm, "urgent");
    var buf = aw.toArrayList();
    defer buf.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("@urgent", buf.items);
}

test "writeTagColored: with color wraps in ANSI escapes" {
    var aw = std.Io.Writer.Allocating.init(std.testing.allocator);
    const entries = [_]TagColor{.{ .tag = "urgent", .color = .{ .r = 255, .g = 85, .b = 0 } }};
    const cm = ColorMap{ .entries = &entries };
    try writeTagColored(&aw.writer, cm, "urgent");
    var buf = aw.toArrayList();
    defer buf.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("\x1b[38;2;255;85;0m@urgent\x1b[0m", buf.items);
}
