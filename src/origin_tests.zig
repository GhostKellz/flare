//! Tests for source precedence and value origin tracking.

const std = @import("std");
const flare = @import("root.zig");

const io = std.Options.debug_io;
const Dir = std.Io.Dir;

test "origin: file-loaded values report .file origin with path detail" {
    const allocator = std.testing.allocator;

    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = "test_config.toml", .format = .toml },
        },
    });
    defer config.deinit();

    const origin = config.getSource("database.host") orelse return error.MissingOrigin;
    try std.testing.expectEqual(flare.OriginKind.file, origin.kind);
    try std.testing.expectEqualStrings("test_config.toml", origin.detail.?);
    try std.testing.expectEqual(@as(u32, 0), origin.generation);
}

test "origin: default-only keys report .default origin" {
    const allocator = std.testing.allocator;

    var config = try flare.Config.init(allocator);
    defer config.deinit();

    try config.setDefault("timeout", .{ .int_value = 30 });

    const origin = config.getSource("timeout") orelse return error.MissingOrigin;
    try std.testing.expectEqual(flare.OriginKind.default, origin.kind);
    // Value still resolves through defaults.
    try std.testing.expectEqual(@as(i64, 30), try config.getInt("timeout", null));
}

test "origin: CLI overrides file and reports .cli origin" {
    const allocator = std.testing.allocator;

    var args = [_][]const u8{"--database.host=cli-host"};
    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = "test_config.toml", .format = .toml },
        },
        .cli = .{ .args = &args },
    });
    defer config.deinit();

    // CLI wins over the file value.
    try std.testing.expectEqualStrings("cli-host", try config.getString("database.host", null));

    const origin = config.getSource("database.host") orelse return error.MissingOrigin;
    try std.testing.expectEqual(flare.OriginKind.cli, origin.kind);
    try std.testing.expectEqualStrings("--database.host=cli-host", origin.detail.?);
}

test "origin: precedence default < file < cli" {
    const allocator = std.testing.allocator;

    // A key present only in defaults keeps .default; a key overridden by file
    // reports .file; a key overridden by CLI reports .cli.
    var args = [_][]const u8{"--name=cli-name"};
    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = "test_config.toml", .format = .toml },
        },
        .cli = .{ .args = &args },
    });
    defer config.deinit();

    // Add a default that nothing overrides.
    try config.setDefault("only_default", .{ .bool_value = true });

    try std.testing.expectEqual(flare.OriginKind.default, (config.getSource("only_default").?).kind);
    // database.port only comes from the file.
    try std.testing.expectEqual(flare.OriginKind.file, (config.getSource("database.port").?).kind);
    // name is overridden on the CLI.
    try std.testing.expectEqual(flare.OriginKind.cli, (config.getSource("name").?).kind);
}

test "origin: unset key returns null source" {
    const allocator = std.testing.allocator;

    var config = try flare.Config.init(allocator);
    defer config.deinit();

    try std.testing.expect(config.getSource("does.not.exist") == null);
}

test "origin: explain renders a human-readable line" {
    const allocator = std.testing.allocator;

    var args = [_][]const u8{"--port=9090"};
    var config = try flare.load(allocator, .{ .cli = .{ .args = &args } });
    defer config.deinit();

    const line = try config.explain(allocator, "port");
    defer allocator.free(line);

    // Should mention the key, the layer, and the flag detail.
    try std.testing.expect(std.mem.indexOf(u8, line, "port") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "command-line flag") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "--port=9090") != null);

    const unset = try config.explain(allocator, "missing");
    defer allocator.free(unset);
    try std.testing.expect(std.mem.indexOf(u8, unset, "<unset>") != null);
}

test "origin: reload bumps generation and re-resolves origins" {
    const allocator = std.testing.allocator;

    const path = "test_origin_reload.json";
    {
        const file = try Dir.cwd().createFile(io, path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, "{\"service\": \"a\"}");
    }
    defer Dir.cwd().deleteFile(io, path) catch {};

    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{.{ .path = path, .format = .json }},
    });
    defer config.deinit();

    const before = config.getSource("service") orelse return error.MissingOrigin;
    try std.testing.expectEqual(@as(u32, 0), before.generation);

    try config.reload();

    const after = config.getSource("service") orelse return error.MissingOrigin;
    try std.testing.expectEqual(flare.OriginKind.file, after.kind);
    try std.testing.expectEqual(@as(u32, 1), after.generation);
}
