# API Reference

Complete reference for all Flare types, functions, and methods.

## Core Functions

### `flare.load()`

Load configuration from multiple sources.

```zig
pub fn load(allocator: std.mem.Allocator, options: LoadOptions) FlareError!Config
```

**Parameters:**
- `allocator` - Memory allocator for the configuration
- `options` - Configuration loading options

**Returns:** `Config` instance or `FlareError`

**Example:**
```zig
var config = try flare.load(allocator, .{
    .files = &[_]flare.FileSource{
        .{ .path = "config.json" },
    },
    .env = .{ .prefix = "APP", .separator = "__" },
});
defer config.deinit();
```

## Core Types

### `Config`

Main configuration container with arena-based memory management.

#### Methods

##### `deinit()`

Clean up all allocated memory.

```zig
pub fn deinit(self: *Self) void
```

**Usage:**
```zig
var config = try flare.load(allocator, options);
defer config.deinit(); // Always call this
```

##### `getString()`

Get a string value with optional default.

```zig
pub fn getString(self: *Self, key: []const u8, default_value: ?[]const u8) FlareError![]const u8
```

**Parameters:**
- `key` - Configuration key (supports dot notation)
- `default_value` - Default value if key not found (null = required)

**Returns:** String value or `FlareError`

**Example:**
```zig
const host = try config.getString("database.host", "localhost");
const required_key = try config.getString("api.key", null); // Error if missing
```

##### `getInt()`

Get an integer value with optional default.

```zig
pub fn getInt(self: *Self, key: []const u8, default_value: ?i64) FlareError!i64
```

**Parameters:**
- `key` - Configuration key
- `default_value` - Default value if key not found (null = required)

**Returns:** Integer value or `FlareError`

**Type Coercion:**
- String numbers are parsed: `"42"` → `42`
- Floats are truncated: `3.14` → `3`
- Booleans: `true` → `1`, `false` → `0`

**Example:**
```zig
const port = try config.getInt("server.port", 8080);
const workers = try config.getInt("server.workers", 4);
```

##### `getFloat()`

Get a float value with optional default.

```zig
pub fn getFloat(self: *Self, key: []const u8, default_value: ?f64) FlareError!f64
```

**Parameters:**
- `key` - Configuration key
- `default_value` - Default value if key not found (null = required)

**Returns:** Float value or `FlareError`

**Type Coercion:**
- String numbers are parsed: `"3.14"` → `3.14`
- Integers are converted: `42` → `42.0`

**Example:**
```zig
const timeout = try config.getFloat("server.timeout", 30.0);
const rate = try config.getFloat("api.rate_limit", 100.0);
```

##### `getBool()`

Get a boolean value with optional default.

```zig
pub fn getBool(self: *Self, key: []const u8, default_value: ?bool) FlareError!bool
```

**Parameters:**
- `key` - Configuration key
- `default_value` - Default value if key not found (null = required)

**Returns:** Boolean value or `FlareError`

**Type Coercion:**
- Strings: `"true"`, `"1"` → `true`; `"false"`, `"0"` → `false`
- Numbers: `0` → `false`; any other number → `true`

**Example:**
```zig
const debug = try config.getBool("debug", false);
const ssl_enabled = try config.getBool("database.ssl", true);
```

##### `setDefault()`

Set a default value for a configuration key.

```zig
pub fn setDefault(self: *Self, key: []const u8, value: Value) !void
```

**Parameters:**
- `key` - Configuration key
- `value` - Default value to set

**Example:**
```zig
try config.setDefault("server.port", flare.Value{ .int_value = 8080 });
try config.setDefault("app.name", flare.Value{ .string_value = "My App" });
try config.setDefault("debug", flare.Value{ .bool_value = false });
```

##### `setValue()`

Set a configuration value (used internally by loaders).

```zig
pub fn setValue(self: *Self, key: []const u8, value: Value) !void
```

**Parameters:**
- `key` - Configuration key
- `value` - Value to set

##### `validateRequired()`

Validate that required keys are present.

```zig
pub fn validateRequired(self: *Self, required_keys: []const []const u8) FlareError!void
```

**Parameters:**
- `required_keys` - Array of required configuration keys

**Returns:** `void` or `FlareError.MissingKey`

**Example:**
```zig
const required = [_][]const u8{
    "database.host",
    "database.port",
    "api.key"
};
try config.validateRequired(&required);
```

##### `hasKey()`

Check if a configuration key exists.

```zig
pub fn hasKey(self: *Self, key: []const u8) bool
```

**Parameters:**
- `key` - Configuration key to check

**Returns:** `true` if key exists, `false` otherwise

