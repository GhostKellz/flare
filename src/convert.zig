//! TOML to JSON conversion utilities
//! Ported from ZonTOM to Flare

const std = @import("std");
const toml_value = @import("toml_value.zig");

const TomlValue = toml_value.TomlValue;
const TomlTable = toml_value.TomlTable;
const TomlArray = toml_value.TomlArray;

pub const ConvertError = error{
    OutOfMemory,
    InvalidValue,
};

/// Convert a TOML table to compact JSON string
pub fn toJSON(allocator: std.mem.Allocator, table: *const TomlTable) ConvertError![]const u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);

    try writeTableAsJSON(allocator, &output, table);
    return output.toOwnedSlice(allocator) catch return ConvertError.OutOfMemory;
}

fn writeTableAsJSON(allocator: std.mem.Allocator, output: *std.ArrayList(u8), table: *const TomlTable) ConvertError!void {
    output.append(allocator, '{') catch return ConvertError.OutOfMemory;

    var first = true;
    var it = table.map.iterator();
    while (it.next()) |entry| {
        if (!first) output.appendSlice(allocator, ", ") catch return ConvertError.OutOfMemory;
        first = false;

        // Write key
        try writeJSONString(allocator, output, entry.key_ptr.*);
        output.appendSlice(allocator, ": ") catch return ConvertError.OutOfMemory;

        // Write value
        try writeValueAsJSON(allocator, output, entry.value_ptr.*);
    }

    output.append(allocator, '}') catch return ConvertError.OutOfMemory;
}

fn writeValueAsJSON(allocator: std.mem.Allocator, output: *std.ArrayList(u8), val: TomlValue) ConvertError!void {
    switch (val) {
        .string => |s| try writeJSONString(allocator, output, s),
        .integer => |i| {
            var buf: [32]u8 = undefined;
            const slice = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return ConvertError.InvalidValue;
            output.appendSlice(allocator, slice) catch return ConvertError.OutOfMemory;
        },
        .float => |f| {
            var buf: [64]u8 = undefined;
            const slice = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return ConvertError.InvalidValue;
            output.appendSlice(allocator, slice) catch return ConvertError.OutOfMemory;
        },
        .boolean => |b| output.appendSlice(allocator, if (b) "true" else "false") catch return ConvertError.OutOfMemory,
        .datetime => |dt| {
            output.append(allocator, '"') catch return ConvertError.OutOfMemory;
            var buf: [64]u8 = undefined;
            const slice = std.fmt.bufPrint(&buf, "{}", .{dt}) catch return ConvertError.InvalidValue;
            output.appendSlice(allocator, slice) catch return ConvertError.OutOfMemory;
            output.append(allocator, '"') catch return ConvertError.OutOfMemory;
        },
        .date => |d| {
            output.append(allocator, '"') catch return ConvertError.OutOfMemory;
            var buf: [16]u8 = undefined;
            const slice = std.fmt.bufPrint(&buf, "{}", .{d}) catch return ConvertError.InvalidValue;
            output.appendSlice(allocator, slice) catch return ConvertError.OutOfMemory;
            output.append(allocator, '"') catch return ConvertError.OutOfMemory;
        },
        .time => |t| {
            output.append(allocator, '"') catch return ConvertError.OutOfMemory;
            var buf: [32]u8 = undefined;
            const slice = std.fmt.bufPrint(&buf, "{}", .{t}) catch return ConvertError.InvalidValue;
            output.appendSlice(allocator, slice) catch return ConvertError.OutOfMemory;
            output.append(allocator, '"') catch return ConvertError.OutOfMemory;
        },
        .array => |arr| try writeArrayAsJSON(allocator, output, arr),
        .table => |tbl| try writeTableAsJSON(allocator, output, tbl),
    }
}

fn writeArrayAsJSON(allocator: std.mem.Allocator, output: *std.ArrayList(u8), arr: TomlArray) ConvertError!void {
    output.append(allocator, '[') catch return ConvertError.OutOfMemory;

    for (arr.items.items, 0..) |item, i| {
        if (i > 0) output.appendSlice(allocator, ", ") catch return ConvertError.OutOfMemory;
        try writeValueAsJSON(allocator, output, item);
    }

    output.append(allocator, ']') catch return ConvertError.OutOfMemory;
}

