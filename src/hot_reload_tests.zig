//! Hot reload tests for flare configuration library

const std = @import("std");
const flare = @import("root.zig");

test "hot reload initialization" {
    const allocator = std.testing.allocator;

    // Create a temporary config file
    const test_config_path = "test_hot_reload.json";
    const initial_content =
        \\{
        \\  "database": {
        \\    "host": "localhost",
        \\    "port": 5432
        \\  },
        \\  "debug": false
        \\}
    ;

    // Write initial config
    const file = try std.fs.cwd().createFile(test_config_path, .{});
    try file.writeAll(initial_content);
    file.close();
    defer std.fs.cwd().deleteFile(test_config_path) catch {};

    // Load config with file watching enabled
    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = test_config_path, .format = .json },
        },
    });
    defer config.deinit();

    // Enable hot reload
    try config.enableHotReload(null);

    // Verify initial values
    const db_host = try config.getString("database.host", null);
    try std.testing.expect(std.mem.eql(u8, db_host, "localhost"));

    const db_port = try config.getInt("database.port", null);
    try std.testing.expect(db_port == 5432);
}

test "hot reload file change detection" {
    const allocator = std.testing.allocator;

    const test_config_path = "test_hot_reload_change.json";
    const initial_content =
        \\{
        \\  "value": 100
        \\}
    ;

    // Write initial config
    {
        const file = try std.fs.cwd().createFile(test_config_path, .{});
        defer file.close();
        try file.writeAll(initial_content);
    }
    defer std.fs.cwd().deleteFile(test_config_path) catch {};

    // Load config
    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = test_config_path, .format = .json },
        },
    });
    defer config.deinit();

    // Enable hot reload
    try config.enableHotReload(null);

    // Verify initial value
    const initial_value = try config.getInt("value", null);
    try std.testing.expect(initial_value == 100);

    // Wait a bit to ensure different mtime
    std.Thread.sleep(1_000_000_000); // 1 second

    // Update the config file
    const updated_content =
        \\{
        \\  "value": 200
        \\}
    ;
    {
        const file = try std.fs.cwd().createFile(test_config_path, .{});
        defer file.close();
        try file.writeAll(updated_content);
    }

    // Check and reload
    const changed = try config.checkAndReload();
    try std.testing.expect(changed == true);

    // Verify updated value
    const updated_value = try config.getInt("value", null);
    try std.testing.expect(updated_value == 200);
}

test "hot reload with callback" {
    const allocator = std.testing.allocator;

    const test_config_path = "test_hot_reload_callback.json";
    const initial_content =
        \\{
        \\  "counter": 1
        \\}
    ;

    // Write initial config
    {
        const file = try std.fs.cwd().createFile(test_config_path, .{});
        defer file.close();
        try file.writeAll(initial_content);
    }
    defer std.fs.cwd().deleteFile(test_config_path) catch {};

    // Load config
    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = test_config_path, .format = .json },
        },
    });
    defer config.deinit();

    // Callback state
    const CallbackState = struct {
        var called: bool = false;
    };
    CallbackState.called = false;

    const testCallback = struct {
        fn callback(_: *flare.Config) void {
            CallbackState.called = true;
        }
    }.callback;

    // Enable hot reload with callback
    try config.enableHotReload(testCallback);

    // Update the config file
    std.Thread.sleep(1_000_000_000); // 1 second
    const updated_content =
        \\{
        \\  "counter": 2
        \\}
    ;
    {
        const file = try std.fs.cwd().createFile(test_config_path, .{});
        defer file.close();
        try file.writeAll(updated_content);
    }

    // Check and reload - should trigger callback
    _ = try config.checkAndReload();
    try std.testing.expect(CallbackState.called == true);
}

test "hot reload manual reload" {
    const allocator = std.testing.allocator;

    const test_config_path = "test_hot_reload_manual.json";
    const initial_content =
        \\{
        \\  "setting": "initial"
        \\}
    ;

    // Write initial config
    {
        const file = try std.fs.cwd().createFile(test_config_path, .{});
        defer file.close();
        try file.writeAll(initial_content);
    }
    defer std.fs.cwd().deleteFile(test_config_path) catch {};

    // Load config
    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = test_config_path, .format = .json },
        },
    });
    defer config.deinit();

    // Verify initial value
    const initial_setting = try config.getString("setting", null);
    try std.testing.expect(std.mem.eql(u8, initial_setting, "initial"));

    // Update the config file
    const updated_content =
        \\{
        \\  "setting": "updated"
        \\}
    ;
    {
        const file = try std.fs.cwd().createFile(test_config_path, .{});
        defer file.close();
        try file.writeAll(updated_content);
    }

    // Manually reload
    try config.reload();

    // Verify updated value
    const updated_setting = try config.getString("setting", null);
    try std.testing.expect(std.mem.eql(u8, updated_setting, "updated"));
}

test "hot reload preserves defaults" {
    const allocator = std.testing.allocator;

    const test_config_path = "test_hot_reload_defaults.json";
    const initial_content =
        \\{
        \\  "dynamic": "value1"
        \\}
    ;

    // Write initial config
    {
        const file = try std.fs.cwd().createFile(test_config_path, .{});
        defer file.close();
        try file.writeAll(initial_content);
    }
    defer std.fs.cwd().deleteFile(test_config_path) catch {};

    // Load config
    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = test_config_path, .format = .json },
        },
    });
    defer config.deinit();

    // Set defaults
    try config.setDefault("default_key", flare.Value{ .string_value = "default_value" });

    // Verify both values
    const dynamic1 = try config.getString("dynamic", null);
    const default1 = try config.getString("default_key", null);
    try std.testing.expect(std.mem.eql(u8, dynamic1, "value1"));
    try std.testing.expect(std.mem.eql(u8, default1, "default_value"));

    // Update the config file
    const updated_content =
        \\{
        \\  "dynamic": "value2"
        \\}
    ;
    {
        const file = try std.fs.cwd().createFile(test_config_path, .{});
        defer file.close();
        try file.writeAll(updated_content);
    }

    // Reload
    try config.reload();

    // Verify dynamic value changed but default remained
    const dynamic2 = try config.getString("dynamic", null);
    const default2 = try config.getString("default_key", null);
    try std.testing.expect(std.mem.eql(u8, dynamic2, "value2"));
    try std.testing.expect(std.mem.eql(u8, default2, "default_value"));
}
