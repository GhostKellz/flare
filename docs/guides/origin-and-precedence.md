# Origin Tracking & Precedence

Flare records **where every configuration value came from**. After a load you
can ask which layer won for any key — a default, a specific file, an environment
variable, a CLI flag, or a programmatic set — and get a human-readable
explanation. This is Flare's answer to "why is this value what it is?".

## Precedence order

Sources are applied lowest-to-highest, so later layers override earlier ones for
the same key:

1. **Defaults** (lowest) - `setDefault()` or `LoadOptions.defaults`.
2. **Files** - in the order listed in `LoadOptions.files`; later files override
   earlier ones.
3. **Environment variables**.
4. **CLI flags** (highest).

Reads resolve `data` first and fall back to `defaults`, so a value set by any
non-default layer always beats a default.

## Inspecting a value's origin

Every resolved key has a `ValueOrigin`:

```zig
pub const OriginKind = enum { default, file, env, cli, set };

pub const ValueOrigin = struct {
    kind: OriginKind,
    detail: ?[]const u8 = null, // file path, env var name, or --flag
    generation: u32 = 0,        // reload counter; 0 on first load
};
```

### `getSource()`

Returns the origin of a key's resolved value (mirroring the same
data-then-defaults precedence as reads), or `null` if the key is unset:

```zig
if (config.getSource("database.host")) |origin| {
    switch (origin.kind) {
        .file => std.debug.print("from file: {s}\n", .{origin.detail.?}),
        .env => std.debug.print("from env var: {s}\n", .{origin.detail.?}),
        .cli => std.debug.print("from CLI flag: {s}\n", .{origin.detail.?}),
        .default => std.debug.print("using default\n", .{}),
        .set => std.debug.print("set programmatically\n", .{}),
    }
}
```

### `explain()`

Formats a ready-to-print line. The caller owns the returned slice:

```zig
const line = try config.explain(allocator, "database.host");
defer allocator.free(line);
std.debug.print("{s}\n", .{line});
// database.host <- file (config.toml), generation 0
```

The `generation` starts at `0` and increments on each successful hot reload, so
you can tell whether a value came from the initial load or a later reload.

## Strict mode: cross-source conflict diagnostics

By default Flare silently lets a higher-precedence layer override a
lower-precedence one — that is the point of precedence. **Strict mode** adds a
diagnostic when an override also *changes the value's type* across sources
(often a sign of a misconfiguration, e.g. a port that is an int in a file but a
string in the environment).

Enable it before loading, or toggle it on an existing config:

```zig
var config = try flare.load(allocator, .{
    .files = &[_]flare.FileSource{ .{ .path = "config.toml" } },
    .env = .{ .prefix = "APP", .separator = "__", .env_map = &env_map },
    .strict = true,
});
defer config.deinit();

if (config.hasConflicts()) {
    for (config.getConflicts()) |c| {
        std.debug.print(
            "conflict at '{s}': {s} ({s}) overridden by {s} ({s})\n",
            .{ c.key, @tagName(c.previous_kind), c.previous_type, @tagName(c.new_kind), c.new_type },
        );
    }
}
```

```zig
pub const ValueConflict = struct {
    key: []const u8,
    previous_kind: OriginKind,
    previous_type: []const u8,
    new_kind: OriginKind,
    new_type: []const u8,
};
```

Strict mode is **off by default** and records **no** conflicts when disabled.
Conflicts are informational: the higher-precedence value still wins. Use them in
CI or startup checks to fail loudly on suspicious overrides.

## See also

- [Configuration Sources](../getting-started/configuration-sources.md) - the source types and multi-file layouts.
- [Architecture](../internals/architecture.md) - how the origins sidecar is populated.
- [API Reference](../reference/api.md) - full signatures.
