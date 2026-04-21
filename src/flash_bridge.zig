//! Flash CLI Framework Integration Bridge
//! Provides seamless integration between Flash CLI and Flare configuration

const std = @import("std");
const flare = @import("root.zig");

/// Flash CLI Context wrapper for Flare integration
pub const FlashContext = struct {
    /// Parsed CLI arguments from Flash
    args: [][]const u8,
    /// Command-specific flags
    flags: std.StringHashMap([]const u8),
    /// Subcommand if present
    command: ?[]const u8 = null,
};

/// Initialize Flare config with Flash CLI context
/// flag_links maps Flash flag names to config keys
pub fn initWithFlash(
    allocator: std.mem.Allocator,
    flash_context: FlashContext,
    options: FlashConfigOptions,
    flag_links: []const FlagLink,
) !flare.Config {
    // Load base configuration from files and env
    var config = try flare.load(allocator, .{
        .files = options.config_files,
        .env = options.env_source,
    });

    // Apply Flash flags using FlagLink mappings
    // This ensures flag "host" maps to config key "database.host"
    const arena = config.getArenaAllocator();

    for (flag_links) |link| {
        // Check if this flag was provided
        var flag_value: ?[]const u8 = null;

        if (flash_context.flags.get(link.flag_name)) |v| {
            flag_value = v;
        } else if (link.short) |short| {
            if (flash_context.flags.get(short)) |v| {
                flag_value = v;
            }
        }

        if (flag_value) |value| {
            // Parse and set the value at the config_key path
            const parsed = try flare.parseCliValue(arena, value);
            // Recursively set nested values (for JSON objects/arrays)
            try setValueRecursive(&config, arena, link.config_key, parsed);
        }
    }

    return config;
}

/// Recursively set config values, flattening nested objects into dotted keys
fn setValueRecursive(config: *flare.Config, arena: std.mem.Allocator, prefix: []const u8, value: flare.Value) !void {
    switch (value) {
        .map_value => |map| {
            // For maps, recursively set each key with dotted path
            var it = map.iterator();
            while (it.next()) |entry| {
                const full_key = if (prefix.len > 0)
                    try std.fmt.allocPrint(arena, "{s}.{s}", .{ prefix, entry.key_ptr.* })
                else
                    try arena.dupe(u8, entry.key_ptr.*);
                try setValueRecursive(config, arena, full_key, entry.value_ptr.*);
            }
            // Also store the map itself at the prefix (for getMap())
            try config.setValue(prefix, value);
        },
        .array_value => |arr| {
            // Store array as-is
            try config.setValue(prefix, value);
            // Also store individual elements with indexed keys
            for (arr.items, 0..) |item, i| {
                const indexed_key = try std.fmt.allocPrint(arena, "{s}[{d}]", .{ prefix, i });
                try config.setValue(indexed_key, item);
            }
        },
        else => {
            // Primitive values - just set directly
            try config.setValue(prefix, value);
        },
    }
}

/// Options for Flash configuration integration
pub const FlashConfigOptions = struct {
    /// Configuration files to load (in order of precedence)
    config_files: ?[]const flare.FileSource = null,
    /// Environment variable configuration
    env_source: ?flare.EnvSource = null,
    /// Schema for validation
    schema: ?*const flare.Schema = null,
};

/// Flash Command with integrated configuration
pub const ConfigAwareCommand = struct {
    name: []const u8,
    about: []const u8,
    config_options: FlashConfigOptions,
    flag_links: []const FlagLink,
    handler: *const fn (context: CommandContext) anyerror!void,
};

