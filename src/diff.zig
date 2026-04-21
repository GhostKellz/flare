//! TOML diff and merge utilities
//! Ported from ZonTOM to Flare
//!
//! Ownership: DiffResult owns all data it contains. The old_value and new_value
//! fields are deep-cloned from the source tables, so DiffResult remains valid
//! even after the original tables are deinitialized. Call DiffResult.deinit()
//! to free all owned memory.

const std = @import("std");
const toml_value = @import("toml_value.zig");

const TomlValue = toml_value.TomlValue;
const TomlTable = toml_value.TomlTable;
const TomlArray = toml_value.TomlArray;

pub const DiffType = enum {
    added,
    removed,
    modified,
};

/// A single difference between two TOML tables.
/// All values are owned by the parent DiffResult.
pub const Diff = struct {
    path: []const u8,
    diff_type: DiffType,
    /// Cloned value from old table (owned by DiffResult)
    old_value: ?TomlValue,
    /// Cloned value from new table (owned by DiffResult)
    new_value: ?TomlValue,
};

/// Result of comparing two TOML tables.
/// Owns all contained data including paths and cloned values.
pub const DiffResult = struct {
    allocator: std.mem.Allocator,
    diffs: std.ArrayList(Diff),

    pub fn init(allocator: std.mem.Allocator) DiffResult {
        return .{
            .allocator = allocator,
            .diffs = .empty,
        };
    }

    /// Free all owned memory including paths and cloned values.
    pub fn deinit(self: *DiffResult) void {
        for (self.diffs.items) |*item| {
            self.allocator.free(item.path);
            if (item.old_value) |*v| v.deinit(self.allocator);
            if (item.new_value) |*v| v.deinit(self.allocator);
        }
        self.diffs.deinit(self.allocator);
    }

    pub fn count(self: *const DiffResult) usize {
        return self.diffs.items.len;
    }

    pub fn isEmpty(self: *const DiffResult) bool {
        return self.diffs.items.len == 0;
    }
};

pub const DiffError = error{
    OutOfMemory,
};

/// Compare two TOML tables and return differences
pub fn diff(allocator: std.mem.Allocator, old: *const TomlTable, new: *const TomlTable) DiffError!DiffResult {
    var result = DiffResult.init(allocator);
    errdefer result.deinit();
    try diffTables(allocator, &result, old, new, "");
    return result;
}

fn appendOwnedDiff(
    allocator: std.mem.Allocator,
    result: *DiffResult,
    path: []const u8,
    diff_type: DiffType,
    old_value: ?TomlValue,
    new_value: ?TomlValue,
) DiffError!void {
    var owned_old: ?TomlValue = null;
    var owned_new: ?TomlValue = null;

    if (old_value) |value| {
        owned_old = value.clone(allocator) catch return DiffError.OutOfMemory;
    }
    errdefer if (owned_old) |*value| value.deinit(allocator);

    if (new_value) |value| {
        owned_new = value.clone(allocator) catch return DiffError.OutOfMemory;
    }
    errdefer if (owned_new) |*value| value.deinit(allocator);

    result.diffs.append(allocator, .{
        .path = path,
        .diff_type = diff_type,
        .old_value = owned_old,
        .new_value = owned_new,
    }) catch return DiffError.OutOfMemory;
}

fn diffTables(
    allocator: std.mem.Allocator,
    result: *DiffResult,
    old: *const TomlTable,
    new: *const TomlTable,
    prefix: []const u8,
) DiffError!void {
    // Check for removed and modified keys
    var old_it = old.map.iterator();
    while (old_it.next()) |old_entry| {
        const key = old_entry.key_ptr.*;
        const old_val = old_entry.value_ptr.*;

        const path = if (prefix.len > 0)
            std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, key }) catch return DiffError.OutOfMemory
        else
            allocator.dupe(u8, key) catch return DiffError.OutOfMemory;

        if (new.get(key)) |new_val| {
            // Key exists in both - check if modified
            if (!valuesEqual(old_val, new_val)) {
                if (old_val == .table and new_val == .table) {
                    // Recursively diff nested tables
                    try diffTables(allocator, result, old_val.table, new_val.table, path);
                    allocator.free(path);
                } else {
                    try appendOwnedDiff(allocator, result, path, .modified, old_val, new_val);
                }
            } else {
                allocator.free(path);
            }
        } else {
            try appendOwnedDiff(allocator, result, path, .removed, old_val, null);
        }
    }

    // Check for added keys
    var new_it = new.map.iterator();
    while (new_it.next()) |new_entry| {
        const key = new_entry.key_ptr.*;
        const new_val = new_entry.value_ptr.*;

        if (old.get(key) == null) {
            const path = if (prefix.len > 0)
                std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, key }) catch return DiffError.OutOfMemory
            else
                allocator.dupe(u8, key) catch return DiffError.OutOfMemory;

            try appendOwnedDiff(allocator, result, path, .added, null, new_val);
        }
    }
}

