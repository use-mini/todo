const std = @import("std");

pub const c = @cImport({
    @cInclude("sqlite3.h");
});

test "sqlite smoke: open in-memory, select 1" {
    var db: ?*c.sqlite3 = null;
    var rc = c.sqlite3_open(":memory:", &db);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc);
    defer _ = c.sqlite3_close(db);

    var stmt: ?*c.sqlite3_stmt = null;
    rc = c.sqlite3_prepare_v2(db, "SELECT 1", -1, &stmt, null);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK), rc);
    defer _ = c.sqlite3_finalize(stmt);

    rc = c.sqlite3_step(stmt);
    try std.testing.expectEqual(@as(c_int, c.SQLITE_ROW), rc);
    try std.testing.expectEqual(@as(c_int, 1), c.sqlite3_column_int(stmt, 0));
}

pub const StoreError = error{
    OpenFailed,
    ExecFailed,
    PrepareFailed,
    StepFailed,
    BindFailed,
    OutOfMemory,
};

fn exec(db: *c.sqlite3, sql: [:0]const u8) StoreError!void {
    var errmsg: [*c]u8 = null;
    const rc = c.sqlite3_exec(db, sql.ptr, null, null, &errmsg);
    if (rc != c.SQLITE_OK) {
        if (errmsg != null) c.sqlite3_free(errmsg);
        return StoreError.ExecFailed;
    }
}

fn prepare(db: *c.sqlite3, sql: [:0]const u8) StoreError!*c.sqlite3_stmt {
    var stmt: ?*c.sqlite3_stmt = null;
    if (c.sqlite3_prepare_v2(db, sql.ptr, -1, &stmt, null) != c.SQLITE_OK) {
        return StoreError.PrepareFailed;
    }
    return stmt.?;
}

fn bindText(stmt: *c.sqlite3_stmt, idx: c_int, text: []const u8) StoreError!void {
    const rc = c.sqlite3_bind_text(stmt, idx, text.ptr, @intCast(text.len), c.SQLITE_TRANSIENT);
    if (rc != c.SQLITE_OK) return StoreError.BindFailed;
}

fn bindInt(stmt: *c.sqlite3_stmt, idx: c_int, val: i64) StoreError!void {
    if (c.sqlite3_bind_int64(stmt, idx, val) != c.SQLITE_OK) return StoreError.BindFailed;
}

const SCHEMA: [:0]const u8 =
    \\PRAGMA foreign_keys = ON;
    \\PRAGMA journal_mode = WAL;
    \\CREATE TABLE IF NOT EXISTS items (
    \\    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    \\    text         TEXT    NOT NULL,
    \\    state        TEXT    NOT NULL CHECK (state IN ('active','completed','cleared')),
    \\    created_at   INTEGER NOT NULL,
    \\    completed_at INTEGER,
    \\    cleared_at   INTEGER
    \\);
    \\CREATE TABLE IF NOT EXISTS item_tags (
    \\    item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    \\    tag     TEXT    NOT NULL,
    \\    PRIMARY KEY (item_id, tag)
    \\);
    \\CREATE INDEX IF NOT EXISTS idx_items_state   ON items(state);
    \\CREATE INDEX IF NOT EXISTS idx_item_tags_tag ON item_tags(tag);
;

