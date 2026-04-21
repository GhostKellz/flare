


# Flare - Viper for Zig

**What viper is to Cobra in Go, Flare is to Flash in Zig**

Flare is a configuration management library for Zig that complements the Flash CLI framework. Flash CLI framework can be found here: https://github.com/ghostkellz/flare

## 🎉 **STATUS: MVP v0.1.0 COMPLETED!**

**✅ All core MVP features implemented and tested:**
- Arena-based Config type with proper memory management
- JSON file loading with nested object support
- Environment variable loading with prefix + key mapping
- Typed getters with smart type coercion (getBool, getInt, getFloat, getString)
- Path addressing with dotted notation (database.host, server.port)
- Comprehensive validation and error handling
- Complete documentation and examples
- Working demo application

## Overview

- **C Libraries Replaced:** libconfig, YAML/TOML/JSON parsers
- **Scope:** Hierarchical config, validation, hot reloading, environment merging
- **Features:** Schema validation, type safety, configuration drift detection
- **Impact:** ⚙️ Lower priority — important eventually, but not critical path
## 1. MVP (v0.1.0) ✅ **COMPLETED**

**Goal:** Single-binary apps can load config from file + env + CLI and read typed values.

### Core Features

- ✅ **Core type:** `flare.Config`
- ✅ **Immutable snapshot** with internal arena allocator
- ✅ **Layers & precedence:** ENV > file(s) > defaults (CLI planned for v0.2)
- ✅ **Typed getters:** `getBool`, `getInt`, `getFloat`, `getString` (getList, getMap, getEnum planned for v0.2)
- ✅ **Path addressing:** dotted keys `db.host` (arrays `servers[0]` planned for v0.2)
- ✅ **Defaults API:** `setDefault("db.port", 5432)`

### Loaders

- ✅ **File:** JSON (std) - TOML, YAML planned for v0.2
- ✅ **ENV:** prefix + key mapping (e.g. `APP__DB__HOST` → `db.host`)
- ⏳ **CLI:** integration hook for Flash (planned for v0.2)

### Merge Semantics

- ✅ **Override semantics:** ENV > files > defaults
- ✅ **Deterministic precedence** with clear documentation

### Minimal Validation

- ✅ **Required keys:** `validateRequired()` method
- ✅ **Type checks:** Built into typed getters with coercion
- ✅ **Error model:** rich `error{ ParseError, MissingKey, TypeMismatch, Io, Validation, OutOfMemory, InvalidPath }`

### Example Usage ✅

```zig
const flare = @import("flare");

var cfg = try flare.load(allocator, .{
    .files = &[_]flare.FileSource{
        .{ .path = "config.json" },
    },
    .env = .{ .prefix = "APP", .separator = "__" },
    // CLI support coming in v0.2
});
defer cfg.deinit();

const port = try cfg.getInt("http.port", 8080);
const host = try cfg.getString("database.host", "localhost");
const debug = try cfg.getBool("debug", false);
```

## 2. v0.2: Schema & Validation

### Declarative Schema

- Types, ranges, regex, one-of enums, required/optional
- Coercions (string→int/bool/duration)
- Human-friendly error reporting (key path + reason + suggestion)
- `validate(cfg, schema)` returns report object

```zig
const Schema = flare.schema;
const schema = Schema.root(.{
  .http = Schema.table(.{
    .port = Schema.port().default(8080),
    .mode = Schema.enumeration(&.{ "dev","prod" }).default("dev"),
  }),
});
try flare.validate(cfg, schema);
```

## 3. v0.3: Live Reload & Watch

- File watchers (cross-platform; poll fallback)
- On-change callback with diff of key paths
- Atomic replace with new snapshot
- Debounce + coalesce events

## 4. v0.4: Advanced Data Types

- Durations (`1s`, `500ms`), sizes (`64MiB`), addrs (`host:port`), URLs
- Secret wrapper type (redacted in logs)
- Map/list interpolation: `${env:HOME}`, `${file:/path}`, `${ref:other.key}`

## 5. v0.5: Pluggable Sources

### Source API
- `Source.init/read/watch/close`

### Remote Providers (feature-gated)
- Consul KV
- etcd
- S3/GCS object (poll)
- Vault/KMS decrypt filter (optional)

## 6. Flash Integration (first-class)

- `flash.plugin.flare`: bind flags ↔ config paths
- Auto-generated `--config`, `--print-config`, `--set key=val`
- Help section showing effective precedence
- Shell completion for known keys (via Flash completion)

```zig
const flash = @import("flash");
const flare = @import("flare");

pub fn main() !void {
    var app = flash.app("mytool")
        .plugin(flare.flashPlugin(.{
            .env_prefix = "MY",
            .keys = &.{
                .{ .flag="--http-port", .path="http.port", .type=.int, .default="8080" },
                .{ .flag="--mode",      .path="http.mode", .type=.enum, .choices=&.{ "dev","prod" } },
            },
        }))
        .cmd(flash.cmd("serve").run(run));
    try app.run();
}
```

