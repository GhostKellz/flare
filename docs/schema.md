# Schema System

Flare's schema system provides declarative configuration validation, allowing you to define the expected structure of your configuration and validate it at runtime.

## Overview

The schema system allows you to:
- **Define configuration structure** declaratively
- **Validate types and constraints** automatically
- **Set default values** at the schema level
- **Get detailed error messages** with field paths
- **Enforce required fields** and optional fields

## Basic Schema Definition

### Simple Field Types

```zig
const allocator = std.testing.allocator;

// String field with constraints
const name_schema = flare.Schema.string(.{
    .min_length = 1,
    .max_length = 100,
}).required().withDescription("Application name");

// Integer field with range validation
const port_schema = flare.Schema.int(.{
    .min = 1,
    .max = 65535,
}).default(flare.Value{ .int_value = 8080 });

// Boolean field with default
const debug_schema = flare.Schema.boolean()
    .default(flare.Value{ .bool_value = false });

// Float field with constraints
const timeout_schema = flare.Schema.float(.{
    .min = 0.1,
    .max = 300.0,
});
```

### Object Schema

Define nested configuration objects:

```zig
// Database configuration schema
var db_fields = std.StringHashMap(*const flare.Schema).init(allocator);
defer db_fields.deinit();

const host_schema = try allocator.create(flare.Schema);
host_schema.* = flare.Schema.string(.{}).required();

const port_schema = try allocator.create(flare.Schema);
port_schema.* = flare.Schema.int(.{ .min = 1, .max = 65535 })
    .default(flare.Value{ .int_value = 5432 });

try db_fields.put("host", host_schema);
try db_fields.put("port", port_schema);

const database_schema = try allocator.create(flare.Schema);
database_schema.* = flare.Schema{
    .schema_type = .object,
    .fields = db_fields,
};
```

### Root Schema

Create a complete application schema:

```zig
var fields = std.StringHashMap(*const flare.Schema).init(allocator);
defer fields.deinit();

// Application fields
const app_name_schema = try allocator.create(flare.Schema);
app_name_schema.* = flare.Schema.string(.{ .min_length = 1 }).required();

const debug_schema = try allocator.create(flare.Schema);
debug_schema.* = flare.Schema.boolean()
    .default(flare.Value{ .bool_value = false });

try fields.put("name", app_name_schema);
try fields.put("debug", debug_schema);
try fields.put("database", database_schema);

const root_schema = flare.Schema{
    .schema_type = .object,
    .fields = fields,
};
```

## Schema-Aware Configuration

### Create Config with Schema

```zig
// Create configuration with schema
var config = try flare.Config.initWithSchema(allocator, &root_schema);
defer config.deinit();

// Load data from files/environment
var loaded_config = try flare.load(allocator, .{
    .files = &[_]flare.FileSource{
        .{ .path = "config.json" },
    },
});
defer loaded_config.deinit();

// Copy values to schema-aware config
const name = try loaded_config.getString("name", "default");
const debug = try loaded_config.getBool("debug", false);

try config.setValue("name", flare.Value{ .string_value = name });
try config.setValue("debug", flare.Value{ .bool_value = debug });
```

### Validate Configuration

```zig
// Validate against schema
var validation_result = try config.validateSchema();
defer validation_result.deinit(allocator);

if (validation_result.hasErrors()) {
    std.debug.print("❌ Configuration validation failed:\n");
    for (validation_result.errors.items) |error_item| {
        std.debug.print("  - {s}: {s}\n", .{ error_item.path, error_item.message });
    }
    return;
} else {
    std.debug.print("✅ Configuration is valid!\n");
}
```

## Validation Constraints

### String Constraints

```zig
const string_schema = flare.Schema.string(.{
    .min_length = 3,        // Minimum length
    .max_length = 50,       // Maximum length
    .pattern = "^[a-zA-Z]", // Regex pattern (planned)
});
```

### Integer Constraints

```zig
const int_schema = flare.Schema.int(.{
    .min = 1000,    // Minimum value
    .max = 9999,    // Maximum value
});
```

### Float Constraints

```zig
const float_schema = flare.Schema.float(.{
    .min = 0.0,     // Minimum value
    .max = 100.0,   // Maximum value
});
```

## Method Chaining

Schemas support fluent method chaining:

```zig
const user_schema = flare.Schema.string(.{ .min_length = 1 })
    .required()
    .default(flare.Value{ .string_value = "anonymous" })
    .withDescription("User name for authentication");

const timeout_schema = flare.Schema.float(.{ .min = 0.1 })
    .default(flare.Value{ .float_value = 30.0 })
    .withDescription("Request timeout in seconds");
```

## Error Types and Messages

The schema system provides detailed error information:

