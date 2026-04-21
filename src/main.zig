//! Flare Configuration Library - Demo Application
//!
//! This executable demonstrates how to use Flare for configuration management.
//! Run with: zig build run

const std = @import("std");
const flare = @import("flare");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    std.debug.print("Flare Configuration Library Demo\n", .{});
    std.debug.print("================================\n\n", .{});

    // Load configuration from JSON file with environment variable support
    // In Zig 0.17+, environ_map is passed via std.process.Init
    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = "test_config.json" },
        },
        .env = .{ .prefix = "APP", .separator = "__", .env_map = init.environ_map },
    });
    defer config.deinit();

    // Access configuration values with defaults
    const db_host = try config.getString("database.host", "unknown");
    const db_port = try config.getInt("database.port", 0);
    const server_port = try config.getInt("server.port", 3000);
    const debug = try config.getBool("debug", true);

    std.debug.print("Database config:\n", .{});
    std.debug.print("  Host: {s}\n", .{db_host});
    std.debug.print("  Port: {d}\n", .{db_port});
    std.debug.print("\nServer port: {d}\n", .{server_port});
    std.debug.print("Debug mode: {}\n", .{debug});

    // Set programmatic defaults
    try config.setDefault("app.name", flare.Value{ .string_value = "My Flare App" });
    try config.setDefault("app.version", flare.Value{ .string_value = "0.2.0" });

    const app_name = try config.getString("app.name", "Unknown App");
    const app_version = try config.getString("app.version", "0.0.0");

    std.debug.print("\nApplication:\n", .{});
    std.debug.print("  Name: {s}\n", .{app_name});
    std.debug.print("  Version: {s}\n", .{app_version});

    // Demonstrate TOML parsing
    std.debug.print("\n--- TOML 1.0 Demo ---\n\n", .{});

    const toml_source =
        \\title = "TOML Demo"
        \\
        \\[database]
        \\host = "db.example.com"
        \\port = 5432
        \\
        \\[[servers]]
        \\name = "alpha"
        \\ip = "10.0.0.1"
        \\
        \\[[servers]]
        \\name = "beta"
        \\ip = "10.0.0.2"
    ;

    const table = try flare.parseToml(allocator, toml_source);
    defer {
        table.deinit();
        allocator.destroy(table);
    }

    std.debug.print("Title: {s}\n", .{table.get("title").?.string});

    const db = table.get("database").?.table;
    std.debug.print("Database: {s}:{d}\n", .{ db.get("host").?.string, db.get("port").?.integer });

    const servers = table.get("servers").?.array;
    std.debug.print("Servers: {d} configured\n", .{servers.items.items.len});
    for (servers.items.items, 0..) |server, i| {
        const s = server.table;
        std.debug.print("  [{d}] {s} @ {s}\n", .{ i, s.get("name").?.string, s.get("ip").?.string });
    }
}
