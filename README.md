<div align="center">

# 🔥 Flare

<img src="assets/icons/flare.png" alt="Flare Logo" width="200" height="200">

[![Built with Zig](https://img.shields.io/badge/Built%20with-Zig-yellow.svg?style=for-the-badge&logo=zig)](https://ziglang.org/)
[![Zig Version](https://img.shields.io/badge/Zig-0.16.0--dev-orange.svg?style=for-the-badge)](https://ziglang.org/download/)
[![Flash CLI Integration](https://img.shields.io/badge/Flash%20CLI-Integration-gold.svg?style=for-the-badge)](https://github.com/ghostkellz/flash)

[![Status](https://img.shields.io/badge/Status-MVP%20Complete-brightgreen.svg?style=for-the-badge)](https://github.com/ghostkellz/flare)
[![Version](https://img.shields.io/badge/Version-0.1.0-green.svg?style=for-the-badge)](https://github.com/ghostkellz/flare/releases)
[![License](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](LICENSE)

**What Viper is to Cobra in Go, Flare is to Flash in Zig**

*A powerful configuration management library for Zig that provides hierarchical configuration loading, type-safe access, and seamless integration with environment variables and configuration files.*

</div>

## Features

- 🏗️ **Arena-based memory management** - Efficient allocation and cleanup
- 📁 **Multiple configuration sources** - JSON/TOML files, environment variables, defaults
- 🎯 **Type-safe getters** - `getBool()`, `getInt()`, `getFloat()`, `getString()`
- 🔄 **Smart type coercion** - Automatic conversion between compatible types
- 🗂️ **Dotted key notation** - Access nested values with `db.host`, `server.port`
- ⚡ **Zero-copy string handling** - Memory-efficient string operations
- ✅ **Schema validation** - Declarative configuration structure with constraints
- 📋 **TOML support** - Full TOML parser with automatic format detection
- 🌍 **Environment variable mapping** - `APP_DB__HOST` → `db.host`
- 🔍 **Detailed error reporting** - Field path and constraint violation messages

## Quick Start

### Installation

Add Flare to your `build.zig.zon`:

```bash
zig fetch --save https://github.com/ghostkellz/flare/archive/refs/heads/main.tar.gz
```

For full Flash CLI integration, also add Flash:

```bash
zig fetch --save https://github.com/ghostkellz/flash/archive/refs/heads/main.tar.gz
```

### Basic Usage

```zig
const std = @import("std");
const flare = @import("flare");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load configuration from multiple sources
    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = "config.json" },
        },
        .env = .{ .prefix = "APP", .separator = "__" },
    });
    defer config.deinit();

    // Access configuration values with defaults
    const db_host = try config.getString("database.host", "localhost");
    const db_port = try config.getInt("database.port", 5432);
    const debug = try config.getBool("debug", false);

    std.debug.print("Connecting to {s}:{d} (debug: {})\\n", .{ db_host, db_port, debug });
}
```

### Example Configuration File

**config.toml:**
```toml
debug = false

[database]
host = "localhost"
port = 5432
ssl = true

[server]
host = "0.0.0.0"
port = 8080
```

**Or config.json:**
```json
{
  "database": {
    "host": "localhost",
    "port": 5432,
    "ssl": true
  },
  "server": {
    "host": "0.0.0.0",
    "port": 8080
  },
  "debug": false
}
```

### Environment Variables

Set environment variables with your configured prefix:

```bash
export APP__DATABASE__HOST=production-db.example.com
export APP__DATABASE__PORT=5432
export APP__DEBUG=true
```

## Schema Validation

Define and validate your configuration structure:

```zig
// Define schema
const MySchema = try flare.Schema.root(allocator, .{
    .database = try flare.Schema.object(allocator, .{
        .host = flare.Schema.string(.{}).required(),
        .port = flare.Schema.int(.{ .min = 1, .max = 65535 }),
    }),
    .debug = flare.Schema.boolean().default(flare.Value{ .bool_value = false }),
});

// Create schema-aware config
var config = try flare.Config.initWithSchema(allocator, &MySchema);
defer config.deinit();

// Load and validate
try loadConfigFromSources(&config);
var validation = try config.validateSchema();
defer validation.deinit(allocator);

if (validation.hasErrors()) {
    for (validation.errors.items) |error_item| {
        std.debug.print("❌ {s}\n", .{error_item.message});
    }
}
```

## Configuration Precedence

Flare follows a clear precedence order (highest to lowest):

1. **CLI Arguments** (highest) - *via Flash CLI integration*
2. **Environment variables**
3. **Configuration files**
4. **Default values** (lowest)

Later sources override earlier ones for the same key.

## Flash CLI Integration

Flare is designed to complement the Flash CLI framework, providing seamless configuration management for command-line applications:

```zig
const std = @import("std");
const flash = @import("flash");
const flare = @import("flare");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Flash CLI + Flare configuration integration
    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = "config.json", .required = false },
        },
        .env = .{ .prefix = "MYAPP", .separator = "__" },
        // CLI integration coming in v0.2.0
    });
    defer config.deinit();

    // Use configuration in your Flash CLI app
    const port = try config.getInt("server.port", 8080);
    const debug = try config.getBool("debug", false);

    // Your Flash CLI application logic here...
}
```

## API Reference

### Core Types

- `Config` - Main configuration container
- `Value` - Union type for configuration values
- `LoadOptions` - Options for loading configuration
- `FlareError` - Error types for configuration operations

### Key Methods

- `flare.load()` - Load configuration from multiple sources
- `config.getString()` - Get string value with optional default
- `config.getInt()` - Get integer value with optional default
- `config.getBool()` - Get boolean value with optional default
- `config.getFloat()` - Get float value with optional default
- `config.setDefault()` - Set default values
- `config.validateRequired()` - Validate required keys are present

## Documentation

- [Getting Started Guide](docs/getting-started.md) - Basic setup and usage with schema validation
- [Schema System](docs/schema.md) - Declarative configuration validation and constraints
- [Configuration Sources](docs/sources.md) - JSON, TOML, environment variables, and precedence
- [API Reference](docs/api-reference.md) - Complete API documentation with all methods
- [Examples](docs/examples.md) - Real-world usage examples with TOML and schema validation

## Requirements

- Zig 0.16.0 or later

## License

MIT License - see LICENSE file for details.

## Contributing

Contributions are welcome! Please see CONTRIBUTING.md for guidelines.