fn valuesEqual(a: TomlValue, b: TomlValue) bool {
    if (@intFromEnum(a) != @intFromEnum(b)) return false;

    return switch (a) {
        .string => |s| std.mem.eql(u8, s, b.string),
        .integer => |i| i == b.integer,
        .float => |f| f == b.float,
        .boolean => |bo| bo == b.boolean,
        .datetime => |dt| std.meta.eql(dt, b.datetime),
        .date => |d| std.meta.eql(d, b.date),
        .time => |t| std.meta.eql(t, b.time),
        .array => arraysEqual(a.array, b.array),
        .table => false, // Tables compared recursively above
    };
}

fn arraysEqual(a: TomlArray, b: TomlArray) bool {
    if (a.items.items.len != b.items.items.len) return false;
    for (a.items.items, b.items.items) |item_a, item_b| {
        if (!valuesEqual(item_a, item_b)) return false;
    }
    return true;
}

pub const MergeError = error{
    OutOfMemory,
};

/// Merge two TOML tables (overlay overwrites base)
pub fn merge(allocator: std.mem.Allocator, base: *const TomlTable, overlay: *const TomlTable) MergeError!*TomlTable {
    const result = allocator.create(TomlTable) catch return MergeError.OutOfMemory;
    result.* = TomlTable.init(allocator);
    errdefer {
        result.deinit();
        allocator.destroy(result);
    }

    // Copy all from base
    var base_it = base.map.iterator();
    while (base_it.next()) |entry| {
        var val = entry.value_ptr.*;
        result.put(entry.key_ptr.*, val.clone(allocator) catch return MergeError.OutOfMemory) catch return MergeError.OutOfMemory;
    }

    // Merge overlay
    var overlay_it = overlay.map.iterator();
    while (overlay_it.next()) |entry| {
        const key = entry.key_ptr.*;

        if (result.getPtr(key)) |existing| {
            // Key exists - merge if both are tables
            if (existing.* == .table and entry.value_ptr.* == .table) {
                const merged_table = try merge(allocator, existing.table, entry.value_ptr.table);
                // Free old table
                existing.table.deinit();
                allocator.destroy(existing.table);
                existing.* = TomlValue{ .table = merged_table };
            } else {
                // Otherwise replace - free old value first
                existing.deinit(allocator);
                var new_val = entry.value_ptr.*;
                existing.* = new_val.clone(allocator) catch return MergeError.OutOfMemory;
            }
        } else {
            // New key
            var val = entry.value_ptr.*;
            result.put(key, val.clone(allocator) catch return MergeError.OutOfMemory) catch return MergeError.OutOfMemory;
        }
    }

    return result;
}

// ============================================================================
// Tests
// ============================================================================

const flare = @import("root.zig");

test "diff: detect added fields" {
    const testing = std.testing;

    const old_toml = "name = \"test\"";
    const new_toml =
        \\name = "test"
        \\version = "1.0"
    ;

    var old_table = try flare.parseToml(testing.allocator, old_toml);
    defer {
        old_table.deinit();
        testing.allocator.destroy(old_table);
    }

    var new_table = try flare.parseToml(testing.allocator, new_toml);
    defer {
        new_table.deinit();
        testing.allocator.destroy(new_table);
    }

    var result = try diff(testing.allocator, old_table, new_table);
    defer result.deinit();

    try testing.expectEqual(@as(usize, 1), result.count());
    try testing.expectEqual(DiffType.added, result.diffs.items[0].diff_type);
    try testing.expectEqualStrings("version", result.diffs.items[0].path);
}

test "diff: detect removed fields" {
    const testing = std.testing;

    const old_toml =
        \\name = "test"
        \\version = "1.0"
    ;
    const new_toml = "name = \"test\"";

    var old_table = try flare.parseToml(testing.allocator, old_toml);
    defer {
        old_table.deinit();
        testing.allocator.destroy(old_table);
    }

    var new_table = try flare.parseToml(testing.allocator, new_toml);
    defer {
        new_table.deinit();
        testing.allocator.destroy(new_table);
    }

    var result = try diff(testing.allocator, old_table, new_table);
    defer result.deinit();

    try testing.expectEqual(@as(usize, 1), result.count());
    try testing.expectEqual(DiffType.removed, result.diffs.items[0].diff_type);
    try testing.expectEqualStrings("version", result.diffs.items[0].path);
}

