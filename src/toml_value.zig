//! Native TOML value types for full TOML 1.0 support
//! These types mirror the TOML specification and enable advanced features
//! like struct deserialization, stringify, and diff/merge.

const std = @import("std");
const root = @import("root.zig");

/// Native TOML value type (full TOML 1.0 support)
pub const TomlValue = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    datetime: Datetime,
    date: Date,
    time: Time,
    array: TomlArray,
    table: *TomlTable,

    pub fn deinit(self: *TomlValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            .array => |*arr| arr.deinit(allocator),
            .table => |tbl| {
                tbl.deinit();
                allocator.destroy(tbl);
            },
            else => {},
        }
    }

    /// Clone a TomlValue (deep copy)
    pub fn clone(self: TomlValue, allocator: std.mem.Allocator) error{OutOfMemory}!TomlValue {
        return switch (self) {
            .string => |s| TomlValue{ .string = try allocator.dupe(u8, s) },
            .integer => |i| TomlValue{ .integer = i },
            .float => |f| TomlValue{ .float = f },
            .boolean => |b| TomlValue{ .boolean = b },
            .datetime => |dt| TomlValue{ .datetime = dt },
            .date => |d| TomlValue{ .date = d },
            .time => |t| TomlValue{ .time = t },
            .array => |arr| blk: {
                var new_arr = TomlArray.init(allocator);
                try new_arr.items.ensureTotalCapacity(allocator, arr.items.items.len);
                for (arr.items.items) |item| {
                    var item_copy = item;
                    try new_arr.items.append(allocator, try item_copy.clone(allocator));
                }
                break :blk TomlValue{ .array = new_arr };
            },
            .table => |tbl| blk: {
                const new_tbl = try allocator.create(TomlTable);
                new_tbl.* = try tbl.clone();
                break :blk TomlValue{ .table = new_tbl };
            },
        };
    }
};

/// Array of TOML values
pub const TomlArray = struct {
    items: std.ArrayList(TomlValue),

    pub fn init(_: std.mem.Allocator) TomlArray {
        return .{ .items = .empty };
    }

    pub fn deinit(self: *TomlArray, allocator: std.mem.Allocator) void {
        for (self.items.items) |*item| {
            item.deinit(allocator);
        }
        self.items.deinit(allocator);
    }

    pub fn append(self: *TomlArray, allocator: std.mem.Allocator, value: TomlValue) !void {
        try self.items.append(allocator, value);
    }

    pub fn len(self: *const TomlArray) usize {
        return self.items.items.len;
    }
};