```zig
pub const SchemaError = error{
    MissingRequiredField,  // Required field not present
    TypeMismatch,         // Wrong data type
    ValueOutOfRange,      // Value violates min/max constraints
    InvalidFormat,        // Value doesn't match pattern
    ValidationFailed,     // General validation failure
};
```

### Error Messages

Validation errors include:
- **Field path** - Full path to the problematic field
- **Error type** - Specific type of validation failure
- **Human-readable message** - Detailed description of the issue

```zig
// Example validation errors:
// "Missing required field at 'database.host'"
// "Value out of range at 'server.port' (min: 1000, actual: 80)"
// "Type mismatch at 'debug' (expected: bool, got: string)"
```

## Advanced Usage

### Custom Validation

```zig
// Validate specific constraints in your application
var result = try config.validateSchema();
defer result.deinit(allocator);

// Additional custom validation
if (!result.hasErrors()) {
    const port = try config.getInt("server.port", 8080);
    const ssl_enabled = try config.getBool("ssl.enabled", false);

    if (port == 80 && ssl_enabled) {
        std.debug.print("Warning: SSL enabled on port 80\n");
    }
}
```

### Schema Evolution

```zig
// Handle schema migrations and backwards compatibility
const v1_schema = createV1Schema(allocator);
const v2_schema = createV2Schema(allocator);

// Try v2 first, fallback to v1
var result = try config.validateSchema(); // v2
if (result.hasErrors()) {
    config.setSchema(&v1_schema);
    result.deinit(allocator);
    result = try config.validateSchema(); // v1
}
```

## Integration with TOML/JSON

Schema validation works with any configuration source:

```zig
// Load from TOML with schema validation
var config = try flare.Config.initWithSchema(allocator, &my_schema);
var toml_data = try flare.load(allocator, .{
    .files = &[_]flare.FileSource{
        .{ .path = "config.toml", .format = .toml },
    },
});

// Copy and validate
try copyConfigData(&config, &toml_data);
var result = try config.validateSchema();
```

## Best Practices

### 1. Define Schemas Early
```zig
// Define your schema at the application level
const AppSchema = createAppSchema();

pub fn main() !void {
    var config = try flare.Config.initWithSchema(allocator, &AppSchema);
    // ... use config
}
```

### 2. Use Descriptive Field Names
```zig
const database_schema = flare.Schema.object(allocator, .{
    .connection_host = flare.Schema.string(.{}).required(),
    .connection_port = flare.Schema.int(.{ .min = 1, .max = 65535 }),
    .connection_timeout_seconds = flare.Schema.float(.{ .min = 0.1 }),
});
```

### 3. Provide Sensible Defaults
```zig
const server_schema = flare.Schema.object(allocator, .{
    .host = flare.Schema.string(.{})
        .default(flare.Value{ .string_value = "0.0.0.0" }),
    .port = flare.Schema.int(.{ .min = 1, .max = 65535 })
        .default(flare.Value{ .int_value = 8080 }),
    .workers = flare.Schema.int(.{ .min = 1, .max = 32 })
        .default(flare.Value{ .int_value = 4 }),
});
```

### 4. Use Validation in Development
```zig
if (std.debug.runtime_safety) {
    var result = try config.validateSchema();
    defer result.deinit(allocator);

    if (result.hasErrors()) {
        std.debug.print("Development mode: Configuration errors detected!\n");
        for (result.errors.items) |error_item| {
            std.debug.print("  {s}\n", .{error_item.message});
        }
        std.process.exit(1);
    }
}
```

## Array Schemas

Define schemas for arrays and validate their contents:

```zig
// Simple array of strings
const tags_schema = flare.Schema.array(.{
    .min_items = 1,
    .max_items = 10,
    .item_schema = &flare.Schema.string(.{ .min_length = 1 }),
});

// Array of server objects
var server_fields = std.StringHashMap(*const flare.Schema).init(allocator);

const server_name = try allocator.create(flare.Schema);
server_name.* = flare.Schema.string(.{}).required();

const server_url = try allocator.create(flare.Schema);
server_url.* = flare.Schema.string(.{ .pattern = "^https?://" }).required();

try server_fields.put("name", server_name);
try server_fields.put("url", server_url);

const server_item_schema = try allocator.create(flare.Schema);
server_item_schema.* = flare.Schema{
    .schema_type = .object,
    .fields = server_fields,
};

const servers_schema = flare.Schema.array(.{
    .min_items = 1,
    .item_schema = server_item_schema,
});
```

### Working with Array Configuration

```toml
# config.toml
tags = ["api", "database", "web"]

[[servers]]
name = "api-primary"
url = "https://api1.example.com"
region = "us-east-1"

[[servers]]
name = "api-secondary"
url = "https://api2.example.com"
region = "us-west-2"
```

