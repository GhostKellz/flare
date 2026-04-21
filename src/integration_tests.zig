//! Integration tests for schema validation and TOML loading

const std = @import("std");
const flare = @import("root.zig");

test "schema with TOML integration" {
    const allocator = std.testing.allocator;

    // Create a schema
    var fields = std.StringHashMap(*const flare.Schema).init(allocator);
    defer fields.deinit();

    const app_name_schema = try allocator.create(flare.Schema);
    defer allocator.destroy(app_name_schema);
    app_name_schema.* = flare.Schema.string(.{ .min_length = 1 }).required();

    const debug_schema = try allocator.create(flare.Schema);
    defer allocator.destroy(debug_schema);
    debug_schema.* = flare.Schema.boolean();

    // Database sub-schema
    var db_fields = std.StringHashMap(*const flare.Schema).init(allocator);
    defer db_fields.deinit();

    const host_schema = try allocator.create(flare.Schema);
    defer allocator.destroy(host_schema);
    host_schema.* = flare.Schema.string(.{}).required();

    const port_schema = try allocator.create(flare.Schema);
    defer allocator.destroy(port_schema);
    port_schema.* = flare.Schema.int(.{ .min = 1, .max = 65535 });

    try db_fields.put("host", host_schema);
    try db_fields.put("port", port_schema);

    const database_schema = try allocator.create(flare.Schema);
    defer allocator.destroy(database_schema);
    database_schema.* = flare.Schema{
        .schema_type = .object,
        .fields = db_fields,
    };

    try fields.put("name", app_name_schema);
    try fields.put("debug", debug_schema);
    try fields.put("database", database_schema);

    const root_schema = flare.Schema{
        .schema_type = .object,
        .fields = fields,
    };

    // Load TOML config
    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = "test_config.toml", .format = .toml },
        },
    });
    defer config.deinit();

    // Test that values are loaded correctly
    const name = try config.getString("name", null);
    const db_host = try config.getString("database.host", null);
    const db_port = try config.getInt("database.port", null);
    const debug = try config.getBool("debug", null);

    try std.testing.expect(std.mem.eql(u8, name, "my-app"));
    try std.testing.expect(std.mem.eql(u8, db_host, "localhost"));
    try std.testing.expect(db_port == 5432);
    try std.testing.expect(debug == false);

    // Create schema-aware config for validation
    var schema_config = try flare.Config.initWithSchema(allocator, &root_schema);
    defer schema_config.deinit();

    // Copy values for validation
    try schema_config.setValue("name", flare.Value{ .string_value = name });
    try schema_config.setValue("database_host", flare.Value{ .string_value = db_host });
    try schema_config.setValue("database_port", flare.Value{ .int_value = db_port });
    try schema_config.setValue("debug", flare.Value{ .bool_value = debug });

    // Validate
    var result = try schema_config.validateSchema();
    defer result.deinit(allocator);

    try std.testing.expect(!result.hasErrors());
}

test "schema validation catches constraint violations" {

    // Create schema with constraints
    const port_schema = flare.Schema.int(.{ .min = 1000, .max = 9999 }); // Restricted range

    // Test value that violates constraints
    const invalid_port = flare.Value{ .int_value = 80 }; // Too low

    try std.testing.expectError(flare.SchemaError.ValueOutOfRange,
        port_schema.validate(invalid_port, "port"));

    // Test valid value
    const valid_port = flare.Value{ .int_value = 8080 };
    try port_schema.validate(valid_port, "port");
}

test "file format auto-detection" {
    const allocator = std.testing.allocator;

    // Test JSON file loading
    var json_config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = "test_config.json" }, // .format = .auto (default)
        },
    });
    defer json_config.deinit();

    const json_name = try json_config.getString("name", null);
    try std.testing.expect(std.mem.eql(u8, json_name, "my-app"));

    // Test TOML file loading
    var toml_config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = "test_config.toml" }, // .format = .auto (default)
        },
    });
    defer toml_config.deinit();

    const toml_name = try toml_config.getString("name", null);
    try std.testing.expect(std.mem.eql(u8, toml_name, "my-app"));
}

test "mixed JSON and TOML loading with precedence" {
    const allocator = std.testing.allocator;

    // Load both files - TOML should override JSON since it's loaded later
    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = "test_config.json", .format = .json },
            .{ .path = "test_config.toml", .format = .toml },
        },
    });
    defer config.deinit();

    // Both files have the same structure, so values should match
    const name = try config.getString("name", null);
    const db_host = try config.getString("database.host", null);

    try std.testing.expect(std.mem.eql(u8, name, "my-app"));
    try std.testing.expect(std.mem.eql(u8, db_host, "localhost"));
}