fn writeJSONString(allocator: std.mem.Allocator, output: *std.ArrayList(u8), s: []const u8) ConvertError!void {
    output.append(allocator, '"') catch return ConvertError.OutOfMemory;
    for (s) |c| {
        switch (c) {
            '"' => output.appendSlice(allocator, "\\\"") catch return ConvertError.OutOfMemory,
            '\\' => output.appendSlice(allocator, "\\\\") catch return ConvertError.OutOfMemory,
            '\n' => output.appendSlice(allocator, "\\n") catch return ConvertError.OutOfMemory,
            '\r' => output.appendSlice(allocator, "\\r") catch return ConvertError.OutOfMemory,
            '\t' => output.appendSlice(allocator, "\\t") catch return ConvertError.OutOfMemory,
            0x08 => output.appendSlice(allocator, "\\b") catch return ConvertError.OutOfMemory,
            0x0C => output.appendSlice(allocator, "\\f") catch return ConvertError.OutOfMemory,
            else => if (c < 0x20) {
                var buf: [6]u8 = undefined;
                const slice = std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{c}) catch return ConvertError.InvalidValue;
                output.appendSlice(allocator, slice) catch return ConvertError.OutOfMemory;
            } else {
                output.append(allocator, c) catch return ConvertError.OutOfMemory;
            },
        }
    }
    output.append(allocator, '"') catch return ConvertError.OutOfMemory;
}

/// Convert a TOML table to pretty-printed JSON
pub fn toJSONPretty(allocator: std.mem.Allocator, table: *const TomlTable, indent_size: usize) ConvertError![]const u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);

    try writeTableAsJSONPretty(allocator, &output, table, indent_size, 0);
    output.append(allocator, '\n') catch return ConvertError.OutOfMemory;
    return output.toOwnedSlice(allocator) catch return ConvertError.OutOfMemory;
}

fn writeTableAsJSONPretty(allocator: std.mem.Allocator, output: *std.ArrayList(u8), table: *const TomlTable, indent_size: usize, level: usize) ConvertError!void {
    output.appendSlice(allocator, "{\n") catch return ConvertError.OutOfMemory;

    var first = true;
    var it = table.map.iterator();
    while (it.next()) |entry| {
        if (!first) output.appendSlice(allocator, ",\n") catch return ConvertError.OutOfMemory;
        first = false;

        // Indent
        try writeIndent(allocator, output, indent_size, level + 1);

        // Write key
        try writeJSONString(allocator, output, entry.key_ptr.*);
        output.appendSlice(allocator, ": ") catch return ConvertError.OutOfMemory;

        // Write value
        try writeValueAsJSONPretty(allocator, output, entry.value_ptr.*, indent_size, level + 1);
    }

    output.append(allocator, '\n') catch return ConvertError.OutOfMemory;
    try writeIndent(allocator, output, indent_size, level);
    output.append(allocator, '}') catch return ConvertError.OutOfMemory;
}

fn writeValueAsJSONPretty(allocator: std.mem.Allocator, output: *std.ArrayList(u8), val: TomlValue, indent_size: usize, level: usize) ConvertError!void {
    switch (val) {
        .string => |s| try writeJSONString(allocator, output, s),
        .integer => |i| {
            var buf: [32]u8 = undefined;
            const slice = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return ConvertError.InvalidValue;
            output.appendSlice(allocator, slice) catch return ConvertError.OutOfMemory;
        },
        .float => |f| {
            var buf: [64]u8 = undefined;
            const slice = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return ConvertError.InvalidValue;
            output.appendSlice(allocator, slice) catch return ConvertError.OutOfMemory;
        },
        .boolean => |b| output.appendSlice(allocator, if (b) "true" else "false") catch return ConvertError.OutOfMemory,
        .datetime => |dt| {
            output.append(allocator, '"') catch return ConvertError.OutOfMemory;
            var buf: [64]u8 = undefined;
            const slice = std.fmt.bufPrint(&buf, "{}", .{dt}) catch return ConvertError.InvalidValue;
            output.appendSlice(allocator, slice) catch return ConvertError.OutOfMemory;
            output.append(allocator, '"') catch return ConvertError.OutOfMemory;
        },
        .date => |d| {
            output.append(allocator, '"') catch return ConvertError.OutOfMemory;
            var buf: [16]u8 = undefined;
            const slice = std.fmt.bufPrint(&buf, "{}", .{d}) catch return ConvertError.InvalidValue;
            output.appendSlice(allocator, slice) catch return ConvertError.OutOfMemory;
            output.append(allocator, '"') catch return ConvertError.OutOfMemory;
        },
        .time => |t| {
            output.append(allocator, '"') catch return ConvertError.OutOfMemory;
            var buf: [32]u8 = undefined;
            const slice = std.fmt.bufPrint(&buf, "{}", .{t}) catch return ConvertError.InvalidValue;
            output.appendSlice(allocator, slice) catch return ConvertError.OutOfMemory;
            output.append(allocator, '"') catch return ConvertError.OutOfMemory;
        },
        .array => |arr| try writeArrayAsJSONPretty(allocator, output, arr, indent_size, level),
        .table => |tbl| try writeTableAsJSONPretty(allocator, output, tbl, indent_size, level),
    }
}

