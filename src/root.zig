//! Flare - Configuration management library for Zig
//! What viper is to Cobra in Go, Flare is to Flash in Zig

const std = @import("std");
const build_options = @import("build_options");

/// Library version, sourced from build.zig.zon (single source of truth).
pub const VERSION = build_options.version;

// Export schema and validation modules
pub const Schema = @import("schema.zig").Schema;
pub const SchemaError = @import("schema.zig").SchemaError;
pub const ValidationResult = @import("schema.zig").ValidationResult;
pub const Validator = @import("validator.zig").Validator;
pub const validateConfig = @import("validator.zig").validateConfig;

// Export Flash bridge module
pub const flash = @import("flash_bridge.zig");

// Export native TOML types (full TOML 1.0 support)
pub const toml_value = @import("toml_value.zig");
pub const TomlValue = toml_value.TomlValue;
pub const TomlTable = toml_value.TomlTable;
pub const TomlArray = toml_value.TomlArray;
pub const Datetime = toml_value.Datetime;
pub const Date = toml_value.Date;
pub const Time = toml_value.Time;
pub const tomlValueToFlareValue = toml_value.tomlValueToFlareValue;
pub const flareValueToTomlValue = toml_value.flareValueToTomlValue;

// Export TOML lexer and parser (full TOML 1.0 parser)
pub const toml_lexer = @import("toml_lexer.zig");
pub const toml_parser = @import("toml_parser.zig");
pub const parseToml = toml_parser.parseToml;
pub const parseTomlWithContext = toml_parser.parseTomlWithContext;
pub const ParseError = toml_parser.ParseError;
pub const ParseResult = toml_parser.ParseResult;
pub const ErrorContext = toml_parser.ErrorContext;

// Export struct deserialization
pub const deserialize_mod = @import("deserialize.zig");
pub const parseInto = deserialize_mod.parseInto;
pub const deserialize = deserialize_mod.deserialize;
pub const freeDeserialized = deserialize_mod.free;
pub const DeserializeError = deserialize_mod.DeserializeError;

// Export struct serialization (struct -> TOML)
pub const serialize_mod = @import("serialize.zig");
pub const serialize = serialize_mod.serialize;
pub const toTomlString = serialize_mod.toTomlString;
pub const SerializeError = serialize_mod.SerializeError;

// Export TOML stringification
pub const stringify_mod = @import("stringify.zig");
pub const stringify = stringify_mod.stringify;
pub const stringifyWithOptions = stringify_mod.stringifyWithOptions;
pub const saveToFile = stringify_mod.saveToFile;
pub const saveToFileWithOptions = stringify_mod.saveToFileWithOptions;
pub const FormatOptions = stringify_mod.FormatOptions;
pub const StringifyError = stringify_mod.StringifyError;

// Export TOML to JSON conversion
pub const convert = @import("convert.zig");
pub const toJSON = convert.toJSON;
pub const toJSONPretty = convert.toJSONPretty;
pub const ConvertError = convert.ConvertError;

// Export TOML diff and merge utilities
pub const diff_mod = @import("diff.zig");
pub const diff = diff_mod.diff;
pub const merge = diff_mod.merge;
pub const Diff = diff_mod.Diff;
pub const DiffType = diff_mod.DiffType;
pub const DiffResult = diff_mod.DiffResult;
pub const DiffError = diff_mod.DiffError;
pub const MergeError = diff_mod.MergeError;

// Export schema generation from types
pub const schema_gen = @import("schema_gen.zig");
pub const schemaFrom = schema_gen.schemaFrom;
pub const TomlSchema = schema_gen.TomlSchema;
pub const FieldSchema = schema_gen.FieldSchema;
pub const ValueType = schema_gen.ValueType;
pub const Constraint = schema_gen.Constraint;
pub const SchemaBuilder = schema_gen.SchemaBuilder;
pub const TomlValidationResult = schema_gen.TomlValidationResult;

/// Flare error types
pub const FlareError = error{
    ParseError,
    MissingKey,
    TypeMismatch,
    Io,
    Validation,
    OutOfMemory,
    InvalidPath,
    InvalidArrayIndex,
    InvalidFormat,
    WatcherNotInitialized,
};

/// Configuration value types
pub const Value = union(enum) {
    null_value,
    bool_value: bool,
    int_value: i64,
    float_value: f64,
    string_value: []const u8,
    array_value: std.ArrayList(Value),
    map_value: std.StringHashMap(Value),
};

/// Which layer a config value's final value came from.
/// Ordered lowest to highest precedence, matching load order.
pub const OriginKind = enum {
    default,
    file,
    env,
    cli,
    /// Set programmatically via setValue after load.
    set,
};

/// Provenance of a resolved config value: which layer won, an optional detail
/// (file path, env var name, or CLI flag), and the reload generation in which
/// it was set. Enables Viper-style "why does this key have this value?" queries.
pub const ValueOrigin = struct {
    kind: OriginKind,
    /// Human-facing source detail: file path / env var name / CLI flag.
    detail: ?[]const u8 = null,
    /// Reload generation the value was written in (0 on initial load).
    generation: u32 = 0,
};

/// A strict-mode diagnostic: a key whose value type changed when a
/// higher-precedence source overrode a lower one (e.g. a file set `port` to an
/// int and an env var later set it to a string). Recorded only when strict mode
/// is enabled. Detection is by exact (already-flattened) key, so it fires on
/// keys written identically across sources.
pub const ValueConflict = struct {
    key: []const u8,
    /// Origin layer and value type of the value that was overwritten.
    previous_kind: OriginKind,
    previous_type: []const u8,
    /// Origin layer and value type of the overriding value.
    new_kind: OriginKind,
    new_type: []const u8,
};

/// Short type name for a Value tag, used in strict-mode conflict diagnostics.
fn valueTypeName(value: Value) []const u8 {
    return switch (value) {
        .null_value => "null",
        .bool_value => "bool",
        .int_value => "int",
        .float_value => "float",
        .string_value => "string",
        .array_value => "array",
        .map_value => "object",
    };
}

/// Callback function type for config change notifications
pub const ChangeCallback = *const fn (*Config) void;

/// File watcher state for hot reload
pub const FileWatcher = struct {
    path: []const u8,
    last_modified: i128, // nanoseconds since epoch
};

