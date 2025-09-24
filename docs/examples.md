# Examples

Real-world examples of using Flare for configuration management with schema validation and TOML support.

## Basic TOML Configuration

Simple web server configuration using TOML format with schema validation.

**config.toml:**
```toml
[app]
name = "My Web Server"
version = "1.0.0"
debug = false

[server]
host = "0.0.0.0"
port = 8080
workers = 4

[database]
host = "localhost"
port = 5432
name = "webapp"
ssl = true

[database.pool]
min_connections = 5
max_connections = 20
timeout = 30.0
```

**main.zig:**
```zig
const std = @import("std");
const flare = @import("flare");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Define schema for validation
    const schema = try createServerSchema(allocator);
    defer destroySchema(allocator, schema);

    // Load TOML configuration with schema validation
    var config = try flare.Config.initWithSchema(allocator, &schema);
    defer config.deinit();

    // Load from TOML file (auto-detected format)
    var file_config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = "config.toml" }, // Auto-detected as TOML
        },
        .env = .{ .prefix = "SERVER", .separator = "__" },
    });
    defer file_config.deinit();

    // Copy values to schema-aware config
    try copyConfigValues(&config, &file_config);

    // Validate against schema
    var validation = try config.validateSchema();
    defer validation.deinit(allocator);

    if (validation.hasErrors()) {
        std.debug.print("❌ Configuration validation failed:\n");
        for (validation.errors.items) |error_item| {
            std.debug.print("  - {s}\n", .{error_item.message});
        }
        return;
    }

    std.debug.print("✅ Configuration validated successfully!\n");

    // Use validated configuration
    const app_name = try config.getString("app_name", "Unknown");
    const server_port = try config.getInt("server_port", 8080);
    const db_host = try config.getString("database_host", "localhost");

    std.debug.print("🚀 Starting {s} on port {d}\n", .{ app_name, server_port });
    std.debug.print("📊 Database: {s}\n", .{db_host});
}

fn createServerSchema(allocator: std.mem.Allocator) !flare.Schema {
    // Create app schema
    var app_fields = std.StringHashMap(*const flare.Schema).init(allocator);
    const name_schema = try allocator.create(flare.Schema);
    name_schema.* = flare.Schema.string(.{ .min_length = 1 }).required();
    try app_fields.put("name", name_schema);

    const app_schema = try allocator.create(flare.Schema);
    app_schema.* = flare.Schema{ .schema_type = .object, .fields = app_fields };

    // Create server schema
    var server_fields = std.StringHashMap(*const flare.Schema).init(allocator);
    const port_schema = try allocator.create(flare.Schema);
    port_schema.* = flare.Schema.int(.{ .min = 1, .max = 65535 }).required();
    try server_fields.put("port", port_schema);

    const server_schema = try allocator.create(flare.Schema);
    server_schema.* = flare.Schema{ .schema_type = .object, .fields = server_fields };

    // Create root schema
    var root_fields = std.StringHashMap(*const flare.Schema).init(allocator);
    try root_fields.put("app", app_schema);
    try root_fields.put("server", server_schema);

    return flare.Schema{ .schema_type = .object, .fields = root_fields };
}

fn destroySchema(allocator: std.mem.Allocator, schema: flare.Schema) void {
    // Cleanup schema memory - simplified for example
    if (schema.fields) |fields| {
        fields.deinit();
    }
}

fn copyConfigValues(dest: *flare.Config, src: *flare.Config) !void {
    // Copy key values from source to destination
    // Simplified - in real code you'd iterate over all values
    if (src.getValue("name")) |v| try dest.setValue("app_name", v);
    if (src.getValue("server_port")) |v| try dest.setValue("server_port", v);
    if (src.getValue("database_host")) |v| try dest.setValue("database_host", v);
}
```

**Environment Overrides:**
```bash
# Override server port
export SERVER__SERVER__PORT=3000

# Override database settings
export SERVER__DATABASE__HOST=prod-db.com
export SERVER__DATABASE__SSL=true
```

## Web Server Configuration

A complete example for a web server with database, caching, and logging configuration.

### Configuration File (`config.json`)

