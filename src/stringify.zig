//! TOML stringification - convert TomlTable back to TOML format
const std = @import("std");
const toml_value = @import("toml_value.zig");
const toml_parser = @import("toml_parser.zig");

const TomlValue = toml_value.TomlValue;
const TomlTable = toml_value.TomlTable;
const TomlArray = toml_value.TomlArray;
const Datetime = toml_value.Datetime;
const Date = toml_value.Date;
const Time = toml_value.Time;

pub const StringifyError = error{
    OutOfMemory,
    InvalidValue,
};

pub const FormatOptions = struct {
    /// Indent size for nested structures
    indent: usize = 2,
    /// Use spaces instead of tabs
    use_spaces: bool = true,
    /// Add blank lines between sections
    blank_lines: bool = true,
    /// Sort keys alphabetically
    sort_keys: bool = false,
    /// Inline tables for short tables (max keys)
    inline_table_threshold: usize = 3,
};

pub const Stringifier = struct {
    allocator: std.mem.Allocator,
    options: FormatOptions,
    output: std.ArrayList(u8),
    current_indent: usize,

    pub fn init(allocator: std.mem.Allocator, options: FormatOptions) Stringifier {
        return .{
            .allocator = allocator,
            .options = options,
            .output = .empty,
            .current_indent = 0,
        };
    }

    pub fn deinit(self: *Stringifier) void {
        self.output.deinit(self.allocator);
    }

    pub fn stringify(self: *Stringifier, table: *const TomlTable) StringifyError![]const u8 {
        try self.stringifyTable(table, &.{});
        return self.output.items;
    }

    fn stringifyTable(self: *Stringifier, table: *const TomlTable, path: []const []const u8) StringifyError!void {
        var keys: std.ArrayList([]const u8) = .empty;
        defer keys.deinit(self.allocator);

        // Collect all keys
        var it = table.map.iterator();
        while (it.next()) |entry| {
            try keys.append(self.allocator, entry.key_ptr.*);
        }

        // Sort if requested
        if (self.options.sort_keys) {
            std.mem.sort([]const u8, keys.items, {}, struct {
                fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                    return std.mem.order(u8, a, b) == .lt;
                }
            }.lessThan);
        }

        // First pass: write simple key-value pairs
        var first_value = true;
        for (keys.items) |key| {
            const val = table.map.get(key).?;

            // Skip tables and arrays of tables for first pass
            if (val == .table) continue;
            if (val == .array) {
                // Check if it's an array of tables
                if (val.array.items.items.len > 0 and val.array.items.items[0] == .table) {
                    continue;
                }
            }

            if (!first_value and self.options.blank_lines and path.len == 0) {
                // Don't add blank lines for simple values
            }
            first_value = false;

            try self.writeIndent();
            try self.writeKey(key);
            try self.output.appendSlice(self.allocator, " = ");
            try self.writeValue(&val);
            try self.output.append(self.allocator, '\n');
        }

        // Second pass: write tables
        var first_table = true;
        for (keys.items) |key| {
            const val = table.map.get(key).?;

            if (val != .table) continue;

            if (!first_table and self.options.blank_lines) {
                try self.output.append(self.allocator, '\n');
            }
            first_table = false;

            // Build new path
            var new_path: std.ArrayList([]const u8) = .empty;
            defer new_path.deinit(self.allocator);
            try new_path.appendSlice(self.allocator, path);
            try new_path.append(self.allocator, key);

            // Write table header
            if (new_path.items.len > 0) {
                try self.output.append(self.allocator, '[');
                for (new_path.items, 0..) |segment, i| {
                    if (i > 0) try self.output.append(self.allocator, '.');
                    try self.writeKey(segment);
                }
                try self.output.appendSlice(self.allocator, "]\n");
            }

            try self.stringifyTable(val.table, new_path.items);
        }

        // Third pass: write array of tables
        for (keys.items) |key| {
            const val = table.map.get(key).?;

            if (val != .array) continue;
            if (val.array.items.items.len == 0) continue;
            if (val.array.items.items[0] != .table) continue;

            // Build new path
            var new_path: std.ArrayList([]const u8) = .empty;
            defer new_path.deinit(self.allocator);
            try new_path.appendSlice(self.allocator, path);
            try new_path.append(self.allocator, key);

            // Write each table in the array
            for (val.array.items.items) |item| {
                if (self.options.blank_lines) {
                    try self.output.append(self.allocator, '\n');
                }

                try self.output.appendSlice(self.allocator, "[[");
                for (new_path.items, 0..) |segment, i| {
                    if (i > 0) try self.output.append(self.allocator, '.');
                    try self.writeKey(segment);
                }
                try self.output.appendSlice(self.allocator, "]]\n");

                try self.stringifyTable(item.table, new_path.items);
            }
        }
    }

    fn writeValue(self: *Stringifier, val: *const TomlValue) StringifyError!void {
        switch (val.*) {
            .string => |s| try self.writeString(s),
            .integer => |i| try self.appendFmt("{d}", .{i}),
            .float => |f| {
                if (std.math.isNan(f)) {
                    try self.output.appendSlice(self.allocator, "nan");
                } else if (std.math.isPositiveInf(f)) {
                    try self.output.appendSlice(self.allocator, "inf");
                } else if (std.math.isNegativeInf(f)) {
                    try self.output.appendSlice(self.allocator, "-inf");
                } else {
                    try self.appendFmt("{d}", .{f});
                }
            },
            .boolean => |b| try self.output.appendSlice(self.allocator, if (b) "true" else "false"),
            .datetime => |dt| try self.writeDatetime(dt),
            .date => |d| try self.writeDate(d),
            .time => |t| try self.writeTime(t),
            .array => |arr| try self.writeArray(&arr),
            .table => |tbl| try self.writeInlineTable(tbl),
        }
    }

    fn writeString(self: *Stringifier, s: []const u8) StringifyError!void {
        try self.output.append(self.allocator, '"');

        for (s) |c| {
            switch (c) {
                '"' => try self.output.appendSlice(self.allocator, "\\\""),
                '\\' => try self.output.appendSlice(self.allocator, "\\\\"),
                '\n' => try self.output.appendSlice(self.allocator, "\\n"),
                '\r' => try self.output.appendSlice(self.allocator, "\\r"),
                '\t' => try self.output.appendSlice(self.allocator, "\\t"),
                '\x08' => try self.output.appendSlice(self.allocator, "\\b"),
                '\x0C' => try self.output.appendSlice(self.allocator, "\\f"),
                else => try self.output.append(self.allocator, c),
            }
        }

        try self.output.append(self.allocator, '"');
    }

    fn writeDatetime(self: *Stringifier, dt: Datetime) StringifyError!void {
        try self.appendFmt("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{
            dt.year, dt.month,  dt.day,
            dt.hour, dt.minute, dt.second,
        });

        // Preserve fractional seconds (nanoseconds)
        if (dt.nanosecond > 0) {
            try self.writeFractionalSeconds(dt.nanosecond);
        }

        if (dt.offset_minutes) |offset| {
            if (offset == 0) {
                try self.output.append(self.allocator, 'Z');
            } else {
                const sign: u8 = if (offset < 0) '-' else '+';
                const abs_offset: u16 = @abs(offset);
                const hours = abs_offset / 60;
                const minutes = abs_offset % 60;
                try self.appendFmt("{c}{d:0>2}:{d:0>2}", .{ sign, hours, minutes });
            }
        }
    }

    fn writeDate(self: *Stringifier, d: Date) StringifyError!void {
        try self.appendFmt("{d:0>4}-{d:0>2}-{d:0>2}", .{ d.year, d.month, d.day });
    }

    fn writeTime(self: *Stringifier, t: Time) StringifyError!void {
        try self.appendFmt("{d:0>2}:{d:0>2}:{d:0>2}", .{ t.hour, t.minute, t.second });

        // Preserve fractional seconds (nanoseconds)
        if (t.nanosecond > 0) {
            try self.writeFractionalSeconds(t.nanosecond);
        }
    }

    /// Write fractional seconds, trimming trailing zeros
    fn writeFractionalSeconds(self: *Stringifier, nanosecond: u32) StringifyError!void {
        try self.output.append(self.allocator, '.');

        // Format as 9 digits, then trim trailing zeros
        var buf: [9]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "{d:0>9}", .{nanosecond}) catch return error.InvalidValue;

        // Find last non-zero digit
        var end: usize = 9;
        while (end > 1 and buf[end - 1] == '0') {
            end -= 1;
        }

        try self.output.appendSlice(self.allocator, buf[0..end]);
    }

    fn writeArray(self: *Stringifier, arr: *const TomlArray) StringifyError!void {
        try self.output.append(self.allocator, '[');

        for (arr.items.items, 0..) |item, i| {
            if (i > 0) try self.output.appendSlice(self.allocator, ", ");
            try self.writeValue(&item);
        }

        try self.output.append(self.allocator, ']');
    }

    fn writeInlineTable(self: *Stringifier, tbl: *const TomlTable) StringifyError!void {
        try self.output.appendSlice(self.allocator, "{ ");

        var it = tbl.map.iterator();
        var first = true;
        while (it.next()) |entry| {
            if (!first) try self.output.appendSlice(self.allocator, ", ");
            first = false;

            try self.writeKey(entry.key_ptr.*);
            try self.output.appendSlice(self.allocator, " = ");
            try self.writeValue(entry.value_ptr);
        }

        try self.output.appendSlice(self.allocator, " }");
    }

    fn writeKey(self: *Stringifier, key: []const u8) StringifyError!void {
        // Check if key needs quoting
        const needs_quotes = for (key) |c| {
            if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-') {
                break true;
            }
        } else false;

        if (needs_quotes) {
            try self.writeString(key);
        } else {
            try self.output.appendSlice(self.allocator, key);
        }
    }

    fn writeIndent(self: *Stringifier) StringifyError!void {
        const indent_char: u8 = if (self.options.use_spaces) ' ' else '\t';
        const indent_size = if (self.options.use_spaces) self.options.indent else 1;

        var i: usize = 0;
        while (i < self.current_indent * indent_size) : (i += 1) {
            try self.output.append(self.allocator, indent_char);
        }
    }

    fn appendFmt(self: *Stringifier, comptime fmt: []const u8, args: anytype) StringifyError!void {
        var buf: [256]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, fmt, args) catch return error.InvalidValue;
        try self.output.appendSlice(self.allocator, result);
    }
};

