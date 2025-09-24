# Flash CLI Integration Guide

This guide shows how to integrate Flare configuration management with Flash CLI framework to create powerful, configuration-aware CLI applications.

## Overview

Flare + Flash integration provides:

- **Automatic Configuration Loading** - Config files, environment variables, and CLI flags merged seamlessly
- **Schema Validation** - Define and validate configuration structure
- **Precedence Handling** - CLI flags override environment variables override config files
- **Type Safety** - Full type checking and conversion
- **Zero Boilerplate** - Minimal setup required

## Basic Integration

### Step 1: Set Up Dependencies

Add both Flare and Flash to your `build.zig`:

```zig
// Add dependencies
const flash_dep = b.dependency("flash", .{
    .target = target,
    .optimize = optimize,
});
const flare_dep = b.dependency("flare", .{
    .target = target,
    .optimize = optimize,
});

// Add imports to your executable
exe.root_module.addImport("flash", flash_dep.module("flash"));
exe.root_module.addImport("flare", flare_dep.module("flare"));
```

### Step 2: Create a Simple CLI with Config

```zig
const std = @import("std");
const flash = @import("flash");
const flare = @import("flare");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Define CLI with configuration
    const cli = flash.CLI(.{
        .name = "myapp",
        .version = "1.0.0",
        .about = "My awesome CLI with configuration",
    });

    // Set up configuration options
    const config_options = flare.flash.FlashConfigOptions{
        .config_files = &[_]flare.FileSource{
            .{ .path = "config.toml", .required = false },
            .{ .path = "~/.myapp/config.toml", .required = false },
        },
        .env_source = .{ .prefix = "MYAPP", .separator = "_" },
    };

    // Create a command with configuration
    const connect_cmd = flare.flash.createConfigCommand(
        "connect",
        "Connect to database with configuration",
        config_options,
        &[_]flare.flash.FlagLink{
            .{ .flag_name = "host", .config_key = "database.host", .short = "h" },
            .{ .flag_name = "port", .config_key = "database.port", .short = "p" },
            .{ .flag_name = "ssl", .config_key = "database.ssl" },
        },
        connectHandler,
    );

    // Run the CLI
    try cli.run(allocator);
}

fn connectHandler(ctx: flare.flash.CommandContext) !void {
    // Configuration is automatically loaded and available
    const host = try ctx.config.getString("database.host", "localhost");
    const port = try ctx.config.getInt("database.port", 5432);
    const ssl = try ctx.config.getBool("database.ssl", false);

    std.debug.print("Connecting to database:\n");
    std.debug.print("  Host: {s}\n", .{host});
    std.debug.print("  Port: {d}\n", .{port});
    std.debug.print("  SSL: {}\n", .{ssl});

    // Your connection logic here...
}
```

### Step 3: Create Configuration Files

Create `config.toml`:

```toml
[database]
host = "localhost"
port = 5432
ssl = true
timeout = 30

[logging]
level = "info"
file = "/var/log/myapp.log"
```

### Step 4: Use Your CLI

```bash
# Uses config file values
./myapp connect

# Environment variables override config file
export MYAPP_DATABASE_HOST=prod.example.com
./myapp connect

# CLI flags have highest precedence
./myapp connect --host=dev.example.com --port=3306 --ssl=false
```

## Advanced Integration

### Schema-Validated Configuration

Define schemas to ensure configuration correctness:

```zig
const std = @import("std");
const flare = @import("flare");

// Define your configuration schema
fn createAppSchema(allocator: std.mem.Allocator) !flare.Schema {
    return flare.Schema.root(allocator, .{
        .database = flare.Schema.object(allocator, .{
            .host = flare.Schema.string(.{})
                .required()
                .withDescription("Database hostname"),
            .port = flare.Schema.int(.{ .min = 1, .max = 65535 })
                .default(flare.Value{ .int_value = 5432 })
                .withDescription("Database port"),
            .ssl = flare.Schema.boolean()
                .default(flare.Value{ .bool_value = true })
                .withDescription("Enable SSL connection"),
            .timeout = flare.Schema.int(.{ .min = 1, .max = 300 })
                .default(flare.Value{ .int_value = 30 }),
        }),
        .logging = flare.Schema.object(allocator, .{
            .level = flare.Schema.string(.{})
                .default(flare.Value{ .string_value = "info" }),
            .file = flare.Schema.string(.{}),
        }),
    });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create schema
    const app_schema = try createAppSchema(allocator);

    // Configure with schema validation
    const config_options = flare.flash.FlashConfigOptions{
        .config_files = &[_]flare.FileSource{
            .{ .path = "config.toml", .required = false },
        },
        .env_source = .{ .prefix = "MYAPP", .separator = "_" },
        .schema = &app_schema,
    };

    const connect_cmd = flare.flash.createConfigCommand(
        "connect",
        "Connect with validated configuration",
        config_options,
        &[_]flare.flash.FlagLink{
            .{ .flag_name = "host", .config_key = "database.host" },
            .{ .flag_name = "port", .config_key = "database.port" },
        },
        validatedConnectHandler,
    );

    // CLI setup and run...
}

fn validatedConnectHandler(ctx: flare.flash.CommandContext) !void {
    // Configuration is already validated against schema
    const host = try ctx.config.getString("database.host", "localhost");
    const port = try ctx.config.getInt("database.port", 5432);
    const ssl = try ctx.config.getBool("database.ssl", true);
    const timeout = try ctx.config.getInt("database.timeout", 30);

    std.debug.print("✅ Configuration validated successfully\n");
    std.debug.print("Connecting to {s}:{d} (SSL: {}, timeout: {d}s)\n",
                    .{ host, port, ssl, timeout });
}
```