/// TOML table (string-keyed map)
pub const TomlTable = struct {
    map: std.StringHashMap(TomlValue),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TomlTable {
        return .{
            .map = std.StringHashMap(TomlValue).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TomlTable) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var val = entry.value_ptr.*;
            val.deinit(self.allocator);
        }
        self.map.deinit();
    }

    pub fn put(self: *TomlTable, key: []const u8, value: TomlValue) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);
        try self.map.put(key_copy, value);
    }

    pub fn get(self: *const TomlTable, key: []const u8) ?TomlValue {
        return self.map.get(key);
    }

    pub fn getPtr(self: *TomlTable, key: []const u8) ?*TomlValue {
        return self.map.getPtr(key);
    }

    pub fn contains(self: *const TomlTable, key: []const u8) bool {
        return self.map.contains(key);
    }

    pub fn count(self: *const TomlTable) usize {
        return self.map.count();
    }

    pub fn iterator(self: *const TomlTable) std.StringHashMap(TomlValue).Iterator {
        return self.map.iterator();
    }

    /// Deep clone the table
    pub fn clone(self: *const TomlTable) error{OutOfMemory}!TomlTable {
        var new_table = TomlTable.init(self.allocator);
        var it = self.map.iterator();
        while (it.next()) |entry| {
            var val = entry.value_ptr.*;
            try new_table.put(entry.key_ptr.*, try val.clone(self.allocator));
        }
        return new_table;
    }

    // ========================================================================
    // Typed accessor helpers for ergonomic TOML value retrieval
    // ========================================================================

    /// Get a string value by key
    pub fn getString(self: *const TomlTable, key: []const u8) ?[]const u8 {
        const val = self.map.get(key) orelse return null;
        return if (val == .string) val.string else null;
    }

    /// Get an integer value by key
    pub fn getInt(self: *const TomlTable, key: []const u8) ?i64 {
        const val = self.map.get(key) orelse return null;
        return if (val == .integer) val.integer else null;
    }

    /// Get a boolean value by key
    pub fn getBool(self: *const TomlTable, key: []const u8) ?bool {
        const val = self.map.get(key) orelse return null;
        return if (val == .boolean) val.boolean else null;
    }

    /// Get a float value by key
    pub fn getFloat(self: *const TomlTable, key: []const u8) ?f64 {
        const val = self.map.get(key) orelse return null;
        return if (val == .float) val.float else null;
    }

    /// Get a nested table by key
    pub fn getTable(self: *const TomlTable, key: []const u8) ?*TomlTable {
        const val = self.map.get(key) orelse return null;
        return if (val == .table) val.table else null;
    }

    /// Get an array by key
    pub fn getArray(self: *const TomlTable, key: []const u8) ?TomlArray {
        const val = self.map.get(key) orelse return null;
        return if (val == .array) val.array else null;
    }

    /// Get a datetime value by key
    pub fn getDatetime(self: *const TomlTable, key: []const u8) ?Datetime {
        const val = self.map.get(key) orelse return null;
        return if (val == .datetime) val.datetime else null;
    }

    /// Get a date value by key
    pub fn getDate(self: *const TomlTable, key: []const u8) ?Date {
        const val = self.map.get(key) orelse return null;
        return if (val == .date) val.date else null;
    }

    /// Get a time value by key
    pub fn getTime(self: *const TomlTable, key: []const u8) ?Time {
        const val = self.map.get(key) orelse return null;
        return if (val == .time) val.time else null;
    }

    /// Get a value by dotted path (e.g., "server.host")
    pub fn getPath(self: *const TomlTable, path: []const u8) ?TomlValue {
        var current: *const TomlTable = self;
        var it = std.mem.splitScalar(u8, path, '.');

        while (it.next()) |segment| {
            const remaining = it.rest();
            const val = current.map.get(segment) orelse return null;

            if (remaining.len == 0) {
                // Last segment - return the value
                return val;
            } else {
                // More segments to traverse - must be a table
                if (val == .table) {
                    current = val.table;
                } else {
                    return null;
                }
            }
        }

        return null;
    }

    /// Get a string by dotted path (e.g., "server.host")
    pub fn getPathString(self: *const TomlTable, path: []const u8) ?[]const u8 {
        const val = self.getPath(path) orelse return null;
        return if (val == .string) val.string else null;
    }

    /// Get an integer by dotted path (e.g., "server.port")
    pub fn getPathInt(self: *const TomlTable, path: []const u8) ?i64 {
        const val = self.getPath(path) orelse return null;
        return if (val == .integer) val.integer else null;
    }

    /// Get a boolean by dotted path
    pub fn getPathBool(self: *const TomlTable, path: []const u8) ?bool {
        const val = self.getPath(path) orelse return null;
        return if (val == .boolean) val.boolean else null;
    }
};

/// RFC 3339 datetime with timezone
pub const Datetime = struct {
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    nanosecond: u32 = 0,
    offset_minutes: ?i16 = null, // null = local time, 0 = UTC

    pub fn format(
        self: Datetime,
        comptime fmt: []const u8,
        options: anytype,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{
            self.year,
            self.month,
            self.day,
            self.hour,
            self.minute,
            self.second,
        });
        if (self.nanosecond > 0) {
            try writer.print(".{d:0>9}", .{self.nanosecond});
        }
        if (self.offset_minutes) |offset| {
            if (offset == 0) {
                try writer.writeAll("Z");
            } else {
                const sign: u8 = if (offset >= 0) '+' else '-';
                const abs_offset: u16 = @intCast(@abs(offset));
                const hours = abs_offset / 60;
                const mins = abs_offset % 60;
                try writer.print("{c}{d:0>2}:{d:0>2}", .{ sign, hours, mins });
            }
        }
    }

    /// Create a UTC datetime
    pub fn utc(year: u16, month: u8, day: u8, hour: u8, minute: u8, second: u8) Datetime {
        return .{
            .year = year,
            .month = month,
            .day = day,
            .hour = hour,
            .minute = minute,
            .second = second,
            .offset_minutes = 0,
        };
    }

    /// Create a local datetime (no timezone)
    pub fn local(year: u16, month: u8, day: u8, hour: u8, minute: u8, second: u8) Datetime {
        return .{
            .year = year,
            .month = month,
            .day = day,
            .hour = hour,
            .minute = minute,
            .second = second,
            .offset_minutes = null,
        };
    }
};

