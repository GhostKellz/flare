# Getting Started with Flare

**Flare** is a powerful configuration management library for Zig that provides hierarchical configuration loading, type-safe access, schema validation, and CLI integration. What Viper is to Cobra in Go, Flare is to Flash in Zig.

This guide will walk you through setting up and using Flare in your Zig project, from basic configuration loading to advanced Flash CLI integration.

## Installation

### Method 1: Using zig fetch (Recommended)

Add Flare to your project using Zig's package manager:

```bash
zig fetch --save https://github.com/ghostkellz/flare/archive/refs/heads/main.tar.gz
```

Then add it to your `build.zig`:

```zig
const flare_dep = b.dependency("flare", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("flare", flare_dep.module("flare"));
```

### Method 2: Git Submodule

```bash
git submodule add https://github.com/ghostkellz/flare.git vendor/flare
```

## Basic Configuration Loading

### Step 1: Create a Configuration File

Flare supports both JSON and TOML formats. Create a `config.toml` file in your project root:

```toml
[app]
name = "My Awesome App"
version = "1.0.0"

[database]
host = "localhost"
port = 5432
name = "myapp"
ssl = false

[server]
host = "0.0.0.0"
port = 8080
timeout = 30.0

# Arrays are fully supported
[[servers]]
name = "api-primary"
url = "https://api.example.com"
region = "us-east-1"

[[servers]]
name = "api-secondary"
url = "https://api-backup.example.com"
region = "us-west-2"

[logging]
level = "info"
enabled = true
```

Or use JSON format:

```json
{
  "app": {
    "name": "My Awesome App",
    "version": "1.0.0"
  },
  "database": {
    "host": "localhost",
    "port": 5432,
    "name": "myapp",
    "ssl": false
  },
  "servers": [
    {
      "name": "api-primary",
      "url": "https://api.example.com",
      "region": "us-east-1"
    }
  ]
}
```

### Step 2: Load and Use Configuration

```zig
const std = @import("std");
const flare = @import("flare");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get environment variables for loading
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    // Load configuration with full precedence chain
    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = "config.toml", .required = false, .format = .toml },
            .{ .path = "config.json", .required = false, .format = .json },
        },
        .env = .{ .prefix = "APP", .separator = "__", .env_map = &env_map },
        .cli = .{ .args = try std.process.argsAlloc(allocator) },
    });
    defer config.deinit();

    // Access configuration values with type safety
    const app_name = try config.getString("app.name", "Default App");
    const db_host = try config.getString("database.host", "localhost");
    const db_port = try config.getInt("database.port", 5432);
    const server_timeout = try config.getFloat("server.timeout", 30.0);
    const logging_enabled = try config.getBool("logging.enabled", true);

    // Access arrays and collections
    const servers = try config.getArray("servers");

    std.debug.print("Starting {s}\\n", .{app_name});
    std.debug.print("Database: {s}:{d}\\n", .{ db_host, db_port });
    std.debug.print("Server timeout: {d}s\\n", .{server_timeout});
    std.debug.print("Logging: {}\\n", .{logging_enabled});
    std.debug.print("Found {d} servers\\n", .{servers.items.len});
}
```

## Environment Variable Integration

Flare can automatically load environment variables with a specified prefix:

```zig
// Get environment map (required for env var loading)
var env_map = try std.process.getEnvMap(allocator);
defer env_map.deinit();

var config = try flare.load(allocator, .{
    .files = &[_]flare.FileSource{
        .{ .path = "config.json", .required = false },
    },
    .env = .{
        .prefix = "MYAPP",
        .separator = "_",
        .env_map = &env_map,
    },
});
```

Now you can override configuration with environment variables:

```bash
export APP__DATABASE__HOST=production-db.example.com
export APP__DATABASE__PORT=5432
export APP__LOGGING__LEVEL=debug
export APP__LOGGING__ENABLED=true
```

### Environment Variable Mapping

Environment variables are automatically converted:

