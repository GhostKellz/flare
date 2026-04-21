//! Flare - Configuration management library for Zig
//! What viper is to Cobra in Go, Flare is to Flash in Zig

const std = @import("std");

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

// Export TOML stringification
pub const stringify_mod = @import("stringify.zig");
pub const stringify = stringify_mod.stringify;
pub const stringifyWithOptions = stringify_mod.stringifyWithOptions;
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
    schema_def: ?*const Schema = null,
    watched_files: ?std.ArrayList(FileWatcher) = null,
    load_options: ?LoadOptions = null,
    change_callback: ?ChangeCallback = null,

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

    /// Set a value in the config (used by loaders)
    pub fn setValue(self: *Self, key: []const u8, value: Value) !void {
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
        try self.data.put(owned_key, owned_value);
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

    /// Check if any watched files have changed and reload if necessary
    /// Returns true if config was reloaded
    pub fn checkAndReload(self: *Self) !bool {
        if (self.watched_files == null) {
            return false;
        }

        var changed = false;
        for (self.watched_files.?.items) |*watcher| {
            const stat = std.Io.Dir.cwd().statFile(std.Options.debug_io, watcher.path, .{}) catch continue;
            const mtime_ns = @as(i128, stat.mtime.nanoseconds);

            if (mtime_ns > watcher.last_modified) {
                changed = true;
                watcher.last_modified = mtime_ns;
            }
        }

        if (changed and self.load_options != null) {
            // Reload configuration
            try self.reload();

            // Call callback if registered
            if (self.change_callback) |callback| {
                callback(self);
            }
        }

        return changed;
    }

    /// Reload configuration from original load options
    /// Resets arena to prevent unbounded memory growth while preserving defaults.
    pub fn reload(self: *Self) !void {
        if (self.load_options == null) {
            return FlareError.WatcherNotInitialized;
        }

        // Step 1: Clone defaults to parent allocator (outside arena)
        var saved_defaults = std.StringHashMap(Value).init(self.allocator);
        defer {
            // Free temporary copies after we're done
            var iter = saved_defaults.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                freeValueWithAllocator(self.allocator, entry.value_ptr.*);
            }
            saved_defaults.deinit();
        }

        var defaults_iter = self.defaults.iterator();
        while (defaults_iter.next()) |entry| {
            const key = try self.allocator.dupe(u8, entry.key_ptr.*);
            errdefer self.allocator.free(key);
            const value = try cloneValueWithAllocator(self.allocator, entry.value_ptr.*);
            try saved_defaults.put(key, value);
        }

        // Step 2: Reset arena to free all previous allocations
        _ = self.arena.reset(.free_all);

        // Step 3: Reinitialize hashmaps with fresh arena allocator
        const arena_allocator = self.arena.allocator();
        self.data = std.StringHashMap(Value).init(arena_allocator);
        self.defaults = std.StringHashMap(Value).init(arena_allocator);

        // Step 4: Restore defaults into fresh arena
        var saved_iter = saved_defaults.iterator();
        while (saved_iter.next()) |entry| {
            const arena_key = try arena_allocator.dupe(u8, entry.key_ptr.*);
            const arena_value = try cloneValueWithAllocator(arena_allocator, entry.value_ptr.*);
            try self.defaults.put(arena_key, arena_value);
        }

        const options = self.load_options.?;

        // Reload from files
        if (options.files) |files| {
            for (files) |file_source| {
                loadFile(self, file_source) catch |err| {
                    if (file_source.required) {
                        return err;
                    }
                };
            }
        }

        // Reload from environment variables
        if (options.env) |env_source| {
            try loadEnv(self, env_source);
        }

        // Reload from CLI args
        if (options.cli) |cli_source| {
            try loadCli(self, cli_source);
        }
    }
};

/// Load configuration from multiple sources
pub const LoadOptions = struct {
    files: ?[]const FileSource = null,
    env: ?EnvSource = null,
    cli: ?CliSource = null,
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

    // Store load options for hot reload capability
    config.load_options = options;

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

    switch (format) {
        .json => {
            // Parse JSON using arena allocator
            const parsed = std.json.parseFromSlice(std.json.Value, arena_allocator, contents, .{}) catch return FlareError.ParseError;
            defer parsed.deinit();

            // Convert JSON to config values
            try loadJsonObject(config, "", parsed.value);
        },
        .toml => {
            // Use new TOML 1.0 parser
            try loadTomlContent(config, contents);
        },
        .auto => {
            // This should not happen after determineFileFormat
            return FlareError.ParseError;
        },
    }
}

/// Load TOML content using the new TOML 1.0 parser
fn loadTomlContent(config: *Config, contents: []const u8) FlareError!void {
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
    try loadTomlTable(config, toml_table, "");
}