**Example:**
```zig
if (config.hasKey("database.password")) {
    const password = try config.getString("database.password", null);
    // Use password
}
```

##### `getCount()`

Get the total number of configuration values.

```zig
pub fn getCount(self: *Self) usize
```

**Returns:** Number of configuration values loaded

##### Schema-Related Methods

##### `initWithSchema()`

Create a Config instance with schema validation.

```zig
pub fn initWithSchema(allocator: std.mem.Allocator, schema_def: *const Schema) !Config
```

**Parameters:**
- `allocator` - Memory allocator
- `schema_def` - Schema definition for validation

**Returns:** Schema-aware Config instance

**Example:**
```zig
var config = try flare.Config.initWithSchema(allocator, &my_schema);
defer config.deinit();
```

##### `validateSchema()`

Validate configuration against schema (if present).

```zig
pub fn validateSchema(self: *Config) !ValidationResult
```

**Returns:** ValidationResult with errors/warnings

**Example:**
```zig
var result = try config.validateSchema();
defer result.deinit(allocator);

if (result.hasErrors()) {
    for (result.errors.items) |error_item| {
        std.debug.print("Error: {s}\n", .{error_item.message});
    }
}
```

##### `setSchema()`

Set or update the schema for this configuration.

```zig
pub fn setSchema(self: *Config, schema_def: *const Schema) void
```

**Parameters:**
- `schema_def` - Schema definition to set

### `Value`

Union type representing configuration values.

```zig
pub const Value = union(enum) {
    null_value,
    bool_value: bool,
    int_value: i64,
    float_value: f64,
    string_value: []const u8,
};
```

**Variants:**
- `null_value` - Null/undefined value
- `bool_value: bool` - Boolean value
- `int_value: i64` - Integer value
- `float_value: f64` - Floating-point value
- `string_value: []const u8` - String value

## Schema System

### `Schema`

Declarative configuration structure definition with validation.

```zig
pub const Schema = struct {
    schema_type: SchemaType,
    is_required: bool = false,
    default_value: ?Value = null,
    description: ?[]const u8 = null,
    // Type-specific constraints...
}
```

#### Schema Creation Methods

##### `Schema.string()`

Create a string schema with optional constraints.

```zig
pub fn string(constraints: StringConstraints) Schema
```

**Example:**
```zig
const name_schema = flare.Schema.string(.{
    .min_length = 1,
    .max_length = 100,
});
```

##### `Schema.int()`

Create an integer schema with optional constraints.

```zig
pub fn int(constraints: IntConstraints) Schema
```

**Example:**
```zig
const port_schema = flare.Schema.int(.{
    .min = 1,
    .max = 65535,
});
```

##### `Schema.boolean()`

Create a boolean schema.

```zig
pub fn boolean() Schema
```

**Example:**
```zig
const debug_schema = flare.Schema.boolean();
```

##### `Schema.float()`

Create a float schema with optional constraints.

```zig
pub fn float(constraints: FloatConstraints) Schema
```

**Example:**
```zig
const timeout_schema = flare.Schema.float(.{
    .min = 0.1,
    .max = 300.0,
});
```

##### `Schema.object()`

Create an object schema with field definitions.

```zig
pub fn object(allocator: std.mem.Allocator, field_definitions: anytype) !Schema
```

**Example:**
```zig
const db_schema = try flare.Schema.object(allocator, .{
    .host = flare.Schema.string(.{}).required(),
    .port = flare.Schema.int(.{ .min = 1, .max = 65535 }),
});
```

##### `Schema.root()`

Create a root schema (same as object, semantically clearer).

```zig
pub fn root(allocator: std.mem.Allocator, field_definitions: anytype) !Schema
```

#### Method Chaining

##### `required()`

Mark the field as required.

```zig
pub fn required(self: Schema) Schema
```

**Example:**
```zig
const required_field = flare.Schema.string(.{}).required();
```

##### `default()`

Set a default value for the field.

```zig
pub fn default(self: Schema, value: Value) Schema
```

**Example:**
```zig
const port_with_default = flare.Schema.int(.{})
    .default(flare.Value{ .int_value = 8080 });
```

##### `withDescription()`

Add a description to the field.

```zig
pub fn withDescription(self: Schema, desc: []const u8) Schema
```

### Constraint Types

#### `StringConstraints`

```zig
pub const StringConstraints = struct {
    min_length: ?usize = null,
    max_length: ?usize = null,
    pattern: ?[]const u8 = null, // Future: regex
};
```

#### `IntConstraints`

```zig
pub const IntConstraints = struct {
    min: ?i64 = null,
    max: ?i64 = null,
};
```

#### `FloatConstraints`