### Multi-Command Application

Create a CLI with multiple commands sharing configuration:

```zig
const std = @import("std");
const flash = @import("flash");
const flare = @import("flare");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Shared configuration options
    const config_options = flare.flash.FlashConfigOptions{
        .config_files = &[_]flare.FileSource{
            .{ .path = "config.toml", .required = false },
            .{ .path = "~/.myapp/config.toml", .required = false },
        },
        .env_source = .{ .prefix = "MYAPP", .separator = "_" },
    };

    const cli = flash.CLI(.{
        .name = "dbtools",
        .version = "1.0.0",
        .about = "Database management tools",
        .commands = &.{
            // Database connection command
            flare.flash.createConfigCommand(
                "connect",
                "Connect to database",
                config_options,
                &[_]flare.flash.FlagLink{
                    .{ .flag_name = "host", .config_key = "database.host", .short = "h" },
                    .{ .flag_name = "port", .config_key = "database.port", .short = "p" },
                },
                connectHandler,
            ),

            // Migration command
            flare.flash.createConfigCommand(
                "migrate",
                "Run database migrations",
                config_options,
                &[_]flare.flash.FlagLink{
                    .{ .flag_name = "dry-run", .config_key = "migration.dry_run" },
                    .{ .flag_name = "target", .config_key = "migration.target" },
                },
                migrateHandler,
            ),

            // Backup command
            flare.flash.createConfigCommand(
                "backup",
                "Backup database",
                config_options,
                &[_]flare.flash.FlagLink{
                    .{ .flag_name = "output", .config_key = "backup.output_dir", .short = "o" },
                    .{ .flag_name = "compress", .config_key = "backup.compress" },
                },
                backupHandler,
            ),
        },
    });

    try cli.run(allocator);
}

fn connectHandler(ctx: flare.flash.CommandContext) !void {
    const host = try ctx.config.getString("database.host", "localhost");
    const port = try ctx.config.getInt("database.port", 5432);

    std.debug.print("Connecting to {s}:{d}...\n", .{ host, port });
    // Connection logic
}

fn migrateHandler(ctx: flare.flash.CommandContext) !void {
    const dry_run = try ctx.config.getBool("migration.dry_run", false);
    const target = try ctx.config.getString("migration.target", null) catch null;

    if (dry_run) {
        std.debug.print("🔍 Dry run mode - no changes will be made\n");
    }

    if (target) |t| {
        std.debug.print("Migrating to version: {s}\n", .{t});
    } else {
        std.debug.print("Migrating to latest version\n");
    }
}

fn backupHandler(ctx: flare.flash.CommandContext) !void {
    const output_dir = try ctx.config.getString("backup.output_dir", "/tmp/backups");
    const compress = try ctx.config.getBool("backup.compress", true);

    std.debug.print("Backing up to: {s}\n", .{output_dir});
    std.debug.print("Compression: {}\n", .{compress});
}
```

### Working with Arrays and Complex Data

Handle configuration with arrays and nested objects:

```zig
// config.toml
// [[servers]]
// name = "api-primary"
// url = "https://api1.example.com"
// region = "us-east"
//
// [[servers]]
// name = "api-secondary"
// url = "https://api2.example.com"
// region = "us-west"

fn serverListHandler(ctx: flare.flash.CommandContext) !void {
    // Access array of servers
    const servers = try ctx.config.getArray("servers");

    std.debug.print("Found {d} servers:\n", .{servers.items.len});

    for (servers.items, 0..) |server, i| {
        if (server.map_value.get("name")) |name| {
            if (server.map_value.get("url")) |url| {
                if (server.map_value.get("region")) |region| {
                    std.debug.print("  [{d}] {s}: {s} ({s})\n",
                                    .{ i, name.string_value, url.string_value, region.string_value });
                }
            }
        }
    }

    // Access specific server by index
    const first_server = try ctx.config.getByIndex("servers", 0);
    if (first_server.map_value.get("name")) |name| {
        std.debug.print("Primary server: {s}\n", .{name.string_value});
    }
}
```

## Environment-Specific Configuration

Handle multiple environments (development, staging, production):

