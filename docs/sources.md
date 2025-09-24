# Configuration Sources

Flare supports loading configuration from multiple sources with a clear precedence system. This document explains each source type and how they interact.

## Source Precedence

Flare follows this precedence order (highest to lowest):

1. **Environment Variables** (highest priority)
2. **Configuration Files** (medium priority)
3. **Default Values** (lowest priority)

Values from higher-priority sources override those from lower-priority sources.

## File Sources

### JSON Files

Flare natively supports JSON configuration files with nested object support.

```zig
const files = [_]flare.FileSource{
    .{ .path = "config.json", .required = true },
    .{ .path = "config.local.json", .required = false },
};

var config = try flare.load(allocator, .{
    .files = &files,
});
```

#### FileSource Options

- `path: []const u8` - Path to the configuration file
- `required: bool = true` - Whether the file must exist (default: true)

If a required file is missing, `flare.load()` returns `FlareError.Io`.
If an optional file is missing, it's silently skipped.

#### Nested Object Flattening

JSON objects are automatically flattened using underscore notation internally:

```json
{
  "database": {
    "connection": {
      "host": "localhost",
      "port": 5432
    }
  }
}
```

Access as: `database.connection.host` or `database.connection.port`

### TOML Files

Flare fully supports TOML configuration files with automatic format detection:

```zig
var config = try flare.load(allocator, .{
    .files = &[_]flare.FileSource{
        .{ .path = "config.toml" },  // Auto-detected as TOML
        .{ .path = "config.json" },  // Auto-detected as JSON
    },
});
```

**Example config.toml:**
```toml
name = "my-app"
debug = false

[database]
host = "localhost"
port = 5432
ssl = true

[server]
host = "0.0.0.0"
port = 8080
timeout = 30.5
```

#### Format Detection

- `.json` files → JSON parser
- `.toml` files → TOML parser
- Unknown extensions → JSON parser (default)

#### Explicit Format Selection

```zig
.files = &[_]flare.FileSource{
    .{ .path = "config.conf", .format = .toml },  // Force TOML
    .{ .path = "data.txt", .format = .json },     // Force JSON
}
```

### Future File Format Support

Planned support for additional formats:

- **YAML** - Coming in v0.3.0

## Environment Variable Sources

Environment variables provide a powerful way to override configuration at runtime.

### Basic Usage

```zig
var config = try flare.load(allocator, .{
    .env = .{
        .prefix = "MYAPP",
        .separator = "__"
    },
});
```

#### EnvSource Options

- `prefix: []const u8` - Required prefix for environment variables
- `separator: []const u8 = "_"` - Separator for nested keys (default: "_")

### Environment Variable Mapping

Environment variables are mapped to configuration keys using this pattern:

```
{PREFIX}{SEPARATOR}{KEY_PATH}
```

#### Examples with `prefix = "MYAPP"` and `separator = "__"`

| Environment Variable | Configuration Key | Value Type |
|---------------------|-------------------|------------|
| `MYAPP__DATABASE__HOST` | `database.host` | string |
| `MYAPP__DATABASE__PORT` | `database.port` | int |
| `MYAPP__DEBUG` | `debug` | bool |
| `MYAPP__SERVER__TIMEOUT` | `server.timeout` | float |

### Type Detection and Parsing

Environment variable values are automatically parsed:

#### Boolean Values
- `"true"`, `"TRUE"` → `true`
- `"false"`, `"FALSE"` → `false`

#### Numeric Values
- `"42"` → `42` (int)
- `"3.14"` → `3.14` (float)
- `"invalid123"` → `"invalid123"` (string)

#### String Values
- Any value that doesn't parse as bool/number becomes a string

### Case Conversion

Environment variable keys are automatically converted to lowercase:

- `MYAPP__DATABASE__HOST` → `database.host`
- `MYAPP__SERVER__PORT` → `server.port`

## Default Values

Default values provide fallbacks when configuration is not found in files or environment variables.

### Setting Defaults

```zig
// Set defaults before or after loading
try config.setDefault("database.timeout", flare.Value{ .int_value = 30 });
try config.setDefault("server.workers", flare.Value{ .int_value = 4 });
try config.setDefault("app.name", flare.Value{ .string_value = "My App" });
```

### Using Defaults in Getters

```zig
// Inline defaults - used if key not found anywhere
const timeout = try config.getInt("database.timeout", 30);
const workers = try config.getInt("server.workers", 4);
const name = try config.getString("app.name", "Default App");

// No default - returns error if key not found
const required_key = try config.getString("required.key", null); // FlareError.MissingKey if not found
```

## Loading Strategy

### Multiple Files with Precedence

```zig
var config = try flare.load(allocator, .{
    .files = &[_]flare.FileSource{
        .{ .path = "config.base.json", .required = true },      // Base configuration
        .{ .path = "config.development.json", .required = false }, // Development overrides
        .{ .path = "config.local.json", .required = false },      // Local developer overrides
    },
    .env = .{ .prefix = "MYAPP", .separator = "__" },             // Environment overrides
});
```

Processing order:
1. `config.base.json` (loaded first)
2. `config.development.json` (overrides base)
3. `config.local.json` (overrides development)
4. Environment variables (override everything)

### Recommended Directory Structure

```
project/
├── config/
│   ├── config.base.json      # Base configuration
│   ├── config.development.json
│   ├── config.production.json
│   └── config.test.json
├── config.local.json         # Git-ignored local overrides
└── src/
    └── main.zig
```

## Environment-Specific Loading

### Development Environment

```zig
const env = std.process.getEnvVarOwned(allocator, "ENVIRONMENT") catch "development";
defer allocator.free(env);

const config_file = try std.fmt.allocPrint(allocator, "config/config.{s}.json", .{env});
defer allocator.free(config_file);

var config = try flare.load(allocator, .{
    .files = &[_]flare.FileSource{
        .{ .path = "config/config.base.json", .required = true },
        .{ .path = config_file, .required = false },
        .{ .path = "config.local.json", .required = false },
    },
    .env = .{ .prefix = "MYAPP", .separator = "__" },
});
```

### Production Environment

```bash
export ENVIRONMENT=production
export MYAPP__DATABASE__HOST=prod-db.example.com
export MYAPP__DATABASE__PASSWORD_FILE=/secrets/db-password
export MYAPP__LOG__LEVEL=warn
```

## Best Practices

### 1. Use Hierarchical Keys

Structure your configuration with clear hierarchies:

```json
{
  "database": {
    "primary": { "host": "...", "port": 5432 },
    "replica": { "host": "...", "port": 5432 }
  },
  "cache": {
    "redis": { "host": "...", "port": 6379 },
    "memory": { "size": 1024 }
  }
}
```

### 2. Provide Sensible Defaults

Always provide reasonable defaults for optional configuration:

```zig
const timeout = try config.getInt("server.timeout", 30);
const workers = try config.getInt("server.workers", 4);
const debug = try config.getBool("debug", false);
```

### 3. Use Environment Variables for Secrets

Never put secrets in configuration files. Use environment variables:

```zig
const db_password = try config.getString("database.password", null);
const api_key = try config.getString("api.key", null);
```

### 4. Validate Required Configuration

Always validate that required configuration is present:

```zig
const required = [_][]const u8{
    "database.host",
    "database.name",
    "api.endpoint"
};
try config.validateRequired(&required);
```

### 5. Document Your Configuration

Document all configuration options and their environment variable equivalents in your README.