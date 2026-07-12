#!/usr/bin/env bash
# Release consumer smoke test.
#
# Proves that Flare is consumable as a real dependency through its packaging
# surface (build.zig.zon name/version/paths + the exposed `flare` module) --
# not just as an in-repo module. It builds a throwaway consumer package that
# pulls Flare in via `zig fetch --save`, compiles against the public API, and
# runs it.
#
# Usage: scripts/consumer_smoke.sh
# Exit code is non-zero if packaging or the public API regresses.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d -p "${repo_root}/.scratch" consumer_smoke.XXXXXX)"
trap 'rm -rf "${work}"' EXIT

# 1. Stage a pruned copy of the package (the release-archive equivalent), placed
#    outside the repo tree so `zig fetch` does not recurse into build caches.
pkg="${work}/flare-pkg"
mkdir -p "${pkg}"
cp "${repo_root}/build.zig" "${repo_root}/build.zig.zon" "${pkg}/"
cp -r "${repo_root}/src" "${pkg}/src"

# 2. Scaffold the consumer package.
consumer="${work}/consumer"
mkdir -p "${consumer}/src"

cat >"${consumer}/src/main.zig" <<'ZIG'
const std = @import("std");
const flare = @import("flare");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var config = try flare.Config.init(allocator);
    defer config.deinit();

    try config.setValue("service.name", .{ .string_value = "consumer-smoke" });
    const name = try config.getString("service.name", null);
    if (!std.mem.eql(u8, name, "consumer-smoke")) return error.SmokeFailed;
    std.debug.print("consumer smoke ok: {s}\n", .{name});
}
ZIG

cat >"${consumer}/build.zig" <<'ZIG'
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const flare_dep = b.dependency("flare", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "consumer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "flare", .module = flare_dep.module("flare") },
            },
        }),
    });
    b.installArtifact(exe);
}
ZIG

# Minimal manifest; the flare dependency is added by `zig fetch --save` below.
cat >"${consumer}/build.zig.zon" <<'ZIG'
.{
    .name = .consumer,
    .version = "0.0.0",
    .fingerprint = 0x705b3727e5f52cc4,
    .minimum_zig_version = "0.17.0-dev.836+e357134f0",
    .dependencies = .{},
    .paths = .{ "build.zig", "build.zig.zon", "src" },
}
ZIG

# 3. Fetch the dependency, build, and run.
cd "${consumer}"
zig fetch --save=flare "${pkg}"
zig build
./zig-out/bin/consumer

echo "consumer smoke test: PASS"