/// Command context with integrated configuration
pub const CommandContext = struct {
    /// Flash CLI context
    flash_context: FlashContext,
    /// Flare configuration (already loaded and validated)
    config: *flare.Config,
    /// Allocator for command use
    allocator: std.mem.Allocator,
    /// Flag links for config_key -> flag_name mapping
    flag_links: []const FlagLink,

    /// Get config value with Flash flag override support
    /// Looks up the config_key in flag_links to find the corresponding flag_name
    pub fn getConfigValue(self: CommandContext, config_key: []const u8) ?flare.Value {
        // First check if there's a FlagLink that maps a flag to this config key
        for (self.flag_links) |link| {
            if (std.mem.eql(u8, link.config_key, config_key)) {
                // Found a link - check if this flag was provided
                if (self.flash_context.flags.get(link.flag_name)) |flag_value| {
                    // Parse using config's arena to avoid ownership issues
                    const arena = self.config.getArenaAllocator();
                    const value = flare.parseCliValue(arena, flag_value) catch return null;
                    return value;
                }
                // Also check short flag if present
                if (link.short) |short| {
                    if (self.flash_context.flags.get(short)) |flag_value| {
                        const arena = self.config.getArenaAllocator();
                        const value = flare.parseCliValue(arena, flag_value) catch return null;
                        return value;
                    }
                }
            }
        }

        // Fall back to config value
        return self.config.getValue(config_key);
    }
};

/// Helper to link Flash flags to config keys
pub const FlagLink = struct {
    /// The Flash flag name (e.g., "host", "port")
    flag_name: []const u8,
    /// The config key path (e.g., "database.host", "server.port")
    config_key: []const u8,
    /// Optional short flag (e.g., "h" for --host)
    short: ?[]const u8 = null,
};

/// Create a Flash command with Flare config integration
pub fn createConfigCommand(
    name: []const u8,
    about: []const u8,
    config_options: FlashConfigOptions,
    flag_links: []const FlagLink,
    handler: *const fn (context: CommandContext) anyerror!void,
) ConfigAwareCommand {
    return ConfigAwareCommand{
        .name = name,
        .about = about,
        .config_options = config_options,
        .flag_links = flag_links,
        .handler = handler,
    };
}

/// Middleware to inject configuration into Flash command handlers
pub fn configMiddleware(
    allocator: std.mem.Allocator,
    flash_context: FlashContext,
    config_options: FlashConfigOptions,
    flag_links: []const FlagLink,
    next: *const fn (context: CommandContext) anyerror!void,
) !void {
    // Initialize configuration with Flash context and flag mappings
    var config = try initWithFlash(allocator, flash_context, config_options, flag_links);
    defer config.deinit();

    // Validate against schema if provided
    if (config_options.schema) |schema| {
        config.setSchema(schema);
        var validation_result = try config.validateSchema();
        defer validation_result.deinit(allocator);

        if (validation_result.hasErrors()) {
            std.debug.print("Configuration validation failed:\n", .{});
            for (validation_result.errors.items) |err| {
                std.debug.print("  - {s}: {s}\n", .{ err.path, err.message });
            }
            return error.ValidationFailed;
        }
    }

    // Create command context with flag links for runtime lookups
    const context = CommandContext{
        .flash_context = flash_context,
        .config = &config,
        .allocator = allocator,
        .flag_links = flag_links,
    };

    // Call the actual handler
    try next(context);
}

