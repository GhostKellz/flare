const std = @import("std");
const flare = @import("flare");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🔥 Flare Schema & TOML Demo\n\n", .{});

    // Create a comprehensive schema
    var fields = std.StringHashMap(*const flare.Schema).init(allocator);
    defer fields.deinit();

    const name_schema = try allocator.create(flare.Schema);
    defer allocator.destroy(name_schema);
    name_schema.* = flare.Schema.string(.{ .min_length = 1, .max_length = 50 })
        .required()
        .withDescription("Application name");

    const debug_schema = try allocator.create(flare.Schema);
    defer allocator.destroy(debug_schema);
    debug_schema.* = flare.Schema.boolean().default(flare.Value{ .bool_value = false });

    // Database schema
    var db_fields = std.StringHashMap(*const flare.Schema).init(allocator);
    defer db_fields.deinit();

    const host_schema = try allocator.create(flare.Schema);
    defer allocator.destroy(host_schema);
    host_schema.* = flare.Schema.string(.{}).required();

    const port_schema = try allocator.create(flare.Schema);
    defer allocator.destroy(port_schema);
    port_schema.* = flare.Schema.int(.{ .min = 1, .max = 65535 })
        .default(flare.Value{ .int_value = 5432 });

    const ssl_schema = try allocator.create(flare.Schema);
    defer allocator.destroy(ssl_schema);
    ssl_schema.* = flare.Schema.boolean().default(flare.Value{ .bool_value = true });

    try db_fields.put("host", host_schema);
    try db_fields.put("port", port_schema);
    try db_fields.put("ssl", ssl_schema);

    const database_schema = try allocator.create(flare.Schema);
    defer allocator.destroy(database_schema);
    database_schema.* = flare.Schema{
        .schema_type = .object,
        .fields = db_fields,
    };

    try fields.put("name", name_schema);
    try fields.put("debug", debug_schema);
    try fields.put("database", database_schema);

    const root_schema = flare.Schema{
        .schema_type = .object,
        .fields = fields,
    };

    // Test with TOML file
    std.debug.print("📋 Testing with TOML configuration...\n", .{});
    var toml_config = try flare.Config.initWithSchema(allocator, &root_schema);
    defer toml_config.deinit();

    // Try to load TOML file
    const toml_load_result = flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = "test_config.toml", .format = .toml },
        },
    });

    if (toml_load_result) |config| {
        defer config.deinit();
        std.debug.print("✅ TOML loaded successfully!\n", .{});

        // Copy values to schema-aware config
        const name = try config.getString("name", "unknown");
        const db_host = try config.getString("database.host", "localhost");
        const db_port = try config.getInt("database.port", 5432);
        const debug = try config.getBool("debug", false);

        try toml_config.setValue("name", flare.Value{ .string_value = name });
        try toml_config.setValue("database_host", flare.Value{ .string_value = db_host });
        try toml_config.setValue("database_port", flare.Value{ .int_value = db_port });
        try toml_config.setValue("debug", flare.Value{ .bool_value = debug });

        std.debug.print("  App: {s}\n", .{name});
        std.debug.print("  DB: {s}:{d}\n", .{ db_host, db_port });
        std.debug.print("  Debug: {}\n\n", .{debug});

        // Validate against schema
        std.debug.print("🔍 Validating against schema...\n", .{});
        var validation_result = try toml_config.validateSchema();
        defer validation_result.deinit();

        if (validation_result.hasErrors()) {
            std.debug.print("❌ Validation failed:\n", .{});
            for (validation_result.errors.items) |error_item| {
                std.debug.print("  - {s}: {s}\n", .{ error_item.path, error_item.message });
            }
        } else {
            std.debug.print("✅ Schema validation passed!\n", .{});
        }
    } else |err| {
        std.debug.print("❌ Failed to load TOML: {}\n", .{err});
    }

    // Test schema validation with missing required field
    std.debug.print("\n🧪 Testing validation with missing required field...\n", .{});
    var invalid_config = try flare.Config.initWithSchema(allocator, &root_schema);
    defer invalid_config.deinit();

    // Only set debug, missing required "name" and "database.host"
    try invalid_config.setValue("debug", flare.Value{ .bool_value = true });

    var invalid_result = try invalid_config.validateSchema();
    defer invalid_result.deinit();

    if (invalid_result.hasErrors()) {
        std.debug.print("✅ Correctly caught validation errors:\n", .{});
        for (invalid_result.errors.items) |error_item| {
            std.debug.print("  - {s}\n", .{error_item.message});
        }
    } else {
        std.debug.print("❌ Expected validation to fail!\n", .{});
    }

    std.debug.print("\n🎉 Schema & TOML demo complete!\n", .{});
}