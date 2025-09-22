const std = @import("std");
const flare = @import("flare");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🔥 Flare Configuration Library Demo\n", .{});

    // Load configuration from JSON file with environment variable support
    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = "test_config.json" },
        },
        .env = .{ .prefix = "APP", .separator = "__" },
    });
    defer config.deinit();

    // Demonstrate accessing configuration values
    const db_host = try config.getString("database.host", "unknown");
    const db_port = try config.getInt("database.port", 0);
    const server_port = try config.getInt("server.port", 3000);
    const debug = try config.getBool("debug", true);

    std.debug.print("Database config:\n", .{});
    std.debug.print("  Host: {s}\n", .{db_host});
    std.debug.print("  Port: {d}\n", .{db_port});
    std.debug.print("Server port: {d}\n", .{server_port});
    std.debug.print("Debug mode: {}\n", .{debug});

    // Set some defaults
    try config.setDefault("app.name", flare.Value{ .string_value = "My Flare App" });
    try config.setDefault("app.version", flare.Value{ .string_value = "0.1.0" });

    const app_name = try config.getString("app.name", "Unknown App");
    const app_version = try config.getString("app.version", "0.0.0");

    std.debug.print("Application:\n", .{});
    std.debug.print("  Name: {s}\n", .{app_name});
    std.debug.print("  Version: {s}\n", .{app_version});
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