fn writeArrayAsJSONPretty(allocator: std.mem.Allocator, output: *std.ArrayList(u8), arr: TomlArray, indent_size: usize, level: usize) ConvertError!void {
    if (arr.items.items.len == 0) {
        output.appendSlice(allocator, "[]") catch return ConvertError.OutOfMemory;
        return;
    }

    // Check if all items are simple (not tables/arrays)
    var all_simple = true;
    for (arr.items.items) |item| {
        if (item == .table or item == .array) {
            all_simple = false;
            break;
        }
    }

    if (all_simple and arr.items.items.len <= 5) {
        // Inline simple arrays
        output.append(allocator, '[') catch return ConvertError.OutOfMemory;
        for (arr.items.items, 0..) |item, i| {
            if (i > 0) output.appendSlice(allocator, ", ") catch return ConvertError.OutOfMemory;
            try writeValueAsJSONPretty(allocator, output, item, indent_size, level);
        }
        output.append(allocator, ']') catch return ConvertError.OutOfMemory;
    } else {
        // Multi-line arrays
        output.appendSlice(allocator, "[\n") catch return ConvertError.OutOfMemory;
        for (arr.items.items, 0..) |item, i| {
            if (i > 0) output.appendSlice(allocator, ",\n") catch return ConvertError.OutOfMemory;
            try writeIndent(allocator, output, indent_size, level + 1);
            try writeValueAsJSONPretty(allocator, output, item, indent_size, level + 1);
        }
        output.append(allocator, '\n') catch return ConvertError.OutOfMemory;
        try writeIndent(allocator, output, indent_size, level);
        output.append(allocator, ']') catch return ConvertError.OutOfMemory;
    }
}

fn writeIndent(allocator: std.mem.Allocator, output: *std.ArrayList(u8), indent_size: usize, level: usize) ConvertError!void {
    var i: usize = 0;
    while (i < level * indent_size) : (i += 1) {
        output.append(allocator, ' ') catch return ConvertError.OutOfMemory;
    }
}

// ============================================================================
// Tests
// ============================================================================

const flare = @import("root.zig");

test "toJSON: simple table" {
    const testing = std.testing;

    const source =
        \\name = "test"
        \\port = 8080
        \\enabled = true
    ;

    var table = try flare.parseToml(testing.allocator, source);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    const json = try toJSON(testing.allocator, table);
    defer testing.allocator.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "\"name\": \"test\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"port\": 8080") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"enabled\": true") != null);
}

test "toJSON: nested table" {
    const testing = std.testing;

    const source =
        \\[server]
        \\host = "localhost"
        \\port = 8080
    ;

    var table = try flare.parseToml(testing.allocator, source);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    const json = try toJSON(testing.allocator, table);
    defer testing.allocator.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "\"server\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"host\": \"localhost\"") != null);
}

test "toJSON: array" {
    const testing = std.testing;

    const source = "numbers = [1, 2, 3]";

    var table = try flare.parseToml(testing.allocator, source);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    const json = try toJSON(testing.allocator, table);
    defer testing.allocator.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "\"numbers\": [1, 2, 3]") != null);
}

test "toJSONPretty: formatted output" {
    const testing = std.testing;

    const source =
        \\name = "test"
        \\port = 8080
    ;

    var table = try flare.parseToml(testing.allocator, source);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    const json = try toJSONPretty(testing.allocator, table, 2);
    defer testing.allocator.free(json);

    // Should have newlines and indentation
    try testing.expect(std.mem.indexOf(u8, json, "{\n") != null);
    try testing.expect(std.mem.indexOf(u8, json, "  \"") != null);
}

test "toJSON: escape special characters" {
    const testing = std.testing;

    const source =
        \\text = "hello\nworld"
    ;

    var table = try flare.parseToml(testing.allocator, source);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    const json = try toJSON(testing.allocator, table);
    defer testing.allocator.free(json);

    // Newline should be escaped as \n in JSON
    try testing.expect(std.mem.indexOf(u8, json, "\\n") != null);
}