// ============================================================================
// TOML 1.0 Feature Tests - verify features work through load path
// ============================================================================

test "TOML 1.0: nested tables through load path" {
    const allocator = std.testing.allocator;

    // Parse TOML with nested tables directly and verify flattening
    const toml_content =
        \\title = "Config"
        \\[database]
        \\host = "localhost"
        \\port = 5432
        \\[database.connection]
        \\timeout = 30
        \\retries = 3
    ;

    const table = try flare.parseToml(allocator, toml_content);
    defer {
        table.deinit();
        allocator.destroy(table);
    }

    // Verify nested structure parsed correctly
    try std.testing.expectEqualStrings("Config", table.get("title").?.string);
    const db = table.get("database").?.table;
    try std.testing.expectEqualStrings("localhost", db.get("host").?.string);
    try std.testing.expectEqual(@as(i64, 5432), db.get("port").?.integer);

    const conn = db.get("connection").?.table;
    try std.testing.expectEqual(@as(i64, 30), conn.get("timeout").?.integer);
    try std.testing.expectEqual(@as(i64, 3), conn.get("retries").?.integer);
}

test "TOML 1.0: arrays of tables" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\[[servers]]
        \\name = "alpha"
        \\ip = "10.0.0.1"
        \\
        \\[[servers]]
        \\name = "beta"
        \\ip = "10.0.0.2"
        \\
        \\[[servers]]
        \\name = "gamma"
        \\ip = "10.0.0.3"
    ;

    const table = try flare.parseToml(allocator, toml_content);
    defer {
        table.deinit();
        allocator.destroy(table);
    }

    const servers = table.get("servers").?.array;
    try std.testing.expectEqual(@as(usize, 3), servers.items.items.len);

    const alpha = servers.items.items[0].table;
    try std.testing.expectEqualStrings("alpha", alpha.get("name").?.string);
    try std.testing.expectEqualStrings("10.0.0.1", alpha.get("ip").?.string);

    const gamma = servers.items.items[2].table;
    try std.testing.expectEqualStrings("gamma", gamma.get("name").?.string);
}

test "TOML 1.0: inline tables" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\point = { x = 1, y = 2 }
        \\person = { name = "John", age = 30 }
    ;

    const table = try flare.parseToml(allocator, toml_content);
    defer {
        table.deinit();
        allocator.destroy(table);
    }

    const point = table.get("point").?.table;
    try std.testing.expectEqual(@as(i64, 1), point.get("x").?.integer);
    try std.testing.expectEqual(@as(i64, 2), point.get("y").?.integer);

    const person = table.get("person").?.table;
    try std.testing.expectEqualStrings("John", person.get("name").?.string);
    try std.testing.expectEqual(@as(i64, 30), person.get("age").?.integer);
}

test "TOML 1.0: datetime parsing" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\created = 2023-12-25T10:30:45Z
        \\local_time = 14:30:00
        \\date_only = 2023-12-25
    ;

    const table = try flare.parseToml(allocator, toml_content);
    defer {
        table.deinit();
        allocator.destroy(table);
    }

    const created = table.get("created").?.datetime;
    try std.testing.expectEqual(@as(u16, 2023), created.year);
    try std.testing.expectEqual(@as(u8, 12), created.month);
    try std.testing.expectEqual(@as(u8, 25), created.day);
    try std.testing.expectEqual(@as(u8, 10), created.hour);
    try std.testing.expectEqual(@as(u8, 30), created.minute);
    try std.testing.expectEqual(@as(u8, 45), created.second);

    const local_time = table.get("local_time").?.time;
    try std.testing.expectEqual(@as(u8, 14), local_time.hour);
    try std.testing.expectEqual(@as(u8, 30), local_time.minute);

    const date_only = table.get("date_only").?.date;
    try std.testing.expectEqual(@as(u16, 2023), date_only.year);
    try std.testing.expectEqual(@as(u8, 12), date_only.month);
    try std.testing.expectEqual(@as(u8, 25), date_only.day);
}

