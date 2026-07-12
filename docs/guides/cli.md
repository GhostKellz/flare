# CLI: validate & lint

Flare ships a small command-line tool that validates configuration files. It
parses each file with the same engine your application uses at load time and
reports per-file diagnostics, making it suitable for CI gates and pre-commit
hooks.

## Building the CLI

The CLI is the default executable target:

```bash
zig build              # produces the `flare` binary in zig-out/bin
zig build run          # runs the demonstration (no arguments)
```

## Usage

```
Usage:
  flare                       Run the demonstration.
  flare validate <file>...    Parse each config file and report errors.
  flare lint <file>...        Alias for validate.
  flare help                  Show this help.
```

`validate` and `lint` are aliases. Format is chosen by extension: `.toml` is
parsed as TOML 1.0, everything else (including `.json`) is parsed as JSON.

## Examples

Validate a single TOML file:

```bash
$ flare validate config.toml
config.toml: OK
All 1 file(s) valid.
```

Validate several files at once:

```bash
$ flare lint config.toml config.json settings.toml
config.toml: OK
config.json: OK
settings.toml: OK
All 3 file(s) valid.
```

A malformed TOML file reports line and column, plus a hint when the parser can
offer one:

```bash
$ flare validate broken.toml
broken.toml:4:9: unexpected token
    hint: expected '=' after key
1 of 1 file(s) failed validation.
```

Invalid JSON is reported through `std.json`:

```bash
$ flare validate bad.json
bad.json: invalid JSON (SyntaxError)
1 of 1 file(s) failed validation.
```

## Exit codes

The exit status is scriptable so the tool can gate automation:

| Code | Meaning |
| --- | --- |
| `0` | All files parsed successfully. |
| `1` | At least one file failed to parse. |
| `2` | Usage error (unknown command, or no files given to `validate`/`lint`). |

Example CI usage:

```bash
flare validate config/*.toml || exit 1
```

## See also

- [Configuration Sources](../getting-started/configuration-sources.md) - the formats the CLI understands.
- [Architecture](../internals/architecture.md#diagnostics) - how TOML diagnostics are produced.