/// Date only (no time component)
pub const Date = struct {
    year: u16,
    month: u8,
    day: u8,

    pub fn format(
        self: Date,
        comptime fmt: []const u8,
        options: anytype,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{d:0>4}-{d:0>2}-{d:0>2}", .{ self.year, self.month, self.day });
    }

    pub fn init(year: u16, month: u8, day: u8) Date {
        return .{ .year = year, .month = month, .day = day };
    }
};

/// Time only (no date component)
pub const Time = struct {
    hour: u8,
    minute: u8,
    second: u8,
    nanosecond: u32 = 0,

    pub fn format(
        self: Time,
        comptime fmt: []const u8,
        options: anytype,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{d:0>2}:{d:0>2}:{d:0>2}", .{ self.hour, self.minute, self.second });
        if (self.nanosecond > 0) {
            try writer.print(".{d:0>9}", .{self.nanosecond});
        }
    }

    pub fn init(hour: u8, minute: u8, second: u8) Time {
        return .{ .hour = hour, .minute = minute, .second = second };
    }

    pub fn initWithNano(hour: u8, minute: u8, second: u8, nanosecond: u32) Time {
        return .{ .hour = hour, .minute = minute, .second = second, .nanosecond = nanosecond };
    }
};

// ============================================================================
// Conversion functions between TomlValue and flare's Config Value
// ============================================================================

/// Convert TomlValue to flare's Value (for Config integration)
pub fn tomlValueToFlareValue(allocator: std.mem.Allocator, tv: TomlValue) !root.Value {
    return switch (tv) {
        .string => |s| root.Value{ .string_value = try allocator.dupe(u8, s) },
        .integer => |i| root.Value{ .int_value = i },
        .float => |f| root.Value{ .float_value = f },
        .boolean => |b| root.Value{ .bool_value = b },
        // Datetime types convert to ISO 8601 strings
        .datetime => |dt| blk: {
            var buf: [64]u8 = undefined;
            var writer: std.Io.Writer = .fixed(&buf);
            dt.format("", .{}, &writer) catch return error.OutOfMemory;
            break :blk root.Value{ .string_value = try allocator.dupe(u8, buf[0..writer.end]) };
        },
        .date => |d| blk: {
            var buf: [16]u8 = undefined;
            var writer: std.Io.Writer = .fixed(&buf);
            d.format("", .{}, &writer) catch return error.OutOfMemory;
            break :blk root.Value{ .string_value = try allocator.dupe(u8, buf[0..writer.end]) };
        },
        .time => |t| blk: {
            var buf: [32]u8 = undefined;
            var writer: std.Io.Writer = .fixed(&buf);
            t.format("", .{}, &writer) catch return error.OutOfMemory;
            break :blk root.Value{ .string_value = try allocator.dupe(u8, buf[0..writer.end]) };
        },
        .array => |arr| blk: {
            var array_list: std.ArrayList(root.Value) = .empty;
            try array_list.ensureTotalCapacity(allocator, arr.items.items.len);
            for (arr.items.items) |item| {
                try array_list.append(allocator, try tomlValueToFlareValue(allocator, item));
            }
            break :blk root.Value{ .array_value = array_list };
        },
        .table => |tbl| blk: {
            var map = std.StringHashMap(root.Value).init(allocator);
            var it = tbl.map.iterator();
            while (it.next()) |entry| {
                const key = try allocator.dupe(u8, entry.key_ptr.*);
                const value = try tomlValueToFlareValue(allocator, entry.value_ptr.*);
                try map.put(key, value);
            }
            break :blk root.Value{ .map_value = map };
        },
    };
}