test "TOML 1.0: escape sequences in strings" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\tab = "hello\tworld"
        \\newline = "line1\nline2"
        \\quote = "say \"hello\""
        \\backslash = "path\\to\\file"
    ;

    const table = try flare.parseToml(allocator, toml_content);
    defer {
        table.deinit();
        allocator.destroy(table);
    }

    try std.testing.expectEqualStrings("hello\tworld", table.get("tab").?.string);
    try std.testing.expectEqualStrings("line1\nline2", table.get("newline").?.string);
    try std.testing.expectEqualStrings("say \"hello\"", table.get("quote").?.string);
    try std.testing.expectEqualStrings("path\\to\\file", table.get("backslash").?.string);
}

test "TOML 1.0: arrays with mixed compatible types" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\integers = [1, 2, 3, 4, 5]
        \\strings = ["red", "green", "blue"]
        \\booleans = [true, false, true]
    ;

    const table = try flare.parseToml(allocator, toml_content);
    defer {
        table.deinit();
        allocator.destroy(table);
    }

    const integers = table.get("integers").?.array;
    try std.testing.expectEqual(@as(usize, 5), integers.items.items.len);
    try std.testing.expectEqual(@as(i64, 3), integers.items.items[2].integer);

    const strings = table.get("strings").?.array;
    try std.testing.expectEqual(@as(usize, 3), strings.items.items.len);
    try std.testing.expectEqualStrings("green", strings.items.items[1].string);

    const booleans = table.get("booleans").?.array;
    try std.testing.expectEqual(@as(usize, 3), booleans.items.items.len);
    try std.testing.expectEqual(false, booleans.items.items[1].boolean);
}

// ============================================================================
// Invalid TOML Rejection Tests - verify parser correctly rejects malformed TOML
// ============================================================================

test "reject invalid TOML: unclosed table header" {
    const allocator = std.testing.allocator;
    const result = flare.parseToml(allocator, "[table");
    try std.testing.expectError(flare.ParseError.UnexpectedToken, result);
}

test "reject invalid TOML: missing value" {
    const allocator = std.testing.allocator;
    const result = flare.parseToml(allocator, "key = ");
    try std.testing.expectError(flare.ParseError.UnexpectedToken, result);
}

test "reject invalid TOML: unclosed string" {
    const allocator = std.testing.allocator;
    // Lexer errors bubble up through parser - must return an error
    if (flare.parseToml(allocator, "key = \"unclosed")) |table| {
        table.deinit();
        allocator.destroy(table);
        return error.TestUnexpectedResult; // Should have failed
    } else |_| {
        // Expected to fail
    }
}

test "reject invalid TOML: invalid escape sequence" {
    const allocator = std.testing.allocator;
    if (flare.parseToml(allocator, "key = \"bad\\qescape\"")) |table| {
        table.deinit();
        allocator.destroy(table);
        return error.TestUnexpectedResult;
    } else |_| {
        // Expected to fail
    }
}

test "reject invalid TOML: duplicate key" {
    const allocator = std.testing.allocator;
    const result = flare.parseToml(allocator,
        \\name = "first"
        \\name = "second"
    );
    try std.testing.expectError(flare.ParseError.DuplicateKey, result);
}

test "reject invalid TOML: unexpected character" {
    const allocator = std.testing.allocator;
    // @ is an invalid character
    if (flare.parseToml(allocator, "key = @invalid")) |table| {
        table.deinit();
        allocator.destroy(table);
        return error.TestUnexpectedResult;
    } else |_| {
        // Expected to fail
    }
}

// ============================================================================
// Nested Object Access Tests - verify getMap() works with loaded config
// ============================================================================

test "getMap() on loaded JSON config" {
    const allocator = std.testing.allocator;

    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = "test_config.json", .format = .json },
        },
    });
    defer config.deinit();

    // getMap() should return the nested database object
    const db_map = try config.getMap("database");

    // Verify nested values are accessible
    const host_val = db_map.get("host") orelse return error.MissingKey;
    try std.testing.expectEqualStrings("localhost", host_val.string_value);

    const port_val = db_map.get("port") orelse return error.MissingKey;
    try std.testing.expectEqual(@as(i64, 5432), port_val.int_value);

    const ssl_val = db_map.get("ssl") orelse return error.MissingKey;
    try std.testing.expectEqual(true, ssl_val.bool_value);

    // Also verify flattened access still works
    const db_host = try config.getString("database.host", null);
    try std.testing.expectEqualStrings("localhost", db_host);
}

