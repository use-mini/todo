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
