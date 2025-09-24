//! Configuration validator that validates Config instances against Schema definitions
//! Provides comprehensive validation with detailed error reporting

const std = @import("std");
const root = @import("root.zig");
const schema = @import("schema.zig");

/// Comprehensive validator for Config instances
pub const Validator = struct {
    allocator: std.mem.Allocator,
    schema_def: *const schema.Schema,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, schema_def: *const schema.Schema) Self {
        return Self{
            .allocator = allocator,
            .schema_def = schema_def,
        };
    }

    /// Validate a Config instance against the schema
    pub fn validate(self: *Self, config: *root.Config) !schema.ValidationResult {
        var result = schema.ValidationResult.init(self.allocator);

        // Validate root level
        try self.validateObject(config, self.schema_def, "", &result);

        return result;
    }

    /// Validate an object schema against config data
    fn validateObject(
        self: *Self,
        config: *root.Config,
        object_schema: *const schema.Schema,
        path_prefix: []const u8,
        result: *schema.ValidationResult
    ) !void {
        if (object_schema.schema_type != .object) {
            return schema.SchemaError.ValidationFailed;
        }

        if (object_schema.fields) |fields| {
            var field_iter = fields.iterator();
            while (field_iter.next()) |entry| {
                const field_name = entry.key_ptr.*;
                const field_schema = entry.value_ptr.*;

                // Build full path for error reporting
                const full_path = if (path_prefix.len == 0)
                    field_name
                else
                    try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ path_prefix, field_name });
                defer if (path_prefix.len > 0) self.allocator.free(full_path);

                // Get value from config
                const config_value = config.getValue(full_path);

                // Validate this field
                self.validateField(field_schema, config_value, full_path, result) catch |err| {
                    try result.errors.append(self.allocator, schema.ValidationError{
                        .path = try self.allocator.dupe(u8, full_path),
                        .message = try self.getErrorMessage(err, full_path),
                        .error_type = err,
                    });
                };

                // If this is a nested object, validate recursively
                if (field_schema.schema_type == .object and config_value != null) {
                    try self.validateObject(config, field_schema, full_path, result);
                }
            }
        }
    }

    /// Validate a single field against its schema
    fn validateField(
        self: *Self,
        field_schema: *const schema.Schema,
        value: ?root.Value,
        path: []const u8,
        result: *schema.ValidationResult
    ) !void {
        _ = self; // Mark as used
        _ = result; // Unused for now

        // Use the schema's built-in validation
        try field_schema.validate(value, path);
    }

    /// Get a human-readable error message for a validation error
    fn getErrorMessage(self: *Self, err: schema.SchemaError, path: []const u8) ![]const u8 {
        return switch (err) {
            schema.SchemaError.MissingRequiredField =>
                try std.fmt.allocPrint(self.allocator, "Missing required field at '{s}'", .{path}),
            schema.SchemaError.TypeMismatch =>
                try std.fmt.allocPrint(self.allocator, "Type mismatch at '{s}'", .{path}),
            schema.SchemaError.ValueOutOfRange =>
                try std.fmt.allocPrint(self.allocator, "Value out of range at '{s}'", .{path}),
            schema.SchemaError.InvalidFormat =>
                try std.fmt.allocPrint(self.allocator, "Invalid format at '{s}'", .{path}),
            schema.SchemaError.ValidationFailed =>
                try std.fmt.allocPrint(self.allocator, "Validation failed at '{s}'", .{path}),
        };
    }
};

/// Convenient validation function for Config with Schema
pub fn validateConfig(allocator: std.mem.Allocator, config: *root.Config, schema_def: *const schema.Schema) !schema.ValidationResult {
    var validator = Validator.init(allocator, schema_def);
    return validator.validate(config);
}

test "validator basic functionality" {
    const allocator = std.testing.allocator;

    // Create a simple schema
    var fields = std.StringHashMap(*const schema.Schema).init(allocator);
    defer fields.deinit();

    const name_schema = try allocator.create(schema.Schema);
    defer allocator.destroy(name_schema);
    name_schema.* = schema.Schema.string(.{ .min_length = 1 }).required();

    const port_schema = try allocator.create(schema.Schema);
    defer allocator.destroy(port_schema);
    port_schema.* = schema.Schema.int(.{ .min = 1, .max = 65535 });

    try fields.put("name", name_schema);
    try fields.put("port", port_schema);

    const root_schema = schema.Schema{
        .schema_type = .object,
        .fields = fields,
    };

    // Create a config with valid data
    var config = try root.Config.init(allocator);
    defer config.deinit();

    try config.setValue("name", root.Value{ .string_value = "test-app" });
    try config.setValue("port", root.Value{ .int_value = 8080 });

    // Validate - should pass
    var result = try validateConfig(allocator, &config, &root_schema);
    defer result.deinit(allocator);

    try std.testing.expect(!result.hasErrors());
}

test "validator catches missing required field" {
    const allocator = std.testing.allocator;

    // Create schema with required field
    var fields = std.StringHashMap(*const schema.Schema).init(allocator);
    defer fields.deinit();

    const name_schema = try allocator.create(schema.Schema);
    defer allocator.destroy(name_schema);
    name_schema.* = schema.Schema.string(.{}).required();

    try fields.put("name", name_schema);

    const root_schema = schema.Schema{
        .schema_type = .object,
        .fields = fields,
    };

    // Create config without the required field
    var config = try root.Config.init(allocator);
    defer config.deinit();

    // Validate - should fail
    var result = try validateConfig(allocator, &config, &root_schema);
    defer result.deinit(allocator);

    try std.testing.expect(result.hasErrors());
    try std.testing.expect(result.errors.items.len == 1);
    try std.testing.expect(result.errors.items[0].error_type == schema.SchemaError.MissingRequiredField);
}