## 7. Performance & Footprint

- Benchmarks vs naive std-only approach (load + merge + get)
- JSON fast-path using streaming parser
- Arena reuse across reloads
- Zero-copy slices for strings when safe

## 8. Testing Matrix

- Unit tests: loaders, merge rules, getters, schema
- Property tests: round-trip encode/decode (where applicable)
- Cross-platform integration tests (temp files + env)
- Fuzz harness for file parsers
- Snapshot tests for error messages

## 9. Docs & Examples

- `README.md` with quick start + Flash example
- `docs/architecture.md` (layers, precedence, snapshot model)

### Recipes
- Multi-file includes (`config.{base,dev,local}.toml`)
- Secrets & redaction
- Hot-reload web server
- Remote source example (Consul)
- API reference (zdox or zdoc)

## 10. Security Considerations

- Redact secret types from logs and panics
- Disable interpolation providers by default (opt-in)
- Strict file permissions check (warn on world-readable secrets)
- Path traversal safeguards for includes

## 11. Nice-to-Have (post-0.5)

- Generated config docs from schema (Markdown/HTML)
- Type-safe codegen from schema to Zig struct
- Bidirectional: dump effective config to file
- Remote change notifications to running Flash app (IPC hook)
- WASM build (for RIPPLE) with file/ENV shims

## 12. Milestones & Releases

- ✅ **v0.1.0 (MVP):** files + env + typed getters, validation, arena allocator **COMPLETED**
- ⏳ **v0.2.0:** schema + validation, CLI integration, TOML/YAML support
- ⏳ **v0.3.0:** hot reload & watch functionality
- ⏳ **v0.4.0:** advanced types + interpolation, list/map support
- ⏳ **v0.5.0:** plugins/remote providers, array indexing
- ⏳ **v1.0.0:** API freeze, full docs, performance targets met

## 13. Non-Goals (for now)

- ❌ Templating engine
- ❌ Full i18n of errors (just clear English)
- ❌ Replacing Flash—Flare complements Flash

## 14. Considerations for the Future 
When a database does make sense (optional providers)
### Zqlite as config backend (maybe)

```bash
zig fetch --save https://github.com/ghostkellz/zqlite/archive/refs/heads/main.tar.gz
```

Can also be found via fetching the web at github.com/ghostkellz/zqlite
**This is OPTIONAL after we get through most milestones!!!**

Use zqlite only if you need one of these:

- Centralized config store for multiple processes/services on one host
- Versioning/history of config with rollback
- Atomic multi-key updates and transactions (e.g., update 20 keys or none)
- Caching/merging many sources with fast indexed queries
- Encrypted at-rest secrets with KMS integration (store ciphertext + metadata)
- Telemetry of effective config (audit who/what changed)

### Suggested approach

Keep Flare core file/env/CLI-only. Offer DB as an optional provider:

```
flare
 ├─ core/           # no DB
 ├─ sources/
 │   ├─ file.zig
 │   ├─ env.zig
 │   ├─ cli.zig
 │   └─ zqlite.zig  # optional, behind feature flag
 └─ examples/
```


### Provider interface (sketch)

```zig
pub const Source = struct {
    pub const VTable = struct {
        read: fn (self: *anyopaque, alloc: *Allocator) !ConfigDoc,
        watch: ?fn (self: *anyopaque, cb: ChangeFn) !void,
        deinit: fn (self: *anyopaque) void,
    };
    ptr: *anyopaque,
    vt: *const VTable,
};
```


### Zqlite provider idea

```sql
-- Table schema
CREATE TABLE config(
    k TEXT PRIMARY KEY,
    v BLOB,
    t TEXT, -- type
    ver INTEGER,
    ts INTEGER
);

-- Optional tables
CREATE TABLE history(...);
CREATE TABLE secrets(k, ciphertext, meta);

-- Migration
PRAGMA journal_mode=WAL; -- for hot-reload friendly reads

-- Indices
CREATE INDEX idx_k ON config(k);
CREATE INDEX idx_ts ON config(ts DESC);
CREATE INDEX idx_ver ON config(ver DESC);
```

**Pros:** durability, atomicity, audit trail
**Cons:** more moving parts, not WASM-friendly (RIPPLE won't use it natively), larger attack surface

### Recommendation

1. Ship v0.1–0.3 of Flare without any DB
2. Add a flare-source-zqlite plugin later if/when you need shared, versioned config or secret storage on servers
3. For RIPPLE/WASM, stick to file (virtual), env shims, and in-memory defaults—no DB