test "getMap() on loaded TOML config" {
    const allocator = std.testing.allocator;

    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = "test_config.toml", .format = .toml },
        },
    });
    defer config.deinit();

    // getMap() should return the nested database object
    const db_map = try config.getMap("database");

    // Verify nested values
    const host_val = db_map.get("host") orelse return error.MissingKey;
    try std.testing.expectEqualStrings("localhost", host_val.string_value);

    const port_val = db_map.get("port") orelse return error.MissingKey;
    try std.testing.expectEqual(@as(i64, 5432), port_val.int_value);

    // Also verify flattened access still works
    const db_port = try config.getInt("database.port", null);
    try std.testing.expectEqual(@as(i64, 5432), db_port);
}

test "schema validation on loaded config via load()" {
    const allocator = std.testing.allocator;

    // Create schema for the config structure
    var db_fields = std.StringHashMap(*const flare.Schema).init(allocator);
    defer db_fields.deinit();

    const host_schema = try allocator.create(flare.Schema);
    defer allocator.destroy(host_schema);
    host_schema.* = flare.Schema.string(.{}).required();

    const port_schema = try allocator.create(flare.Schema);
    defer allocator.destroy(port_schema);
    port_schema.* = flare.Schema.int(.{ .min = 1, .max = 65535 });

    try db_fields.put("host", host_schema);
    try db_fields.put("port", port_schema);

    // Create root schema with nested database object
    var root_fields = std.StringHashMap(*const flare.Schema).init(allocator);
    defer root_fields.deinit();

    const name_schema = try allocator.create(flare.Schema);
    defer allocator.destroy(name_schema);
    name_schema.* = flare.Schema.string(.{}).required();

    const db_schema = try allocator.create(flare.Schema);
    defer allocator.destroy(db_schema);
    db_schema.* = flare.Schema{
        .schema_type = .object,
        .fields = db_fields,
    };

    try root_fields.put("name", name_schema);
    try root_fields.put("database", db_schema);

    const root_schema = flare.Schema{
        .schema_type = .object,
        .fields = root_fields,
    };

    // Load config from file - this creates BOTH flattened and nested representations
    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = "test_config.toml", .format = .toml },
        },
    });
    defer config.deinit();

    // Set the schema for validation
    config.setSchema(&root_schema);

    // Validate - should pass with dual representation
    var result = try config.validateSchema();
    defer result.deinit(allocator);

    // The dual representation means:
    // 1. "database.host" via getValueByPath -> "database_host" works for scalars
    // 2. "database" -> map_value works for nested object validation
    try std.testing.expect(!result.hasErrors());
}

// ============================================================================
// TOML 1.0 Base-Prefixed Integer Tests
// ============================================================================

test "TOML 1.0: hexadecimal integers" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\hex1 = 0xDEADBEEF
        \\hex2 = 0xff
        \\hex3 = 0x00FF
        \\hex4 = 0xCAFE_BABE
    ;

    const table = try flare.parseToml(allocator, toml_content);
    defer {
        table.deinit();
        allocator.destroy(table);
    }

    try std.testing.expectEqual(@as(i64, 0xDEADBEEF), table.get("hex1").?.integer);
    try std.testing.expectEqual(@as(i64, 0xff), table.get("hex2").?.integer);
    try std.testing.expectEqual(@as(i64, 0x00FF), table.get("hex3").?.integer);
    try std.testing.expectEqual(@as(i64, 0xCAFEBABE), table.get("hex4").?.integer);
}

test "TOML 1.0: octal integers" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\oct1 = 0o755
        \\oct2 = 0o644
        \\oct3 = 0o7_7_7
    ;

    const table = try flare.parseToml(allocator, toml_content);
    defer {
        table.deinit();
        allocator.destroy(table);
    }

    try std.testing.expectEqual(@as(i64, 0o755), table.get("oct1").?.integer);
    try std.testing.expectEqual(@as(i64, 0o644), table.get("oct2").?.integer);
    try std.testing.expectEqual(@as(i64, 0o777), table.get("oct3").?.integer);
}

test "TOML 1.0: binary integers" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\bin1 = 0b11010110
        \\bin2 = 0b1111_0000
        \\bin3 = 0b0
    ;

    const table = try flare.parseToml(allocator, toml_content);
    defer {
        table.deinit();
        allocator.destroy(table);
    }

    try std.testing.expectEqual(@as(i64, 0b11010110), table.get("bin1").?.integer);
    try std.testing.expectEqual(@as(i64, 0b11110000), table.get("bin2").?.integer);
    try std.testing.expectEqual(@as(i64, 0), table.get("bin3").?.integer);
}