```zig
// Load and validate array configuration
var config = try flare.Config.initWithSchema(allocator, &app_schema);
defer config.deinit();

// Load from TOML
var toml_config = try flare.load(allocator, .{
    .files = &[_]flare.FileSource{
        .{ .path = "config.toml", .format = .toml },
    },
});
defer toml_config.deinit();

// Copy arrays to schema-aware config
const tags = try toml_config.getArray("tags");
try config.setValue("tags", flare.Value{ .array_value = tags });

const servers = try toml_config.getArray("servers");
try config.setValue("servers", flare.Value{ .array_value = servers });

// Validate
var result = try config.validateSchema();
defer result.deinit(allocator);
```

## Advanced Schema Patterns

### Conditional Schemas

Create schemas that adapt based on configuration values:

```zig
// Database schema that varies by type
fn createDatabaseSchema(allocator: std.mem.Allocator, db_type: []const u8) !flare.Schema {
    var fields = std.StringHashMap(*const flare.Schema).init(allocator);

    // Common fields
    const host_schema = try allocator.create(flare.Schema);
    host_schema.* = flare.Schema.string(.{}).required();
    try fields.put("host", host_schema);

    const port_schema = try allocator.create(flare.Schema);

    if (std.mem.eql(u8, db_type, "postgresql")) {
        port_schema.* = flare.Schema.int(.{ .min = 1, .max = 65535 })
            .default(flare.Value{ .int_value = 5432 });
    } else if (std.mem.eql(u8, db_type, "mysql")) {
        port_schema.* = flare.Schema.int(.{ .min = 1, .max = 65535 })
            .default(flare.Value{ .int_value = 3306 });
    } else {
        port_schema.* = flare.Schema.int(.{ .min = 1, .max = 65535 });
    }

    try fields.put("port", port_schema);

    return flare.Schema{
        .schema_type = .object,
        .fields = fields,
    };
}
```

### Schema Composition

Build complex schemas from simpler components:

```zig
fn createServerSchema(allocator: std.mem.Allocator) !flare.Schema {
    return flare.Schema.object(allocator, .{
        .name = flare.Schema.string(.{ .min_length = 1 }).required(),
        .host = flare.Schema.string(.{}).required(),
        .port = flare.Schema.int(.{ .min = 1, .max = 65535 }),
        .ssl = flare.Schema.boolean().default(flare.Value{ .bool_value = true }),
    });
}

fn createLoadBalancerSchema(allocator: std.mem.Allocator) !flare.Schema {
    const server_schema = try createServerSchema(allocator);

    return flare.Schema.object(allocator, .{
        .algorithm = flare.Schema.string(.{})
            .default(flare.Value{ .string_value = "round_robin" }),
        .health_check_interval = flare.Schema.int(.{ .min = 1 })
            .default(flare.Value{ .int_value = 30 }),
        .servers = flare.Schema.array(.{
            .min_items = 1,
            .item_schema = &server_schema,
        }).required(),
    });
}
```

### Environment-Specific Schemas

```zig
fn createEnvAwareSchema(allocator: std.mem.Allocator, environment: []const u8) !flare.Schema {
    var fields = std.StringHashMap(*const flare.Schema).init(allocator);

    // Common fields
    const app_name = try allocator.create(flare.Schema);
    app_name.* = flare.Schema.string(.{}).required();
    try fields.put("name", app_name);

    // Environment-specific requirements
    if (std.mem.eql(u8, environment, "production")) {
        // Production requires stricter validation
        const log_level = try allocator.create(flare.Schema);
        log_level.* = flare.Schema.string(.{})
            .default(flare.Value{ .string_value = "warn" });
        try fields.put("log_level", log_level);

        // SSL required in production
        const ssl_cert = try allocator.create(flare.Schema);
        ssl_cert.* = flare.Schema.string(.{}).required();
        try fields.put("ssl_cert_path", ssl_cert);
    } else {
        // Development allows more flexibility
        const log_level = try allocator.create(flare.Schema);
        log_level.* = flare.Schema.string(.{})
            .default(flare.Value{ .string_value = "debug" });
        try fields.put("log_level", log_level);
    }

    return flare.Schema{
        .schema_type = .object,
        .fields = fields,
    };
}
```

## Future Features (Planned)

- **Union types** - Multiple possible types for a field
- **Custom validators** - User-defined validation functions
- **Schema inheritance** - Extend existing schemas
- **JSON Schema export** - Generate JSON Schema documents
- **Pattern validation** - Full regex pattern matching for strings
- **Cross-field validation** - Validate relationships between fields

## See Also

- [Getting Started](getting-started.md) - Basic configuration usage
- [Configuration Sources](sources.md) - Different ways to load configuration
- [API Reference](api-reference.md) - Complete API documentation