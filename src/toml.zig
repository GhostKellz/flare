//! Basic TOML parser for Flare configuration
//! Supports basic TOML syntax: key=value, [sections], and nested objects

const std = @import("std");
const root = @import("root.zig");

/// TOML parsing errors
pub const TomlError = error{
    ParseError,
    InvalidFormat,
    OutOfMemory,
};

/// Simple TOML parser that converts TOML to our Value format
pub const TomlParser = struct {
    allocator: std.mem.Allocator,
    content: []const u8,
    pos: usize = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, content: []const u8) Self {
        return Self{
            .allocator = allocator,
            .content = content,
        };
    }

    /// Parse TOML content into a flat key-value map (using underscore notation)
    pub fn parse(self: *Self) !std.StringHashMap(root.Value) {
        var result = std.StringHashMap(root.Value).init(self.allocator);
        var current_section: ?[]const u8 = null;

        // Reset position
        self.pos = 0;

        while (self.pos < self.content.len) {
            self.skipWhitespace();
            if (self.pos >= self.content.len) break;

            // Skip empty lines and comments
            if (self.peek() == '\n' or self.peek() == '#') {
                self.skipLine();
                continue;
            }

            // Check for section header [section]
            if (self.peek() == '[') {
                current_section = try self.parseSection();
                continue;
            }

            // Parse key=value pair
            const key = try self.parseKey();
            self.skipWhitespace();

            if (self.pos >= self.content.len or self.peek() != '=') {
                return TomlError.ParseError;
            }
            self.advance(); // skip '='
            self.skipWhitespace();

            const value = try self.parseValue();

            // Build full key with section prefix
            const full_key = if (current_section) |section|
                try std.fmt.allocPrint(self.allocator, "{s}_{s}", .{ section, key })
            else
                try self.allocator.dupe(u8, key);

            try result.put(full_key, value);
            self.skipWhitespace();
        }

        return result;
    }

    /// Parse a section header like [database]
    fn parseSection(self: *Self) ![]const u8 {
        if (self.peek() != '[') return TomlError.ParseError;
        self.advance(); // skip '['

        const start = self.pos;
        while (self.pos < self.content.len and self.peek() != ']') {
            self.advance();
        }

        if (self.pos >= self.content.len) return TomlError.ParseError;
        const section_name = self.content[start..self.pos];
        self.advance(); // skip ']'
        self.skipLine(); // skip rest of line

        return try self.allocator.dupe(u8, section_name);
    }

    /// Parse a key (left side of =)
    fn parseKey(self: *Self) ![]const u8 {
        const start = self.pos;
        while (self.pos < self.content.len) {
            const c = self.peek();
            if (c == '=' or c == ' ' or c == '\t' or c == '\n') break;
            self.advance();
        }

        if (start == self.pos) return TomlError.ParseError;
        return try self.allocator.dupe(u8, self.content[start..self.pos]);
    }

    /// Parse a value (right side of =)
    fn parseValue(self: *Self) !root.Value {
        const c = self.peek();

        // String value (quoted)
        if (c == '"') {
            return try self.parseString();
        }

        // Parse unquoted value - could be bool, int, float, or unquoted string
        const start = self.pos;
        while (self.pos < self.content.len) {
            const ch = self.peek();
            if (ch == '\n' or ch == '#') break;
            self.advance();
        }

        const raw_value = std.mem.trim(u8, self.content[start..self.pos], " \t\r");

        // Try boolean first
        if (std.mem.eql(u8, raw_value, "true")) {
            return root.Value{ .bool_value = true };
        }
        if (std.mem.eql(u8, raw_value, "false")) {
            return root.Value{ .bool_value = false };
        }

        // Try integer
        if (std.fmt.parseInt(i64, raw_value, 10)) |int_val| {
            return root.Value{ .int_value = int_val };
        } else |_| {}

        // Try float
        if (std.fmt.parseFloat(f64, raw_value)) |float_val| {
            return root.Value{ .float_value = float_val };
        } else |_| {}

        // Default to string
        const owned_string = try self.allocator.dupe(u8, raw_value);
        return root.Value{ .string_value = owned_string };
    }

    /// Parse a quoted string value
    fn parseString(self: *Self) !root.Value {
        if (self.peek() != '"') return TomlError.ParseError;
        self.advance(); // skip opening quote

        const start = self.pos;
        while (self.pos < self.content.len and self.peek() != '"') {
            // TODO: Handle escape sequences
            self.advance();
        }

        if (self.pos >= self.content.len) return TomlError.ParseError;
        const string_content = self.content[start..self.pos];
        self.advance(); // skip closing quote

        const owned_string = try self.allocator.dupe(u8, string_content);
        return root.Value{ .string_value = owned_string };
    }

    /// Skip whitespace (but not newlines)
    fn skipWhitespace(self: *Self) void {
        while (self.pos < self.content.len) {
            const c = self.peek();
            if (c == ' ' or c == '\t' or c == '\r') {
                self.advance();
            } else {
                break;
            }
        }
    }

    /// Skip to end of line
    fn skipLine(self: *Self) void {
        while (self.pos < self.content.len and self.peek() != '\n') {
            self.advance();
        }
        if (self.pos < self.content.len) self.advance(); // skip '\n'
    }

    /// Peek at current character
    fn peek(self: *Self) u8 {
        if (self.pos >= self.content.len) return 0;
        return self.content[self.pos];
    }

    /// Advance position by one character
    fn advance(self: *Self) void {
        if (self.pos < self.content.len) {
            self.pos += 1;
        }
    }
};

