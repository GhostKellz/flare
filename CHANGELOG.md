# Changelog

All notable changes to Flare will be documented in this file.

## [0.2.3] - 2026-07-11

### Added
- **Strict-mode conflict diagnostics** - `LoadOptions.strict` / `setStrict()` records cross-source type conflicts (e.g. a key that is an int in a file but a string from the environment). Inspect via `hasConflicts()` / `getConflicts()`.
- **Schema string constraints** - `pattern` (glob, `*`/`?`) is now enforced instead of silently ignored, and a new `choices` constraint validates enum-style string values. Backed by a `globMatch` helper.
- **Richer validation errors** - `ValidationError` now carries the offending `actual` value and its source `origin`, so messages read like `Value out of range at 'db.port' (got 70000, from command-line flag --port)`.
- **`flare validate` / `flare lint <file>...` CLI** - parses each config file and reports per-file status with TOML line/column diagnostics. Scriptable exit codes: `0` all valid, `1` any file invalid, `2` usage error. The no-argument demo is preserved.
- **Round-trip tests** - TOML `parse→stringify→parse` (scalars, nested tables, arrays) and `TOML→JSON` re-validated through `std.json`.

### Changed
- **Hot reload preserves last-known-good config.** A failed reload (invalid syntax, deleted required file) no longer wipes the running config: new state is built in a staging arena and swapped in only on success. `lastReloadError()` exposes the failure.
- **Reload debounce** - `setReloadDebounce()` coalesces rapid file changes; `checkAndReload()` commits watcher mtimes and fires callbacks only after a successful reload.

### Docs
- `docs/sources.md` documents intentional non-goals: YAML is out of scope, JSON comments/trailing commas are rejected, and duplicate keys are errors rather than last-wins.

### Removed
- Dead `src/toml.zig` (legacy; the real engine is `toml_lexer` + `toml_parser` + `toml_value`) and stray root build artifacts (`test_arraylist*`, `test_env`).

## [0.2.2] - 2026-06-14

### Added
- **Struct-to-TOML serialization** - `serialize(T, allocator, value)` converts a Zig struct to a `TomlTable`, and `toTomlString(T, allocator, value)` produces a TOML string directly. Inverse of `parseInto`/`deserialize`; null optional fields are omitted.
- **`saveToFile()` / `saveToFileWithOptions()`** - serialize a `TomlTable` to TOML text and write it to disk.

### Changed
- Updated build system and source for Zig `0.17.0-dev.836` (`b.args` → `RunStep.addPassthruArgs()`; `std.builtin.Type.Struct` field reflection now uses parallel `field_names`/`field_types`/`field_attrs` arrays).
- Bumped `minimum_zig_version` to `0.17.0-dev.836+e357134f0`.

### Performance
- Strict-mode schema validation (`TomlSchema.validate`) now builds a known-field set once for O(n) unknown-field detection instead of an O(n×m) linear scan.

### New Files
- `src/serialize.zig` - Comptime struct-to-TOML serialization.

---

## [0.2.0] - 2026-04-21

### Added
- Full TOML 1.0 parser with lexer + parser pipeline
- TomlValue, TomlTable, TomlArray native types
- Datetime, Date, Time types with RFC 3339 formatting and nanosecond precision
- Struct deserialization with `parseInto(T, source)`
- TOML stringify with `stringify()` and `stringifyWithOptions()`
- FormatOptions for output formatting (indent, sort_keys, blank_lines)
- Schema generation from Zig types with `schemaFrom(T)`
- SchemaBuilder pattern for declarative schema creation
- Constraint union (min_value, max_value, min_length, max_length, one_of, custom)
- TomlSchema for validating TomlTables
- Conversion functions between TomlValue and flare's Value
- Comprehensive TOML 1.0 integration tests
- Optional field deserialization (missing `?T` fields become `null`)
- Fractional seconds preservation in datetime stringify
- Base-prefixed integers (0x hex, 0o octal, 0b binary)
- Unicode escape decoding in strings (\uXXXX and \UXXXXXXXX)
- Schema.deinit() for proper cleanup of allocated schema trees
- Dual representation in config loaders (both flattened keys AND nested map_values)
- Public `parseCliValue()` function for parsing CLI-style string values
- **Parse diagnostics API** - `parseTomlWithContext()` returns `ParseResult` with `ErrorContext` (line, column, source_line, message, suggestion)
- **TOML-to-JSON conversion** - `toJSON()` and `toJSONPretty()` for converting TOML tables to JSON strings
- **TOML helper methods on TomlTable** - typed accessors (`getString`, `getInt`, `getBool`, `getFloat`, `getTable`, `getArray`, `getDatetime`, `getDate`, `getTime`) and dotted path access (`getPath`, `getPathString`, `getPathInt`, `getPathBool`)
- **Diff/merge utilities** - `diff()` compares two TOML tables (returns added/removed/modified), `merge()` combines tables with overlay semantics
- **Flash bridge nested JSON flattening** - CLI flag values containing JSON objects/arrays are recursively flattened into dotted keys

### Changed
- **TOML loading now uses new TOML 1.0 parser** (previously used basic parser)
- `getValueByPath()` now uses stack buffer instead of arena allocation (performance fix)
- `reload()` now properly resets arena to prevent unbounded memory growth
- `reload()` preserves defaults across reloads
- Updated to Zig 0.17.0-dev with `std.process.Init` main signature
- DiffResult now owns cloned values (safe to use after source tables freed)
- 109 tests (up from 77 in previous iteration)

### Fixed
- Memory leak in `getValueByPath()` - no longer allocates on every dotted key read
- Memory growth in `reload()` - arena now properly reset between reloads
- Defaults preserved during hot reload
- Optional struct fields now deserialize to `null` instead of MissingField error
- Fractional seconds (nanoseconds) now preserved in datetime/time stringify
- `getMap()` now works on loaded config (dual representation fix)
- Schema validation works on nested objects loaded from files
- Flash bridge `parseCliValue()` reference and `deinit()` call fixes
- DiffResult ownership - values are deep-cloned, safe after source table deallocation

### Deprecated
- `src/toml.zig` - Legacy basic TOML parser, will be removed in v0.3.0

### New Files
- `src/toml_value.zig` - Native TOML types with full TOML 1.0 support
- `src/toml_lexer.zig` - Full TOML 1.0 lexer with escape sequences
- `src/toml_parser.zig` - Full TOML 1.0 parser with public error context
- `src/deserialize.zig` - Comptime struct deserialization
- `src/stringify.zig` - TOML output with formatting options
- `src/schema_gen.zig` - Schema generation from Zig types
- `src/convert.zig` - TOML-to-JSON conversion utilities
- `src/diff.zig` - TOML table diff and merge utilities

---

## [0.1.3] - 2026-04-19

### Changed
- Updated to Zig 0.16.0-dev.2193 API compatibility

---

## [0.1.2] - Previous

### Features
- TOML and JSON parsing
- Environment variable loading
- CLI argument parsing
- Hot reload with file watching
- Schema validation
- Flash CLI integration