/// Convenience function to stringify a table with default options
pub fn stringify(allocator: std.mem.Allocator, table: *const TomlTable) ![]const u8 {
    var stringifier = Stringifier.init(allocator, .{});
    defer stringifier.deinit();

    const result = try stringifier.stringify(table);
    return try allocator.dupe(u8, result);
}

/// Stringify with custom formatting options
pub fn stringifyWithOptions(allocator: std.mem.Allocator, table: *const TomlTable, options: FormatOptions) ![]const u8 {
    var stringifier = Stringifier.init(allocator, options);
    defer stringifier.deinit();

    const result = try stringifier.stringify(table);
    return try allocator.dupe(u8, result);
}

test "stringify simple values" {
    const testing = std.testing;

    const source =
        \\name = "flare"
        \\version = 1
        \\enabled = true
    ;

    const table = try toml_parser.parseToml(testing.allocator, source);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    const result = try stringify(testing.allocator, table);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "name = \"flare\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "version = 1") != null);
    try testing.expect(std.mem.indexOf(u8, result, "enabled = true") != null);
}

test "stringify with table" {
    const testing = std.testing;

    const source =
        \\[package]
        \\name = "test"
        \\version = "1.0"
    ;

    const table = try toml_parser.parseToml(testing.allocator, source);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    const result = try stringify(testing.allocator, table);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "[package]") != null);
    try testing.expect(std.mem.indexOf(u8, result, "name = \"test\"") != null);
}