// ============================================================================
// TOML 1.0 Unicode Escape Tests
// ============================================================================

test "TOML 1.0: Unicode escapes \\uXXXX" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\smiley = "\u263A"
        \\heart = "\u2764"
        \\basic = "\u0041"
    ;

    const table = try flare.parseToml(allocator, toml_content);
    defer {
        table.deinit();
        allocator.destroy(table);
    }

    // U+263A = WHITE SMILING FACE = ☺ (UTF-8: E2 98 BA)
    try std.testing.expectEqualStrings("\u{263A}", table.get("smiley").?.string);
    // U+2764 = HEAVY BLACK HEART = ❤ (UTF-8: E2 9D A4)
    try std.testing.expectEqualStrings("\u{2764}", table.get("heart").?.string);
    // U+0041 = LATIN CAPITAL LETTER A
    try std.testing.expectEqualStrings("A", table.get("basic").?.string);
}

test "TOML 1.0: Unicode escapes \\UXXXXXXXX" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\emoji = "\U0001F600"
        \\rocket = "\U0001F680"
    ;

    const table = try flare.parseToml(allocator, toml_content);
    defer {
        table.deinit();
        allocator.destroy(table);
    }

    // U+1F600 = GRINNING FACE
    try std.testing.expectEqualStrings("\u{1F600}", table.get("emoji").?.string);
    // U+1F680 = ROCKET
    try std.testing.expectEqualStrings("\u{1F680}", table.get("rocket").?.string);
}

// ============================================================================
// CLI JSON Recursive Parsing Tests
// ============================================================================

test "parseCliValue: nested object JSON preserves structure" {
    const allocator = std.testing.allocator;

    // Simulate --database='{"host":"db.example.com","options":{"ssl":true,"timeout":30}}'
    const json_input =
        \\{"host":"db.example.com","options":{"ssl":true,"timeout":30}}
    ;

    const value = try flare.parseCliValue(allocator, json_input);
    defer {
        // Clean up allocated memory
        if (value == .map_value) {
            var map = value.map_value;
            var iter = map.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                if (entry.value_ptr.* == .string_value) {
                    allocator.free(entry.value_ptr.string_value);
                } else if (entry.value_ptr.* == .map_value) {
                    var nested = entry.value_ptr.map_value;
                    var nested_iter = nested.iterator();
                    while (nested_iter.next()) |nested_entry| {
                        allocator.free(nested_entry.key_ptr.*);
                    }
                    nested.deinit();
                }
            }
            map.deinit();
        }
    }

    // Should be a map_value, not null
    try std.testing.expect(value == .map_value);

    const map = value.map_value;

    // Check top-level string
    const host = map.get("host").?;
    try std.testing.expect(host == .string_value);
    try std.testing.expectEqualStrings("db.example.com", host.string_value);

    // Check nested object (this was previously null_value!)
    const options = map.get("options").?;
    try std.testing.expect(options == .map_value);

    const options_map = options.map_value;
    const ssl = options_map.get("ssl").?;
    try std.testing.expect(ssl == .bool_value);
    try std.testing.expectEqual(true, ssl.bool_value);

    const timeout = options_map.get("timeout").?;
    try std.testing.expect(timeout == .int_value);
    try std.testing.expectEqual(@as(i64, 30), timeout.int_value);
}

test "parseCliValue: array of objects from CLI" {
    const allocator = std.testing.allocator;

    // Simulate --servers='[{"name":"api-1","url":"https://api1.com"},{"name":"api-2","url":"https://api2.com"}]'
    const json_input =
        \\[{"name":"api-1","url":"https://api1.com"},{"name":"api-2","url":"https://api2.com"}]
    ;

    const value = try flare.parseCliValue(allocator, json_input);
    defer {
        // Clean up allocated memory
        if (value == .array_value) {
            var arr = value.array_value;
            for (arr.items) |item| {
                if (item == .map_value) {
                    var map = item.map_value;
                    var iter = map.iterator();
                    while (iter.next()) |entry| {
                        allocator.free(entry.key_ptr.*);
                        if (entry.value_ptr.* == .string_value) {
                            allocator.free(entry.value_ptr.string_value);
                        }
                    }
                    map.deinit();
                }
            }
            arr.deinit(allocator);
        }
    }

    // Should be an array_value
    try std.testing.expect(value == .array_value);

    const arr = value.array_value;
    try std.testing.expectEqual(@as(usize, 2), arr.items.len);

    // First server object (this was previously null_value!)
    const server1 = arr.items[0];
    try std.testing.expect(server1 == .map_value);

    const name1 = server1.map_value.get("name").?;
    try std.testing.expect(name1 == .string_value);
    try std.testing.expectEqualStrings("api-1", name1.string_value);

    // Second server object
    const server2 = arr.items[1];
    try std.testing.expect(server2 == .map_value);

    const url2 = server2.map_value.get("url").?;
    try std.testing.expect(url2 == .string_value);
    try std.testing.expectEqualStrings("https://api2.com", url2.string_value);
}