```zig
fn createEnvironmentAwareCLI() !void {
    const env = std.process.getEnvVarOwned(allocator, "APP_ENV") catch "development";

    const config_files = switch (std.mem.eql(u8, env, "production")) {
        true => &[_]flare.FileSource{
            .{ .path = "config.toml", .required = true },
            .{ .path = "config.production.toml", .required = true },
        },
        false => &[_]flare.FileSource{
            .{ .path = "config.toml", .required = false },
            .{ .path = "config.development.toml", .required = false },
            .{ .path = "config.local.toml", .required = false },
        },
    };

    const config_options = flare.flash.FlashConfigOptions{
        .config_files = config_files,
        .env_source = .{ .prefix = "APP", .separator = "_" },
    };

    // Use config_options in your commands...
}
```

## Configuration Debugging

Add a config command to inspect current configuration:

```zig
fn configShowHandler(ctx: flare.flash.CommandContext) !void {
    std.debug.print("📋 Current Configuration\n");
    std.debug.print("========================\n\n");

    // Database settings
    std.debug.print("[Database]\n");
    const db_host = try ctx.config.getString("database.host", "not set");
    const db_port = try ctx.config.getInt("database.port", 0);
    const db_ssl = try ctx.config.getBool("database.ssl", false);

    std.debug.print("  host = \"{s}\"\n", .{db_host});
    std.debug.print("  port = {d}\n", .{db_port});
    std.debug.print("  ssl = {}\n\n", .{db_ssl});

    // Logging settings
    std.debug.print("[Logging]\n");
    const log_level = try ctx.config.getString("logging.level", "not set");
    const log_file = try ctx.config.getString("logging.file", "not set");

    std.debug.print("  level = \"{s}\"\n", .{log_level});
    std.debug.print("  file = \"{s}\"\n\n", .{log_file});

    std.debug.print("Total configuration values: {d}\n", .{ctx.config.getCount()});
}

const config_cmd = flare.flash.createConfigCommand(
    "config",
    "Show current configuration",
    config_options,
    &[_]flare.flash.FlagLink{},
    configShowHandler,
);
```

## Best Practices

### 1. Use Schema Validation

Always define schemas for production applications:

```zig
// ❌ Bad - no validation
var config = try flare.load(allocator, options);

// ✅ Good - with validation
const schema = try createAppSchema(allocator);
const options_with_schema = flare.flash.FlashConfigOptions{
    .config_files = config_files,
    .schema = &schema,
};
```

### 2. Provide Sensible Defaults

```zig
// ✅ Always provide defaults for optional settings
const timeout = try ctx.config.getInt("database.timeout", 30);
const log_level = try ctx.config.getString("logging.level", "info");
const workers = try ctx.config.getInt("server.workers", 4);
```

### 3. Handle Missing Required Configuration

```zig
// ✅ Graceful error handling
const api_key = ctx.config.getString("api.key", null) catch |err| switch (err) {
    flare.FlareError.MissingKey => {
        std.debug.print("❌ Error: API key is required but not configured\n");
        std.debug.print("Set it via:\n");
        std.debug.print("  - Config file: api.key = \"your-key\"\n");
        std.debug.print("  - Environment: MYAPP_API_KEY=your-key\n");
        std.debug.print("  - CLI flag: --api-key=your-key\n");
        return;
    },
    else => return err,
};
```

### 4. Configuration File Organization

```toml
# config.toml - base configuration
[database]
host = "localhost"
port = 5432

[logging]
level = "info"

# config.production.toml - production overrides
[database]
host = "prod-db.example.com"
ssl = true

[logging]
level = "warn"
file = "/var/log/app.log"
```

### 5. Use Flag Links Consistently

```zig
// ✅ Consistent naming
&[_]flare.flash.FlagLink{
    .{ .flag_name = "database-host", .config_key = "database.host", .short = "H" },
    .{ .flag_name = "database-port", .config_key = "database.port", .short = "P" },
    .{ .flag_name = "log-level", .config_key = "logging.level", .short = "L" },
}
```

## Common Patterns

### Database CLI Tools

Perfect for database management tools that need connection configuration:

```bash
# Connect with defaults from config file
./dbtools connect

# Override specific settings
./dbtools connect --host=prod-replica.db.com --port=3307

# Run migrations with environment-specific settings
MYAPP_DATABASE_HOST=staging.db.com ./dbtools migrate --dry-run
```

### API Clients

Great for API clients with authentication and endpoint configuration:

```bash
# Use configured API endpoint and auth
./apiclient users list

# Override API endpoint for testing
./apiclient users list --api-endpoint=https://staging-api.com

# Use different auth token
MYAPP_API_TOKEN=dev-token ./apiclient users create --name="Test User"
```

### Deployment Tools

Excellent for deployment and ops tools:

```bash
# Deploy with production config
./deploy --env=production

# Deploy to specific cluster
./deploy --cluster=us-west-2 --replicas=5

# Deploy with config file override
./deploy --config=deploy.staging.toml
```

Flash + Flare integration makes building these kinds of CLI applications straightforward while maintaining flexibility and type safety.