- `APP__DATABASE__HOST` → `database.host`
- `APP__SERVER__PORT` → `server.port`
- `APP__LOGGING__ENABLED` → `logging.enabled`

## CLI Arguments Integration

Flare automatically parses CLI arguments with the highest precedence:

```bash
# These CLI flags override environment variables and config files
./myapp --database-host=prod.example.com --database-port=3306 --debug=true

# Short flags are supported too
./myapp -h prod.example.com -p 3306 -d

# JSON arrays and objects as CLI arguments
./myapp --servers='[{"name":"api-1","url":"https://api1.com"}]'
```

### CLI Argument Conversion

CLI arguments are converted to configuration keys:

- `--database-host` → `database.host`
- `--server-port` → `server.port`
- `--log-level` → `log.level`

### Configuration Precedence

Flare follows a clear precedence order:

1. **CLI Arguments** (Highest priority)
2. **Environment Variables**
3. **Configuration Files**
4. **Default Values** (Lowest priority)

## Setting Defaults in Code

You can set default values programmatically:

```zig
// Set defaults before loading
try config.setDefault("database.timeout", flare.Value{ .int_value = 5 });
try config.setDefault("server.workers", flare.Value{ .int_value = 4 });
try config.setDefault("app.environment", flare.Value{ .string_value = "development" });

// These defaults will be used if not found in files or environment
const timeout = try config.getInt("database.timeout", 10);
const workers = try config.getInt("server.workers", 1);
const env = try config.getString("app.environment", "production");
```

## Configuration Validation

Ensure required configuration keys are present:

```zig
// Validate required keys
const required_keys = [_][]const u8{
    "database.host",
    "database.port",
    "app.name"
};

config.validateRequired(&required_keys) catch |err| switch (err) {
    flare.FlareError.MissingKey => {
        std.debug.print("Missing required configuration key!\\n", .{});
        return;
    },
    else => return err,
};
```

## Type Coercion

Flare automatically converts between compatible types:

### String to Number
```zig
// JSON: "port": "8080"
// Environment: MYAPP_PORT=8080
const port = try config.getInt("port", 3000); // Returns 8080 as i64
```

### String to Boolean
```zig
// Environment: MYAPP_DEBUG=true
// JSON: "debug": "1"
const debug = try config.getBool("debug", false); // Returns true
```

### Number to Float
```zig
// JSON: "timeout": 30
const timeout = try config.getFloat("timeout", 0.0); // Returns 30.0
```

## Error Handling

Flare provides detailed error types for better error handling:

```zig
const value = config.getString("some.key", null) catch |err| switch (err) {
    flare.FlareError.MissingKey => {
        std.debug.print("Key not found and no default provided\\n", .{});
        return;
    },
    flare.FlareError.TypeMismatch => {
        std.debug.print("Value exists but wrong type\\n", .{});
        return;
    },
    flare.FlareError.ParseError => {
        std.debug.print("Failed to parse configuration file\\n", .{});
        return;
    },
    else => return err,
};
```

## Multiple Configuration Files

Load configuration from multiple files with precedence:

```zig
var env_map = try std.process.getEnvMap(allocator);
defer env_map.deinit();

var config = try flare.load(allocator, .{
    .files = &[_]flare.FileSource{
        .{ .path = "config.json", .required = true },
        .{ .path = "config.local.json", .required = false },
        .{ .path = "config.production.json", .required = false },
    },
    .env = .{ .prefix = "MYAPP", .separator = "_", .env_map = &env_map },
});
```

Files are processed in order, with later files overriding earlier ones.

## Working with Arrays and Collections

Flare provides powerful support for arrays and nested objects:

### Accessing Arrays

```zig
// Config: servers = [{"name": "api-1", "url": "..."}, {"name": "api-2", "url": "..."}]

// Get the entire array
const servers = try config.getArray("servers");
std.debug.print("Found {d} servers\n", .{servers.items.len});

// Get array element by index
const first_server = try config.getByIndex("servers", 0);

// Iterate over array items to access nested values
for (servers.items) |server| {
    if (server.map_value.get("name")) |name| {
        std.debug.print("Server: {s}\n", .{name.string_value});
    }
}
```