/// Core configuration type with immutable snapshot and memory pool
pub const Config = struct {
    allocator: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    data: std.StringHashMap(Value),
    defaults: std.StringHashMap(Value),
    /// Provenance sidecar: flattened data key -> origin of its current value.
    origins: std.StringHashMap(ValueOrigin),
    /// Bumped on each reload so origins can report which generation set a value.
    generation: u32 = 0,
    schema_def: ?*const Schema = null,
    watched_files: ?std.ArrayList(FileWatcher) = null,
    load_options: ?LoadOptions = null,
    change_callback: ?ChangeCallback = null,
    /// Diagnostic from the most recent reload attempt: null while the last
    /// reload (or initial load) succeeded, otherwise the error that caused the
    /// attempt to be rejected. On failure the previous good state is retained.
    last_reload_error: ?FlareError = null,
    /// Minimum quiescence window (nanoseconds) a watched file must be stable for
    /// before `checkAndReload` acts on it. 0 (default) reloads immediately.
    /// Coalesces bursts of rapid writes into a single reload once the file
    /// settles. Set via `setReloadDebounce`.
    reload_debounce_ns: i128 = 0,
    /// When true, cross-source value-type changes are recorded in `conflicts`
    /// as they are applied. Off by default; enable via LoadOptions.strict.
    strict: bool = false,
    /// Strict-mode conflict log (arena-backed). Populated during load/reload.
    conflicts: std.ArrayList(ValueConflict) = .empty,

    const Self = @This();

    /// Initialize a new Config instance
    pub fn init(allocator: std.mem.Allocator) !Self {
        const arena = try allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(allocator);
        const arena_allocator = arena.allocator();

        return Self{
            .allocator = allocator,
            .arena = arena,
            .data = std.StringHashMap(Value).init(arena_allocator),
            .defaults = std.StringHashMap(Value).init(arena_allocator),
            .origins = std.StringHashMap(ValueOrigin).init(arena_allocator),
            .schema_def = null,
        };
    }

    /// Initialize a new Config instance with schema validation
    pub fn initWithSchema(allocator: std.mem.Allocator, schema_def: *const Schema) !Self {
        var config = try init(allocator);
        config.schema_def = schema_def;
        return config;
    }

    /// Clean up resources - arena allocator handles all memory cleanup
    pub fn deinit(self: *Self) void {
        if (self.watched_files) |*watchers| {
            // Free each watched file path
            for (watchers.items) |watcher| {
                self.allocator.free(watcher.path);
            }
            watchers.deinit(self.allocator);
        }
        const arena = self.arena;
        arena.deinit();
        self.allocator.destroy(arena);
    }

    /// Get arena allocator for config operations
    pub fn getArenaAllocator(self: *Self) std.mem.Allocator {
        return self.arena.allocator();
    }

    /// Set a default value for a configuration key
    pub fn setDefault(self: *Self, key: []const u8, value: Value) !void {
        const arena_allocator = self.getArenaAllocator();
        const owned_key = try arena_allocator.dupe(u8, key);
        const owned_value = try self.cloneValue(value);
        try self.defaults.put(owned_key, owned_value);
    }

    /// Get a boolean value by key path
    pub fn getBool(self: *Self, key: []const u8, default_value: ?bool) FlareError!bool {
        if (self.getValue(key)) |value| {
            return switch (value) {
                .bool_value => |b| b,
                .string_value => |s| std.mem.eql(u8, s, "true") or std.mem.eql(u8, s, "1"),
                .int_value => |i| i != 0,
                else => FlareError.TypeMismatch,
            };
        }
        return default_value orelse FlareError.MissingKey;
    }

    /// Get an integer value by key path
    pub fn getInt(self: *Self, key: []const u8, default_value: ?i64) FlareError!i64 {
        if (self.getValue(key)) |value| {
            return switch (value) {
                .int_value => |i| i,
                .float_value => |f| @intFromFloat(f),
                .string_value => |s| std.fmt.parseInt(i64, s, 10) catch FlareError.TypeMismatch,
                else => FlareError.TypeMismatch,
            };
        }
        return default_value orelse FlareError.MissingKey;
    }

    /// Get a float value by key path
    pub fn getFloat(self: *Self, key: []const u8, default_value: ?f64) FlareError!f64 {
        if (self.getValue(key)) |value| {
            return switch (value) {
                .float_value => |f| f,
                .int_value => |i| @floatFromInt(i),
                .string_value => |s| std.fmt.parseFloat(f64, s) catch FlareError.TypeMismatch,
                else => FlareError.TypeMismatch,
            };
        }
        return default_value orelse FlareError.MissingKey;
    }

    /// Get a string value by key path
    pub fn getString(self: *Self, key: []const u8, default_value: ?[]const u8) FlareError![]const u8 {
        if (self.getValue(key)) |value| {
            return switch (value) {
                .string_value => |s| s,
                else => FlareError.TypeMismatch,
            };
        }
        return default_value orelse FlareError.MissingKey;
    }

    /// Get an array value by key path
    pub fn getArray(self: *Self, key: []const u8) FlareError!std.ArrayList(Value) {
        if (self.getValue(key)) |value| {
            return switch (value) {
                .array_value => |arr| arr,
                else => FlareError.TypeMismatch,
            };
        }
        return FlareError.MissingKey;
    }

    /// Get a map value by key path
    pub fn getMap(self: *Self, key: []const u8) FlareError!std.StringHashMap(Value) {
        if (self.getValue(key)) |value| {
            return switch (value) {
                .map_value => |map| map,
                else => FlareError.TypeMismatch,
            };
        }
        return FlareError.MissingKey;
    }

    /// Get a list of strings by key path
    pub fn getStringList(self: *Self, key: []const u8) FlareError![][]const u8 {
        const array = try self.getArray(key);
        const arena_allocator = self.getArenaAllocator();
        const result = try arena_allocator.alloc([]const u8, array.items.len);

        for (array.items, 0..) |item, i| {
            result[i] = switch (item) {
                .string_value => |s| s,
                else => return FlareError.TypeMismatch,
            };
        }
        return result;
    }

    /// Get a value by array index (e.g., "servers[0]")
    pub fn getByIndex(self: *Self, key: []const u8, index: usize) FlareError!Value {
        const array = try self.getArray(key);
        if (index >= array.items.len) {
            return FlareError.InvalidArrayIndex;
        }
        return array.items[index];
    }

    /// Internal helper to get a value by key, checking data first, then defaults
    pub fn getValue(self: *Self, key: []const u8) ?Value {
        // First try the direct key lookup
        if (self.data.get(key)) |value| {
            return value;
        }
        if (self.defaults.get(key)) |value| {
            return value;
        }

        // If not found and key contains dots, try path traversal
        if (std.mem.indexOf(u8, key, ".") != null) {
            return self.getValueByPath(key);
        }

        return null;
    }

    /// Helper to navigate nested paths (e.g., "db.host", "servers[0]")
    /// Uses stack buffer to avoid arena allocation on every read
    fn getValueByPath(self: *Self, path: []const u8) ?Value {
        // Use stack buffer for dot-to-underscore transformation (256 bytes covers most keys)
        var stack_buffer: [256]u8 = undefined;

        const key = if (path.len <= stack_buffer.len) blk: {
            // Common case: use stack buffer (zero allocation)
            for (path, 0..) |c, i| {
                stack_buffer[i] = if (c == '.') '_' else c;
            }
            break :blk stack_buffer[0..path.len];
        } else blk: {
            // Rare case: very long key, fall back to arena allocation
            const arena_allocator = self.getArenaAllocator();
            const heap_buffer = arena_allocator.alloc(u8, path.len) catch return null;
            for (path, 0..) |c, i| {
                heap_buffer[i] = if (c == '.') '_' else c;
            }
            break :blk heap_buffer;
        };

        // Try the flattened key in both data and defaults
        if (self.data.get(key)) |value| {
            return value;
        }
        return self.defaults.get(key);
    }

    /// Return the origin of a key's resolved value, mirroring getValue's
    /// data-then-defaults precedence. Returns null when the key is unset.
    pub fn getSource(self: *Self, key: []const u8) ?ValueOrigin {
        if (self.data.get(key)) |_| return self.origins.get(key);
        if (self.defaults.get(key)) |_| return ValueOrigin{ .kind = .default, .generation = self.generation };

        if (std.mem.indexOf(u8, key, ".") != null) {
            var stack_buffer: [256]u8 = undefined;
            if (key.len <= stack_buffer.len) {
                for (key, 0..) |c, i| stack_buffer[i] = if (c == '.') '_' else c;
                const flat = stack_buffer[0..key.len];
                if (self.data.get(flat)) |_| return self.origins.get(flat);
                if (self.defaults.get(flat)) |_| return ValueOrigin{ .kind = .default, .generation = self.generation };
            }
        }
        return null;
    }

    /// Format a human-readable explanation of why a key has its final value:
    /// which layer set it, the source detail, and the reload generation.
    /// Caller owns the returned slice (allocated with `alloc`).
    pub fn explain(self: *Self, alloc: std.mem.Allocator, key: []const u8) ![]const u8 {
        const origin = self.getSource(key) orelse
            return std.fmt.allocPrint(alloc, "{s}: <unset>", .{key});

        const layer = switch (origin.kind) {
            .default => "default",
            .file => "file",
            .env => "environment variable",
            .cli => "command-line flag",
            .set => "programmatic set",
        };
        if (origin.detail) |d| {
            return std.fmt.allocPrint(alloc, "{s} <- {s} ({s}), generation {d}", .{ key, layer, d, origin.generation });
        }
        return std.fmt.allocPrint(alloc, "{s} <- {s}, generation {d}", .{ key, layer, origin.generation });
    }

    /// Set a value in the config (used by loaders).
    /// Records the value's origin as a programmatic set.
    pub fn setValue(self: *Self, key: []const u8, value: Value) !void {
        return self.setValueWithOrigin(key, value, .{ .kind = .set });
    }

    /// Set a value and record where it came from. Loaders pass the layer origin
    /// (file/env/cli) so precedence can later be explained. The generation field
    /// of the supplied origin is ignored and replaced with the current one.
    pub fn setValueWithOrigin(self: *Self, key: []const u8, value: Value, origin: ValueOrigin) !void {
        const arena_allocator = self.getArenaAllocator();
        const owned_key = try arena_allocator.dupe(u8, key);
        const owned_value = switch (value) {
            .null_value => .null_value,
            .bool_value => |b| Value{ .bool_value = b },
            .int_value => |i| Value{ .int_value = i },
            .float_value => |f| Value{ .float_value = f },
            .string_value => |s| Value{ .string_value = try arena_allocator.dupe(u8, s) },
            .array_value => |arr| blk: {
                var new_array: std.ArrayList(Value) = .empty;
                try new_array.ensureTotalCapacity(arena_allocator, arr.items.len);
                for (arr.items) |item| {
                    try new_array.append(arena_allocator, try self.cloneValue(item));
                }
                break :blk Value{ .array_value = new_array };
            },
            .map_value => |map| blk: {
                var new_map = std.StringHashMap(Value).init(arena_allocator);
                var iter = map.iterator();
                while (iter.next()) |entry| {
                    const k = try arena_allocator.dupe(u8, entry.key_ptr.*);
                    const v = try self.cloneValue(entry.value_ptr.*);
                    try new_map.put(k, v);
                }
                break :blk Value{ .map_value = new_map };
            },
        };
        // Strict mode: flag a value-type change under an existing key before we
        // overwrite it, attributing the previous value to its recorded origin.
        if (self.strict) {
            if (self.data.get(owned_key)) |existing| {
                if (@as(std.meta.Tag(Value), existing) != @as(std.meta.Tag(Value), owned_value)) {
                    const prev_origin = self.origins.get(owned_key);
                    try self.conflicts.append(arena_allocator, .{
                        .key = owned_key,
                        .previous_kind = if (prev_origin) |o| o.kind else .default,
                        .previous_type = valueTypeName(existing),
                        .new_kind = origin.kind,
                        .new_type = valueTypeName(owned_value),
                    });
                }
            }
        }

        try self.data.put(owned_key, owned_value);

        // Record provenance under the same arena-owned key.
        var stored_origin = origin;
        stored_origin.generation = self.generation;
        if (origin.detail) |d| stored_origin.detail = try arena_allocator.dupe(u8, d);
        try self.origins.put(owned_key, stored_origin);
    }

    /// Helper to clone a value for storage (uses arena allocator)
    fn cloneValue(self: *Self, value: Value) !Value {
        return cloneValueWithAllocator(self.getArenaAllocator(), value);
    }

    /// Clone a value using a specific allocator
    fn cloneValueWithAllocator(alloc: std.mem.Allocator, value: Value) !Value {
        return switch (value) {
            .null_value => .null_value,
            .bool_value => |b| Value{ .bool_value = b },
            .int_value => |i| Value{ .int_value = i },
            .float_value => |f| Value{ .float_value = f },
            .string_value => |s| Value{ .string_value = try alloc.dupe(u8, s) },
            .array_value => |arr| blk: {
                var new_array: std.ArrayList(Value) = .empty;
                try new_array.ensureTotalCapacity(alloc, arr.items.len);
                for (arr.items) |item| {
                    try new_array.append(alloc, try cloneValueWithAllocator(alloc, item));
                }
                break :blk Value{ .array_value = new_array };
            },
            .map_value => |map| blk: {
                var new_map = std.StringHashMap(Value).init(alloc);
                var iter = map.iterator();
                while (iter.next()) |entry| {
                    const k = try alloc.dupe(u8, entry.key_ptr.*);
                    const v = try cloneValueWithAllocator(alloc, entry.value_ptr.*);
                    try new_map.put(k, v);
                }
                break :blk Value{ .map_value = new_map };
            },
        };
    }

    /// Free a value that was allocated with a specific allocator
    fn freeValueWithAllocator(alloc: std.mem.Allocator, value: Value) void {
        switch (value) {
            .string_value => |s| alloc.free(s),
            .array_value => |arr| {
                for (arr.items) |item| {
                    freeValueWithAllocator(alloc, item);
                }
                var mutable_arr = arr;
                mutable_arr.deinit(alloc);
            },
            .map_value => |map| {
                var iter = map.iterator();
                while (iter.next()) |entry| {
                    alloc.free(entry.key_ptr.*);
                    freeValueWithAllocator(alloc, entry.value_ptr.*);
                }
                var mutable_map = map;
                mutable_map.deinit();
            },
            else => {},
        }
    }

    /// Validate that all required keys are present
    pub fn validateRequired(self: *Self, required_keys: []const []const u8) FlareError!void {
        for (required_keys) |key| {
            if (self.getValue(key) == null) {
                return FlareError.MissingKey;
            }
        }
    }

    /// Check if a key exists in the configuration
    pub fn hasKey(self: *Self, key: []const u8) bool {
        return self.getValue(key) != null;
    }

    /// Get number of configuration values loaded
    pub fn getCount(self: *Self) usize {
        return self.data.count() + self.defaults.count();
    }

    /// Validate configuration against schema (if present)
    pub fn validateSchema(self: *Self) !ValidationResult {
        if (self.schema_def) |schema_def| {
            return validateConfig(self.allocator, self, schema_def);
        } else {
            // No schema defined, return empty result
            return ValidationResult.init(self.allocator);
        }
    }

    /// Set schema for this configuration
    pub fn setSchema(self: *Self, schema_def: *const Schema) void {
        self.schema_def = schema_def;
    }

    /// Enable hot reload for configuration files
    /// This initializes file watching for all loaded config files
    pub fn enableHotReload(self: *Self, callback: ?ChangeCallback) !void {
        if (self.load_options == null) {
            return FlareError.WatcherNotInitialized;
        }

        self.change_callback = callback;
        self.watched_files = .empty;

        // Initialize watchers for all config files
        if (self.load_options.?.files) |files| {
            for (files) |file_source| {
                const stat = std.Io.Dir.cwd().statFile(std.Options.debug_io, file_source.path, .{}) catch continue;
                const watcher = FileWatcher{
                    .path = try self.allocator.dupe(u8, file_source.path),
                    .last_modified = @as(i128, stat.mtime.nanoseconds),
                };
                try self.watched_files.?.append(self.allocator, watcher);
            }
        }
    }

    /// Check if any watched files have changed and reload if necessary.
    /// Returns true only if a reload actually happened.
    ///
    /// This is deliberately an explicit polling API: Flare spawns no background
    /// thread or OS file-watch handle, so the caller decides when to poll (event
    /// loop tick, timer, SIGHUP handler, ...). Detected changes are debounced by
    /// `reload_debounce_ns` and watcher timestamps are advanced only after a
    /// successful reload, so a failed reload (see `reload`) is retried on the
    /// next poll while the last-known-good config stays in effect.
    pub fn checkAndReload(self: *Self) !bool {
        if (self.watched_files == null or self.load_options == null) {
            return false;
        }

        var changed = false;
        var newest_mtime: i128 = 0;
        for (self.watched_files.?.items) |*watcher| {
            const stat = std.Io.Dir.cwd().statFile(std.Options.debug_io, watcher.path, .{}) catch continue;
            const mtime_ns = @as(i128, stat.mtime.nanoseconds);
            if (mtime_ns > watcher.last_modified) {
                changed = true;
                if (mtime_ns > newest_mtime) newest_mtime = mtime_ns;
            }
        }

        if (!changed) {
            return false;
        }

        // Debounce: wait for the file to stop changing. If the newest write is
        // still within the quiescence window, defer to a later poll so a burst
        // of rapid writes collapses into one reload.
        if (self.reload_debounce_ns > 0) {
            // Wall-clock now, same domain as the file mtimes we compare against.
            const now = @as(i128, std.Io.Timestamp.now(std.Options.debug_io, .real).nanoseconds);
            if (now - newest_mtime < self.reload_debounce_ns) {
                return false;
            }
        }

        // Reload; on failure the previous good state is preserved and the error
        // propagates without advancing watcher timestamps (so we retry later).
        try self.reload();

        // Commit new timestamps only after a successful reload.
        for (self.watched_files.?.items) |*watcher| {
            const stat = std.Io.Dir.cwd().statFile(std.Options.debug_io, watcher.path, .{}) catch continue;
            watcher.last_modified = @as(i128, stat.mtime.nanoseconds);
        }

        if (self.change_callback) |callback| {
            callback(self);
        }

        return true;
    }

    /// Reload configuration from the original load options.
    ///
    /// Last-known-good semantics: the new configuration is built in a separate
    /// staging arena and only swapped in once every required source has loaded
    /// successfully. If a required file is missing/invalid (or any loader
    /// errors), the staging arena is discarded, the previous good state is left
    /// completely untouched, `last_reload_error` records the failure, and the
    /// error is returned. This prevents a bad edit from wiping a running
    /// service's config. On success the old arena is freed (bounding memory
    /// growth across reloads) and the generation counter is bumped.
    pub fn reload(self: *Self) !void {
        if (self.load_options == null) {
            return FlareError.WatcherNotInitialized;
        }
        const options = self.load_options.?;

        // Build the next state in a fresh, independent arena so a failure can be
        // rolled back by simply throwing the staging arena away.
        const staging_arena = try self.allocator.create(std.heap.ArenaAllocator);
        staging_arena.* = std.heap.ArenaAllocator.init(self.allocator);
        const staging_alloc = staging_arena.allocator();

        // On any failure below, tear down the staging arena and leave `self`
        // exactly as it was. Success paths clear this guard via `committed`.
        var committed = false;
        errdefer {
            if (!committed) {
                staging_arena.deinit();
                self.allocator.destroy(staging_arena);
            }
        }

        var staged = Self{
            .allocator = self.allocator,
            .arena = staging_arena,
            .data = std.StringHashMap(Value).init(staging_alloc),
            .defaults = std.StringHashMap(Value).init(staging_alloc),
            .origins = std.StringHashMap(ValueOrigin).init(staging_alloc),
            .generation = self.generation + 1,
            .schema_def = self.schema_def,
            .load_options = self.load_options,
            .strict = self.strict,
        };

        // Carry defaults forward (they are not sourced from files).
        var defaults_iter = self.defaults.iterator();
        while (defaults_iter.next()) |entry| {
            const key = try staging_alloc.dupe(u8, entry.key_ptr.*);
            const value = try cloneValueWithAllocator(staging_alloc, entry.value_ptr.*);
            try staged.defaults.put(key, value);
        }

        // Reload from files (lowest precedence). A failing required file aborts
        // the whole reload; optional files are skipped as before.
        if (options.files) |files| {
            for (files) |file_source| {
                loadFile(&staged, file_source) catch |err| {
                    if (file_source.required) {
                        self.last_reload_error = err;
                        return err;
                    }
                };
            }
        }

        if (options.env) |env_source| {
            loadEnv(&staged, env_source) catch |err| {
                self.last_reload_error = err;
                return err;
            };
        }

        if (options.cli) |cli_source| {
            loadCli(&staged, cli_source) catch |err| {
                self.last_reload_error = err;
                return err;
            };
        }

        // Commit: swap the staged state in and free the old arena.
        committed = true;
        const old_arena = self.arena;
        self.arena = staged.arena;
        self.data = staged.data;
        self.defaults = staged.defaults;
        self.origins = staged.origins;
        self.conflicts = staged.conflicts;
        self.generation = staged.generation;
        self.last_reload_error = null;
        old_arena.deinit();
        self.allocator.destroy(old_arena);
    }

    /// Nanosecond quiescence window a watched file must be stable for before
    /// `checkAndReload` acts on a detected change. Coalesces rapid successive
    /// writes into a single reload. 0 disables debouncing (immediate reload).
    pub fn setReloadDebounce(self: *Self, ns: i128) void {
        self.reload_debounce_ns = ns;
    }

    /// Diagnostic accessor: the error from the last failed reload attempt, or
    /// null if the most recent reload/load succeeded. On failure the previous
    /// good configuration remains in effect.
    pub fn lastReloadError(self: *const Self) ?FlareError {
        return self.last_reload_error;
    }

    /// Enable or disable strict mode (cross-source type-change detection).
    /// Only affects values set after the call.
    pub fn setStrict(self: *Self, strict: bool) void {
        self.strict = strict;
    }

    /// Whether any cross-source value-type conflicts were recorded in strict mode.
    pub fn hasConflicts(self: *const Self) bool {
        return self.conflicts.items.len > 0;
    }

    /// The strict-mode conflict log (empty unless strict mode is enabled).
    pub fn getConflicts(self: *const Self) []const ValueConflict {
        return self.conflicts.items;
    }
};

