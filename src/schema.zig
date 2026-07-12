//! Schema definition and validation types for Flare configuration
//! Provides declarative configuration structure with validation

const std = @import("std");
const flare = @import("root.zig");

/// Schema validation errors
pub const SchemaError = error{
    MissingRequiredField,
    TypeMismatch,
    ValueOutOfRange,
    InvalidFormat,
    /// String value was not one of the allowed `choices`.
    InvalidChoice,
    ValidationFailed,
};

/// Schema field types
pub const SchemaType = enum {
    string,
    int,
    bool,
    float,
    object,
    array,
};

/// Validation constraints for different types
pub const StringConstraints = struct {
    min_length: ?usize = null,
    max_length: ?usize = null,
    /// Glob-style pattern the value must match in full. Supports `*` (any run,
    /// including empty) and `?` (exactly one character); all other characters
    /// match literally. This is intentionally NOT a full regex engine — Zig's
    /// std has no regex, and a glob covers the common "must look like X" cases
    /// honestly. A value that does not match yields `SchemaError.InvalidFormat`.
    pattern: ?[]const u8 = null,
    /// Closed set of allowed values (enum/choice). A value outside the set
    /// yields `SchemaError.InvalidChoice`.
    choices: ?[]const []const u8 = null,
};

pub const IntConstraints = struct {
    min: ?i64 = null,
    max: ?i64 = null,
};

pub const FloatConstraints = struct {
    min: ?f64 = null,
    max: ?f64 = null,
};

pub const ArrayConstraints = struct {
    min_items: ?usize = null,
    max_items: ?usize = null,
    item_schema: ?*const Schema = null,
};