/// Parse TOML content and load into a Config
pub fn loadTomlIntoConfig(config: *root.Config, content: []const u8) !void {
    var parser = TomlParser.init(config.getArenaAllocator(), content);
    var values = try parser.parse();
    defer values.deinit();

    var iter = values.iterator();
    while (iter.next()) |entry| {
        try config.setValue(entry.key_ptr.*, entry.value_ptr.*);
    }
}

test "basic toml parsing" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\name = "test-app"
        \\debug = true
        \\port = 8080
        \\timeout = 30.5
        \\
        \\[database]
        \\host = "localhost"
        \\port = 5432
        \\ssl = true
    ;

    var parser = TomlParser.init(allocator, toml_content);
    var result = try parser.parse();
    defer result.deinit();

    // Test root level values
    const name = result.get("name").?;
    try std.testing.expect(name == .string_value);
    try std.testing.expect(std.mem.eql(u8, name.string_value, "test-app"));

    const debug = result.get("debug").?;
    try std.testing.expect(debug == .bool_value);
    try std.testing.expect(debug.bool_value == true);

    const port = result.get("port").?;
    try std.testing.expect(port == .int_value);
    try std.testing.expect(port.int_value == 8080);

    // Test section values
    const db_host = result.get("database_host").?;
    try std.testing.expect(db_host == .string_value);
    try std.testing.expect(std.mem.eql(u8, db_host.string_value, "localhost"));

    const db_port = result.get("database_port").?;
    try std.testing.expect(db_port == .int_value);
    try std.testing.expect(db_port.int_value == 5432);
}

test "toml integration with config" {
    const allocator = std.testing.allocator;

    const toml_content =
        \\app_name = "my-app"
        \\[database]
        \\host = "localhost"
        \\port = 5432
    ;

    var config = try root.Config.init(allocator);
    defer config.deinit();

    try loadTomlIntoConfig(&config, toml_content);

    // Test access via dot notation
    const app_name = try config.getString("app_name", null);
    try std.testing.expect(std.mem.eql(u8, app_name, "my-app"));

    const db_host = try config.getString("database.host", null);
    try std.testing.expect(std.mem.eql(u8, db_host, "localhost"));

    const db_port = try config.getInt("database.port", null);
    try std.testing.expect(db_port == 5432);
}