/// Load configuration from multiple sources
pub const LoadOptions = struct {
    files: ?[]const FileSource = null,
    env: ?EnvSource = null,
    cli: ?CliSource = null,
    /// Enable strict mode: record cross-source value-type changes in the
    /// config's conflict log (see `getConflicts`). Off by default.
    strict: bool = false,
};

pub const FileFormat = enum {
    json,
    toml,
    auto, // Auto-detect from extension
};

pub const FileSource = struct {
    path: []const u8,
    required: bool = true,
    format: FileFormat = .auto,
};

pub const EnvSource = struct {
    prefix: []const u8,
    separator: []const u8 = "_",
    /// Optional pre-created environment map. If not provided, environment
    /// loading will be skipped. In Zig 0.16+, pass your main function's
    /// environ_map here.
    env_map: ?*const std.process.Environ.Map = null,
};

pub const CliSource = struct {
    args: [][]const u8,
};

/// Main entry point to load configuration
pub fn load(allocator: std.mem.Allocator, options: LoadOptions) FlareError!Config {
    var config = Config.init(allocator) catch return FlareError.OutOfMemory;
    // A required-file parse failure (or any loader error) must not leak the
    // partially-built config's arena; tear it down on the error path.
    errdefer config.deinit();

    // Store load options for hot reload capability
    config.load_options = options;
    config.strict = options.strict;

    // Load from files first (lowest precedence)
    if (options.files) |files| {
        for (files) |file_source| {
            loadFile(&config, file_source) catch |err| {
                if (file_source.required) {
                    return err;
                }
                // If file is optional and fails to load, continue
            };
        }
    }

    // Load from environment variables (higher precedence)
    if (options.env) |env_source| {
        try loadEnv(&config, env_source);
    }

    // Load from CLI args (highest precedence)
    if (options.cli) |cli_source| {
        try loadCli(&config, cli_source);
    }

    return config;
}