/// Core schema definition
pub const Schema = struct {
    schema_type: SchemaType,
    is_required: bool = false,
    default_value: ?flare.Value = null,
    description: ?[]const u8 = null,

    // Type-specific constraints
    string_constraints: ?StringConstraints = null,
    int_constraints: ?IntConstraints = null,
    float_constraints: ?FloatConstraints = null,
    array_constraints: ?ArrayConstraints = null,

    // For object schemas
    fields: ?std.StringHashMap(*const Schema) = null,

    const Self = @This();

    /// Create a string schema with optional constraints
    pub fn string(constraints: StringConstraints) Schema {
        return Schema{
            .schema_type = .string,
            .string_constraints = constraints,
        };
    }

    /// Create an integer schema with optional constraints
    pub fn int(constraints: IntConstraints) Schema {
        return Schema{
            .schema_type = .int,
            .int_constraints = constraints,
        };
    }

    /// Create a boolean schema
    pub fn boolean() Schema {
        return Schema{
            .schema_type = .bool,
        };
    }

    /// Create a float schema with optional constraints
    pub fn float(constraints: FloatConstraints) Schema {
        return Schema{
            .schema_type = .float,
            .float_constraints = constraints,
        };
    }

    /// Create an array schema with optional constraints
    pub fn array(constraints: ArrayConstraints) Schema {
        return Schema{
            .schema_type = .array,
            .array_constraints = constraints,
        };
    }

    /// Create an object schema with field definitions
    pub fn object(allocator: std.mem.Allocator, field_definitions: anytype) !Schema {
        var fields = std.StringHashMap(*const Schema).init(allocator);

        const type_info = @typeInfo(@TypeOf(field_definitions));
        if (type_info != .@"struct") {
            @compileError("object fields must be a struct");
        }

        inline for (type_info.@"struct".field_names) |name| {
            const field_schema = try allocator.create(Schema);
            field_schema.* = @field(field_definitions, name);
            try fields.put(name, field_schema);
        }

        return Schema{
            .schema_type = .object,
            .fields = fields,
        };
    }

    /// Create a root schema (object schema at top level)
    pub fn root(allocator: std.mem.Allocator, field_definitions: anytype) !Schema {
        return object(allocator, field_definitions);
    }

    /// Set this field as required
    pub fn required(self: Schema) Schema {
        var result = self;
        result.is_required = true;
        return result;
    }

    /// Set a default value for this field (metadata only).
    ///
    /// NOTE: This is for documentation and introspection purposes only.
    /// Schema defaults are NOT automatically injected into config values.
    /// To apply runtime defaults, use `config.setDefault("key", value)` instead.
    ///
    /// Use cases for schema defaults:
    /// - Generating documentation with default values
    /// - Schema-based tooling that needs to know expected defaults
    /// - Validation that checks whether a value matches the expected default
    pub fn default(self: Schema, value: flare.Value) Schema {
        var result = self;
        result.default_value = value;
        return result;
    }

    /// Add a description to this field
    pub fn withDescription(self: Schema, desc: []const u8) Schema {
        var result = self;
        result.description = desc;
        return result;
    }

    /// Clean up allocated schema resources
    /// Call this on schemas created with Schema.object() or Schema.root()
    /// to free the allocated field schema nodes
    pub fn deinit(self: *Schema, allocator: std.mem.Allocator) void {
        if (self.fields) |*fields| {
            var iter = fields.iterator();
            while (iter.next()) |entry| {
                // Get mutable pointer and recursively deinit
                const field_schema_ptr = @constCast(entry.value_ptr.*);
                field_schema_ptr.deinit(allocator);
                allocator.destroy(field_schema_ptr);
            }
            fields.deinit();
            self.fields = null;
        }

        // Clean up array item schema if present
        if (self.array_constraints) |*constraints| {
            if (constraints.item_schema) |item_schema| {
                const mutable_item = @constCast(item_schema);
                mutable_item.deinit(allocator);
                allocator.destroy(mutable_item);
                constraints.item_schema = null;
            }
        }
    }

    /// Validate a value against this schema
    pub fn validate(self: *const Self, value: ?flare.Value, path: []const u8) SchemaError!void {
        _ = path; // Used for error context in callers

        // Check if required field is missing
        if (self.is_required and value == null) {
            return SchemaError.MissingRequiredField;
        }

        // If value is null and not required, validation passes
        if (value == null) {
            return;
        }

        const val = value.?;

        // Type validation
        switch (self.schema_type) {
            .string => {
                if (val != .string_value) {
                    return SchemaError.TypeMismatch;
                }
                try self.validateString(val.string_value);
            },
            .int => {
                if (val != .int_value) {
                    return SchemaError.TypeMismatch;
                }
                try self.validateInt(val.int_value);
            },
            .bool => {
                if (val != .bool_value) {
                    return SchemaError.TypeMismatch;
                }
            },
            .float => {
                if (val != .float_value) {
                    return SchemaError.TypeMismatch;
                }
                try self.validateFloat(val.float_value);
            },
            .object => {
                // Object must be a map_value
                if (val != .map_value) {
                    return SchemaError.TypeMismatch;
                }
                // If we have field schemas, validate each field
                if (self.fields) |fields| {
                    var iter = fields.iterator();
                    while (iter.next()) |entry| {
                        const field_name = entry.key_ptr.*;
                        const field_schema = entry.value_ptr.*;

                        // Check if field exists in value
                        if (val.map_value.get(field_name)) |field_value| {
                            // Validate the field value against its schema
                            try field_schema.validate(field_value, field_name);
                        } else if (field_schema.is_required) {
                            return SchemaError.MissingRequiredField;
                        }
                    }
                }
            },
            .array => {
                // Array must be an array_value
                if (val != .array_value) {
                    return SchemaError.TypeMismatch;
                }
                // Validate array constraints
                if (self.array_constraints) |constraints| {
                    const arr = val.array_value;
                    if (constraints.min_items) |min| {
                        if (arr.items.len < min) {
                            return SchemaError.ValueOutOfRange;
                        }
                    }
                    if (constraints.max_items) |max| {
                        if (arr.items.len > max) {
                            return SchemaError.ValueOutOfRange;
                        }
                    }
                    // Validate each item if item_schema is provided
                    if (constraints.item_schema) |item_schema| {
                        for (arr.items, 0..) |item, i| {
                            var item_path_buf: [256]u8 = undefined;
                            const item_path = std.fmt.bufPrint(&item_path_buf, "[{d}]", .{i}) catch "";
                            try item_schema.validate(item, item_path);
                        }
                    }
                }
            },
        }
    }

    /// Validate string constraints
    fn validateString(self: *const Self, value: []const u8) SchemaError!void {
        if (self.string_constraints) |constraints| {
            if (constraints.min_length) |min| {
                if (value.len < min) {
                    return SchemaError.ValueOutOfRange;
                }
            }
            if (constraints.max_length) |max| {
                if (value.len > max) {
                    return SchemaError.ValueOutOfRange;
                }
            }
            if (constraints.choices) |choices| {
                var matched = false;
                for (choices) |choice| {
                    if (std.mem.eql(u8, value, choice)) {
                        matched = true;
                        break;
                    }
                }
                if (!matched) {
                    return SchemaError.InvalidChoice;
                }
            }
            if (constraints.pattern) |pattern| {
                if (!globMatch(pattern, value)) {
                    return SchemaError.InvalidFormat;
                }
            }
        }
    }

    /// Validate integer constraints
    fn validateInt(self: *const Self, value: i64) SchemaError!void {
        if (self.int_constraints) |constraints| {
            if (constraints.min) |min| {
                if (value < min) {
                    return SchemaError.ValueOutOfRange;
                }
            }
            if (constraints.max) |max| {
                if (value > max) {
                    return SchemaError.ValueOutOfRange;
                }
            }
        }
    }

    /// Validate float constraints
    fn validateFloat(self: *const Self, value: f64) SchemaError!void {
        if (self.float_constraints) |constraints| {
            if (constraints.min) |min| {
                if (value < min) {
                    return SchemaError.ValueOutOfRange;
                }
            }
            if (constraints.max) |max| {
                if (value > max) {
                    return SchemaError.ValueOutOfRange;
                }
            }
        }
    }
};