/// Example usage with Flash CLI
pub fn exampleUsage() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    // Define flag links - maps CLI flags to config keys
    const flag_links = [_]FlagLink{
        .{ .flag_name = "host", .config_key = "database.host", .short = "h" },
        .{ .flag_name = "port", .config_key = "database.port", .short = "p" },
        .{ .flag_name = "ssl", .config_key = "database.ssl" },
    };

    // Example: Database connection command with config
    const db_command = createConfigCommand(
        "connect",
        "Connect to database",
        .{
            .config_files = &[_]flare.FileSource{
                .{ .path = "config.toml", .required = false },
                .{ .path = "~/.myapp/config.toml", .required = false },
            },
            .env_source = .{ .prefix = "MYAPP", .separator = "_", .env_map = &env_map },
        },
        &flag_links,
        struct {
            fn handler(ctx: CommandContext) !void {
                // Use getConfigValue which respects FlagLink mappings
                // Flag "host" maps to config key "database.host"
                const host_val = ctx.getConfigValue("database.host");
                const host = if (host_val) |v| v.string_value else "localhost";

                const port = ctx.config.getInt("database.port", 5432) catch 5432;
                const ssl = ctx.config.getBool("database.ssl", true) catch true;

                std.debug.print("Connecting to database:\n", .{});
                std.debug.print("  Host: {s}\n", .{host});
                std.debug.print("  Port: {d}\n", .{port});
                std.debug.print("  SSL: {}\n", .{ssl});
            }
        }.handler,
    );

    // Simulate Flash context - user passes --host flag
    var flags = std.StringHashMap([]const u8).init(allocator);
    defer flags.deinit();
    try flags.put("host", "prod.db.example.com");

    const flash_ctx = FlashContext{
        .args = &[_][]const u8{},
        .flags = flags,
        .command = "connect",
    };

    // Execute with config middleware - flag_links enables proper mapping
    try configMiddleware(
        allocator,
        flash_ctx,
        db_command.config_options,
        db_command.flag_links,
        db_command.handler,
    );
}

test "flash bridge initialization with flag links" {
    const allocator = std.testing.allocator;

    var flags = std.StringHashMap([]const u8).init(allocator);
    defer flags.deinit();

    // User passes --host and --port flags
    try flags.put("host", "prod.example.com");
    try flags.put("port", "3306");

    const flash_ctx = FlashContext{
        .args = &[_][]const u8{},
        .flags = flags,
    };

    // Define flag links: flag "host" maps to config key "database.host"
    const flag_links = [_]FlagLink{
        .{ .flag_name = "host", .config_key = "database.host" },
        .{ .flag_name = "port", .config_key = "database.port" },
    };

    var config = try initWithFlash(allocator, flash_ctx, .{}, &flag_links);
    defer config.deinit();

    // Test that flags were mapped to correct config keys
    const db_host = try config.getString("database.host", null);
    const db_port = try config.getInt("database.port", null);

    try std.testing.expectEqualStrings("prod.example.com", db_host);
    try std.testing.expectEqual(@as(i64, 3306), db_port);
}

test "flash bridge getConfigValue with flag links" {
    const allocator = std.testing.allocator;

    var flags = std.StringHashMap([]const u8).init(allocator);
    defer flags.deinit();

    // User passes -h (short flag for host)
    try flags.put("h", "short.example.com");

    const flash_ctx = FlashContext{
        .args = &[_][]const u8{},
        .flags = flags,
    };

    const flag_links = [_]FlagLink{
        .{ .flag_name = "host", .config_key = "database.host", .short = "h" },
    };

    var config = try initWithFlash(allocator, flash_ctx, .{}, &flag_links);
    defer config.deinit();

    // Create command context
    const ctx = CommandContext{
        .flash_context = flash_ctx,
        .config = &config,
        .allocator = allocator,
        .flag_links = &flag_links,
    };

    // getConfigValue should find the short flag and map it
    const value = ctx.getConfigValue("database.host");
    try std.testing.expect(value != null);
    try std.testing.expectEqualStrings("short.example.com", value.?.string_value);
}

test "flash bridge unmapped flags do not override config" {
    const allocator = std.testing.allocator;

    var flags = std.StringHashMap([]const u8).init(allocator);
    defer flags.deinit();

    // User passes --random flag that is not in flag_links
    try flags.put("random", "should-not-appear");

    const flash_ctx = FlashContext{
        .args = &[_][]const u8{},
        .flags = flags,
    };

    // Only map "host" to "database.host"
    const flag_links = [_]FlagLink{
        .{ .flag_name = "host", .config_key = "database.host" },
    };

    var config = try initWithFlash(allocator, flash_ctx, .{}, &flag_links);
    defer config.deinit();

    // "random" flag should NOT create a "random" config key
    const random_val = config.getValue("random");
    try std.testing.expect(random_val == null);

    // And definitely not override "database.host"
    const db_host = config.getValue("database.host");
    try std.testing.expect(db_host == null);
}

