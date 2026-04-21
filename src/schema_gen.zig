//! Auto-generate schemas from Zig types
//!
//! Automatically create schema definitions from struct types

const std = @import("std");
const schema_mod = @import("schema.zig");
const toml_value = @import("toml_value.zig");
const toml_parser = @import("toml_parser.zig");

const TomlValue = toml_value.TomlValue;
const TomlTable = toml_value.TomlTable;

/// Value types for schema validation against TomlValues
pub const ValueType = enum {
    string,
    integer,
    float,
    boolean,
    datetime,
    date,
    time,
    array,
    table,
    any,
};

/// Constraint types for field validation
pub const Constraint = union(enum) {
    min_value: i64,
    max_value: i64,
    min_length: usize,
    max_length: usize,
    pattern: []const u8,
    one_of: []const []const u8,
    custom: *const fn (value: *const TomlValue) bool,
};

/// Field schema definition
pub const FieldSchema = struct {
    name: []const u8,
    field_type: ValueType,
    required: bool = false,
    constraints: []const Constraint = &.{},
    description: ?[]const u8 = null,
    nested_schema: ?*const TomlSchema = null,
};

/// Schema for validating TomlTables
pub const TomlSchema = struct {
    fields: []const FieldSchema,
    allow_unknown: bool = false,
    description: ?[]const u8 = null,

    pub fn validate(self: *const TomlSchema, table: *const TomlTable, allocator: std.mem.Allocator) TomlValidationResult {
        var result = TomlValidationResult.init(allocator);

        // Check required fields and validate existing ones
        for (self.fields) |field| {
            const val = table.get(field.name);

            if (val == null) {
                if (field.required) {
                    const msg = std.fmt.allocPrint(
                        allocator,
                        "Missing required field: '{s}'",
                        .{field.name},
                    ) catch continue;
                    result.addError(msg) catch {};
                }
                continue;
            }

            // Type validation
            self.validateType(field, val.?, &result, allocator) catch {};

            // Constraint validation
            self.validateConstraints(field, val.?, &result, allocator) catch {};

            // Nested schema validation
            if (field.nested_schema) |nested| {
                if (val.? == .table) {
                    var nested_result = nested.validate(val.?.table, allocator);
                    defer nested_result.deinit();

                    if (!nested_result.valid) {
                        for (nested_result.errors.items) |err| {
                            const prefixed = std.fmt.allocPrint(
                                allocator,
                                "{s}.{s}",
                                .{ field.name, err },
                            ) catch continue;
                            result.addError(prefixed) catch {};
                        }
                    }
                }
            }
        }

        // Check for unknown fields if strict mode
        if (!self.allow_unknown) {
            var it = table.map.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                var found = false;

                for (self.fields) |field| {
                    if (std.mem.eql(u8, field.name, key)) {
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    const msg = std.fmt.allocPrint(
                        allocator,
                        "Unknown field: '{s}'",
                        .{key},
                    ) catch continue;
                    result.addError(msg) catch {};
                }
            }
        }

        return result;
    }

    fn validateType(self: *const TomlSchema, field: FieldSchema, val: TomlValue, result: *TomlValidationResult, allocator: std.mem.Allocator) !void {
        _ = self;

        const matches = switch (field.field_type) {
            .string => val == .string,
            .integer => val == .integer,
            .float => val == .float,
            .boolean => val == .boolean,
            .datetime => val == .datetime,
            .date => val == .date,
            .time => val == .time,
            .array => val == .array,
            .table => val == .table,
            .any => true,
        };

        if (!matches) {
            const msg = try std.fmt.allocPrint(
                allocator,
                "Field '{s}' has wrong type (expected {s})",
                .{ field.name, @tagName(field.field_type) },
            );
            try result.addError(msg);
        }
    }

    fn validateConstraints(self: *const TomlSchema, field: FieldSchema, val: TomlValue, result: *TomlValidationResult, allocator: std.mem.Allocator) !void {
        _ = self;

        for (field.constraints) |constraint| {
            switch (constraint) {
                .min_value => |min| {
                    if (val == .integer and val.integer < min) {
                        const msg = try std.fmt.allocPrint(
                            allocator,
                            "Field '{s}' value {d} is less than minimum {d}",
                            .{ field.name, val.integer, min },
                        );
                        try result.addError(msg);
                    }
                },
                .max_value => |max| {
                    if (val == .integer and val.integer > max) {
                        const msg = try std.fmt.allocPrint(
                            allocator,
                            "Field '{s}' value {d} is greater than maximum {d}",
                            .{ field.name, val.integer, max },
                        );
                        try result.addError(msg);
                    }
                },
                .min_length => |min| {
                    if (val == .string and val.string.len < min) {
                        const msg = try std.fmt.allocPrint(
                            allocator,
                            "Field '{s}' length {d} is less than minimum {d}",
                            .{ field.name, val.string.len, min },
                        );
                        try result.addError(msg);
                    }
                },
                .max_length => |max| {
                    if (val == .string and val.string.len > max) {
                        const msg = try std.fmt.allocPrint(
                            allocator,
                            "Field '{s}' length {d} is greater than maximum {d}",
                            .{ field.name, val.string.len, max },
                        );
                        try result.addError(msg);
                    }
                },
                .pattern => {
                    // Pattern matching would require regex library - skip for now
                },
                .one_of => |options| {
                    if (val == .string) {
                        var found = false;
                        for (options) |opt| {
                            if (std.mem.eql(u8, val.string, opt)) {
                                found = true;
                                break;
                            }
                        }
                        if (!found) {
                            const msg = try std.fmt.allocPrint(
                                allocator,
                                "Field '{s}' value '{s}' is not one of the allowed values",
                                .{ field.name, val.string },
                            );
                            try result.addError(msg);
                        }
                    }
                },
                .custom => |func| {
                    if (!func(&val)) {
                        const msg = try std.fmt.allocPrint(
                            allocator,
                            "Field '{s}' failed custom validation",
                            .{field.name},
                        );
                        try result.addError(msg);
                    }
                },
            }
        }
    }
};