/// Match `text` against a glob `pattern` supporting `*` (any run, including
/// empty) and `?` (exactly one character). Linear-time with single-star
/// backtracking; the whole text must be consumed. Used for
/// `StringConstraints.pattern`.
fn globMatch(pattern: []const u8, text: []const u8) bool {
    var p: usize = 0;
    var t: usize = 0;
    var star: ?usize = null;
    var star_t: usize = 0;

    while (t < text.len) {
        if (p < pattern.len and (pattern[p] == '?' or pattern[p] == text[t])) {
            p += 1;
            t += 1;
        } else if (p < pattern.len and pattern[p] == '*') {
            // Record the star position and the text index it started matching
            // from, so we can backtrack and let it swallow one more character.
            star = p;
            star_t = t;
            p += 1;
        } else if (star) |sp| {
            p = sp + 1;
            star_t += 1;
            t = star_t;
        } else {
            return false;
        }
    }

    // Any trailing stars in the pattern match the empty remainder.
    while (p < pattern.len and pattern[p] == '*') p += 1;
    return p == pattern.len;
}

/// Validation result containing errors and warnings
pub const ValidationResult = struct {
    errors: std.ArrayList(ValidationError),
    warnings: std.ArrayList(ValidationWarning),

    pub fn init(_: std.mem.Allocator) ValidationResult {
        return ValidationResult{
            .errors = .empty,
            .warnings = .empty,
        };
    }

    pub fn deinit(self: *ValidationResult, allocator: std.mem.Allocator) void {
        for (self.errors.items) |err| {
            allocator.free(err.path);
            allocator.free(err.message);
            if (err.actual) |actual| allocator.free(actual);
        }
        self.errors.deinit(allocator);

        for (self.warnings.items) |warn| {
            allocator.free(warn.path);
            allocator.free(warn.message);
        }
        self.warnings.deinit(allocator);
    }

    pub fn hasErrors(self: *const ValidationResult) bool {
        return self.errors.items.len > 0;
    }
};

pub const ValidationError = struct {
    path: []const u8,
    message: []const u8,
    error_type: SchemaError,
    /// Formatted rendering of the value that failed validation (owned by the
    /// ValidationResult). Null when the failure is a missing value.
    actual: ?[]const u8 = null,
    /// Which source layer the failing value came from (file/env/cli/...),
    /// resolved via the config's origin sidecar. Null when unknown or absent.
    origin: ?flare.ValueOrigin = null,
};

pub const ValidationWarning = struct {
    path: []const u8,
    message: []const u8,
};

