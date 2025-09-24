//! Flash + Flare Integration Demo
//! Shows how to build a CLI application with Flash that uses Flare for configuration

const std = @import("std");
const flare = @import("flare");

/// Example application configuration schema
fn createAppSchema(allocator: std.mem.Allocator) !flare.Schema {
    var fields = std.StringHashMap(*const flare.Schema).init(allocator);

    // Database configuration schema
    var db_fields = std.StringHashMap(*const flare.Schema).init(allocator);

    const db_host = try allocator.create(flare.Schema);
    db_host.* = flare.Schema.string(.{})
        .required()
        .withDescription("Database hostname");
    try db_fields.put("host", db_host);

    const db_port = try allocator.create(flare.Schema);
    db_port.* = flare.Schema.int(.{ .min = 1, .max = 65535 })
        .default(flare.Value{ .int_value = 5432 })
        .withDescription("Database port");
    try db_fields.put("port", db_port);

    const db_ssl = try allocator.create(flare.Schema);
    db_ssl.* = flare.Schema.boolean()
        .default(flare.Value{ .bool_value = true })
        .withDescription("Enable SSL for database connection");
    try db_fields.put("ssl", db_ssl);

    const db_pool_size = try allocator.create(flare.Schema);
    db_pool_size.* = flare.Schema.int(.{ .min = 1, .max = 100 })
        .default(flare.Value{ .int_value = 10 })
        .withDescription("Connection pool size");
    try db_fields.put("pool_size", db_pool_size);

    const database_schema = try allocator.create(flare.Schema);
    database_schema.* = flare.Schema{
        .schema_type = .object,
        .fields = db_fields,
        .is_required = true,
    };
    try fields.put("database", database_schema);

    // Server configuration
    var server_fields = std.StringHashMap(*const flare.Schema).init(allocator);

    const server_port = try allocator.create(flare.Schema);
    server_port.* = flare.Schema.int(.{ .min = 1, .max = 65535 })
        .default(flare.Value{ .int_value = 8080 })
        .withDescription("Server port");
    try server_fields.put("port", server_port);

    const server_host = try allocator.create(flare.Schema);
    server_host.* = flare.Schema.string(.{})
        .default(flare.Value{ .string_value = "0.0.0.0" })
        .withDescription("Server bind address");
    try server_fields.put("host", server_host);

    const server_schema = try allocator.create(flare.Schema);
    server_schema.* = flare.Schema{
        .schema_type = .object,
        .fields = server_fields,
    };
    try fields.put("server", server_schema);

    // Application settings
    const debug_schema = try allocator.create(flare.Schema);
    debug_schema.* = flare.Schema.boolean()
        .default(flare.Value{ .bool_value = false })
        .withDescription("Enable debug mode");
    try fields.put("debug", debug_schema);

    const log_level = try allocator.create(flare.Schema);
    log_level.* = flare.Schema.string(.{})
        .default(flare.Value{ .string_value = "info" })
        .withDescription("Log level (debug, info, warn, error)");
    try fields.put("log_level", log_level);

    return flare.Schema{
        .schema_type = .object,
        .fields = fields,
    };
}

/// Database connection handler using configuration
fn connectDatabase(ctx: flare.flash.CommandContext) !void {
    std.debug.print("\n📊 Database Connection\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━\n", .{});

    const host = try ctx.config.getString("database.host", "localhost");
    const port = try ctx.config.getInt("database.port", 5432);
    const ssl = try ctx.config.getBool("database.ssl", true);
    const pool_size = try ctx.config.getInt("database.pool_size", 10);

    std.debug.print("Host:      {s}\n", .{host});
    std.debug.print("Port:      {d}\n", .{port});
    std.debug.print("SSL:       {}\n", .{ssl});
    std.debug.print("Pool Size: {d}\n", .{pool_size});

    std.debug.print("\n✅ Database connection configured successfully!\n", .{});
}

/// Server startup handler
fn startServer(ctx: flare.flash.CommandContext) !void {
    std.debug.print("\n🚀 Server Startup\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━\n", .{});

    const host = try ctx.config.getString("server.host", "0.0.0.0");
    const port = try ctx.config.getInt("server.port", 8080);
    const debug = try ctx.config.getBool("debug", false);
    const log_level = try ctx.config.getString("log_level", "info");

    std.debug.print("Bind Address: {s}:{d}\n", .{ host, port });
    std.debug.print("Debug Mode:   {}\n", .{debug});
    std.debug.print("Log Level:    {s}\n", .{log_level});

    std.debug.print("\n✅ Server configured and ready to start!\n", .{});
}