/// Validation result for TomlSchema
pub const TomlValidationResult = struct {
    valid: bool,
    errors: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TomlValidationResult {
        return .{
            .valid = true,
            .errors = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TomlValidationResult) void {
        for (self.errors.items) |err| {
            self.allocator.free(err);
        }
        self.errors.deinit(self.allocator);
    }

    pub fn addError(self: *TomlValidationResult, message: []const u8) !void {
        try self.errors.append(self.allocator, message);
        self.valid = false;
    }
};

/// Builder pattern for creating TomlSchemas
pub const SchemaBuilder = struct {
    allocator: std.mem.Allocator,
    fields: std.ArrayList(FieldSchema),
    allow_unknown: bool,
    description: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator) SchemaBuilder {
        return .{
            .allocator = allocator,
            .fields = .empty,
            .allow_unknown = false,
            .description = null,
        };
    }

    pub fn deinit(self: *SchemaBuilder) void {
        self.fields.deinit(self.allocator);
    }

    pub fn allowUnknown(self: *SchemaBuilder, allow: bool) *SchemaBuilder {
        self.allow_unknown = allow;
        return self;
    }

    pub fn setDescription(self: *SchemaBuilder, desc: []const u8) *SchemaBuilder {
        self.description = desc;
        return self;
    }

    pub fn addField(self: *SchemaBuilder, field: FieldSchema) !*SchemaBuilder {
        try self.fields.append(self.allocator, field);
        return self;
    }

    pub fn build(self: *SchemaBuilder) !TomlSchema {
        const fields_slice = try self.allocator.dupe(FieldSchema, self.fields.items);
        return TomlSchema{
            .fields = fields_slice,
            .allow_unknown = self.allow_unknown,
            .description = self.description,
        };
    }
};

/// Generate a schema from a Zig struct type
pub fn schemaFrom(comptime T: type, allocator: std.mem.Allocator) !TomlSchema {
    const type_info = @typeInfo(T);

    switch (type_info) {
        .@"struct" => |struct_info| {
            var builder = SchemaBuilder.init(allocator);
            defer builder.deinit();

            inline for (struct_info.fields) |field| {
                const field_schema = createFieldSchema(field);
                _ = try builder.addField(field_schema);
            }

            _ = builder.allowUnknown(false);
            return try builder.build();
        },
        else => @compileError("schemaFrom only works with struct types"),
    }
}