test "diff: detect modified fields" {
    const testing = std.testing;

    const old_toml =
        \\name = "old"
        \\version = "1.0"
    ;
    const new_toml =
        \\name = "new"
        \\version = "1.0"
    ;

    var old_table = try flare.parseToml(testing.allocator, old_toml);
    defer {
        old_table.deinit();
        testing.allocator.destroy(old_table);
    }

    var new_table = try flare.parseToml(testing.allocator, new_toml);
    defer {
        new_table.deinit();
        testing.allocator.destroy(new_table);
    }

    var result = try diff(testing.allocator, old_table, new_table);
    defer result.deinit();

    try testing.expectEqual(@as(usize, 1), result.count());
    try testing.expectEqual(DiffType.modified, result.diffs.items[0].diff_type);
    try testing.expectEqualStrings("name", result.diffs.items[0].path);
}

test "diff: nested table changes" {
    const testing = std.testing;

    const old_toml =
        \\[server]
        \\host = "localhost"
        \\port = 8080
    ;
    const new_toml =
        \\[server]
        \\host = "localhost"
        \\port = 9090
    ;

    var old_table = try flare.parseToml(testing.allocator, old_toml);
    defer {
        old_table.deinit();
        testing.allocator.destroy(old_table);
    }

    var new_table = try flare.parseToml(testing.allocator, new_toml);
    defer {
        new_table.deinit();
        testing.allocator.destroy(new_table);
    }

    var result = try diff(testing.allocator, old_table, new_table);
    defer result.deinit();

    try testing.expectEqual(@as(usize, 1), result.count());
    try testing.expectEqual(DiffType.modified, result.diffs.items[0].diff_type);
    try testing.expectEqualStrings("server.port", result.diffs.items[0].path);
}

test "diff: no changes" {
    const testing = std.testing;

    const toml =
        \\name = "test"
        \\version = "1.0"
    ;

    var old_table = try flare.parseToml(testing.allocator, toml);
    defer {
        old_table.deinit();
        testing.allocator.destroy(old_table);
    }

    var new_table = try flare.parseToml(testing.allocator, toml);
    defer {
        new_table.deinit();
        testing.allocator.destroy(new_table);
    }

    var result = try diff(testing.allocator, old_table, new_table);
    defer result.deinit();

    try testing.expect(result.isEmpty());
}

test "merge: simple merge" {
    const testing = std.testing;

    const base_toml =
        \\name = "base"
        \\version = "1.0"
    ;
    const overlay_toml = "name = \"overlay\"";

    var base = try flare.parseToml(testing.allocator, base_toml);
    defer {
        base.deinit();
        testing.allocator.destroy(base);
    }

    var overlay = try flare.parseToml(testing.allocator, overlay_toml);
    defer {
        overlay.deinit();
        testing.allocator.destroy(overlay);
    }

    var merged = try merge(testing.allocator, base, overlay);
    defer {
        merged.deinit();
        testing.allocator.destroy(merged);
    }

    try testing.expectEqualStrings("overlay", merged.getString("name").?);
    try testing.expectEqualStrings("1.0", merged.getString("version").?);
}

test "merge: nested table merge" {
    const testing = std.testing;

    const base_toml =
        \\[server]
        \\host = "localhost"
        \\port = 8080
    ;
    const overlay_toml =
        \\[server]
        \\port = 9090
    ;

    var base = try flare.parseToml(testing.allocator, base_toml);
    defer {
        base.deinit();
        testing.allocator.destroy(base);
    }

    var overlay = try flare.parseToml(testing.allocator, overlay_toml);
    defer {
        overlay.deinit();
        testing.allocator.destroy(overlay);
    }

    var merged = try merge(testing.allocator, base, overlay);
    defer {
        merged.deinit();
        testing.allocator.destroy(merged);
    }

    const server = merged.getTable("server").?;
    try testing.expectEqualStrings("localhost", server.getString("host").?);
    try testing.expectEqual(@as(i64, 9090), server.getInt("port").?);
}

