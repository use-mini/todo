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