test "schema creation" {
    // Test basic schema types
    const string_schema = Schema.string(.{ .min_length = 1, .max_length = 100 });
    try std.testing.expect(string_schema.schema_type == .string);
    try std.testing.expect(string_schema.string_constraints.?.min_length == 1);

    const int_schema = Schema.int(.{ .min = 0, .max = 65535 });
    try std.testing.expect(int_schema.schema_type == .int);
    try std.testing.expect(int_schema.int_constraints.?.min == 0);

    const bool_schema = Schema.boolean();
    try std.testing.expect(bool_schema.schema_type == .bool);

    // Test method chaining
    const required_string = Schema.string(.{}).required().default(flare.Value{ .string_value = "default" });
    try std.testing.expect(required_string.is_required == true);
    try std.testing.expect(required_string.default_value != null);
}

test "basic validation" {
    // Test string validation
    const string_schema = Schema.string(.{ .min_length = 3, .max_length = 10 });

    // Valid string
    try string_schema.validate(flare.Value{ .string_value = "hello" }, "test");

    // Too short
    try std.testing.expectError(SchemaError.ValueOutOfRange, string_schema.validate(flare.Value{ .string_value = "hi" }, "test"));

    // Too long
    try std.testing.expectError(SchemaError.ValueOutOfRange, string_schema.validate(flare.Value{ .string_value = "this_is_too_long" }, "test"));

    // Wrong type
    try std.testing.expectError(SchemaError.TypeMismatch, string_schema.validate(flare.Value{ .int_value = 42 }, "test"));

    // Test required validation
    const required_schema = Schema.string(.{}).required();
    try std.testing.expectError(SchemaError.MissingRequiredField, required_schema.validate(null, "test"));
}

test "array validation" {
    const testing = std.testing;

    // Array with min/max items
    const array_schema = Schema{
        .schema_type = .array,
        .array_constraints = .{
            .min_items = 2,
            .max_items = 5,
        },
    };

    // Create a valid array (3 items)
    var valid_array: std.ArrayList(flare.Value) = .empty;
    try valid_array.append(testing.allocator, flare.Value{ .int_value = 1 });
    try valid_array.append(testing.allocator, flare.Value{ .int_value = 2 });
    try valid_array.append(testing.allocator, flare.Value{ .int_value = 3 });
    defer valid_array.deinit(testing.allocator);

    try array_schema.validate(flare.Value{ .array_value = valid_array }, "numbers");

    // Too few items
    var short_array: std.ArrayList(flare.Value) = .empty;
    try short_array.append(testing.allocator, flare.Value{ .int_value = 1 });
    defer short_array.deinit(testing.allocator);

    try testing.expectError(SchemaError.ValueOutOfRange, array_schema.validate(flare.Value{ .array_value = short_array }, "numbers"));

    // Wrong type (not an array)
    try testing.expectError(SchemaError.TypeMismatch, array_schema.validate(flare.Value{ .int_value = 42 }, "numbers"));
}

test "object validation" {
    const testing = std.testing;

    // Create field schemas
    const name_schema = Schema.string(.{ .min_length = 1 }).required();
    const port_schema = Schema.int(.{ .min = 1, .max = 65535 });

    // Build object schema with fields
    var fields = std.StringHashMap(*const Schema).init(testing.allocator);
    defer fields.deinit();

    const name_ptr = try testing.allocator.create(Schema);
    defer testing.allocator.destroy(name_ptr);
    name_ptr.* = name_schema;

    const port_ptr = try testing.allocator.create(Schema);
    defer testing.allocator.destroy(port_ptr);
    port_ptr.* = port_schema;

    try fields.put("name", name_ptr);
    try fields.put("port", port_ptr);

    const object_schema = Schema{
        .schema_type = .object,
        .fields = fields,
    };

    // Create a valid object value
    var valid_map = std.StringHashMap(flare.Value).init(testing.allocator);
    defer valid_map.deinit();
    try valid_map.put("name", flare.Value{ .string_value = "myapp" });
    try valid_map.put("port", flare.Value{ .int_value = 8080 });

    try object_schema.validate(flare.Value{ .map_value = valid_map }, "config");

    // Missing required field
    var missing_name = std.StringHashMap(flare.Value).init(testing.allocator);
    defer missing_name.deinit();
    try missing_name.put("port", flare.Value{ .int_value = 8080 });

    try testing.expectError(SchemaError.MissingRequiredField, object_schema.validate(flare.Value{ .map_value = missing_name }, "config"));

    // Wrong type (not an object)
    try testing.expectError(SchemaError.TypeMismatch, object_schema.validate(flare.Value{ .string_value = "not an object" }, "config"));
}