/// Convert flare's Value to TomlValue (for stringify, etc.)
pub fn flareValueToTomlValue(allocator: std.mem.Allocator, v: root.Value) !TomlValue {
    return switch (v) {
        .null_value => TomlValue{ .string = try allocator.dupe(u8, "") },
        .bool_value => |b| TomlValue{ .boolean = b },
        .int_value => |i| TomlValue{ .integer = i },
        .float_value => |f| TomlValue{ .float = f },
        .string_value => |s| TomlValue{ .string = try allocator.dupe(u8, s) },
        .array_value => |arr| blk: {
            var toml_arr = TomlArray.init(allocator);
            try toml_arr.items.ensureTotalCapacity(allocator, arr.items.len);
            for (arr.items) |item| {
                try toml_arr.items.append(allocator, try flareValueToTomlValue(allocator, item));
            }
            break :blk TomlValue{ .array = toml_arr };
        },
        .map_value => |map| blk: {
            const tbl = try allocator.create(TomlTable);
            tbl.* = TomlTable.init(allocator);
            var it = map.iterator();
            while (it.next()) |entry| {
                try tbl.put(entry.key_ptr.*, try flareValueToTomlValue(allocator, entry.value_ptr.*));
            }
            break :blk TomlValue{ .table = tbl };
        },
    };
}

// ============================================================================
// Tests
// ============================================================================

test "TomlTable basic operations" {
    const testing = std.testing;

    var table = TomlTable.init(testing.allocator);
    defer table.deinit();

    const name_str = try testing.allocator.dupe(u8, "flare");
    try table.put("name", .{ .string = name_str });
    try table.put("version", .{ .integer = 1 });
    try table.put("enabled", .{ .boolean = true });

    const name = table.get("name");
    try testing.expect(name != null);
    try testing.expectEqualStrings("flare", name.?.string);

    const version = table.get("version");
    try testing.expect(version != null);
    try testing.expectEqual(@as(i64, 1), version.?.integer);

    try testing.expect(table.contains("enabled"));
    try testing.expect(!table.contains("nonexistent"));
    try testing.expectEqual(@as(usize, 3), table.count());
}

test "TomlArray operations" {
    const testing = std.testing;

    var arr = TomlArray.init(testing.allocator);
    defer arr.deinit(testing.allocator);

    try arr.append(testing.allocator, .{ .integer = 1 });
    try arr.append(testing.allocator, .{ .integer = 2 });
    try arr.append(testing.allocator, .{ .integer = 3 });

    try testing.expectEqual(@as(usize, 3), arr.len());
    try testing.expectEqual(@as(i64, 2), arr.items.items[1].integer);
}

test "Datetime formatting" {
    const testing = std.testing;

    const dt = Datetime.utc(2024, 12, 25, 10, 30, 45);
    var buf: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    try dt.format("", .{}, &writer);
    try testing.expectEqualStrings("2024-12-25T10:30:45Z", buf[0..writer.end]);

    // Test with offset
    const dt_offset = Datetime{
        .year = 2024,
        .month = 6,
        .day = 15,
        .hour = 14,
        .minute = 30,
        .second = 0,
        .offset_minutes = -300, // UTC-5
    };
    var buf2: [64]u8 = undefined;
    var writer2: std.Io.Writer = .fixed(&buf2);
    try dt_offset.format("", .{}, &writer2);
    try testing.expectEqualStrings("2024-06-15T14:30:00-05:00", buf2[0..writer2.end]);
}

test "Date formatting" {
    const testing = std.testing;

    const d = Date.init(2024, 1, 15);
    var buf: [16]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    try d.format("", .{}, &writer);
    try testing.expectEqualStrings("2024-01-15", buf[0..writer.end]);
}

test "Time formatting" {
    const testing = std.testing;

    const t = Time.init(14, 30, 45);
    var buf: [32]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    try t.format("", .{}, &writer);
    try testing.expectEqualStrings("14:30:45", buf[0..writer.end]);

    // Test with nanoseconds
    const t_nano = Time.initWithNano(10, 15, 30, 123456789);
    var buf2: [32]u8 = undefined;
    var writer2: std.Io.Writer = .fixed(&buf2);
    try t_nano.format("", .{}, &writer2);
    try testing.expectEqualStrings("10:15:30.123456789", buf2[0..writer2.end]);
}

test "TomlValue clone" {
    const testing = std.testing;

    // Test string clone
    var str_val = TomlValue{ .string = try testing.allocator.dupe(u8, "hello") };
    var cloned = try str_val.clone(testing.allocator);
    defer cloned.deinit(testing.allocator);
    defer str_val.deinit(testing.allocator);

    try testing.expectEqualStrings("hello", cloned.string);
    try testing.expect(str_val.string.ptr != cloned.string.ptr); // Different memory
}

