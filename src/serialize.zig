//! Comptime struct serialization to TOML
//!
//! Convert Zig structs into TOML tables (the inverse of `deserialize.zig`).

const std = @import("std");
const toml_value = @import("toml_value.zig");
const stringify_mod = @import("stringify.zig");

const TomlValue = toml_value.TomlValue;
const TomlTable = toml_value.TomlTable;
const TomlArray = toml_value.TomlArray;

pub const SerializeError = error{
    OutOfMemory,
    NullOptional,
};

/// Serialize a Zig struct into a heap-allocated `TomlTable`.
/// Caller owns the result and must `deinit()` then `destroy()` it.
/// Optional fields that are `null` are omitted (TOML has no null type).
pub fn serialize(comptime T: type, allocator: std.mem.Allocator, value: T) !*TomlTable {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") @compileError("serialize only works with structs");

    const table = try allocator.create(TomlTable);
    table.* = TomlTable.init(allocator);
    errdefer {
        table.deinit();
        allocator.destroy(table);
    }

    inline for (type_info.@"struct".field_names, type_info.@"struct".field_types) |name, FieldType| {
        const field_value = @field(value, name);

        if (@typeInfo(FieldType) == .optional) {
            // Omit null optionals; serialize the payload otherwise.
            if (field_value) |inner| {
                try table.put(name, try serializeValue(@typeInfo(FieldType).optional.child, allocator, inner));
            }
        } else {
            try table.put(name, try serializeValue(FieldType, allocator, field_value));
        }
    }

    return table;
}

/// Serialize a Zig struct directly to a TOML string.
/// Caller owns the returned slice.
pub fn toTomlString(comptime T: type, allocator: std.mem.Allocator, value: T) ![]const u8 {
    const table = try serialize(T, allocator, value);
    defer {
        table.deinit();
        allocator.destroy(table);
    }
    return try stringify_mod.stringify(allocator, table);
}

fn serializeValue(comptime T: type, allocator: std.mem.Allocator, value: T) !TomlValue {
    const type_info = @typeInfo(T);

    switch (type_info) {
        .int => return TomlValue{ .integer = @intCast(value) },
        .float => return TomlValue{ .float = @floatCast(value) },
        .bool => return TomlValue{ .boolean = value },
        .pointer => |ptr_info| {
            if (ptr_info.size != .slice) @compileError("Only slice pointers are supported");
            if (ptr_info.child == u8) {
                return TomlValue{ .string = try allocator.dupe(u8, value) };
            }
            var arr = TomlArray.init(allocator);
            errdefer arr.deinit(allocator);
            for (value) |item| {
                try arr.append(allocator, try serializeValue(ptr_info.child, allocator, item));
            }
            return TomlValue{ .array = arr };
        },
        .array => |arr_info| {
            var arr = TomlArray.init(allocator);
            errdefer arr.deinit(allocator);
            for (value) |item| {
                try arr.append(allocator, try serializeValue(arr_info.child, allocator, item));
            }
            return TomlValue{ .array = arr };
        },
        .optional => |opt_info| {
            if (value) |inner| return try serializeValue(opt_info.child, allocator, inner);
            return error.NullOptional;
        },
        .@"struct" => return TomlValue{ .table = try serialize(T, allocator, value) },
        else => @compileError("Unsupported type for serialization: " ++ @typeName(T)),
    }
}

// ============================================================================
// Tests
// ============================================================================

const deserialize_mod = @import("deserialize.zig");

test "serialize simple struct" {
    const testing = std.testing;

    const Config = struct {
        name: []const u8,
        port: i64,
        debug: bool,
    };

    const cfg = Config{ .name = "myapp", .port = 8080, .debug = true };

    const table = try serialize(Config, testing.allocator, cfg);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    try testing.expectEqualStrings("myapp", table.getString("name").?);
    try testing.expectEqual(@as(i64, 8080), table.getInt("port").?);
    try testing.expectEqual(true, table.getBool("debug").?);
}

test "serialize omits null optionals" {
    const testing = std.testing;

    const Config = struct {
        name: []const u8,
        description: ?[]const u8,
        port: ?i64,
    };

    const cfg = Config{ .name = "app", .description = null, .port = 9000 };

    const table = try serialize(Config, testing.allocator, cfg);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    try testing.expect(!table.contains("description"));
    try testing.expectEqual(@as(i64, 9000), table.getInt("port").?);
}

test "toTomlString round-trips through deserialize" {
    const testing = std.testing;

    const Config = struct {
        name: []const u8,
        port: i64,
        debug: bool,
    };

    const cfg = Config{ .name = "roundtrip", .port = 1234, .debug = false };

    const text = try toTomlString(Config, testing.allocator, cfg);
    defer testing.allocator.free(text);

    const parsed = try deserialize_mod.parseInto(Config, testing.allocator, text);
    defer deserialize_mod.free(Config, testing.allocator, parsed);

    try testing.expectEqualStrings("roundtrip", parsed.name);
    try testing.expectEqual(@as(i64, 1234), parsed.port);
    try testing.expectEqual(false, parsed.debug);
}

test "serialize nested struct and slices" {
    const testing = std.testing;

    const Database = struct {
        host: []const u8,
        port: i64,
    };

    const Config = struct {
        name: []const u8,
        ports: []const i64,
        database: Database,
    };

    const cfg = Config{
        .name = "app",
        .ports = &[_]i64{ 8080, 8081 },
        .database = .{ .host = "localhost", .port = 5432 },
    };

    const table = try serialize(Config, testing.allocator, cfg);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    try testing.expectEqualStrings("app", table.getString("name").?);

    const ports = table.get("ports").?.array;
    try testing.expectEqual(@as(usize, 2), ports.items.items.len);
    try testing.expectEqual(@as(i64, 8080), ports.items.items[0].integer);

    const db = table.getTable("database").?;
    try testing.expectEqualStrings("localhost", db.getString("host").?);
    try testing.expectEqual(@as(i64, 5432), db.getInt("port").?);
}