/// Load configuration from a file (JSON or TOML)
fn loadFile(config: *Config, file_source: FileSource) FlareError!void {
    const arena_allocator = config.getArenaAllocator();
    const contents = std.Io.Dir.cwd().readFileAlloc(std.Options.debug_io, file_source.path, arena_allocator, .limited(10 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return FlareError.Io,
        else => return FlareError.Io,
    };

    // Determine file format
    const format = determineFileFormat(file_source.path, file_source.format);

    const origin = ValueOrigin{ .kind = .file, .detail = file_source.path };

    switch (format) {
        .json => {
            // Parse JSON using arena allocator
            const parsed = std.json.parseFromSlice(std.json.Value, arena_allocator, contents, .{}) catch return FlareError.ParseError;
            defer parsed.deinit();

            // Convert JSON to config values
            try loadJsonObject(config, "", parsed.value, origin);
        },
        .toml => {
            // Use new TOML 1.0 parser
            try loadTomlContent(config, contents, origin);
        },
        .auto => {
            // This should not happen after determineFileFormat
            return FlareError.ParseError;
        },
    }
}

/// Load TOML content using the new TOML 1.0 parser
fn loadTomlContent(config: *Config, contents: []const u8, origin: ValueOrigin) FlareError!void {
    const arena_allocator = config.getArenaAllocator();

    // Parse using new TOML 1.0 parser
    const toml_table = toml_parser.parseToml(arena_allocator, contents) catch {
        return FlareError.ParseError;
    };
    defer {
        toml_table.deinit();
        arena_allocator.destroy(toml_table);
    }

    // Convert TomlTable to flattened Config entries
    try loadTomlTable(config, toml_table, "", origin);
}

/// Recursively convert TomlTable entries into Config with flattened keys
/// Stores BOTH flattened keys AND nested map_value objects for getMap()/schema validation
fn loadTomlTable(config: *Config, table: *const toml_value.TomlTable, prefix: []const u8, origin: ValueOrigin) FlareError!void {
    const arena_allocator = config.getArenaAllocator();
    var it = table.map.iterator();

    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        const val = entry.value_ptr.*;

        // Build full key path with underscore separator (matches JSON flattening)
        const full_key = if (prefix.len == 0)
            key
        else
            std.fmt.allocPrint(arena_allocator, "{s}_{s}", .{ prefix, key }) catch return FlareError.OutOfMemory;

        switch (val) {
            .table => |nested| {
                // Recurse into nested tables for flattened keys
                try loadTomlTable(config, nested, full_key, origin);

                // Also store the nested table as a map_value (for getMap() and schema validation)
                const converted = toml_value.tomlValueToFlareValue(arena_allocator, val) catch return FlareError.OutOfMemory;
                try config.setValueWithOrigin(full_key, converted, origin);
            },
            .array => |arr| {
                // Check if array of tables
                if (arr.items.items.len > 0 and arr.items.items[0] == .table) {
                    // Array of tables - store as array of maps
                    var array_list: std.ArrayList(Value) = .empty;
                    array_list.ensureTotalCapacity(arena_allocator, arr.items.items.len) catch return FlareError.OutOfMemory;
                    for (arr.items.items) |item| {
                        const converted = toml_value.tomlValueToFlareValue(arena_allocator, item) catch return FlareError.OutOfMemory;
                        array_list.append(arena_allocator, converted) catch return FlareError.OutOfMemory;
                    }
                    try config.setValueWithOrigin(full_key, Value{ .array_value = array_list }, origin);
                } else {
                    // Regular array - convert directly
                    const converted = toml_value.tomlValueToFlareValue(arena_allocator, val) catch return FlareError.OutOfMemory;
                    try config.setValueWithOrigin(full_key, converted, origin);
                }
            },
            else => {
                // Primitive values (string, integer, float, boolean, datetime, etc.)
                const converted = toml_value.tomlValueToFlareValue(arena_allocator, val) catch return FlareError.OutOfMemory;
                try config.setValueWithOrigin(full_key, converted, origin);
            },
        }
    }
}

