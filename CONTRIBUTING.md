# Contributing to Flare

Thanks for your interest in improving Flare. This guide covers the workflow,
the checks your change must pass, and the conventions we follow.

## Prerequisites

- A recent Zig `0.17.0-dev` toolchain. The minimum is pinned in
  [`build.zig.zon`](build.zig.zon) (`minimum_zig_version`); older releases may
  work but are not tested.

## Development workflow

1. Fork and branch from `main`.
2. Make your change, keeping it focused — the smallest change that solves the
   problem.
3. Add or update tests alongside the code. Tests live next to the modules they
   cover in `src/` (e.g. `integration_tests.zig`, `origin_tests.zig`,
   `hot_reload_tests.zig`).
4. Run the release gate locally (see below) until it is green.
5. Update [`CHANGELOG.md`](CHANGELOG.md) under an appropriate heading and the
   docs in [`docs/`](docs/README.md) if behavior changed.
6. Open a pull request describing the change and its motivation.

## The release gate

Every change must pass `zig build verify` before it can be merged. This single
step runs the full gate:

```bash
zig build verify
```

`verify` is defined in [`build.zig`](build.zig) and depends on:

- **build** - the library installs cleanly.
- **test** - `zig build test` runs the whole test suite.
- **examples** - the programs under `examples/` compile (`zig build examples`).
- **format** - `zig fmt --check` over `src/` and `examples/`.

You can run the pieces individually while iterating:

```bash
zig build test        # tests only
zig build examples    # compile the examples
zig fmt src examples  # auto-format before committing
```

## Code style

- Follow the existing naming and structure; no `file_v2` / `v1` suffixes.
- Comments explain **why**, not **what**. Do not embed version numbers in
  comments or docs — point at the source of truth instead.
- Keep changes minimal and avoid unrelated refactors in the same PR.
- Prefer the smallest allocation/ownership story that works; values loaded into
  a `Config` are owned by its arena.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/): `feat:`,
`fix:`, `docs:`, `refactor:`, `test:`, `chore:`, etc. Keep the subject
imperative and concise; explain the "why" in the body when it is not obvious.

## Documentation

The documentation index is [`docs/README.md`](docs/README.md). Add new docs as
`lowercase-hyphen.md` files under the appropriate folder
(`getting-started/`, `guides/`, `reference/`, `internals/`) and link them from
the index. Diagrams should reflect the real code.

## Security

Do not open public issues for suspected vulnerabilities. Follow the process in
[`SECURITY.md`](SECURITY.md).