/// Show current configuration
fn showConfig(ctx: flare.flash.CommandContext) !void {
    std.debug.print("\n⚙️  Current Configuration\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

    // Database config
    std.debug.print("\n[Database]\n", .{});
    const db_host = try ctx.config.getString("database.host", "not set");
    const db_port = try ctx.config.getInt("database.port", 0);
    const db_ssl = try ctx.config.getBool("database.ssl", false);
    std.debug.print("  host = \"{s}\"\n", .{db_host});
    std.debug.print("  port = {d}\n", .{db_port});
    std.debug.print("  ssl = {}\n", .{db_ssl});

    // Server config
    std.debug.print("\n[Server]\n", .{});
    const srv_host = try ctx.config.getString("server.host", "not set");
    const srv_port = try ctx.config.getInt("server.port", 0);
    std.debug.print("  host = \"{s}\"\n", .{srv_host});
    std.debug.print("  port = {d}\n", .{srv_port});

    // App config
    std.debug.print("\n[Application]\n", .{});
    const debug = try ctx.config.getBool("debug", false);
    const log_level = try ctx.config.getString("log_level", "not set");
    std.debug.print("  debug = {}\n", .{debug});
    std.debug.print("  log_level = \"{s}\"\n", .{log_level});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n🔥 Flare + Flash Integration Demo\n", .{});
    std.debug.print("═════════════════════════════════════\n", .{});

    // Create application schema
    const app_schema = try createAppSchema(allocator);

    // Define configuration sources
    const config_options = flare.flash.FlashConfigOptions{
        .config_files = &[_]flare.FileSource{
            .{ .path = "app.toml", .required = false, .format = .toml },
            .{ .path = "app.json", .required = false, .format = .json },
        },
        .env_source = .{ .prefix = "APP", .separator = "__" },
        .schema = &app_schema,
    };

    // Simulate different commands with different CLI arguments
    std.debug.print("\n📝 Simulating CLI commands with configuration precedence\n", .{});

    // Test 1: Database connect with CLI override
    {
        std.debug.print("\n1️⃣  Command: myapp db connect --database-host=prod.example.com\n", .{});

        var flags = std.StringHashMap([]const u8).init(allocator);
        defer flags.deinit();
        try flags.put("database-host", "prod.example.com");

        const flash_ctx = flare.flash.FlashContext{
            .args = &[_][]const u8{},
            .flags = flags,
            .command = "db connect",
        };

        try flare.flash.configMiddleware(
            allocator,
            flash_ctx,
            config_options,
            connectDatabase,
        );
    }

    // Test 2: Server start with environment variables
    {
        std.debug.print("\n2️⃣  Command: myapp server start --debug\n", .{});

        // Set environment variable (simulated)
        try std.process.setEnvironVar("APP__SERVER__PORT", "3000");

        var flags = std.StringHashMap([]const u8).init(allocator);
        defer flags.deinit();
        try flags.put("debug", "true");

        const flash_ctx = flare.flash.FlashContext{
            .args = &[_][]const u8{},
            .flags = flags,
            .command = "server start",
        };

        try flare.flash.configMiddleware(
            allocator,
            flash_ctx,
            config_options,
            startServer,
        );
    }

    // Test 3: Show config with mixed sources
    {
        std.debug.print("\n3️⃣  Command: myapp config show\n", .{});

        var flags = std.StringHashMap([]const u8).init(allocator);
        defer flags.deinit();

        const flash_ctx = flare.flash.FlashContext{
            .args = &[_][]const u8{},
            .flags = flags,
            .command = "config show",
        };

        try flare.flash.configMiddleware(
            allocator,
            flash_ctx,
            config_options,
            showConfig,
        );
    }

    // Demonstrate arrays and maps
    std.debug.print("\n\n🎯 Advanced Features Demo\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});

    var config = try flare.Config.init(allocator);
    defer config.deinit();

    // Create an array of servers
    var servers: std.ArrayList(flare.Value) = .{};

    var server1 = std.StringHashMap(flare.Value).init(config.getArenaAllocator());
    try server1.put("name", flare.Value{ .string_value = "api-1" });
    try server1.put("url", flare.Value{ .string_value = "https://api1.example.com" });
    try servers.append(config.getArenaAllocator(), flare.Value{ .map_value = server1 });

    var server2 = std.StringHashMap(flare.Value).init(config.getArenaAllocator());
    try server2.put("name", flare.Value{ .string_value = "api-2" });
    try server2.put("url", flare.Value{ .string_value = "https://api2.example.com" });
    try servers.append(config.getArenaAllocator(), flare.Value{ .map_value = server2 });

    try config.setValue("servers", flare.Value{ .array_value = servers });

    // Access array elements
    const servers_array = try config.getArray("servers");
    std.debug.print("\n📡 Configured Servers:\n", .{});
    for (servers_array.items, 0..) |server, i| {
        if (server.map_value.get("name")) |name| {
            if (server.map_value.get("url")) |url| {
                std.debug.print("  [{d}] {s}: {s}\n", .{ i, name.string_value, url.string_value });
            }
        }
    }

    // Access by index
    const first_server = try config.getByIndex("servers", 0);
    if (first_server.map_value.get("name")) |name| {
        std.debug.print("\nFirst server name: {s}\n", .{name.string_value});
    }

    std.debug.print("\n\n✨ Flare + Flash Integration Demo Complete!\n", .{});
    std.debug.print("════════════════════════════════════════════\n", .{});
    std.debug.print("\n📚 Key Features Demonstrated:\n", .{});
    std.debug.print("  ✅ Schema validation\n", .{});
    std.debug.print("  ✅ Configuration precedence (CLI > ENV > File)\n", .{});
    std.debug.print("  ✅ TOML and JSON support\n", .{});
    std.debug.print("  ✅ Flash CLI integration\n", .{});
    std.debug.print("  ✅ Arrays and maps\n", .{});
    std.debug.print("  ✅ Environment variable parsing\n", .{});
    std.debug.print("\n🚀 Ready to go beyond MVP!\n\n", .{});
}

test "flash integration example" {
    // This test ensures the example compiles
    try main();
}