test "parseCliValue: nested arrays preserved" {
    const allocator = std.testing.allocator;

    // Simulate --matrix='[[1,2,3],[4,5,6]]'
    const json_input = "[[1,2,3],[4,5,6]]";

    const value = try flare.parseCliValue(allocator, json_input);
    defer {
        if (value == .array_value) {
            var arr = value.array_value;
            for (arr.items) |item| {
                if (item == .array_value) {
                    var nested = item.array_value;
                    nested.deinit(allocator);
                }
            }
            arr.deinit(allocator);
        }
    }

    // Should be an array_value
    try std.testing.expect(value == .array_value);

    const arr = value.array_value;
    try std.testing.expectEqual(@as(usize, 2), arr.items.len);

    // First nested array (this was previously null_value!)
    const row1 = arr.items[0];
    try std.testing.expect(row1 == .array_value);
    try std.testing.expectEqual(@as(usize, 3), row1.array_value.items.len);

    // Check values in first row
    try std.testing.expectEqual(@as(i64, 1), row1.array_value.items[0].int_value);
    try std.testing.expectEqual(@as(i64, 2), row1.array_value.items[1].int_value);
    try std.testing.expectEqual(@as(i64, 3), row1.array_value.items[2].int_value);

    // Second nested array
    const row2 = arr.items[1];
    try std.testing.expect(row2 == .array_value);
    try std.testing.expectEqual(@as(i64, 6), row2.array_value.items[2].int_value);
}

// ============================================================================
// Parse Diagnostics Tests - parseTomlWithContext
// ============================================================================

test "parseTomlWithContext: successful parse returns table" {
    const allocator = std.testing.allocator;

    const source =
        \\name = "test"
        \\port = 8080
    ;

    const result = flare.parseTomlWithContext(allocator, source);

    try std.testing.expect(result.isSuccess());
    try std.testing.expect(!result.isError());
    try std.testing.expect(result.table != null);
    try std.testing.expect(result.error_context == null);

    // Cleanup
    const table = result.table.?;
    defer {
        table.deinit();
        allocator.destroy(table);
    }

    try std.testing.expectEqualStrings("test", table.get("name").?.string);
    try std.testing.expectEqual(@as(i64, 8080), table.get("port").?.integer);
}

test "parseTomlWithContext: parse error returns line/column context" {
    const allocator = std.testing.allocator;

    // Invalid TOML - unclosed table header
    const source = "[table";

    const result = flare.parseTomlWithContext(allocator, source);

    try std.testing.expect(!result.isSuccess());
    try std.testing.expect(result.isError());
    try std.testing.expect(result.table == null);
    try std.testing.expect(result.error_context != null);

    const ctx = result.error_context.?;
    // Should have line info
    try std.testing.expect(ctx.line >= 1);
}

test "parseTomlWithContext: unterminated string returns context" {
    const allocator = std.testing.allocator;

    // Unterminated string
    const source = "name = \"unclosed";

    const result = flare.parseTomlWithContext(allocator, source);

    try std.testing.expect(result.isError());
    try std.testing.expect(result.error_context != null);

    const ctx = result.error_context.?;
    try std.testing.expectEqualStrings("Unterminated string literal", ctx.message);
    try std.testing.expect(ctx.suggestion != null);
}

test "parseTomlWithContext: source line captured in context" {
    const allocator = std.testing.allocator;

    // Multi-line with error on line 3
    const source =
        \\name = "valid"
        \\port = 8080
        \\bad = "unclosed
    ;

    const result = flare.parseTomlWithContext(allocator, source);

    try std.testing.expect(result.isError());
    try std.testing.expect(result.error_context != null);

    const ctx = result.error_context.?;
    // Should capture source line
    try std.testing.expect(ctx.source_line != null);
}