test "globMatch semantics" {
    const testing = std.testing;

    // Literal
    try testing.expect(globMatch("abc", "abc"));
    try testing.expect(!globMatch("abc", "abd"));

    // ? matches exactly one char
    try testing.expect(globMatch("a?c", "abc"));
    try testing.expect(!globMatch("a?c", "ac"));

    // * matches any run including empty
    try testing.expect(globMatch("*", ""));
    try testing.expect(globMatch("*", "anything"));
    try testing.expect(globMatch("a*", "a"));
    try testing.expect(globMatch("a*c", "abbbbc"));
    try testing.expect(!globMatch("a*c", "abbbbd"));

    // Anchored full match (not a substring search)
    try testing.expect(!globMatch("abc", "xabcx"));
    try testing.expect(globMatch("*.log", "server.log"));
    try testing.expect(!globMatch("*.log", "server.txt"));

    // Multiple stars
    try testing.expect(globMatch("*mid*", "prefix-mid-suffix"));
    try testing.expect(!globMatch("*mid*", "prefix-suffix"));
}

test "string pattern constraint" {
    const testing = std.testing;
    // Semver-ish: digits.digits.digits — approximated with glob wildcards.
    const version_schema = Schema.string(.{ .pattern = "v*.*.*" });
    try version_schema.validate(flare.Value{ .string_value = "v1.2.3" }, "version");
    try testing.expectError(SchemaError.InvalidFormat, version_schema.validate(flare.Value{ .string_value = "1.2.3" }, "version"));

    // Suffix constraint
    const log_schema = Schema.string(.{ .pattern = "*.log" });
    try log_schema.validate(flare.Value{ .string_value = "app.log" }, "file");
    try testing.expectError(SchemaError.InvalidFormat, log_schema.validate(flare.Value{ .string_value = "app.txt" }, "file"));
}

test "string choices constraint" {
    const testing = std.testing;
    const level_schema = Schema.string(.{ .choices = &.{ "debug", "info", "warn", "error" } });

    try level_schema.validate(flare.Value{ .string_value = "info" }, "log.level");
    try level_schema.validate(flare.Value{ .string_value = "error" }, "log.level");
    try testing.expectError(SchemaError.InvalidChoice, level_schema.validate(flare.Value{ .string_value = "trace" }, "log.level"));
}

test "array item_schema enforcement" {
    const testing = std.testing;

    // Each item must be an int in [1, 100].
    const item = Schema.int(.{ .min = 1, .max = 100 });
    const numbers_schema = Schema{
        .schema_type = .array,
        .array_constraints = .{ .item_schema = &item },
    };

    var good: std.ArrayList(flare.Value) = .empty;
    defer good.deinit(testing.allocator);
    try good.append(testing.allocator, flare.Value{ .int_value = 5 });
    try good.append(testing.allocator, flare.Value{ .int_value = 50 });
    try numbers_schema.validate(flare.Value{ .array_value = good }, "numbers");

    // One element out of range fails the whole array.
    var bad: std.ArrayList(flare.Value) = .empty;
    defer bad.deinit(testing.allocator);
    try bad.append(testing.allocator, flare.Value{ .int_value = 5 });
    try bad.append(testing.allocator, flare.Value{ .int_value = 999 });
    try testing.expectError(SchemaError.ValueOutOfRange, numbers_schema.validate(flare.Value{ .array_value = bad }, "numbers"));

    // Wrong element type fails too.
    var wrong: std.ArrayList(flare.Value) = .empty;
    defer wrong.deinit(testing.allocator);
    try wrong.append(testing.allocator, flare.Value{ .string_value = "nope" });
    try testing.expectError(SchemaError.TypeMismatch, numbers_schema.validate(flare.Value{ .array_value = wrong }, "numbers"));
}