fn createFieldSchema(comptime field: std.builtin.Type.StructField) FieldSchema {
    return FieldSchema{
        .name = field.name,
        .field_type = inferValueType(field.type),
        .required = !hasDefault(field),
        .description = null,
    };
}

fn hasDefault(comptime field: std.builtin.Type.StructField) bool {
    return field.default_value_ptr != null;
}

fn inferValueType(comptime T: type) ValueType {
    const type_info = @typeInfo(T);

    return switch (type_info) {
        .int => .integer,
        .float => .float,
        .bool => .boolean,
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice and ptr_info.child == u8) {
                return .string;
            }
            return .array;
        },
        .optional => |opt_info| inferValueType(opt_info.child),
        .@"struct" => .table,
        .array => .array,
        else => .any,
    };
}

test "generate schema from struct" {
    const testing = std.testing;

    const Config = struct {
        name: []const u8,
        port: i64,
        debug: bool = false,
    };

    const schema_val = try schemaFrom(Config, testing.allocator);
    defer testing.allocator.free(schema_val.fields);

    try testing.expectEqual(@as(usize, 3), schema_val.fields.len);
    try testing.expectEqualStrings("name", schema_val.fields[0].name);
    try testing.expectEqual(ValueType.string, schema_val.fields[0].field_type);
    try testing.expectEqual(true, schema_val.fields[0].required);

    try testing.expectEqualStrings("port", schema_val.fields[1].name);
    try testing.expectEqual(ValueType.integer, schema_val.fields[1].field_type);
    try testing.expectEqual(true, schema_val.fields[1].required);

    try testing.expectEqualStrings("debug", schema_val.fields[2].name);
    try testing.expectEqual(ValueType.boolean, schema_val.fields[2].field_type);
    try testing.expectEqual(false, schema_val.fields[2].required);
}

test "schema validation with generated schema" {
    const testing = std.testing;

    const ServerConfig = struct {
        host: []const u8,
        port: i64,
        workers: i64 = 4,
    };

    const schema_val = try schemaFrom(ServerConfig, testing.allocator);
    defer testing.allocator.free(schema_val.fields);

    const valid_toml =
        \\host = "localhost"
        \\port = 8080
    ;

    const table = try toml_parser.parseToml(testing.allocator, valid_toml);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    var result = schema_val.validate(table, testing.allocator);
    defer result.deinit();

    try testing.expect(result.valid);
}

test "schema validation - required fields" {
    const testing = std.testing;

    const source = "name = \"test\"";

    const table = try toml_parser.parseToml(testing.allocator, source);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    const schema = TomlSchema{
        .fields = &[_]FieldSchema{
            .{ .name = "name", .field_type = .string, .required = true },
            .{ .name = "version", .field_type = .string, .required = true },
        },
    };

    var result = schema.validate(table, testing.allocator);
    defer result.deinit();

    try testing.expect(!result.valid);
    try testing.expect(result.errors.items.len > 0);
}

test "schema validation - constraints" {
    const testing = std.testing;

    const source = "port = 99999"; // Too high

    const table = try toml_parser.parseToml(testing.allocator, source);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    const schema = TomlSchema{
        .fields = &[_]FieldSchema{
            .{
                .name = "port",
                .field_type = .integer,
                .required = true,
                .constraints = &[_]Constraint{
                    .{ .min_value = 1 },
                    .{ .max_value = 65535 },
                },
            },
        },
    };

    var result = schema.validate(table, testing.allocator);
    defer result.deinit();

    try testing.expect(!result.valid);
}

test "schema builder pattern" {
    const testing = std.testing;

    var builder = SchemaBuilder.init(testing.allocator);
    defer builder.deinit();

    _ = try builder.addField(.{ .name = "name", .field_type = .string, .required = true });
    _ = try builder.addField(.{ .name = "port", .field_type = .integer, .required = true });
    _ = builder.allowUnknown(true);

    const schema = try builder.build();
    defer testing.allocator.free(schema.fields);

    const source =
        \\name = "test"
        \\port = 8080
    ;

    const table = try toml_parser.parseToml(testing.allocator, source);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    var result = schema.validate(table, testing.allocator);
    defer result.deinit();

    try testing.expect(result.valid);
}
