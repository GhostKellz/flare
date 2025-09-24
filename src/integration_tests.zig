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