test "flash bridge precedence: file vs env vs flag" {
    const allocator = std.testing.allocator;

    // Simulate env vars with a custom map
    var env_map: std.process.Environ.Map = .init(allocator);
    defer env_map.deinit();
    try env_map.put("APP__DATABASE__HOST", "env-host.example.com");
    try env_map.put("APP__DATABASE__PORT", "5432");

    // Simulate Flash flags
    var flags = std.StringHashMap([]const u8).init(allocator);
    defer flags.deinit();
    try flags.put("host", "flag-host.example.com"); // Flag should win

    const flash_ctx = FlashContext{
        .args = &[_][]const u8{},
        .flags = flags,
    };

    const flag_links = [_]FlagLink{
        .{ .flag_name = "host", .config_key = "database.host" },
        .{ .flag_name = "port", .config_key = "database.port" },
    };

    // Load with file + env + Flash - Flash flags should have highest precedence
    var config = try initWithFlash(allocator, flash_ctx, .{
        .config_files = &[_]flare.FileSource{
            .{ .path = "test_config.json" }, // Contains database.host = "localhost"
        },
        .env_source = .{
            .prefix = "APP",
            .separator = "__",
            .env_map = &env_map,
        },
    }, &flag_links);
    defer config.deinit();

    // Flag should override env which overrides file
    const db_host = try config.getString("database.host", null);
    try std.testing.expectEqualStrings("flag-host.example.com", db_host);

    // Port was in env but not flags, so env should override file
    const db_port = try config.getInt("database.port", null);
    try std.testing.expectEqual(@as(i64, 5432), db_port);
}

test "flash bridge: nested JSON flag value" {
    const allocator = std.testing.allocator;

    var flags = std.StringHashMap([]const u8).init(allocator);
    defer flags.deinit();

    // Pass a JSON object as a flag value
    try flags.put("server", "{\"host\":\"override.com\",\"port\":9090}");

    const flash_ctx = FlashContext{
        .args = &[_][]const u8{},
        .flags = flags,
    };

    const flag_links = [_]FlagLink{
        .{ .flag_name = "server", .config_key = "server" },
    };

    var config = try initWithFlash(allocator, flash_ctx, .{}, &flag_links);
    defer config.deinit();

    // JSON should be parsed recursively
    const host = try config.getString("server.host", null);
    const port = try config.getInt("server.port", null);

    try std.testing.expectEqualStrings("override.com", host);
    try std.testing.expectEqual(@as(i64, 9090), port);
}

test "flash bridge: nested JSON array flag value" {
    const allocator = std.testing.allocator;

    var flags = std.StringHashMap([]const u8).init(allocator);
    defer flags.deinit();

    // Pass a JSON array as a flag value
    try flags.put("ports", "[8080,9090,3000]");

    const flash_ctx = FlashContext{
        .args = &[_][]const u8{},
        .flags = flags,
    };

    const flag_links = [_]FlagLink{
        .{ .flag_name = "ports", .config_key = "server.ports" },
    };

    var config = try initWithFlash(allocator, flash_ctx, .{}, &flag_links);
    defer config.deinit();

    // Array should be accessible
    const ports_value = config.getValue("server.ports");
    try std.testing.expect(ports_value != null);
    try std.testing.expect(ports_value.? == .array_value);

    const ports = ports_value.?.array_value.items;
    try std.testing.expectEqual(@as(usize, 3), ports.len);
    try std.testing.expectEqual(@as(i64, 8080), ports[0].int_value);
    try std.testing.expectEqual(@as(i64, 9090), ports[1].int_value);
    try std.testing.expectEqual(@as(i64, 3000), ports[2].int_value);
}