```json
{
  "server": {
    "host": "0.0.0.0",
    "port": 8080,
    "timeout": 30.0,
    "workers": 4,
    "ssl": {
      "enabled": false,
      "cert_file": "",
      "key_file": ""
    }
  },
  "database": {
    "host": "localhost",
    "port": 5432,
    "name": "myapp",
    "user": "postgres",
    "ssl": false,
    "pool": {
      "min_connections": 5,
      "max_connections": 20,
      "timeout": 10.0
    }
  },
  "cache": {
    "redis": {
      "host": "localhost",
      "port": 6379,
      "db": 0,
      "timeout": 5.0
    },
    "memory": {
      "max_size": 1048576,
      "ttl": 3600
    }
  },
  "logging": {
    "level": "info",
    "file": "app.log",
    "max_size": 10485760,
    "rotate": true
  }
}
```

### Application Code (`main.zig`)

```zig
const std = @import("std");
const flare = @import("flare");

const ServerConfig = struct {
    host: []const u8,
    port: i64,
    timeout: f64,
    workers: i64,
    ssl_enabled: bool,
    ssl_cert: []const u8,
    ssl_key: []const u8,
};

const DatabaseConfig = struct {
    host: []const u8,
    port: i64,
    name: []const u8,
    user: []const u8,
    password: []const u8,
    ssl: bool,
    min_connections: i64,
    max_connections: i64,
    timeout: f64,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load configuration with environment variable support
    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = "config.json", .required = true },
            .{ .path = "config.local.json", .required = false },
        },
        .env = .{ .prefix = "MYAPP", .separator = "__" },
    });
    defer config.deinit();

    // Validate required configuration
    const required_keys = [_][]const u8{
        "server.host",
        "server.port",
        "database.host",
        "database.name",
    };
    try config.validateRequired(&required_keys);

    // Load server configuration
    const server = ServerConfig{
        .host = try config.getString("server.host", "0.0.0.0"),
        .port = try config.getInt("server.port", 8080),
        .timeout = try config.getFloat("server.timeout", 30.0),
        .workers = try config.getInt("server.workers", 4),
        .ssl_enabled = try config.getBool("server.ssl.enabled", false),
        .ssl_cert = try config.getString("server.ssl.cert_file", ""),
        .ssl_key = try config.getString("server.ssl.key_file", ""),
    };

    // Load database configuration
    const database = DatabaseConfig{
        .host = try config.getString("database.host", "localhost"),
        .port = try config.getInt("database.port", 5432),
        .name = try config.getString("database.name", null), // Required
        .user = try config.getString("database.user", "postgres"),
        .password = try config.getString("database.password", ""), // From env var
        .ssl = try config.getBool("database.ssl", false),
        .min_connections = try config.getInt("database.pool.min_connections", 5),
        .max_connections = try config.getInt("database.pool.max_connections", 20),
        .timeout = try config.getFloat("database.pool.timeout", 10.0),
    };

    // Start server
    std.debug.print("Starting server on {s}:{d}\\n", .{ server.host, server.port });
    std.debug.print("Database: {s}@{s}:{d}/{s}\\n", .{
        database.user, database.host, database.port, database.name
    });
    std.debug.print("Workers: {d}, Timeout: {d}s\\n", .{ server.workers, @as(i64, @intFromFloat(server.timeout)) });

    if (server.ssl_enabled) {
        std.debug.print("SSL enabled with cert: {s}\\n", .{server.ssl_cert});
    }
}
```

### Environment Variables

```bash
# Override for production
export MYAPP__SERVER__HOST=0.0.0.0
export MYAPP__SERVER__PORT=443
export MYAPP__SERVER__SSL__ENABLED=true
export MYAPP__SERVER__SSL__CERT_FILE=/etc/ssl/cert.pem
export MYAPP__SERVER__SSL__KEY_FILE=/etc/ssl/key.pem

export MYAPP__DATABASE__HOST=prod-db.example.com
export MYAPP__DATABASE__PASSWORD=super_secret_password
export MYAPP__DATABASE__SSL=true
export MYAPP__DATABASE__POOL__MAX_CONNECTIONS=50

export MYAPP__LOGGING__LEVEL=warn
```

## Microservice Configuration

Example for a microservice with service discovery and metrics.

### Configuration (`service.json`)

