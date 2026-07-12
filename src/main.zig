//! Flare Configuration Library - CLI + Demo
//!
//! With no arguments this runs a short demonstration (used by `zig build run`).
//! With `validate`/`lint <file>...` it acts as a config linter: each file is
//! parsed and its status reported, exiting non-zero if any file is invalid so
//! it can gate CI or a pre-commit hook.

const std = @import("std");
const flare = @import("flare");

const io = std.Options.debug_io;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var args_it = init.minimal.args.iterate();
    _ = args_it.skip(); // program name

    const command = args_it.next() orelse {
        // No subcommand: run the demonstration so `zig build run` still works.
        return runDemo(allocator, init);
    };

    if (std.mem.eql(u8, command, "validate") or std.mem.eql(u8, command, "lint")) {
        return runValidate(allocator, &args_it);
    }
    if (std.mem.eql(u8, command, "help") or
        std.mem.eql(u8, command, "-h") or
        std.mem.eql(u8, command, "--help"))
    {
        printUsage();
        return;
    }

    std.debug.print("flare: unknown command '{s}'\n\n", .{command});
    printUsage();
    std.process.exit(2);
}

fn printUsage() void {
    std.debug.print(
        \\Usage:
        \\  flare                       Run the demonstration.
        \\  flare validate <file>...    Parse each config file and report errors.
        \\  flare lint <file>...        Alias for validate.
        \\  flare help                  Show this help.
        \\
        \\Supported formats: .toml (TOML 1.0) and .json. Format is chosen by
        \\extension; unknown extensions are parsed as JSON.
        \\
        \\Exit status: 0 if all files are valid, 1 if any file fails to parse,
        \\2 for usage errors.
        \\
    , .{});
}

/// Parse every path from `args_it`, reporting each file's status. Exits with
/// code 1 if any file is invalid, 2 if no files were given.
fn runValidate(allocator: std.mem.Allocator, args_it: *std.process.Args.Iterator) !void {
    var checked: usize = 0;
    var failures: usize = 0;

    while (args_it.next()) |path| {
        checked += 1;
        if (!validateFile(allocator, path)) failures += 1;
    }

    if (checked == 0) {
        std.debug.print("flare validate: no files given\n\n", .{});
        printUsage();
        std.process.exit(2);
    }

    if (failures != 0) {
        std.debug.print("\n{d} of {d} file(s) failed validation.\n", .{ failures, checked });
        std.process.exit(1);
    }
    std.debug.print("All {d} file(s) valid.\n", .{checked});
}

/// Parse one config file and print its status. Returns true when the file
/// parsed cleanly. TOML surfaces the parser's line/column diagnostics; JSON is
/// validated through std.json, the same path `flare.load` uses.
fn validateFile(allocator: std.mem.Allocator, path: []const u8) bool {
    const contents = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(10 * 1024 * 1024)) catch |err| {
        std.debug.print("{s}: cannot read file ({s})\n", .{ path, @errorName(err) });
        return false;
    };
    defer allocator.free(contents);

    if (std.mem.endsWith(u8, path, ".toml")) {
        const result = flare.parseTomlWithContext(allocator, contents);
        defer result.deinitError(allocator);
        if (result.isError()) {
            const ctx = result.error_context.?;
            std.debug.print("{s}:{d}:{d}: {s}\n", .{ path, ctx.line, ctx.column, ctx.message });
            if (ctx.suggestion) |s| std.debug.print("    hint: {s}\n", .{s});
            return false;
        }
        // Success path still allocates a table; free it since we only need the
        // verdict, not the parsed data.
        if (result.table) |t| {
            t.deinit();
            allocator.destroy(t);
        }
        std.debug.print("{s}: OK\n", .{path});
        return true;
    }

    // Default to JSON for .json and unknown extensions.
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, contents, .{}) catch |err| {
        std.debug.print("{s}: invalid JSON ({s})\n", .{ path, @errorName(err) });
        return false;
    };
    parsed.deinit();
    std.debug.print("{s}: OK\n", .{path});
    return true;
}

fn runDemo(allocator: std.mem.Allocator, init: std.process.Init) !void {
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
    try config.setDefault("app.version", flare.Value{ .string_value = flare.VERSION });

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