/// Convert JSON value to flare Value
/// Convert std.json.Value to flare.Value recursively (standalone version)
/// Used by both file loading and CLI parsing
fn jsonValueToValue(allocator: std.mem.Allocator, json_value: std.json.Value) FlareError!Value {
    return switch (json_value) {
        .string => |s| Value{ .string_value = try allocator.dupe(u8, s) },
        .integer => |i| Value{ .int_value = i },
        .float => |f| Value{ .float_value = f },
        .bool => |b| Value{ .bool_value = b },
        .null => Value.null_value,
        .number_string => |s| blk: {
            if (std.fmt.parseInt(i64, s, 10)) |i| {
                break :blk Value{ .int_value = i };
            } else |_| {
                if (std.fmt.parseFloat(f64, s)) |f| {
                    break :blk Value{ .float_value = f };
                } else |_| {
                    break :blk Value{ .string_value = try allocator.dupe(u8, s) };
                }
            }
        },
        .array => |arr| blk: {
            var array_list: std.ArrayList(Value) = .empty;
            try array_list.ensureTotalCapacity(allocator, arr.items.len);
            for (arr.items) |item| {
                const element_value = try jsonValueToValue(allocator, item);
                try array_list.append(allocator, element_value);
            }
            break :blk Value{ .array_value = array_list };
        },
        .object => |obj| blk: {
            var map = std.StringHashMap(Value).init(allocator);
            for (obj.keys(), obj.values()) |key, value| {
                const owned_key = try allocator.dupe(u8, key);
                const owned_value = try jsonValueToValue(allocator, value);
                try map.put(owned_key, owned_value);
            }
            break :blk Value{ .map_value = map };
        },
    };
}