test "stringify with array" {
    const testing = std.testing;

    const source = "numbers = [1, 2, 3]";

    const table = try toml_parser.parseToml(testing.allocator, source);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    const result = try stringify(testing.allocator, table);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "numbers = [1, 2, 3]") != null);
}

test "stringify with array of tables" {
    const testing = std.testing;

    const source =
        \\[[users]]
        \\name = "Alice"
        \\admin = true
        \\
        \\[[users]]
        \\name = "Bob"
        \\admin = false
    ;

    const table = try toml_parser.parseToml(testing.allocator, source);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    const result = try stringify(testing.allocator, table);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "[[users]]") != null);
    try testing.expect(std.mem.indexOf(u8, result, "name = \"Alice\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "name = \"Bob\"") != null);
}

test "stringify with format options - sorted keys" {
    const testing = std.testing;

    const source =
        \\zebra = 1
        \\apple = 2
        \\monkey = 3
    ;

    const table = try toml_parser.parseToml(testing.allocator, source);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    const result = try stringifyWithOptions(testing.allocator, table, .{ .sort_keys = true });
    defer testing.allocator.free(result);

    // Check that "apple" comes before "monkey" which comes before "zebra"
    const apple_pos = std.mem.indexOf(u8, result, "apple").?;
    const monkey_pos = std.mem.indexOf(u8, result, "monkey").?;
    const zebra_pos = std.mem.indexOf(u8, result, "zebra").?;

    try testing.expect(apple_pos < monkey_pos);
    try testing.expect(monkey_pos < zebra_pos);
}