### Working with Maps

```zig
// Access nested objects as maps
const db_config = try config.getMap("database");
var iter = db_config.iterator();
while (iter.next()) |entry| {
    std.debug.print("{s}: {any}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
}
```

## Schema Validation

Define schemas to validate your configuration structure:

```zig
const std = @import("std");
const flare = @import("flare");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Define field schemas
    const host_schema = flare.Schema.string(.{}).required();
    const port_schema = flare.Schema.int(.{ .min = 1, .max = 65535 });
    const name_schema = flare.Schema.string(.{}).required();

    // Build database object schema
    var db_fields = std.StringHashMap(*const flare.Schema).init(allocator);
    defer db_fields.deinit();

    const host_ptr = try allocator.create(flare.Schema);
    host_ptr.* = host_schema;
    try db_fields.put("host", host_ptr);

    const port_ptr = try allocator.create(flare.Schema);
    port_ptr.* = port_schema;
    try db_fields.put("port", port_ptr);

    // Build root schema
    var root_fields = std.StringHashMap(*const flare.Schema).init(allocator);
    defer root_fields.deinit();

    const name_ptr = try allocator.create(flare.Schema);
    name_ptr.* = name_schema;
    try root_fields.put("name", name_ptr);

    const db_ptr = try allocator.create(flare.Schema);
    db_ptr.* = flare.Schema{ .schema_type = .object, .fields = db_fields };
    try root_fields.put("database", db_ptr);

    const root_schema = flare.Schema{ .schema_type = .object, .fields = root_fields };

    // Load configuration from file
    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{ .{ .path = "config.toml" } },
    });
    defer config.deinit();

    // Attach schema and validate
    config.setSchema(&root_schema);
    var validation = try config.validateSchema();
    defer validation.deinit(allocator);

    if (validation.hasErrors()) {
        for (validation.errors.items) |err| {
            std.debug.print("Validation error at {s}: {s}\n", .{ err.path, err.message });
        }
    }
}
```

## Flash CLI Integration

Integrate Flare seamlessly with Flash CLI applications:

```zig
var env_map = try std.process.getEnvMap(allocator);
defer env_map.deinit();

const flash = @import("flash");
const flare = @import("flare");

// Create a Flash command with automatic config integration
const connect_cmd = flare.flash.createConfigCommand(
    "connect",
    "Connect to database",
    .{
        .config_files = &[_]flare.FileSource{
            .{ .path = "config.toml", .required = false },
        },
        .env_source = .{ .prefix = "MYAPP", .separator = "_", .env_map = &env_map },
        .schema = &database_schema,
    },
    &[_]flare.flash.FlagLink{
        .{ .flag_name = "host", .config_key = "database.host", .short = "h" },
        .{ .flag_name = "port", .config_key = "database.port", .short = "p" },
    },
    connectHandler,
);

fn connectHandler(ctx: flare.flash.CommandContext) !void {
    // Configuration is already loaded and validated
    const host = try ctx.config.getString("database.host", "localhost");
    const port = try ctx.config.getInt("database.port", 5432);

    std.debug.print("Connecting to {s}:{d}...\n", .{ host, port });
}
```

## Advanced Features

### Type Coercion and Conversion

Flare automatically converts between compatible types:

```zig
// String "8080" → int 8080
// String "true" → bool true
// String "3.14" → float 3.14
// Int 42 → float 42.0
```

### Format Auto-detection

```zig
var config = try flare.load(allocator, .{
    .files = &[_]flare.FileSource{
        .{ .path = "config.json", .format = .auto }, // Auto-detects JSON
        .{ .path = "config.toml", .format = .auto }, // Auto-detects TOML
    },
});
```

## Next Steps

- [Learn about Flash CLI integration](flash-integration.md)
- [Explore schema validation in depth](schema.md)
- [Check out the full API reference](api-reference.md)
- [Browse advanced examples](examples.md)
