# Changelog

All notable changes to Flare will be documented in this file.

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