test "round-trip: parse -> stringify -> parse" {
    const testing = std.testing;

    const source =
        \\title = "Round Trip Test"
        \\count = 42
        \\enabled = true
        \\
        \\[database]
        \\host = "localhost"
        \\port = 5432
    ;

    // First parse
    const table1 = try toml_parser.parseToml(testing.allocator, source);
    defer {
        table1.deinit();
        testing.allocator.destroy(table1);
    }

    // Stringify
    const stringified = try stringify(testing.allocator, table1);
    defer testing.allocator.free(stringified);

    // Second parse
    const table2 = try toml_parser.parseToml(testing.allocator, stringified);
    defer {
        table2.deinit();
        testing.allocator.destroy(table2);
    }

    // Verify values match
    try testing.expectEqualStrings("Round Trip Test", table2.get("title").?.string);
    try testing.expectEqual(@as(i64, 42), table2.get("count").?.integer);
    try testing.expectEqual(true, table2.get("enabled").?.boolean);

    const db = table2.get("database").?.table;
    try testing.expectEqualStrings("localhost", db.get("host").?.string);
    try testing.expectEqual(@as(i64, 5432), db.get("port").?.integer);
}

test "stringify datetime with fractional seconds" {
    const testing = std.testing;

    // Create a table with datetime that has nanoseconds
    var table = TomlTable.init(testing.allocator);
    defer table.deinit();

    // Datetime with 123456789 nanoseconds (0.123456789 seconds)
    var dt = Datetime.utc(2023, 12, 25, 10, 30, 45);
    dt.nanosecond = 123456789;
    try table.put("created", .{ .datetime = dt });

    // Datetime with 100000000 nanoseconds (0.1 seconds - should trim trailing zeros)
    var dt2 = Datetime.utc(2023, 12, 25, 10, 30, 45);
    dt2.nanosecond = 100000000;
    try table.put("updated", .{ .datetime = dt2 });

    const result = try stringify(testing.allocator, &table);
    defer testing.allocator.free(result);

    // Should contain fractional seconds
    try testing.expect(std.mem.indexOf(u8, result, ".123456789") != null);
    try testing.expect(std.mem.indexOf(u8, result, ".1") != null);
}