```json
{
  "service": {
    "name": "user-service",
    "version": "1.2.3",
    "environment": "development",
    "port": 3000
  },
  "discovery": {
    "consul": {
      "host": "localhost",
      "port": 8500,
      "register": true,
      "health_check": "/health"
    }
  },
  "metrics": {
    "enabled": true,
    "port": 9090,
    "path": "/metrics"
  },
  "tracing": {
    "jaeger": {
      "endpoint": "http://localhost:14268/api/traces",
      "sample_rate": 0.1
    }
  }
}
```

### Service Code

```zig
const std = @import("std");
const flare = @import("flare");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = "service.json", .required = true },
        },
        .env = .{ .prefix = "SERVICE", .separator = "_" },
    });
    defer config.deinit();

    // Service information
    const service_name = try config.getString("service.name", "unknown-service");
    const service_version = try config.getString("service.version", "0.0.0");
    const service_env = try config.getString("service.environment", "development");
    const service_port = try config.getInt("service.port", 3000);

    // Service discovery
    const consul_enabled = config.hasKey("discovery.consul.host");
    if (consul_enabled) {
        const consul_host = try config.getString("discovery.consul.host", "localhost");
        const consul_port = try config.getInt("discovery.consul.port", 8500);
        const should_register = try config.getBool("discovery.consul.register", true);

        std.debug.print("Service discovery: Consul at {s}:{d} (register: {})\\n",
            .{ consul_host, consul_port, should_register });
    }

    // Metrics
    const metrics_enabled = try config.getBool("metrics.enabled", false);
    if (metrics_enabled) {
        const metrics_port = try config.getInt("metrics.port", 9090);
        const metrics_path = try config.getString("metrics.path", "/metrics");

        std.debug.print("Metrics: Enabled on port {d}{s}\\n", .{ metrics_port, metrics_path });
    }

    // Tracing
    if (config.hasKey("tracing.jaeger.endpoint")) {
        const jaeger_endpoint = try config.getString("tracing.jaeger.endpoint", null);
        const sample_rate = try config.getFloat("tracing.jaeger.sample_rate", 0.1);

        std.debug.print("Tracing: Jaeger at {s} (sample rate: {d})\\n",
            .{ jaeger_endpoint, sample_rate });
    }

    std.debug.print("Starting {s} v{s} ({s}) on port {d}\\n",
        .{ service_name, service_version, service_env, service_port });
}
```

## CLI Tool Configuration

Example for a command-line tool with user preferences.

### User Config (`~/.myapp/config.json`)

```json
{
  "user": {
    "name": "John Doe",
    "email": "john@example.com"
  },
  "preferences": {
    "color_output": true,
    "verbose": false,
    "default_format": "json",
    "editor": "vim"
  },
  "api": {
    "base_url": "https://api.example.com",
    "timeout": 30,
    "retries": 3
  }
}
```

### CLI Tool Code

```zig
const std = @import("std");
const flare = @import("flare");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get home directory for user config
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
        std.debug.print("Could not determine home directory\\n", .{});
        return;
    };
    defer allocator.free(home);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/.myapp/config.json", .{home});
    defer allocator.free(config_path);

    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = config_path, .required = false },
        },
        .env = .{ .prefix = "MYAPP", .separator = "_" },
    });
    defer config.deinit();

    // Set sensible defaults
    try config.setDefault("preferences.color_output", flare.Value{ .bool_value = true });
    try config.setDefault("preferences.verbose", flare.Value{ .bool_value = false });
    try config.setDefault("preferences.default_format", flare.Value{ .string_value = "json" });
    try config.setDefault("api.timeout", flare.Value{ .int_value = 30 });
    try config.setDefault("api.retries", flare.Value{ .int_value = 3 });

    // Load configuration
    const user_name = try config.getString("user.name", "Unknown User");
    const user_email = try config.getString("user.email", "");

    const color_output = try config.getBool("preferences.color_output", true);
    const verbose = try config.getBool("preferences.verbose", false);
    const format = try config.getString("preferences.default_format", "json");
    const editor = try config.getString("preferences.editor", "nano");

    const api_url = try config.getString("api.base_url", "https://api.example.com");
    const api_timeout = try config.getInt("api.timeout", 30);

    // Display configuration
    std.debug.print("User: {s}", .{user_name});
    if (user_email.len > 0) {
        std.debug.print(" <{s}>", .{user_email});
    }
    std.debug.print("\\n", .{});

    std.debug.print("Preferences:\\n", .{});
    std.debug.print("  Color output: {}\\n", .{color_output});
    std.debug.print("  Verbose: {}\\n", .{verbose});
    std.debug.print("  Default format: {s}\\n", .{format});
    std.debug.print("  Editor: {s}\\n", .{editor});

    std.debug.print("API: {s} (timeout: {d}s)\\n", .{ api_url, api_timeout });
}
```