```zig
pub const FloatConstraints = struct {
    min: ?f64 = null,
    max: ?f64 = null,
};
```

### `ValidationResult`

Container for validation results.

```zig
pub const ValidationResult = struct {
    errors: std.ArrayList(ValidationError),
    warnings: std.ArrayList(ValidationWarning),
}
```

#### Methods

##### `hasErrors()`

Check if validation found any errors.

```zig
pub fn hasErrors(self: *const ValidationResult) bool
```

##### `deinit()`

Clean up validation result resources.

```zig
pub fn deinit(self: *ValidationResult, allocator: std.mem.Allocator) void
```

### `ValidationError`

Individual validation error.

```zig
pub const ValidationError = struct {
    path: []const u8,
    message: []const u8,
    error_type: SchemaError,
};
```

### `SchemaError`

Schema validation specific errors.

```zig
pub const SchemaError = error{
    MissingRequiredField,
    TypeMismatch,
    ValueOutOfRange,
    InvalidFormat,
    ValidationFailed,
};
```

### `LoadOptions`

Configuration loading options.

```zig
pub const LoadOptions = struct {
    files: ?[]const FileSource = null,
    env: ?EnvSource = null,
    cli: ?CliSource = null,  // Future: CLI argument support
};
```

**Fields:**
- `files` - Array of file sources to load
- `env` - Environment variable configuration
- `cli` - CLI argument configuration (not implemented)

### `FileSource`

File source configuration.

```zig
pub const FileSource = struct {
    path: []const u8,
    required: bool = true,
    format: FileFormat = .auto,
};
```

**Fields:**
- `path` - Path to the configuration file
- `required` - Whether the file must exist (default: true)
- `format` - File format (auto-detected by default)

### `FileFormat`

Supported configuration file formats.

```zig
pub const FileFormat = enum {
    json,
    toml,
    auto, // Auto-detect from extension
};
```

**Formats:**
- `json` - JSON format
- `toml` - TOML format
- `auto` - Auto-detect from file extension (.json, .toml)

### `EnvSource`

Environment variable source configuration.

```zig
pub const EnvSource = struct {
    prefix: []const u8,
    separator: []const u8 = "_",
};
```

**Fields:**
- `prefix` - Required prefix for environment variables
- `separator` - Separator for nested keys (default: "_")

### `FlareError`

Error types returned by Flare operations.

```zig
pub const FlareError = error{
    ParseError,      // Failed to parse configuration file
    MissingKey,      // Required key not found
    TypeMismatch,    // Value exists but wrong type
    Io,             // File I/O error
    Validation,     // Configuration validation error
    OutOfMemory,    // Memory allocation error
    InvalidPath,    // Invalid configuration path
    InvalidArrayIndex, // Invalid array index (future)
};
```

## Path Addressing

Flare supports dotted key notation for accessing nested configuration:

### JSON Structure
```json
{
  "database": {
    "primary": {
      "host": "localhost",
      "port": 5432
    }
  }
}
```

### Access Patterns
```zig
// Access nested values with dot notation
const host = try config.getString("database.primary.host", "localhost");
const port = try config.getInt("database.primary.port", 5432);

// Environment variable equivalent:
// APP__DATABASE__PRIMARY__HOST=localhost
// APP__DATABASE__PRIMARY__PORT=5432
```

### Key Flattening

Internally, nested keys are flattened with underscores:
- `database.primary.host` → `database_primary_host`
- `server.ssl.enabled` → `server_ssl_enabled`

## Type Coercion Rules

Flare automatically converts between compatible types:

### String → Number
- `"42"` → `42` (int)
- `"3.14"` → `3.14` (float)
- `"invalid"` → `TypeMismatch` error

### String → Boolean
- `"true"`, `"TRUE"`, `"1"` → `true`
- `"false"`, `"FALSE"`, `"0"` → `false`
- Other strings → `TypeMismatch` error

### Number → Boolean
- `0` → `false`
- Any other number → `true`

### Number Conversions
- `int` → `float`: Always succeeds
- `float` → `int`: Truncates decimal part

## Memory Management

Flare uses arena allocation for efficient memory management:

- All configuration data is allocated from a single arena
- Memory is automatically freed when `config.deinit()` is called
- No need to manually free individual strings or values
- Very fast allocation and deallocation

## Thread Safety

Current implementation is **not thread-safe**. Use external synchronization if accessing configuration from multiple threads.

## Performance Characteristics

- **Loading**: O(n) where n is total configuration size
- **Key lookup**: O(1) average case (hash map)
- **Memory usage**: Single allocation per configuration value
- **Cleanup**: O(1) - arena deallocation