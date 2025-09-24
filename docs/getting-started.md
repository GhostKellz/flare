# Getting Started with Flare

**Flare** is a powerful configuration management library for Zig that provides hierarchical configuration loading, type-safe access, and schema validation. What Viper is to Cobra in Go, Flare is to Flash in Zig.

This guide will walk you through setting up and using Flare in your Zig project.

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

Create a `config.json` file in your project root:

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
  "server": {
    "host": "0.0.0.0",
    "port": 8080,
    "timeout": 30.0
  },
  "logging": {
    "level": "info",
    "enabled": true
  }
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

    // Load configuration with defaults
    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = "config.json", .required = false },
        },
    });
    defer config.deinit();

    // Access configuration values
    const app_name = try config.getString("app.name", "Default App");
    const db_host = try config.getString("database.host", "localhost");
    const db_port = try config.getInt("database.port", 5432);
    const server_timeout = try config.getFloat("server.timeout", 30.0);
    const logging_enabled = try config.getBool("logging.enabled", true);

    std.debug.print("Starting {s}\\n", .{app_name});
    std.debug.print("Database: {s}:{d}\\n", .{ db_host, db_port });
    std.debug.print("Server timeout: {d}s\\n", .{server_timeout});
    std.debug.print("Logging: {}\\n", .{logging_enabled});
}
```

## Environment Variable Integration

Flare can automatically load environment variables with a specified prefix:

```zig
var config = try flare.load(allocator, .{
    .files = &[_]flare.FileSource{
        .{ .path = "config.json", .required = false },
    },
    .env = .{
        .prefix = "MYAPP",
        .separator = "_"
    },
});
```

Now you can override configuration with environment variables:

```bash
export MYAPP_DATABASE_HOST=production-db.example.com
export MYAPP_DATABASE_PORT=5432
export MYAPP_LOGGING_LEVEL=debug
export MYAPP_LOGGING_ENABLED=true
```

### Environment Variable Mapping

Environment variables are automatically converted:

- `MYAPP_DATABASE_HOST` → `database.host`
- `MYAPP_SERVER_PORT` → `server.port`
- `MYAPP_LOGGING_ENABLED` → `logging.enabled`

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
var config = try flare.load(allocator, .{
    .files = &[_]flare.FileSource{
        .{ .path = "config.json", .required = true },
        .{ .path = "config.local.json", .required = false },
        .{ .path = "config.production.json", .required = false },
    },
    .env = .{ .prefix = "MYAPP", .separator = "_" },
});
```

Files are processed in order, with later files overriding earlier ones.

## Next Steps

- [Learn about configuration sources](sources.md)
- [Explore the full API reference](api-reference.md)
- [Check out more examples](examples.md)