test "merge: add new keys" {
    const testing = std.testing;

    const base_toml = "name = \"base\"";
    const overlay_toml =
        \\version = "1.0"
        \\debug = true
    ;

    var base = try flare.parseToml(testing.allocator, base_toml);
    defer {
        base.deinit();
        testing.allocator.destroy(base);
    }

    var overlay = try flare.parseToml(testing.allocator, overlay_toml);
    defer {
        overlay.deinit();
        testing.allocator.destroy(overlay);
    }

    var merged = try merge(testing.allocator, base, overlay);
    defer {
        merged.deinit();
        testing.allocator.destroy(merged);
    }

    try testing.expectEqualStrings("base", merged.getString("name").?);
    try testing.expectEqualStrings("1.0", merged.getString("version").?);
    try testing.expect(merged.getBool("debug").?);
}

// ============================================================================
// Ownership Tests - verify DiffResult owns its data independently
// ============================================================================

test "diff: result valid after source tables freed (string values)" {
    const testing = std.testing;

    // Create diff result in outer scope
    var result: DiffResult = undefined;

    {
        // Inner scope - tables will be freed when this block ends
        const old_toml = "name = \"original-name\"";
        const new_toml = "name = \"modified-name\"";

        var old_table = try flare.parseToml(testing.allocator, old_toml);
        var new_table = try flare.parseToml(testing.allocator, new_toml);

        result = try diff(testing.allocator, old_table, new_table);

        // Free source tables BEFORE accessing diff result
        new_table.deinit();
        testing.allocator.destroy(new_table);
        old_table.deinit();
        testing.allocator.destroy(old_table);
    }
    defer result.deinit();

    // DiffResult should still be valid with cloned string values
    try testing.expectEqual(@as(usize, 1), result.count());
    try testing.expectEqual(DiffType.modified, result.diffs.items[0].diff_type);
    try testing.expectEqualStrings("name", result.diffs.items[0].path);
    try testing.expectEqualStrings("original-name", result.diffs.items[0].old_value.?.string);
    try testing.expectEqualStrings("modified-name", result.diffs.items[0].new_value.?.string);
}

test "diff: result valid after source tables freed (nested tables)" {
    const testing = std.testing;

    var result: DiffResult = undefined;

    {
        const old_toml =
            \\[database]
            \\host = "old-host"
            \\port = 5432
        ;
        const new_toml =
            \\[database]
            \\host = "new-host"
            \\port = 5432
        ;

        var old_table = try flare.parseToml(testing.allocator, old_toml);
        var new_table = try flare.parseToml(testing.allocator, new_toml);

        result = try diff(testing.allocator, old_table, new_table);

        // Free source tables
        new_table.deinit();
        testing.allocator.destroy(new_table);
        old_table.deinit();
        testing.allocator.destroy(old_table);
    }
    defer result.deinit();

    // DiffResult should have cloned the nested string values
    try testing.expectEqual(@as(usize, 1), result.count());
    try testing.expectEqualStrings("database.host", result.diffs.items[0].path);
    try testing.expectEqualStrings("old-host", result.diffs.items[0].old_value.?.string);
    try testing.expectEqualStrings("new-host", result.diffs.items[0].new_value.?.string);
}

test "diff: result valid after source tables freed (array values)" {
    const testing = std.testing;

    var result: DiffResult = undefined;

    {
        const old_toml = "ports = [8080, 9090]";
        const new_toml = "ports = [3000, 4000, 5000]";

        var old_table = try flare.parseToml(testing.allocator, old_toml);
        var new_table = try flare.parseToml(testing.allocator, new_toml);

        result = try diff(testing.allocator, old_table, new_table);

        // Free source tables
        new_table.deinit();
        testing.allocator.destroy(new_table);
        old_table.deinit();
        testing.allocator.destroy(old_table);
    }
    defer result.deinit();

    // DiffResult should have cloned the array values
    try testing.expectEqual(@as(usize, 1), result.count());
    try testing.expectEqual(DiffType.modified, result.diffs.items[0].diff_type);
    try testing.expectEqualStrings("ports", result.diffs.items[0].path);

    const old_arr = result.diffs.items[0].old_value.?.array;
    try testing.expectEqual(@as(usize, 2), old_arr.items.items.len);
    try testing.expectEqual(@as(i64, 8080), old_arr.items.items[0].integer);

    const new_arr = result.diffs.items[0].new_value.?.array;
    try testing.expectEqual(@as(usize, 3), new_arr.items.items.len);
    try testing.expectEqual(@as(i64, 3000), new_arr.items.items[0].integer);
}
