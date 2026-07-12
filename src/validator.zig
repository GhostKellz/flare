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
    fn validateObject(self: *Self, config: *root.Config, object_schema: *const schema.Schema, path_prefix: []const u8, result: *schema.ValidationResult) !void {
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
                    // Capture the actual failing value and its source origin so
                    // callers can report "at 'db.port' (got 70000, from file
                    // config.toml)" rather than a bare error code.
                    const actual: ?[]const u8 = if (config_value) |v|
                        try formatValue(self.allocator, v)
                    else
                        null;
                    const origin = config.getSource(full_path);
                    try result.errors.append(self.allocator, schema.ValidationError{
                        .path = try self.allocator.dupe(u8, full_path),
                        .message = try self.getErrorMessage(err, full_path, actual, origin),
                        .error_type = err,
                        .actual = actual,
                        .origin = origin,
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
    fn validateField(self: *Self, field_schema: *const schema.Schema, value: ?root.Value, path: []const u8, result: *schema.ValidationResult) !void {
        _ = self; // Mark as used
        _ = result; // Unused for now

        // Use the schema's built-in validation
        try field_schema.validate(value, path);
    }

    /// Get a human-readable error message for a validation error, enriched with
    /// the actual value and its source origin when available. Produces lines
    /// like "Value out of range at 'db.port' (got 70000, from file config.toml)".
    fn getErrorMessage(self: *Self, err: schema.SchemaError, path: []const u8, actual: ?[]const u8, origin: ?root.ValueOrigin) ![]const u8 {
        const reason = switch (err) {
            schema.SchemaError.MissingRequiredField => "Missing required field",
            schema.SchemaError.TypeMismatch => "Type mismatch",
            schema.SchemaError.ValueOutOfRange => "Value out of range",
            schema.SchemaError.InvalidFormat => "Invalid format",
            schema.SchemaError.InvalidChoice => "Value not in allowed choices",
            schema.SchemaError.ValidationFailed => "Validation failed",
        };

        // Missing values carry no actual/origin detail.
        if (actual == null) {
            return std.fmt.allocPrint(self.allocator, "{s} at '{s}'", .{ reason, path });
        }

        if (origin) |o| {
            const layer = layerName(o.kind);
            if (o.detail) |detail| {
                return std.fmt.allocPrint(self.allocator, "{s} at '{s}' (got {s}, from {s} {s})", .{ reason, path, actual.?, layer, detail });
            }
            return std.fmt.allocPrint(self.allocator, "{s} at '{s}' (got {s}, from {s})", .{ reason, path, actual.?, layer });
        }
        return std.fmt.allocPrint(self.allocator, "{s} at '{s}' (got {s})", .{ reason, path, actual.? });
    }
};

/// Human-facing name for an origin layer, matching Config.explain wording.
fn layerName(kind: root.OriginKind) []const u8 {
    return switch (kind) {
        .default => "default",
        .file => "file",
        .env => "environment variable",
        .cli => "command-line flag",
        .set => "programmatic set",
    };
}

/// Render a config value into a short human-readable form for diagnostics.
/// Caller owns the returned slice.
fn formatValue(allocator: std.mem.Allocator, value: root.Value) ![]const u8 {
    return switch (value) {
        .null_value => allocator.dupe(u8, "null"),
        .bool_value => |b| allocator.dupe(u8, if (b) "true" else "false"),
        .int_value => |i| std.fmt.allocPrint(allocator, "{d}", .{i}),
        .float_value => |f| std.fmt.allocPrint(allocator, "{d}", .{f}),
        .string_value => |s| std.fmt.allocPrint(allocator, "\"{s}\"", .{s}),
        .array_value => |arr| std.fmt.allocPrint(allocator, "<array len={d}>", .{arr.items.len}),
        .map_value => |m| std.fmt.allocPrint(allocator, "<object fields={d}>", .{m.count()}),
    };
}

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
    // Missing values carry no actual/origin detail.
    try std.testing.expect(result.errors.items[0].actual == null);
}

test "validation error captures actual value and origin" {
    const allocator = std.testing.allocator;

    var fields = std.StringHashMap(*const schema.Schema).init(allocator);
    defer fields.deinit();

    const port_schema = try allocator.create(schema.Schema);
    defer allocator.destroy(port_schema);
    port_schema.* = schema.Schema.int(.{ .min = 1, .max = 65535 });
    try fields.put("port", port_schema);

    const root_schema = schema.Schema{
        .schema_type = .object,
        .fields = fields,
    };

    var config = try root.Config.init(allocator);
    defer config.deinit();

    // An out-of-range value set via a CLI-origin write.
    try config.setValueWithOrigin("port", root.Value{ .int_value = 70000 }, .{ .kind = .cli, .detail = "--port" });

    var result = try validateConfig(allocator, &config, &root_schema);
    defer result.deinit(allocator);

    try std.testing.expect(result.hasErrors());
    const err = result.errors.items[0];
    try std.testing.expect(err.error_type == schema.SchemaError.ValueOutOfRange);

    // Actual value is rendered.
    try std.testing.expect(err.actual != null);
    try std.testing.expect(std.mem.eql(u8, err.actual.?, "70000"));

    // Origin layer + detail are captured.
    try std.testing.expect(err.origin != null);
    try std.testing.expect(err.origin.?.kind == .cli);

    // Message threads value + origin together for humans.
    try std.testing.expect(std.mem.indexOf(u8, err.message, "70000") != null);
    try std.testing.expect(std.mem.indexOf(u8, err.message, "--port") != null);
}