pub const Store = struct {
    db: *c.sqlite3,

    pub fn open(path: [:0]const u8) StoreError!Store {
        var db: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(path.ptr, &db);
        if (rc != c.SQLITE_OK) {
            if (db) |d| _ = c.sqlite3_close(d);
            return StoreError.OpenFailed;
        }
        return Store{ .db = db.? };
    }

    pub fn close(self: *Store) void {
        _ = c.sqlite3_close(self.db);
    }

    pub fn initSchema(self: *Store) StoreError!void {
        try exec(self.db, SCHEMA);
    }

    pub fn add(self: *Store, text: []const u8, tags: []const []const u8) StoreError!i64 {
        try exec(self.db, "BEGIN");
        errdefer _ = c.sqlite3_exec(self.db, "ROLLBACK", null, null, null);

        const ins_item = try prepare(self.db,
            "INSERT INTO items (text, state, created_at) VALUES (?, 'active', ?)");
        defer _ = c.sqlite3_finalize(ins_item);
        try bindText(ins_item, 1, text);
        var ts: std.os.linux.timespec = undefined;
        _ = std.os.linux.clock_gettime(.REALTIME, &ts);
        try bindInt(ins_item, 2, ts.sec);
        if (c.sqlite3_step(ins_item) != c.SQLITE_DONE) return StoreError.StepFailed;
        const id = c.sqlite3_last_insert_rowid(self.db);

        if (tags.len > 0) {
            const ins_tag = try prepare(self.db,
                "INSERT OR IGNORE INTO item_tags (item_id, tag) VALUES (?, ?)");
            defer _ = c.sqlite3_finalize(ins_tag);
            for (tags) |tag| {
                _ = c.sqlite3_reset(ins_tag);
                try bindInt(ins_tag, 1, id);
                try bindText(ins_tag, 2, tag);
                if (c.sqlite3_step(ins_tag) != c.SQLITE_DONE) return StoreError.StepFailed;
            }
        }

        try exec(self.db, "COMMIT");
        return id;
    }

    pub fn getById(self: *Store, arena: std.mem.Allocator, id: i64) StoreError!Item {
        const sel_item = try prepare(self.db,
            "SELECT text, created_at FROM items WHERE id = ?");
        defer _ = c.sqlite3_finalize(sel_item);
        try bindInt(sel_item, 1, id);
        if (c.sqlite3_step(sel_item) != c.SQLITE_ROW) return StoreError.StepFailed;
        const text_ptr = c.sqlite3_column_text(sel_item, 0);
        const text_slice = std.mem.sliceTo(text_ptr, 0);
        const text_dup = arena.dupe(u8, text_slice) catch return StoreError.OutOfMemory;
        const created_at = c.sqlite3_column_int64(sel_item, 1);

        const sel_tags = try prepare(self.db,
            "SELECT tag FROM item_tags WHERE item_id = ? ORDER BY tag");
        defer _ = c.sqlite3_finalize(sel_tags);
        try bindInt(sel_tags, 1, id);

        var tag_list: std.ArrayList([]const u8) = .empty;
        while (true) {
            const rc = c.sqlite3_step(sel_tags);
            if (rc == c.SQLITE_DONE) break;
            if (rc != c.SQLITE_ROW) return StoreError.StepFailed;
            const tag_ptr = c.sqlite3_column_text(sel_tags, 0);
            const tag_slice = std.mem.sliceTo(tag_ptr, 0);
            const tag_dup = arena.dupe(u8, tag_slice) catch return StoreError.OutOfMemory;
            tag_list.append(arena, tag_dup) catch return StoreError.OutOfMemory;
        }

        return Item{
            .id = id,
            .text = text_dup,
            .created_at = created_at,
            .tags = tag_list.items,
        };
    }

    pub fn listActive(self: *Store, arena: std.mem.Allocator) StoreError![]Item {
        const sel = try prepare(self.db,
            "SELECT id, text, created_at FROM items WHERE state='active' ORDER BY id");
        defer _ = c.sqlite3_finalize(sel);

        var ids: std.ArrayList(i64) = .empty;
        var texts: std.ArrayList([]const u8) = .empty;
        var created: std.ArrayList(i64) = .empty;
        while (true) {
            const rc = c.sqlite3_step(sel);
            if (rc == c.SQLITE_DONE) break;
            if (rc != c.SQLITE_ROW) return StoreError.StepFailed;
            ids.append(arena, c.sqlite3_column_int64(sel, 0)) catch return StoreError.OutOfMemory;
            const tp = c.sqlite3_column_text(sel, 1);
            const ts = std.mem.sliceTo(tp, 0);
            const dup = arena.dupe(u8, ts) catch return StoreError.OutOfMemory;
            texts.append(arena, dup) catch return StoreError.OutOfMemory;
            created.append(arena, c.sqlite3_column_int64(sel, 2)) catch return StoreError.OutOfMemory;
        }

        const out = arena.alloc(Item, ids.items.len) catch return StoreError.OutOfMemory;
        for (ids.items, 0..) |id, i| {
            const item = try self.getById(arena, id);
            out[i] = Item{
                .id = id,
                .text = texts.items[i],
                .created_at = created.items[i],
                .tags = item.tags,
            };
        }
        return out;
    }

    pub fn listActiveByTags(self: *Store, arena: std.mem.Allocator, tags: []const []const u8) StoreError![]Item {
        if (tags.len == 0) return &.{};

        const sql_prefix: []const u8 =
            \\SELECT DISTINCT i.id
            \\FROM items i
            \\JOIN item_tags t ON t.item_id = i.id
            \\WHERE i.state = 'active'
            \\  AND t.tag IN (
        ;

        var query: std.ArrayList(u8) = .empty;
        query.appendSlice(arena, sql_prefix) catch return StoreError.OutOfMemory;
        var k: usize = 0;
        while (k < tags.len) : (k += 1) {
            if (k != 0) query.append(arena, ',') catch return StoreError.OutOfMemory;
            query.append(arena, '?') catch return StoreError.OutOfMemory;
        }
        query.appendSlice(arena, ") ORDER BY i.id") catch return StoreError.OutOfMemory;
        query.append(arena, 0) catch return StoreError.OutOfMemory;
        const z: [:0]const u8 = query.items[0 .. query.items.len - 1 :0];

        const sel = try prepare(self.db, z);
        defer _ = c.sqlite3_finalize(sel);

        var ti: usize = 0;
        while (ti < tags.len) : (ti += 1) {
            try bindText(sel, @intCast(ti + 1), tags[ti]);
        }

        var ids: std.ArrayList(i64) = .empty;
        while (true) {
            const rc = c.sqlite3_step(sel);
            if (rc == c.SQLITE_DONE) break;
            if (rc != c.SQLITE_ROW) return StoreError.StepFailed;
            ids.append(arena, c.sqlite3_column_int64(sel, 0)) catch return StoreError.OutOfMemory;
        }

        const out = arena.alloc(Item, ids.items.len) catch return StoreError.OutOfMemory;
        for (ids.items, 0..) |id, i| {
            out[i] = try self.getById(arena, id);
        }
        return out;
    }
};

test "open + initSchema creates tables idempotently" {
    var s = try Store.open(":memory:");
    defer s.close();
    try s.initSchema();
    try s.initSchema();

    var stmt: ?*c.sqlite3_stmt = null;
    const sql = "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name";
    try std.testing.expectEqual(@as(c_int, c.SQLITE_OK),
        c.sqlite3_prepare_v2(s.db, sql, -1, &stmt, null));
    defer _ = c.sqlite3_finalize(stmt);

    try std.testing.expectEqual(@as(c_int, c.SQLITE_ROW), c.sqlite3_step(stmt));
    const first = std.mem.sliceTo(c.sqlite3_column_text(stmt, 0), 0);
    try std.testing.expectEqualStrings("item_tags", first);

    try std.testing.expectEqual(@as(c_int, c.SQLITE_ROW), c.sqlite3_step(stmt));
    const second = std.mem.sliceTo(c.sqlite3_column_text(stmt, 0), 0);
    try std.testing.expectEqualStrings("items", second);
}

pub const Item = struct {
    id: i64,
    text: []const u8,
    created_at: i64,
    tags: [][]const u8,
};

test "add returns id; getById round-trips text and tags" {
    var s = try Store.open(":memory:");
    defer s.close();
    try s.initSchema();

    const tags1 = [_][]const u8{ "urgent", "backend" };
    const id1 = try s.add("fix the login bug", &tags1);
    try std.testing.expect(id1 > 0);

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const item = try s.getById(arena, id1);
    try std.testing.expectEqual(id1, item.id);
    try std.testing.expectEqualStrings("fix the login bug", item.text);
    try std.testing.expectEqual(@as(usize, 2), item.tags.len);
    try std.testing.expectEqualStrings("backend", item.tags[0]);
    try std.testing.expectEqualStrings("urgent", item.tags[1]);
}

test "listActive returns active items in id order with their tags" {
    var s = try Store.open(":memory:");
    defer s.close();
    try s.initSchema();

    const t1 = [_][]const u8{ "urgent" };
    const t2 = [_][]const u8{ "backend", "urgent" };
    _ = try s.add("first", &t1);
    _ = try s.add("second", &t2);
    _ = try s.add("third", &.{});

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const items = try s.listActive(arena);
    try std.testing.expectEqual(@as(usize, 3), items.len);
    try std.testing.expectEqualStrings("first", items[0].text);
    try std.testing.expectEqualStrings("second", items[1].text);
    try std.testing.expectEqualStrings("third", items[2].text);
    try std.testing.expectEqual(@as(usize, 1), items[0].tags.len);
    try std.testing.expectEqual(@as(usize, 2), items[1].tags.len);
    try std.testing.expectEqual(@as(usize, 0), items[2].tags.len);
}

test "listActiveByTags returns items with any matching tag" {
    var s = try Store.open(":memory:");
    defer s.close();
    try s.initSchema();

    _ = try s.add("a", &[_][]const u8{"urgent"});
    _ = try s.add("b", &[_][]const u8{ "urgent", "backend" });
    _ = try s.add("c", &[_][]const u8{"backend"});
    _ = try s.add("d", &[_][]const u8{"docs"});

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const filter = [_][]const u8{ "urgent", "backend" };
    const items = try s.listActiveByTags(arena, &filter);
    try std.testing.expectEqual(@as(usize, 3), items.len);
    try std.testing.expectEqualStrings("a", items[0].text);
    try std.testing.expectEqualStrings("b", items[1].text);
    try std.testing.expectEqualStrings("c", items[2].text);

    const single = [_][]const u8{"docs"};
    const items2 = try s.listActiveByTags(arena, &single);
    try std.testing.expectEqual(@as(usize, 1), items2.len);
    try std.testing.expectEqualStrings("d", items2[0].text);

    const none = try s.listActiveByTags(arena, &[_][]const u8{"missing"});
    try std.testing.expectEqual(@as(usize, 0), none.len);
}