## Docker Configuration

Configuration for a containerized application.

### Docker Compose

```yaml
version: '3.8'
services:
  app:
    build: .
    environment:
      - APP__DATABASE__HOST=postgres
      - APP__DATABASE__USER=appuser
      - APP__DATABASE__PASSWORD=secret
      - APP__REDIS__HOST=redis
      - APP__LOG__LEVEL=info
      - APP__ENVIRONMENT=production
    depends_on:
      - postgres
      - redis
    ports:
      - "8080:8080"

  postgres:
    image: postgres:13
    environment:
      - POSTGRES_DB=myapp
      - POSTGRES_USER=appuser
      - POSTGRES_PASSWORD=secret

  redis:
    image: redis:alpine
```

### Application Configuration

```zig
const std = @import("std");
const flare = @import("flare");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = "/app/config/default.json", .required = false },
            .{ .path = "/app/config/production.json", .required = false },
        },
        .env = .{ .prefix = "APP", .separator = "__" },
    });
    defer config.deinit();

    // Container-friendly defaults
    try config.setDefault("server.host", flare.Value{ .string_value = "0.0.0.0" });
    try config.setDefault("server.port", flare.Value{ .int_value = 8080 });
    try config.setDefault("log.level", flare.Value{ .string_value = "info" });

    const environment = try config.getString("environment", "development");
    const db_host = try config.getString("database.host", "localhost");
    const redis_host = try config.getString("redis.host", "localhost");
    const log_level = try config.getString("log.level", "info");

    std.debug.print("Environment: {s}\\n", .{environment});
    std.debug.print("Database: {s}\\n", .{db_host});
    std.debug.print("Redis: {s}\\n", .{redis_host});
    std.debug.print("Log level: {s}\\n", .{log_level});

    // Application startup...
}
```

## Configuration Validation Example

Advanced validation with custom error messages.

```zig
const std = @import("std");
const flare = @import("flare");

const ValidationError = error{
    InvalidPort,
    InvalidLogLevel,
    MissingSecret,
};

fn validateConfig(config: *flare.Config) !void {
    // Check required keys first
    const required = [_][]const u8{
        "server.port",
        "database.host",
        "api.key",
    };
    try config.validateRequired(&required);

    // Custom validation
    const port = try config.getInt("server.port", 0);
    if (port < 1 or port > 65535) {
        std.debug.print("Error: server.port must be between 1 and 65535, got {d}\\n", .{port});
        return ValidationError.InvalidPort;
    }

    const log_level = try config.getString("log.level", "info");
    const valid_levels = [_][]const u8{ "debug", "info", "warn", "error" };
    var level_valid = false;
    for (valid_levels) |level| {
        if (std.mem.eql(u8, log_level, level)) {
            level_valid = true;
            break;
        }
    }
    if (!level_valid) {
        std.debug.print("Error: log.level must be one of: debug, info, warn, error\\n", .{});
        return ValidationError.InvalidLogLevel;
    }

    const api_key = try config.getString("api.key", "");
    if (api_key.len < 32) {
        std.debug.print("Error: api.key must be at least 32 characters\\n", .{});
        return ValidationError.MissingSecret;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = "config.json", .required = true },
        },
        .env = .{ .prefix = "APP", .separator = "__" },
    });
    defer config.deinit();

    validateConfig(&config) catch |err| {
        std.debug.print("Configuration validation failed: {}\\n", .{err});
        std.process.exit(1);
    };

    std.debug.print("Configuration validated successfully!\\n", .{});
}
```

These examples demonstrate the flexibility and power of Flare for various application types and deployment scenarios.