/// Recursively convert TomlTable entries into Config with flattened keys
/// Stores BOTH flattened keys AND nested map_value objects for getMap()/schema validation
fn loadTomlTable(config: *Config, table: *const toml_value.TomlTable, prefix: []const u8) FlareError!void {
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
                try loadTomlTable(config, nested, full_key);

                // Also store the nested table as a map_value (for getMap() and schema validation)
                const converted = toml_value.tomlValueToFlareValue(arena_allocator, val) catch return FlareError.OutOfMemory;
                try config.setValue(full_key, converted);
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
                    try config.setValue(full_key, Value{ .array_value = array_list });
                } else {
                    // Regular array - convert directly
                    const converted = toml_value.tomlValueToFlareValue(arena_allocator, val) catch return FlareError.OutOfMemory;
                    try config.setValue(full_key, converted);
                }
            },
            else => {
                // Primitive values (string, integer, float, boolean, datetime, etc.)
                const converted = toml_value.tomlValueToFlareValue(arena_allocator, val) catch return FlareError.OutOfMemory;
                try config.setValue(full_key, converted);
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
fn loadJsonObject(config: *Config, prefix: []const u8, json_value: std.json.Value) FlareError!void {
    switch (json_value) {
        .object => |obj| {
            const arena_allocator = config.getArenaAllocator();

            // Process children with flattened keys
            for (obj.keys(), obj.values()) |key, value| {
                const full_key = if (prefix.len == 0)
                    key
                else
                    try std.fmt.allocPrint(arena_allocator, "{s}_{s}", .{ prefix, key });

                try loadJsonObject(config, full_key, value);
            }

            // Also store the object itself as a nested map_value (for getMap() and schema validation)
            if (prefix.len > 0) {
                const nested_map = try jsonToValue(config, json_value);
                try config.setValue(prefix, nested_map);
            }
        },
        .string => |s| {
            try config.setValue(prefix, Value{ .string_value = s });
        },
        .integer => |i| {
            try config.setValue(prefix, Value{ .int_value = i });
        },
        .float => |f| {
            try config.setValue(prefix, Value{ .float_value = f });
        },
        .number_string => |s| {
            // Try to parse as integer first, then float, otherwise keep as string
            if (std.fmt.parseInt(i64, s, 10)) |i| {
                try config.setValue(prefix, Value{ .int_value = i });
            } else |_| {
                if (std.fmt.parseFloat(f64, s)) |f| {
                    try config.setValue(prefix, Value{ .float_value = f });
                } else |_| {
                    try config.setValue(prefix, Value{ .string_value = s });
                }
            }
        },
        .bool => |b| {
            try config.setValue(prefix, Value{ .bool_value = b });
        },
        .null => {
            try config.setValue(prefix, Value.null_value);
        },
        .array => |arr| {
            const arena_allocator = config.getArenaAllocator();
            var array_list: std.ArrayList(Value) = .empty;
            try array_list.ensureTotalCapacity(arena_allocator, arr.items.len);
            for (arr.items) |item| {
                const element_value = try jsonToValue(config, item);
                try array_list.append(arena_allocator, element_value);
            }
            try config.setValue(prefix, Value{ .array_value = array_list });
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

        try config.setValue(config_key, value);
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
            std.mem.eql(u8, env_key[read_pos..read_pos + separator.len], separator)) {
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
                const value_str = key_value[eq_pos + 1..];

                // Convert key to config path (replace - with .)
                const config_key = try convertCliKeyToConfigKey(arena_allocator, key);
                const value = try parseCliValue(arena_allocator, value_str);
                try config.setValue(config_key, value);
            } else {
                // Format: --key value (next arg is the value)
                if (i + 1 < cli_source.args.len) {
                    const key = key_value;
                    const value_str = cli_source.args[i + 1];

                    // Convert key to config path
                    const config_key = try convertCliKeyToConfigKey(arena_allocator, key);
                    const value = try parseCliValue(arena_allocator, value_str);
                    try config.setValue(config_key, value);

                    i += 1; // Skip the value arg
                } else {
                    // Boolean flag without value, treat as true
                    const config_key = try convertCliKeyToConfigKey(arena_allocator, key_value);
                    try config.setValue(config_key, Value{ .bool_value = true });
                }
            }
        } else if (std.mem.startsWith(u8, arg, "-")) {
            // Short flag format: -d or -p 8080
            const flag = arg[1..]; // Skip -

            if (i + 1 < cli_source.args.len and !std.mem.startsWith(u8, cli_source.args[i + 1], "-")) {
                // Has a value
                const value_str = cli_source.args[i + 1];
                const value = try parseCliValue(arena_allocator, value_str);
                try config.setValue(flag, value);
                i += 1; // Skip the value
            } else {
                // Boolean flag
                try config.setValue(flag, Value{ .bool_value = true });
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
        (std.mem.startsWith(u8, cli_value, "{") and std.mem.endsWith(u8, cli_value, "}"))) {
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

// Include integration tests
comptime {
    _ = @import("integration_tests.zig");
    _ = @import("hot_reload_tests.zig");
    _ = @import("toml_value.zig");
    _ = @import("toml_lexer.zig");
    _ = @import("toml_parser.zig");
    _ = @import("deserialize.zig");
    _ = @import("stringify.zig");
    _ = @import("schema_gen.zig");
    _ = @import("flash_bridge.zig");
    _ = @import("convert.zig");
    _ = @import("diff.zig");
}
