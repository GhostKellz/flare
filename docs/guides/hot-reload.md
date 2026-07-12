# Hot Reload

Flare can watch configuration files and reload them without restarting your
application. Reloads are **transactional**: a failed reload (bad syntax, a
deleted required file) never wipes the running config — the last-known-good
state stays live and the error is exposed for inspection.

## Enabling hot reload

```zig
const std = @import("std");
const flare = @import("flare");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = try flare.load(allocator, .{
        .files = &[_]flare.FileSource{
            .{ .path = "config.toml", .format = .toml },
        },
    });
    defer config.deinit();

    // Optional callback fired after a successful reload.
    const onReload = struct {
        fn cb(cfg: *flare.Config) void {
            _ = cfg;
            std.debug.print("config reloaded\n", .{});
        }
    }.cb;

    try config.enableHotReload(onReload);

    while (true) {
        const changed = try config.checkAndReload();
        if (changed) {
            const port = try config.getInt("server.port", 8080);
            std.debug.print("now serving on :{d}\n", .{port});
        }
        std.Thread.sleep(1_000_000_000); // poll every second
    }
}
```

`enableHotReload(callback)` initializes watchers for every file source. Pass
`null` for the callback if you only need to poll the return value of
`checkAndReload()`.

## Last-known-good on failure

`reload()` builds the next state in a fresh, independent arena and swaps it in
**only on success**. If any step fails — a required file goes missing, a file no
longer parses, an env/CLI error — the staging arena is discarded and the live
config is left exactly as it was.

Inspect the failure with `lastReloadError()`:

```zig
const changed = config.checkAndReload() catch false;
if (config.lastReloadError()) |err| {
    std.debug.print("reload failed, keeping previous config: {}\n", .{err});
}
```

The change callback is **not** fired on a failed reload, so downstream state is
never updated with a half-built config. Defaults are carried forward across
reloads.

## Debouncing rapid changes

Editors and deploy tooling often write a file several times in quick succession.
`setReloadDebounce(ns)` makes `checkAndReload()` wait for a file to be quiescent
for `ns` nanoseconds before acting, coalescing a burst of writes into a single
reload:

```zig
config.setReloadDebounce(200 * std.time.ns_per_ms); // 200ms quiet window
```

With debouncing, `checkAndReload()` commits watcher mtimes and fires the
callback only after a successful, settled reload. Set `0` to disable debouncing
and reload immediately on the first detected change.

## Generations

Each successful reload bumps a generation counter (starting at `0`). The
generation is recorded on every value's [origin](origin-and-precedence.md), so
you can tell whether a value came from the initial load or a later reload:

```zig
const line = try config.explain(allocator, "server.port");
defer allocator.free(line);
// server.port <- file (config.toml), generation 3
```

## See also

- [Origin Tracking & Precedence](origin-and-precedence.md) - generations and value origins.
- [Architecture](../internals/architecture.md) - the reload state machine.
- [API Reference](../reference/api.md) - `enableHotReload`, `checkAndReload`, `reload`, `setReloadDebounce`, `lastReloadError`.