/// Convert std.json.Value to flare.Value using config's arena allocator
fn jsonToValue(config: *Config, json_value: std.json.Value) FlareError!Value {
    return jsonValueToValue(config.getArenaAllocator(), json_value);
}

/// Recursively load JSON object into config
/// Stores BOTH flattened keys (e.g., "database_host") AND nested map_value objects
/// This enables both dot notation access AND getMap()/schema validation
fn loadJsonObject(config: *Config, prefix: []const u8, json_value: std.json.Value, origin: ValueOrigin) FlareError!void {
    switch (json_value) {
        .object => |obj| {
            const arena_allocator = config.getArenaAllocator();

            // Process children with flattened keys
            for (obj.keys(), obj.values()) |key, value| {
                const full_key = if (prefix.len == 0)
                    key
                else
                    try std.fmt.allocPrint(arena_allocator, "{s}_{s}", .{ prefix, key });

                try loadJsonObject(config, full_key, value, origin);
            }

            // Also store the object itself as a nested map_value (for getMap() and schema validation)
            if (prefix.len > 0) {
                const nested_map = try jsonToValue(config, json_value);
                try config.setValueWithOrigin(prefix, nested_map, origin);
            }
        },
        .string => |s| {
            try config.setValueWithOrigin(prefix, Value{ .string_value = s }, origin);
        },
        .integer => |i| {
            try config.setValueWithOrigin(prefix, Value{ .int_value = i }, origin);
        },
        .float => |f| {
            try config.setValueWithOrigin(prefix, Value{ .float_value = f }, origin);
        },
        .number_string => |s| {
            // Try to parse as integer first, then float, otherwise keep as string
            if (std.fmt.parseInt(i64, s, 10)) |i| {
                try config.setValueWithOrigin(prefix, Value{ .int_value = i }, origin);
            } else |_| {
                if (std.fmt.parseFloat(f64, s)) |f| {
                    try config.setValueWithOrigin(prefix, Value{ .float_value = f }, origin);
                } else |_| {
                    try config.setValueWithOrigin(prefix, Value{ .string_value = s }, origin);
                }
            }
        },
        .bool => |b| {
            try config.setValueWithOrigin(prefix, Value{ .bool_value = b }, origin);
        },
        .null => {
            try config.setValueWithOrigin(prefix, Value.null_value, origin);
        },
        .array => |arr| {
            const arena_allocator = config.getArenaAllocator();
            var array_list: std.ArrayList(Value) = .empty;
            try array_list.ensureTotalCapacity(arena_allocator, arr.items.len);
            for (arr.items) |item| {
                const element_value = try jsonToValue(config, item);
                try array_list.append(arena_allocator, element_value);
            }
            try config.setValueWithOrigin(prefix, Value{ .array_value = array_list }, origin);
        },
    }
}

/// Load configuration from environment variables
fn loadEnv(config: *Config, env_source: EnvSource) FlareError!void {
    const arena_allocator = config.getArenaAllocator();

    // Get environment map - must be provided by caller in Zig 0.16+
    const env_map = env_source.env_map orelse return; // Skip if no env_map provided

    var env_iter = env_map.iterator();
    while (env_iter.next()) |entry| {
        const env_key = entry.key_ptr.*;
        const env_value = entry.value_ptr.*;

        // Check if key starts with our prefix
        if (!std.mem.startsWith(u8, env_key, env_source.prefix)) {
            continue;
        }

        // Skip the prefix and separator
        const prefix_len = env_source.prefix.len;
        if (env_key.len <= prefix_len) {
            continue;
        }

        // Extract the key part after prefix
        const key_part = env_key[prefix_len..];

        // Skip if it doesn't start with separator
        if (!std.mem.startsWith(u8, key_part, env_source.separator)) {
            continue;
        }

        // Get the actual config key (after separator)
        const separator_len = env_source.separator.len;
        if (key_part.len <= separator_len) {
            continue;
        }

        const config_key_raw = key_part[separator_len..];

        // Convert separator-delimited to dot notation
        // e.g., "DB__HOST" -> "db.host"
        const config_key = try convertEnvKeyToConfigKey(arena_allocator, config_key_raw, env_source.separator);

        // Try to parse the value into appropriate type
        const value = try parseEnvValue(arena_allocator, env_value);

        try config.setValueWithOrigin(config_key, value, .{ .kind = .env, .detail = env_key });
    }
}

/// Convert environment key format to config key format
/// e.g., "DB__HOST" with separator "__" -> "db.host"
fn convertEnvKeyToConfigKey(allocator: std.mem.Allocator, env_key: []const u8, separator: []const u8) ![]const u8 {
    // Allocate buffer for the result
    const result = try allocator.alloc(u8, env_key.len);

    var write_pos: usize = 0;
    var read_pos: usize = 0;

    while (read_pos < env_key.len) {
        if (read_pos + separator.len <= env_key.len and
            std.mem.eql(u8, env_key[read_pos .. read_pos + separator.len], separator))
        {
            // Replace separator with dot
            result[write_pos] = '.';
            write_pos += 1;
            read_pos += separator.len;
        } else {
            // Convert to lowercase and copy
            result[write_pos] = std.ascii.toLower(env_key[read_pos]);
            write_pos += 1;
            read_pos += 1;
        }
    }

    return result[0..write_pos];
}