test "conversion to flare Value" {
    const testing = std.testing;

    // Test integer
    const int_val = TomlValue{ .integer = 42 };
    const flare_int = try tomlValueToFlareValue(testing.allocator, int_val);
    try testing.expectEqual(@as(i64, 42), flare_int.int_value);

    // Test boolean
    const bool_val = TomlValue{ .boolean = true };
    const flare_bool = try tomlValueToFlareValue(testing.allocator, bool_val);
    try testing.expect(flare_bool.bool_value);

    // Test string
    var str_val = TomlValue{ .string = try testing.allocator.dupe(u8, "test") };
    defer str_val.deinit(testing.allocator);
    const flare_str = try tomlValueToFlareValue(testing.allocator, str_val);
    defer testing.allocator.free(flare_str.string_value);
    try testing.expectEqualStrings("test", flare_str.string_value);
}

test "TomlTable typed accessors" {
    const testing = std.testing;

    var table = TomlTable.init(testing.allocator);
    defer table.deinit();

    // Add various value types
    try table.put("name", .{ .string = try testing.allocator.dupe(u8, "flare") });
    try table.put("port", .{ .integer = 8080 });
    try table.put("enabled", .{ .boolean = true });
    try table.put("ratio", .{ .float = 0.75 });

    // Test typed accessors
    try testing.expectEqualStrings("flare", table.getString("name").?);
    try testing.expectEqual(@as(i64, 8080), table.getInt("port").?);
    try testing.expect(table.getBool("enabled").?);
    try testing.expectApproxEqAbs(@as(f64, 0.75), table.getFloat("ratio").?, 0.001);

    // Test missing keys return null
    try testing.expect(table.getString("missing") == null);
    try testing.expect(table.getInt("missing") == null);

    // Test type mismatch returns null
    try testing.expect(table.getString("port") == null); // port is integer, not string
    try testing.expect(table.getInt("name") == null); // name is string, not integer
}

test "TomlTable nested table accessor" {
    const testing = std.testing;

    var table = TomlTable.init(testing.allocator);
    defer table.deinit();

    // Create nested table
    const inner = try testing.allocator.create(TomlTable);
    inner.* = TomlTable.init(testing.allocator);
    try inner.put("host", .{ .string = try testing.allocator.dupe(u8, "localhost") });
    try inner.put("port", .{ .integer = 3000 });
    try table.put("server", .{ .table = inner });

    // Test getTable
    const server = table.getTable("server");
    try testing.expect(server != null);
    try testing.expectEqualStrings("localhost", server.?.getString("host").?);
    try testing.expectEqual(@as(i64, 3000), server.?.getInt("port").?);

    // Test missing table
    try testing.expect(table.getTable("missing") == null);

    // Test type mismatch
    try table.put("scalar", .{ .integer = 42 });
    try testing.expect(table.getTable("scalar") == null);
}

test "TomlTable getPath dotted access" {
    const testing = std.testing;

    var root_table = TomlTable.init(testing.allocator);
    defer root_table.deinit();

    // Create nested structure: database.connection.host = "localhost"
    const connection = try testing.allocator.create(TomlTable);
    connection.* = TomlTable.init(testing.allocator);
    try connection.put("host", .{ .string = try testing.allocator.dupe(u8, "localhost") });
    try connection.put("port", .{ .integer = 5432 });

    const database = try testing.allocator.create(TomlTable);
    database.* = TomlTable.init(testing.allocator);
    try database.put("connection", .{ .table = connection });
    try database.put("name", .{ .string = try testing.allocator.dupe(u8, "mydb") });

    try root_table.put("database", .{ .table = database });
    try root_table.put("debug", .{ .boolean = true });

    // Test deep path access
    try testing.expectEqualStrings("localhost", root_table.getPathString("database.connection.host").?);
    try testing.expectEqual(@as(i64, 5432), root_table.getPathInt("database.connection.port").?);
    try testing.expectEqualStrings("mydb", root_table.getPathString("database.name").?);

    // Test single-level path (should work like regular get)
    try testing.expect(root_table.getPathBool("debug").?);

    // Test missing path
    try testing.expect(root_table.getPath("database.nonexistent") == null);
    try testing.expect(root_table.getPath("nonexistent.path") == null);

    // Test path through non-table value returns null
    try testing.expect(root_table.getPath("debug.nested") == null);
}
