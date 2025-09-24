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
pub fn initWithFlash(
    allocator: std.mem.Allocator,
    flash_context: FlashContext,
    options: FlashConfigOptions,
) !flare.Config {
    // Convert Flash flags to CLI args format
    const arena = try allocator.create(std.heap.ArenaAllocator);
    defer allocator.destroy(arena);
    arena.* = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const temp_allocator = arena.allocator();

    var cli_args = std.ArrayList([]const u8).init(temp_allocator);

    // Convert Flash flags to CLI arguments
    var flag_iter = flash_context.flags.iterator();
    while (flag_iter.next()) |entry| {
        const flag_name = entry.key_ptr.*;
        const flag_value = entry.value_ptr.*;

        // Create --flag=value format
        const cli_arg = try std.fmt.allocPrint(temp_allocator, "--{s}={s}", .{ flag_name, flag_value });
        try cli_args.append(cli_arg);
    }

    // Add raw args if any
    for (flash_context.args) |arg| {
        try cli_args.append(arg);
    }

    // Load configuration with full precedence chain
    return flare.load(allocator, .{
        .files = options.config_files,
        .env = options.env_source,
        .cli = flare.CliSource{ .args = cli_args.items },
    });
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

    /// Get config value with Flash flag override support
    pub fn getConfigValue(self: CommandContext, key: []const u8) ?flare.Value {
        // Check if there's a Flash flag that overrides this key
        if (self.flash_context.flags.get(key)) |flag_value| {
            // Parse the flag value and return it
            const value = flare.parseCliValue(self.allocator, flag_value) catch return null;
            return value;
        }

        // Otherwise get from config
        return self.config.getValue(key);
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
    _ = flag_links; // Will be used when Flash provides flag metadata
    return ConfigAwareCommand{
        .name = name,
        .about = about,
        .config_options = config_options,
        .handler = handler,
    };
}

/// Middleware to inject configuration into Flash command handlers
pub fn configMiddleware(
    allocator: std.mem.Allocator,
    flash_context: FlashContext,
    config_options: FlashConfigOptions,
    next: *const fn (context: CommandContext) anyerror!void,
) !void {
    // Initialize configuration with Flash context
    var config = try initWithFlash(allocator, flash_context, config_options);
    defer config.deinit();

    // Validate against schema if provided
    if (config_options.schema) |schema| {
        config.setSchema(schema);
        const validation_result = try config.validateSchema();
        defer validation_result.deinit();

        if (validation_result.hasErrors()) {
            std.debug.print("Configuration validation failed:\n", .{});
            for (validation_result.errors.items) |err| {
                std.debug.print("  - {s}: {s}\n", .{ err.path, err.message });
            }
            return error.ValidationFailed;
        }
    }

    // Create command context
    const context = CommandContext{
        .flash_context = flash_context,
        .config = &config,
        .allocator = allocator,
    };

    // Call the actual handler
    try next(context);
}

/// Example usage with Flash CLI
pub fn exampleUsage() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Example: Database connection command with config
    const db_command = createConfigCommand(
        "connect",
        "Connect to database",
        .{
            .config_files = &[_]flare.FileSource{
                .{ .path = "config.toml", .required = false },
                .{ .path = "~/.myapp/config.toml", .required = false },
            },
            .env_source = .{ .prefix = "MYAPP", .separator = "_" },
        },
        &[_]FlagLink{
            .{ .flag_name = "host", .config_key = "database.host", .short = "h" },
            .{ .flag_name = "port", .config_key = "database.port", .short = "p" },
            .{ .flag_name = "ssl", .config_key = "database.ssl" },
        },
        struct {
            fn handler(ctx: CommandContext) !void {
                const host = ctx.config.getString("database.host", "localhost") catch "localhost";
                const port = ctx.config.getInt("database.port", 5432) catch 5432;
                const ssl = ctx.config.getBool("database.ssl", true) catch true;

                std.debug.print("Connecting to database:\n", .{});
                std.debug.print("  Host: {s}\n", .{host});
                std.debug.print("  Port: {d}\n", .{port});
                std.debug.print("  SSL: {}\n", .{ssl});
            }
        }.handler,
    );

    // Simulate Flash context
    var flags = std.StringHashMap([]const u8).init(allocator);
    defer flags.deinit();
    try flags.put("host", "prod.db.example.com");

    const flash_ctx = FlashContext{
        .args = &[_][]const u8{},
        .flags = flags,
        .command = "connect",
    };

    // Execute with config middleware
    try configMiddleware(
        allocator,
        flash_ctx,
        db_command.config_options,
        db_command.handler,
    );
}

test "flash bridge initialization" {
    const allocator = std.testing.allocator;

    var flags = std.StringHashMap([]const u8).init(allocator);
    defer flags.deinit();

    try flags.put("debug", "true");
    try flags.put("port", "8080");

    const flash_ctx = FlashContext{
        .args = &[_][]const u8{ "--verbose" },
        .flags = flags,
    };

    var config = try initWithFlash(allocator, flash_ctx, .{});
    defer config.deinit();

    // Test that CLI flags were loaded
    const debug = try config.getBool("debug", null);
    const port = try config.getInt("port", null);

    try std.testing.expect(debug == true);
    try std.testing.expect(port == 8080);
}