/// Determine file format from path and explicit format setting
fn determineFileFormat(path: []const u8, explicit_format: FileFormat) FileFormat {
    if (explicit_format != .auto) {
        return explicit_format;
    }

    // Auto-detect from file extension
    if (std.mem.endsWith(u8, path, ".json")) {
        return .json;
    } else if (std.mem.endsWith(u8, path, ".toml")) {
        return .toml;
    }

    // Default to JSON for unknown extensions
    return .json;
}

/// Load configuration from CLI arguments
fn loadCli(config: *Config, cli_source: CliSource) FlareError!void {
    const arena_allocator = config.getArenaAllocator();

    // Parse CLI args in format: --key=value or --key value
    var i: usize = 0;
    while (i < cli_source.args.len) {
        const arg = cli_source.args[i];

        // Check if it starts with -- or -
        if (std.mem.startsWith(u8, arg, "--")) {
            const key_value = arg[2..]; // Skip --

            // Check if it contains =
            if (std.mem.indexOf(u8, key_value, "=")) |eq_pos| {
                // Format: --key=value
                const key = key_value[0..eq_pos];
                const value_str = key_value[eq_pos + 1 ..];

                // Convert key to config path (replace - with .)
                const config_key = try convertCliKeyToConfigKey(arena_allocator, key);
                const value = try parseCliValue(arena_allocator, value_str);
                try config.setValueWithOrigin(config_key, value, .{ .kind = .cli, .detail = arg });
            } else {
                // Format: --key value (next arg is the value)
                if (i + 1 < cli_source.args.len) {
                    const key = key_value;
                    const value_str = cli_source.args[i + 1];

                    // Convert key to config path
                    const config_key = try convertCliKeyToConfigKey(arena_allocator, key);
                    const value = try parseCliValue(arena_allocator, value_str);
                    try config.setValueWithOrigin(config_key, value, .{ .kind = .cli, .detail = arg });

                    i += 1; // Skip the value arg
                } else {
                    // Boolean flag without value, treat as true
                    const config_key = try convertCliKeyToConfigKey(arena_allocator, key_value);
                    try config.setValueWithOrigin(config_key, Value{ .bool_value = true }, .{ .kind = .cli, .detail = arg });
                }
            }
        } else if (std.mem.startsWith(u8, arg, "-")) {
            // Short flag format: -d or -p 8080
            const flag = arg[1..]; // Skip -

            if (i + 1 < cli_source.args.len and !std.mem.startsWith(u8, cli_source.args[i + 1], "-")) {
                // Has a value
                const value_str = cli_source.args[i + 1];
                const value = try parseCliValue(arena_allocator, value_str);
                try config.setValueWithOrigin(flag, value, .{ .kind = .cli, .detail = arg });
                i += 1; // Skip the value
            } else {
                // Boolean flag
                try config.setValueWithOrigin(flag, Value{ .bool_value = true }, .{ .kind = .cli, .detail = arg });
            }
        }

        i += 1;
    }
}

/// Convert CLI key format to config key format
/// e.g., "database-host" -> "database.host"
fn convertCliKeyToConfigKey(allocator: std.mem.Allocator, cli_key: []const u8) ![]const u8 {
    const result = try allocator.alloc(u8, cli_key.len);

    for (cli_key, 0..) |c, i| {
        result[i] = if (c == '-') '.' else c;
    }

    return result;
}

/// Parse CLI argument value into appropriate Value type
/// Parse CLI argument value into appropriate Value type
/// Handles booleans, integers, floats, JSON arrays/objects, and strings
pub fn parseCliValue(allocator: std.mem.Allocator, cli_value: []const u8) !Value {
    // Try parsing as boolean first
    if (std.mem.eql(u8, cli_value, "true") or std.mem.eql(u8, cli_value, "TRUE")) {
        return Value{ .bool_value = true };
    }
    if (std.mem.eql(u8, cli_value, "false") or std.mem.eql(u8, cli_value, "FALSE")) {
        return Value{ .bool_value = false };
    }

    // Try parsing as integer
    if (std.fmt.parseInt(i64, cli_value, 10)) |int_val| {
        return Value{ .int_value = int_val };
    } else |_| {}

    // Try parsing as float
    if (std.fmt.parseFloat(f64, cli_value)) |float_val| {
        return Value{ .float_value = float_val };
    } else |_| {}

    // Try parsing as JSON array or object
    if ((std.mem.startsWith(u8, cli_value, "[") and std.mem.endsWith(u8, cli_value, "]")) or
        (std.mem.startsWith(u8, cli_value, "{") and std.mem.endsWith(u8, cli_value, "}")))
    {
        // Attempt to parse as JSON
        const parsed = std.json.parseFromSlice(std.json.Value, allocator, cli_value, .{}) catch {
            // If JSON parsing fails, treat as string
            const owned_string = try allocator.dupe(u8, cli_value);
            return Value{ .string_value = owned_string };
        };
        defer parsed.deinit();

        // Convert JSON value to flare Value recursively (preserves nested structures)
        return jsonValueToValue(allocator, parsed.value);
    }

    // Default to string
    const owned_string = try allocator.dupe(u8, cli_value);
    return Value{ .string_value = owned_string };
}

/// Parse environment variable value into appropriate Value type
fn parseEnvValue(allocator: std.mem.Allocator, env_value: []const u8) !Value {
    // Try parsing as boolean first
    if (std.mem.eql(u8, env_value, "true") or std.mem.eql(u8, env_value, "TRUE")) {
        return Value{ .bool_value = true };
    }
    if (std.mem.eql(u8, env_value, "false") or std.mem.eql(u8, env_value, "FALSE")) {
        return Value{ .bool_value = false };
    }

    // Try parsing as integer
    if (std.fmt.parseInt(i64, env_value, 10)) |int_val| {
        return Value{ .int_value = int_val };
    } else |_| {}

    // Try parsing as float
    if (std.fmt.parseFloat(f64, env_value)) |float_val| {
        return Value{ .float_value = float_val };
    } else |_| {}

    // Default to string
    const owned_string = try allocator.dupe(u8, env_value);
    return Value{ .string_value = owned_string };
}

test "config initialization" {
    var config = try Config.init(std.testing.allocator);
    defer config.deinit();

    // Test setting and getting defaults
    try config.setDefault("debug", Value{ .bool_value = false });
    try config.setDefault("port", Value{ .int_value = 8080 });
    try config.setDefault("host", Value{ .string_value = "localhost" });

    const debug = try config.getBool("debug", null);
    const port = try config.getInt("port", null);
    const host = try config.getString("host", null);

    try std.testing.expect(debug == false);
    try std.testing.expect(port == 8080);
    try std.testing.expect(std.mem.eql(u8, host, "localhost"));
}

