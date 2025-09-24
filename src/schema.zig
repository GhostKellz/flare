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
    pattern: ?[]const u8 = null,
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
        if (type_info != .Struct) {
            @compileError("object fields must be a struct");
        }

        inline for (type_info.Struct.fields) |field| {
            const field_schema = try allocator.create(Schema);
            field_schema.* = @field(field_definitions, field.name);
            try fields.put(field.name, field_schema);
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

    /// Set a default value for this field
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

    /// Validate a value against this schema
    pub fn validate(self: *const Self, value: ?flare.Value, path: []const u8) SchemaError!void {
        // Check if required field is missing
        if (self.is_required and value == null) {
            std.debug.print("Schema validation failed: missing required field '{s}'\n", .{path});
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
                    std.debug.print("Schema validation failed: expected string at '{s}', got {}\n", .{ path, val });
                    return SchemaError.TypeMismatch;
                }
                try self.validateString(val.string_value, path);
            },
            .int => {
                if (val != .int_value) {
                    std.debug.print("Schema validation failed: expected int at '{s}', got {}\n", .{ path, val });
                    return SchemaError.TypeMismatch;
                }
                try self.validateInt(val.int_value, path);
            },
            .bool => {
                if (val != .bool_value) {
                    std.debug.print("Schema validation failed: expected bool at '{s}', got {}\n", .{ path, val });
                    return SchemaError.TypeMismatch;
                }
            },
            .float => {
                if (val != .float_value) {
                    std.debug.print("Schema validation failed: expected float at '{s}', got {}\n", .{ path, val });
                    return SchemaError.TypeMismatch;
                }
                try self.validateFloat(val.float_value, path);
            },
            .object => {
                // Object validation handled by validator
                return SchemaError.ValidationFailed;
            },
            .array => {
                // Array validation not implemented yet
                return SchemaError.ValidationFailed;
            },
        }
    }

    /// Validate string constraints
    fn validateString(self: *const Self, value: []const u8, path: []const u8) SchemaError!void {
        if (self.string_constraints) |constraints| {
            if (constraints.min_length) |min| {
                if (value.len < min) {
                    std.debug.print("Schema validation failed: string at '{s}' too short (min: {d}, actual: {d})\n", .{ path, min, value.len });
                    return SchemaError.ValueOutOfRange;
                }
            }
            if (constraints.max_length) |max| {
                if (value.len > max) {
                    std.debug.print("Schema validation failed: string at '{s}' too long (max: {d}, actual: {d})\n", .{ path, max, value.len });
                    return SchemaError.ValueOutOfRange;
                }
            }
            // Pattern validation would go here
        }
    }

    /// Validate integer constraints
    fn validateInt(self: *const Self, value: i64, path: []const u8) SchemaError!void {
        if (self.int_constraints) |constraints| {
            if (constraints.min) |min| {
                if (value < min) {
                    std.debug.print("Schema validation failed: int at '{s}' too small (min: {d}, actual: {d})\n", .{ path, min, value });
                    return SchemaError.ValueOutOfRange;
                }
            }
            if (constraints.max) |max| {
                if (value > max) {
                    std.debug.print("Schema validation failed: int at '{s}' too large (max: {d}, actual: {d})\n", .{ path, max, value });
                    return SchemaError.ValueOutOfRange;
                }
            }
        }
    }

    /// Validate float constraints
    fn validateFloat(self: *const Self, value: f64, path: []const u8) SchemaError!void {
        if (self.float_constraints) |constraints| {
            if (constraints.min) |min| {
                if (value < min) {
                    std.debug.print("Schema validation failed: float at '{s}' too small (min: {d}, actual: {d})\n", .{ path, min, value });
                    return SchemaError.ValueOutOfRange;
                }
            }
            if (constraints.max) |max| {
                if (value > max) {
                    std.debug.print("Schema validation failed: float at '{s}' too large (max: {d}, actual: {d})\n", .{ path, max, value });
                    return SchemaError.ValueOutOfRange;
                }
            }
        }
    }
};

/// Validation result containing errors and warnings
pub const ValidationResult = struct {
    errors: std.ArrayList(ValidationError),
    warnings: std.ArrayList(ValidationWarning),

    pub fn init(allocator: std.mem.Allocator) ValidationResult {
        _ = allocator; // Keep for future use
        return ValidationResult{
            .errors = std.ArrayList(ValidationError){},
            .warnings = std.ArrayList(ValidationWarning){},
        };
    }

    pub fn deinit(self: *ValidationResult, allocator: std.mem.Allocator) void {
        self.errors.deinit(allocator);
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
    try std.testing.expectError(SchemaError.ValueOutOfRange,
        string_schema.validate(flare.Value{ .string_value = "hi" }, "test"));

    // Too long
    try std.testing.expectError(SchemaError.ValueOutOfRange,
        string_schema.validate(flare.Value{ .string_value = "this_is_too_long" }, "test"));

    // Wrong type
    try std.testing.expectError(SchemaError.TypeMismatch,
        string_schema.validate(flare.Value{ .int_value = 42 }, "test"));

    // Test required validation
    const required_schema = Schema.string(.{}).required();
    try std.testing.expectError(SchemaError.MissingRequiredField,
        required_schema.validate(null, "test"));
}