test "type coercion" {
    var config = try Config.init(std.testing.allocator);
    defer config.deinit();

    // Test string to bool coercion
    try config.setDefault("flag1", Value{ .string_value = "true" });
    try config.setDefault("flag2", Value{ .string_value = "1" });
    try config.setDefault("flag3", Value{ .string_value = "false" });

    try std.testing.expect(try config.getBool("flag1", null) == true);
    try std.testing.expect(try config.getBool("flag2", null) == true);
    try std.testing.expect(try config.getBool("flag3", null) == false);

    // Test int to float coercion
    try config.setDefault("number", Value{ .int_value = 42 });
    const float_val = try config.getFloat("number", null);
    try std.testing.expect(float_val == 42.0);
}

test "path addressing" {
    var config = try Config.init(std.testing.allocator);
    defer config.deinit();

    // Set some nested-style keys (flattened with underscores)
    try config.setDefault("db_host", Value{ .string_value = "localhost" });
    try config.setDefault("db_port", Value{ .int_value = 5432 });
    try config.setValue("http_timeout", Value{ .int_value = 30 });

    // Test accessing with dotted notation
    const host = try config.getString("db.host", null);
    const port = try config.getInt("db.port", null);
    const timeout = try config.getInt("http.timeout", null);

    try std.testing.expect(std.mem.eql(u8, host, "localhost"));
    try std.testing.expect(port == 5432);
    try std.testing.expect(timeout == 30);
}

test "JSON file loading" {
    var config = try load(std.testing.allocator, LoadOptions{
        .files = &[_]FileSource{
            FileSource{ .path = "test_config.json" },
        },
    });
    defer config.deinit();

    // Test that JSON values are loaded correctly
    const db_host = try config.getString("database.host", null);
    const db_port = try config.getInt("database.port", null);
    const db_ssl = try config.getBool("database.ssl", null);
    const server_port = try config.getInt("server.port", null);
    const timeout = try config.getFloat("server.timeout", null);
    const debug = try config.getBool("debug", null);
    const name = try config.getString("name", null);

    try std.testing.expect(std.mem.eql(u8, db_host, "localhost"));
    try std.testing.expect(db_port == 5432);
    try std.testing.expect(db_ssl == true);
    try std.testing.expect(server_port == 8080);
    try std.testing.expect(timeout == 30.5);
    try std.testing.expect(debug == false);
    try std.testing.expect(std.mem.eql(u8, name, "my-app"));
}

test "environment variable parsing" {
    var config = try Config.init(std.testing.allocator);
    defer config.deinit();

    // Test env key conversion
    const arena_allocator = config.getArenaAllocator();

    const key1 = try convertEnvKeyToConfigKey(arena_allocator, "DB__HOST", "__");
    try std.testing.expect(std.mem.eql(u8, key1, "db.host"));

    const key2 = try convertEnvKeyToConfigKey(arena_allocator, "SERVER__PORT", "__");
    try std.testing.expect(std.mem.eql(u8, key2, "server.port"));

    // Test value parsing
    const bool_val = try parseEnvValue(arena_allocator, "true");
    try std.testing.expect(bool_val == .bool_value and bool_val.bool_value == true);

    const int_val = try parseEnvValue(arena_allocator, "42");
    try std.testing.expect(int_val == .int_value and int_val.int_value == 42);

    const float_val = try parseEnvValue(arena_allocator, "3.14");
    try std.testing.expect(float_val == .float_value and float_val.float_value == 3.14);

    const string_val = try parseEnvValue(arena_allocator, "hello");
    try std.testing.expect(string_val == .string_value);
    try std.testing.expect(std.mem.eql(u8, string_val.string_value, "hello"));
}

test "validation and introspection" {
    var config = try Config.init(std.testing.allocator);
    defer config.deinit();

    // Set up some test data
    try config.setDefault("required_key", Value{ .string_value = "test" });
    try config.setValue("another_key", Value{ .int_value = 42 });

    // Test key existence
    try std.testing.expect(config.hasKey("required_key"));
    try std.testing.expect(config.hasKey("another_key"));
    try std.testing.expect(!config.hasKey("nonexistent_key"));

    // Test required validation
    const required_keys = [_][]const u8{ "required_key", "another_key" };
    try config.validateRequired(&required_keys);

    // Test missing key validation
    const missing_keys = [_][]const u8{ "required_key", "missing_key" };
    const validation_result = config.validateRequired(&missing_keys);
    try std.testing.expectError(FlareError.MissingKey, validation_result);
}

test "strict mode records cross-source type conflict" {
    var config = try Config.init(std.testing.allocator);
    defer config.deinit();
    config.setStrict(true);

    // File layer sets an int.
    try config.setValueWithOrigin("port", Value{ .int_value = 8080 }, .{ .kind = .file, .detail = "app.json" });
    try std.testing.expect(!config.hasConflicts());

    // A higher-precedence source overrides the same key with a different type.
    try config.setValueWithOrigin("port", Value{ .string_value = "high" }, .{ .kind = .cli, .detail = "--port" });
    try std.testing.expect(config.hasConflicts());

    const conflicts = config.getConflicts();
    try std.testing.expect(conflicts.len == 1);
    try std.testing.expect(std.mem.eql(u8, conflicts[0].key, "port"));
    try std.testing.expect(conflicts[0].previous_kind == .file);
    try std.testing.expect(std.mem.eql(u8, conflicts[0].previous_type, "int"));
    try std.testing.expect(conflicts[0].new_kind == .cli);
    try std.testing.expect(std.mem.eql(u8, conflicts[0].new_type, "string"));

    // A same-type override is not a conflict.
    try config.setValueWithOrigin("port", Value{ .string_value = "higher" }, .{ .kind = .set });
    try std.testing.expect(config.getConflicts().len == 1);
}

test "strict mode off by default records no conflicts" {
    var config = try Config.init(std.testing.allocator);
    defer config.deinit();

    try config.setValueWithOrigin("k", Value{ .int_value = 1 }, .{ .kind = .file });
    try config.setValueWithOrigin("k", Value{ .string_value = "x" }, .{ .kind = .cli });
    try std.testing.expect(!config.hasConflicts());
}

// Include integration tests
comptime {
    _ = @import("integration_tests.zig");
    _ = @import("origin_tests.zig");
    _ = @import("hot_reload_tests.zig");
    _ = @import("toml_value.zig");
    _ = @import("toml_lexer.zig");
    _ = @import("toml_parser.zig");
    _ = @import("deserialize.zig");
    _ = @import("serialize.zig");
    _ = @import("stringify.zig");
    _ = @import("schema_gen.zig");
    _ = @import("flash_bridge.zig");
    _ = @import("convert.zig");
    _ = @import("diff.zig");
}
