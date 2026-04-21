//! TOML 1.0 parser - builds a TomlTable structure from tokens
//! Part of Flare's full TOML 1.0 support

const std = @import("std");
const lexer_mod = @import("toml_lexer.zig");
const toml_value = @import("toml_value.zig");

const Token = lexer_mod.Token;
const TokenType = lexer_mod.TokenType;
const Lexer = lexer_mod.Lexer;

pub const TomlValue = toml_value.TomlValue;
pub const TomlTable = toml_value.TomlTable;
pub const TomlArray = toml_value.TomlArray;
pub const Datetime = toml_value.Datetime;
pub const Date = toml_value.Date;
pub const Time = toml_value.Time;

pub const ParseError = error{
    UnexpectedToken,
    InvalidValue,
    InvalidTable,
    DuplicateKey,
    InvalidDatetime,
    OutOfMemory,
};

pub const ErrorContext = struct {
    line: usize,
    column: usize,
    source_line: ?[]const u8,
    message: []const u8,
    suggestion: ?[]const u8,
};

pub const Parser = struct {
    tokens: []const Token,
    current: usize = 0,
    allocator: std.mem.Allocator,
    source: []const u8,
    last_error: ?ErrorContext = null,

    pub fn init(allocator: std.mem.Allocator, source: []const u8, tokens: []const Token) Parser {
        return .{
            .tokens = tokens,
            .allocator = allocator,
            .source = source,
        };
    }

    pub fn getLastError(self: *const Parser) ?ErrorContext {
        return self.last_error;
    }

    pub fn parse(self: *Parser) ParseError!*TomlTable {
        const root = try self.allocator.create(TomlTable);
        root.* = TomlTable.init(self.allocator);
        errdefer {
            root.deinit();
            self.allocator.destroy(root);
        }

        var current_table = root;
        var table_path: std.ArrayList([]const u8) = .empty;
        defer table_path.deinit(self.allocator);

        while (!self.isAtEnd()) {
            // Skip newlines
            while (self.match(.newline)) {}

            if (self.isAtEnd()) break;

            // Check for table headers
            if (self.check(.left_bracket)) {
                _ = self.advance();

                // Check for array of tables [[...]]
                const is_array_table = self.match(.left_bracket);

                // Parse table path
                table_path.clearRetainingCapacity();
                try self.parseTablePath(&table_path);

                if (is_array_table) {
                    if (!self.match(.right_bracket)) {
                        return ParseError.UnexpectedToken;
                    }
                }

                if (!self.match(.right_bracket)) {
                    return ParseError.UnexpectedToken;
                }

                // Navigate/create the table structure
                current_table = try self.getOrCreateTable(root, table_path.items, is_array_table);
            } else {
                // Parse key-value pair
                try self.parseKeyValue(current_table);
            }

            // Skip trailing newlines
            while (self.match(.newline)) {}
        }

        return root;
    }

    fn parseTablePath(self: *Parser, path: *std.ArrayList([]const u8)) ParseError!void {
        const first = try self.consume(.identifier, "Expected table name");
        try path.append(self.allocator, first.lexeme);

        while (self.match(.dot)) {
            const part = try self.consume(.identifier, "Expected identifier after '.'");
            try path.append(self.allocator, part.lexeme);
        }
    }

    fn getOrCreateTable(self: *Parser, root: *TomlTable, path: []const []const u8, is_array: bool) ParseError!*TomlTable {
        if (path.len == 0) return root;

        var current = root;
        for (path, 0..) |key, i| {
            const is_last = i == path.len - 1;

            if (current.getPtr(key)) |existing| {
                if (is_last and is_array) {
                    // For array of tables, append new table to array
                    if (existing.* != .array) {
                        return ParseError.InvalidTable;
                    }
                    const new_table = try self.allocator.create(TomlTable);
                    new_table.* = TomlTable.init(self.allocator);
                    try existing.array.items.append(self.allocator, .{ .table = new_table });
                    const last_idx = existing.array.items.items.len - 1;
                    return existing.array.items.items[last_idx].table;
                } else {
                    // Navigate into existing table or array's last element
                    switch (existing.*) {
                        .table => |tbl| current = tbl,
                        .array => |arr| {
                            // For nested paths under array of tables, use the last table
                            if (arr.items.items.len > 0) {
                                const last = &arr.items.items[arr.items.items.len - 1];
                                if (last.* == .table) {
                                    current = last.table;
                                } else {
                                    return ParseError.InvalidTable;
                                }
                            } else {
                                return ParseError.InvalidTable;
                            }
                        },
                        else => return ParseError.InvalidTable,
                    }
                }
            } else {
                // Create new table or array of tables
                if (is_last and is_array) {
                    var arr = TomlArray.init(self.allocator);
                    const new_table = try self.allocator.create(TomlTable);
                    new_table.* = TomlTable.init(self.allocator);
                    try arr.items.append(self.allocator, .{ .table = new_table });
                    try current.put(key, .{ .array = arr });
                    const arr_ptr = current.getPtr(key).?;
                    const last_idx = arr_ptr.array.items.items.len - 1;
                    return arr_ptr.array.items.items[last_idx].table;
                } else {
                    const new_table = try self.allocator.create(TomlTable);
                    new_table.* = TomlTable.init(self.allocator);
                    try current.put(key, .{ .table = new_table });
                    current = current.getPtr(key).?.table;
                }
            }
        }

        return current;
    }

    fn parseKeyValue(self: *Parser, table: *TomlTable) ParseError!void {
        const key_token = try self.consume(.identifier, "Expected key");
        const key = key_token.lexeme;

        // Handle dotted keys (e.g., a.b.c = value)
        var path: std.ArrayList([]const u8) = .empty;
        defer path.deinit(self.allocator);
        try path.append(self.allocator, key);

        while (self.match(.dot)) {
            const part = try self.consume(.identifier, "Expected identifier after '.'");
            try path.append(self.allocator, part.lexeme);
        }

        _ = try self.consume(.equals, "Expected '=' after key");

        var val = try self.parseValue();
        errdefer val.deinit(self.allocator);

        // Navigate to the correct nested table for dotted keys
        var current_table = table;
        for (path.items[0 .. path.items.len - 1]) |segment| {
            if (current_table.getPtr(segment)) |existing| {
                if (existing.* != .table) {
                    return ParseError.InvalidTable;
                }
                current_table = existing.table;
            } else {
                const new_table = try self.allocator.create(TomlTable);
                new_table.* = TomlTable.init(self.allocator);
                try current_table.put(segment, .{ .table = new_table });
                current_table = current_table.getPtr(segment).?.table;
            }
        }

        const final_key = path.items[path.items.len - 1];
        if (current_table.get(final_key)) |_| {
            return ParseError.DuplicateKey;
        }

        try current_table.put(final_key, val);
    }

    fn parseValue(self: *Parser) ParseError!TomlValue {
        const token = self.advance();

        return switch (token.type) {
            .string => .{ .string = try self.parseString(token.lexeme) },
            .integer => .{ .integer = try self.parseInteger(token.lexeme) },
            .float => .{ .float = try self.parseFloat(token.lexeme) },
            .boolean => .{ .boolean = std.mem.eql(u8, token.lexeme, "true") },
            .datetime => try self.parseDatetimeValue(token.lexeme),
            .left_bracket => try self.parseArray(),
            .left_brace => try self.parseInlineTable(),
            else => ParseError.UnexpectedToken,
        };
    }

    fn parseString(self: *Parser, lexeme: []const u8) ParseError![]const u8 {
        if (lexeme.len < 2) return ParseError.InvalidValue;

        const quote = lexeme[0];
        const is_literal = (quote == '\'');
        var result: std.ArrayList(u8) = .empty;
        defer result.deinit(self.allocator);

        // Check for multi-line strings (triple quotes)
        const is_multiline = lexeme.len >= 6 and lexeme[1] == quote and lexeme[2] == quote;

        if (is_multiline) {
            var content = lexeme[3 .. lexeme.len - 3];

            // TOML spec: trim first newline after opening quotes if present
            if (content.len > 0 and content[0] == '\n') {
                content = content[1..];
            } else if (content.len > 1 and content[0] == '\r' and content[1] == '\n') {
                content = content[2..];
            }

            if (is_literal) {
                try result.appendSlice(self.allocator, content);
            } else {
                var i: usize = 0;
                while (i < content.len) {
                    if (content[i] == '\\') {
                        i += 1;
                        if (i >= content.len) break;

                        const escaped_char = content[i];
                        switch (escaped_char) {
                            'b' => try result.append(self.allocator, '\x08'),
                            't' => try result.append(self.allocator, '\t'),
                            'n' => try result.append(self.allocator, '\n'),
                            'f' => try result.append(self.allocator, '\x0C'),
                            'r' => try result.append(self.allocator, '\r'),
                            '"' => try result.append(self.allocator, '"'),
                            '\\' => try result.append(self.allocator, '\\'),
                            '\n' => {
                                i += 1;
                                while (i < content.len and (content[i] == ' ' or content[i] == '\t' or content[i] == '\n' or content[i] == '\r')) {
                                    i += 1;
                                }
                                i -= 1;
                            },
                            '\r' => {
                                if (i + 1 < content.len and content[i + 1] == '\n') {
                                    i += 2;
                                    while (i < content.len and (content[i] == ' ' or content[i] == '\t' or content[i] == '\n' or content[i] == '\r')) {
                                        i += 1;
                                    }
                                    i -= 1;
                                } else {
                                    try result.append(self.allocator, escaped_char);
                                }
                            },
                            'u' => {
                                // Unicode escape \uXXXX (4 hex digits)
                                const hex_count: usize = 4;
                                if (i + 1 + hex_count > content.len) {
                                    return ParseError.InvalidValue;
                                }
                                const hex_str = content[i + 1 .. i + 1 + hex_count];
                                const codepoint = std.fmt.parseInt(u21, hex_str, 16) catch return ParseError.InvalidValue;
                                try self.appendUtf8(&result, codepoint);
                                i += hex_count;
                            },
                            'U' => {
                                // Unicode escape \UXXXXXXXX (8 hex digits)
                                const hex_count: usize = 8;
                                if (i + 1 + hex_count > content.len) {
                                    return ParseError.InvalidValue;
                                }
                                const hex_str = content[i + 1 .. i + 1 + hex_count];
                                const codepoint = std.fmt.parseInt(u21, hex_str, 16) catch return ParseError.InvalidValue;
                                try self.appendUtf8(&result, codepoint);
                                i += hex_count;
                            },
                            else => {
                                try result.append(self.allocator, escaped_char);
                            },
                        }
                        i += 1;
                    } else {
                        try result.append(self.allocator, content[i]);
                        i += 1;
                    }
                }
            }
        } else {
            const content = lexeme[1 .. lexeme.len - 1];

            if (is_literal) {
                try result.appendSlice(self.allocator, content);
            } else {
                var i: usize = 0;
                while (i < content.len) : (i += 1) {
                    if (content[i] == '\\') {
                        i += 1;
                        if (i >= content.len) break;

                        switch (content[i]) {
                            'b' => try result.append(self.allocator, '\x08'),
                            't' => try result.append(self.allocator, '\t'),
                            'n' => try result.append(self.allocator, '\n'),
                            'f' => try result.append(self.allocator, '\x0C'),
                            'r' => try result.append(self.allocator, '\r'),
                            '"' => try result.append(self.allocator, '"'),
                            '\\' => try result.append(self.allocator, '\\'),
                            'u' => {
                                // Unicode escape \uXXXX (4 hex digits)
                                const hex_count: usize = 4;
                                if (i + 1 + hex_count > content.len) {
                                    return ParseError.InvalidValue;
                                }
                                const hex_str = content[i + 1 .. i + 1 + hex_count];
                                const codepoint = std.fmt.parseInt(u21, hex_str, 16) catch return ParseError.InvalidValue;
                                try self.appendUtf8(&result, codepoint);
                                i += hex_count;
                            },
                            'U' => {
                                // Unicode escape \UXXXXXXXX (8 hex digits)
                                const hex_count: usize = 8;
                                if (i + 1 + hex_count > content.len) {
                                    return ParseError.InvalidValue;
                                }
                                const hex_str = content[i + 1 .. i + 1 + hex_count];
                                const codepoint = std.fmt.parseInt(u21, hex_str, 16) catch return ParseError.InvalidValue;
                                try self.appendUtf8(&result, codepoint);
                                i += hex_count;
                            },
                            else => try result.append(self.allocator, content[i]),
                        }
                    } else {
                        try result.append(self.allocator, content[i]);
                    }
                }
            }
        }

        return self.allocator.dupe(u8, result.items);
    }

    /// Append a Unicode code point as UTF-8 bytes
    fn appendUtf8(self: *Parser, result: *std.ArrayList(u8), codepoint: u21) ParseError!void {
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(codepoint, &buf) catch return ParseError.InvalidValue;
        try result.appendSlice(self.allocator, buf[0..len]);
    }

    fn parseInteger(self: *Parser, lexeme: []const u8) ParseError!i64 {
        // Determine base and content start position
        var base: u8 = 10;
        var content_start: usize = 0;
        var is_negative = false;

        // Handle sign prefix
        if (lexeme.len > 0 and (lexeme[0] == '+' or lexeme[0] == '-')) {
            if (lexeme[0] == '-') is_negative = true;
            content_start = 1;
        }

        // Check for hex/octal/binary prefix
        if (lexeme.len >= content_start + 2) {
            if (lexeme[content_start] == '0') {
                const prefix = lexeme[content_start + 1];
                if (prefix == 'x' or prefix == 'X') {
                    base = 16;
                    content_start += 2;
                } else if (prefix == 'o' or prefix == 'O') {
                    base = 8;
                    content_start += 2;
                } else if (prefix == 'b' or prefix == 'B') {
                    base = 2;
                    content_start += 2;
                } else if (std.ascii.isDigit(prefix)) {
                    // Leading zeros not allowed for decimal (e.g., 007 is invalid)
                    return ParseError.InvalidValue;
                }
            }
        }

        const content = lexeme[content_start..];
        if (content.len == 0) return ParseError.InvalidValue;

        // Validate underscore placement in content
        if (content[0] == '_' or content[content.len - 1] == '_') {
            return ParseError.InvalidValue;
        }

        var prev_was_underscore = false;
        for (content) |c| {
            if (c == '_') {
                if (prev_was_underscore) {
                    return ParseError.InvalidValue;
                }
                prev_was_underscore = true;
            } else {
                prev_was_underscore = false;
            }
        }

        // Remove underscores for parsing
        var cleaned: std.ArrayList(u8) = .empty;
        defer cleaned.deinit(self.allocator);

        for (content) |c| {
            if (c != '_') {
                try cleaned.append(self.allocator, c);
            }
        }

        const result = std.fmt.parseInt(i64, cleaned.items, base) catch return ParseError.InvalidValue;
        return if (is_negative) -result else result;
    }

    fn parseFloat(self: *Parser, lexeme: []const u8) ParseError!f64 {
        if (std.mem.eql(u8, lexeme, "inf") or std.mem.eql(u8, lexeme, "+inf")) {
            return std.math.inf(f64);
        }
        if (std.mem.eql(u8, lexeme, "-inf")) {
            return -std.math.inf(f64);
        }
        if (std.mem.eql(u8, lexeme, "nan") or std.mem.eql(u8, lexeme, "+nan") or std.mem.eql(u8, lexeme, "-nan")) {
            return std.math.nan(f64);
        }

        // Validate underscore placement
        if (lexeme.len > 0) {
            if (lexeme[0] == '_' or lexeme[lexeme.len - 1] == '_') {
                return ParseError.InvalidValue;
            }

            var prev_was_underscore = false;
            var i: usize = 0;
            while (i < lexeme.len) : (i += 1) {
                const c = lexeme[i];

                if (c == '_') {
                    if (prev_was_underscore) {
                        return ParseError.InvalidValue;
                    }
                    if (i > 0) {
                        const prev = lexeme[i - 1];
                        if (prev == '.' or prev == 'e' or prev == 'E' or prev == '+' or prev == '-') {
                            return ParseError.InvalidValue;
                        }
                    }
                    if (i < lexeme.len - 1) {
                        const next = lexeme[i + 1];
                        if (next == '.' or next == 'e' or next == 'E' or next == '+' or next == '-') {
                            return ParseError.InvalidValue;
                        }
                    }
                    prev_was_underscore = true;
                } else {
                    prev_was_underscore = false;
                }
            }
        }

        // Remove underscores for parsing
        var cleaned: std.ArrayList(u8) = .empty;
        defer cleaned.deinit(self.allocator);

        for (lexeme) |c| {
            if (c != '_') {
                try cleaned.append(self.allocator, c);
            }
        }

        return std.fmt.parseFloat(f64, cleaned.items) catch ParseError.InvalidValue;
    }

    fn parseDatetimeValue(self: *Parser, lexeme: []const u8) ParseError!TomlValue {
        // Check if it's just a date (YYYY-MM-DD with length 10)
        if (lexeme.len == 10 and lexeme[4] == '-' and lexeme[7] == '-') {
            return .{ .date = try self.parseDate(lexeme) };
        }

        // Check if it's just a time (HH:MM:SS...)
        if (lexeme.len >= 8 and lexeme[2] == ':' and lexeme[5] == ':') {
            return .{ .time = try self.parseTime(lexeme) };
        }

        // Otherwise it's a full datetime
        return .{ .datetime = try self.parseDatetime(lexeme) };
    }

    fn parseDate(self: *Parser, lexeme: []const u8) ParseError!Date {
        _ = self;
        if (lexeme.len != 10) return ParseError.InvalidDatetime;

        const year = std.fmt.parseInt(u16, lexeme[0..4], 10) catch return ParseError.InvalidDatetime;
        const month = std.fmt.parseInt(u8, lexeme[5..7], 10) catch return ParseError.InvalidDatetime;
        const day = std.fmt.parseInt(u8, lexeme[8..10], 10) catch return ParseError.InvalidDatetime;

        if (month < 1 or month > 12) return ParseError.InvalidDatetime;
        if (day < 1 or day > 31) return ParseError.InvalidDatetime;

        const days_in_month = [_]u8{ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        if (day > days_in_month[month - 1]) return ParseError.InvalidDatetime;

        return .{ .year = year, .month = month, .day = day };
    }

    fn parseTime(self: *Parser, lexeme: []const u8) ParseError!Time {
        _ = self;
        if (lexeme.len < 8) return ParseError.InvalidDatetime;

        const hour = std.fmt.parseInt(u8, lexeme[0..2], 10) catch return ParseError.InvalidDatetime;
        const minute = std.fmt.parseInt(u8, lexeme[3..5], 10) catch return ParseError.InvalidDatetime;
        const second = std.fmt.parseInt(u8, lexeme[6..8], 10) catch return ParseError.InvalidDatetime;

        if (hour > 23) return ParseError.InvalidDatetime;
        if (minute > 59) return ParseError.InvalidDatetime;
        if (second > 60) return ParseError.InvalidDatetime;

        var nanosecond: u32 = 0;

        if (lexeme.len > 8 and lexeme[8] == '.') {
            var pos: usize = 9;
            const frac_start = pos;

            while (pos < lexeme.len and std.ascii.isDigit(lexeme[pos])) {
                pos += 1;
            }

            if (pos == frac_start) return ParseError.InvalidDatetime;

            const frac_str = lexeme[frac_start..pos];
            var nanos: u32 = 0;
            var multiplier: u32 = 100_000_000;

            for (frac_str, 0..) |c, i| {
                if (i >= 9) break;
                const digit = c - '0';
                nanos += digit * multiplier;
                multiplier /= 10;
            }

            nanosecond = nanos;

            if (pos != lexeme.len) return ParseError.InvalidDatetime;
        }

        return .{ .hour = hour, .minute = minute, .second = second, .nanosecond = nanosecond };
    }

    fn parseDatetime(self: *Parser, lexeme: []const u8) ParseError!Datetime {
        _ = self;
        var dt: Datetime = undefined;

        if (lexeme.len < 10) return ParseError.InvalidDatetime;

        dt.year = std.fmt.parseInt(u16, lexeme[0..4], 10) catch return ParseError.InvalidDatetime;
        dt.month = std.fmt.parseInt(u8, lexeme[5..7], 10) catch return ParseError.InvalidDatetime;
        dt.day = std.fmt.parseInt(u8, lexeme[8..10], 10) catch return ParseError.InvalidDatetime;

        if (dt.month < 1 or dt.month > 12) return ParseError.InvalidDatetime;
        if (dt.day < 1 or dt.day > 31) return ParseError.InvalidDatetime;

        const days_in_month = [_]u8{ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        if (dt.day > days_in_month[dt.month - 1]) return ParseError.InvalidDatetime;

        if (lexeme.len > 10 and (lexeme[10] == 'T' or lexeme[10] == 't' or lexeme[10] == ' ')) {
            if (lexeme.len < 19) return ParseError.InvalidDatetime;

            dt.hour = std.fmt.parseInt(u8, lexeme[11..13], 10) catch return ParseError.InvalidDatetime;
            dt.minute = std.fmt.parseInt(u8, lexeme[14..16], 10) catch return ParseError.InvalidDatetime;
            dt.second = std.fmt.parseInt(u8, lexeme[17..19], 10) catch return ParseError.InvalidDatetime;

            if (dt.hour > 23) return ParseError.InvalidDatetime;
            if (dt.minute > 59) return ParseError.InvalidDatetime;
            if (dt.second > 60) return ParseError.InvalidDatetime;

            var pos: usize = 19;

            if (pos < lexeme.len and lexeme[pos] == '.') {
                pos += 1;
                const frac_start = pos;

                while (pos < lexeme.len and std.ascii.isDigit(lexeme[pos])) {
                    pos += 1;
                }

                if (pos == frac_start) return ParseError.InvalidDatetime;

                const frac_str = lexeme[frac_start..pos];
                var nanos: u32 = 0;
                var multiplier: u32 = 100_000_000;

                for (frac_str, 0..) |c, i| {
                    if (i >= 9) break;
                    const digit = c - '0';
                    nanos += digit * multiplier;
                    multiplier /= 10;
                }

                dt.nanosecond = nanos;
            } else {
                dt.nanosecond = 0;
            }

            if (pos < lexeme.len) {
                const tz_char = lexeme[pos];

                if (tz_char == 'Z' or tz_char == 'z') {
                    dt.offset_minutes = 0;
                    pos += 1;
                } else if (tz_char == '+' or tz_char == '-') {
                    pos += 1;

                    if (pos + 5 > lexeme.len) return ParseError.InvalidDatetime;
                    if (lexeme[pos + 2] != ':') return ParseError.InvalidDatetime;

                    const tz_hour = std.fmt.parseInt(i16, lexeme[pos .. pos + 2], 10) catch return ParseError.InvalidDatetime;
                    const tz_min = std.fmt.parseInt(i16, lexeme[pos + 3 .. pos + 5], 10) catch return ParseError.InvalidDatetime;

                    if (tz_hour > 23 or tz_min > 59) return ParseError.InvalidDatetime;

                    var offset: i16 = tz_hour * 60 + tz_min;
                    if (tz_char == '-') offset = -offset;

                    dt.offset_minutes = offset;
                    pos += 5;
                } else {
                    dt.offset_minutes = null;
                }
            } else {
                dt.offset_minutes = null;
            }

            if (pos != lexeme.len) return ParseError.InvalidDatetime;
        } else {
            dt.hour = 0;
            dt.minute = 0;
            dt.second = 0;
            dt.nanosecond = 0;
            dt.offset_minutes = null;
        }

        return dt;
    }

    fn parseArray(self: *Parser) ParseError!TomlValue {
        var arr = TomlArray.init(self.allocator);
        errdefer arr.deinit(self.allocator);

        while (!self.check(.right_bracket) and !self.isAtEnd()) {
            while (self.match(.newline)) {}
            if (self.check(.right_bracket)) break;

            const val = try self.parseValue();
            try arr.items.append(self.allocator, val);

            while (self.match(.newline)) {}

            if (!self.match(.comma)) {
                while (self.match(.newline)) {}
                break;
            }

            while (self.match(.newline)) {}
        }

        _ = try self.consume(.right_bracket, "Expected ']' after array");
        return .{ .array = arr };
    }

    fn parseInlineTable(self: *Parser) ParseError!TomlValue {
        const tbl = try self.allocator.create(TomlTable);
        tbl.* = TomlTable.init(self.allocator);
        errdefer {
            tbl.deinit();
            self.allocator.destroy(tbl);
        }

        while (!self.check(.right_brace) and !self.isAtEnd()) {
            const key_token = try self.consume(.identifier, "Expected key in inline table");
            const key = key_token.lexeme;

            _ = try self.consume(.equals, "Expected '=' after key");

            const val = try self.parseValue();
            try tbl.put(key, val);

            if (!self.match(.comma)) break;
        }

        _ = try self.consume(.right_brace, "Expected '}' after inline table");
        return .{ .table = tbl };
    }

    fn match(self: *Parser, token_type: TokenType) bool {
        if (self.check(token_type)) {
            _ = self.advance();
            return true;
        }
        return false;
    }

    fn check(self: *const Parser, token_type: TokenType) bool {
        if (self.isAtEnd()) return false;
        return self.peek().type == token_type;
    }

    fn advance(self: *Parser) Token {
        if (!self.isAtEnd()) self.current += 1;
        return self.previous();
    }

    fn isAtEnd(self: *const Parser) bool {
        return self.peek().type == .eof;
    }

    fn peek(self: *const Parser) Token {
        return self.tokens[self.current];
    }

    fn previous(self: *const Parser) Token {
        return self.tokens[self.current - 1];
    }

    fn consume(self: *Parser, token_type: TokenType, message: []const u8) ParseError!Token {
        if (self.check(token_type)) return self.advance();

        const token = self.peek();
        self.last_error = ErrorContext{
            .line = token.line,
            .column = token.column,
            .source_line = self.getSourceLine(token.line),
            .message = message,
            .suggestion = self.getSuggestion(token_type, token.type),
        };

        return ParseError.UnexpectedToken;
    }

    fn getSourceLine(self: *const Parser, line_num: usize) ?[]const u8 {
        var current_line: usize = 1;
        var line_start: usize = 0;

        for (self.source, 0..) |c, i| {
            if (current_line == line_num) {
                var line_end = i;
                while (line_end < self.source.len and self.source[line_end] != '\n') {
                    line_end += 1;
                }
                return self.source[line_start..line_end];
            }
            if (c == '\n') {
                current_line += 1;
                line_start = i + 1;
            }
        }

        return null;
    }

    fn getSuggestion(self: *const Parser, expected: TokenType, got: TokenType) ?[]const u8 {
        _ = self;
        return switch (expected) {
            .identifier => switch (got) {
                .equals => "Did you forget to add a key before the '='?",
                .right_bracket => "Expected a table or array name",
                else => "Expected an identifier (name)",
            },
            .equals => switch (got) {
                .identifier => "Did you mean to use a dot '.' for a nested key?",
                else => "Expected '=' after key",
            },
            .right_bracket => switch (got) {
                .eof => "Missing closing bracket ']'",
                else => "Expected ']' to close table or array",
            },
            .right_brace => switch (got) {
                .eof => "Missing closing brace '}'",
                else => "Expected '}' to close inline table",
            },
            else => null,
        };
    }
};

/// Parse TOML source into a TomlTable
pub fn parseToml(allocator: std.mem.Allocator, source: []const u8) !*TomlTable {
    var lex = Lexer.init(allocator, source);
    defer lex.deinit();

    const tokens = lex.scanTokens() catch |err| switch (err) {
        lexer_mod.LexError.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidValue,
    };

    var parser = Parser.init(allocator, source, tokens);
    return parser.parse();
}

/// Result of parsing with context - contains either table or error details
pub const ParseResult = struct {
    table: ?*TomlTable,
    error_context: ?ErrorContext,

    pub fn isSuccess(self: ParseResult) bool {
        return self.table != null;
    }

    pub fn isError(self: ParseResult) bool {
        return self.error_context != null;
    }
};

/// Parse TOML source with detailed error context on failure
/// Returns ParseResult containing either the table or error details
pub fn parseTomlWithContext(allocator: std.mem.Allocator, source: []const u8) ParseResult {
    var lex = Lexer.init(allocator, source);
    defer lex.deinit();

    const tokens = lex.scanTokens() catch |err| {
        // Lexer error - create context from lexer state
        const line = lex.line;
        const column = lex.column;
        return ParseResult{
            .table = null,
            .error_context = .{
                .line = line,
                .column = column,
                .source_line = getSourceLine(source, line),
                .message = switch (err) {
                    lexer_mod.LexError.UnterminatedString => "Unterminated string literal",
                    lexer_mod.LexError.InvalidEscape => "Invalid escape sequence",
                    lexer_mod.LexError.UnexpectedChar => "Unexpected character",
                    lexer_mod.LexError.NumberFormat => "Invalid number format",
                    lexer_mod.LexError.OutOfMemory => "Out of memory",
                },
                .suggestion = switch (err) {
                    lexer_mod.LexError.UnterminatedString => "Add a closing quote",
                    lexer_mod.LexError.InvalidEscape => "Use valid escape: \\n, \\t, \\r, \\\\, \\\", \\uXXXX",
                    else => null,
                },
            },
        };
    };

    var parser = Parser.init(allocator, source, tokens);
    const table = parser.parse() catch {
        // Parser error - get context from parser
        const ctx = parser.getLastError() orelse ErrorContext{
            .line = if (parser.current < parser.tokens.len) parser.tokens[parser.current].line else 1,
            .column = if (parser.current < parser.tokens.len) parser.tokens[parser.current].column else 1,
            .source_line = null,
            .message = "Parse error",
            .suggestion = null,
        };
        return ParseResult{
            .table = null,
            .error_context = ctx,
        };
    };

    return ParseResult{
        .table = table,
        .error_context = null,
    };
}

/// Extract source line for error reporting
fn getSourceLine(source: []const u8, line_number: usize) ?[]const u8 {
    var current_line: usize = 1;
    var line_start: usize = 0;

    for (source, 0..) |c, i| {
        if (current_line == line_number) {
            if (c == '\n') {
                return source[line_start..i];
            }
        } else if (c == '\n') {
            current_line += 1;
            line_start = i + 1;
        }
    }

    // Last line without newline
    if (current_line == line_number) {
        return source[line_start..];
    }

    return null;
}

test "parser basic key-value" {
    const testing = std.testing;

    const source = "name = \"flare\"\nversion = 1";
    var table = try parseToml(testing.allocator, source);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    const name = table.get("name");
    try testing.expect(name != null);
    try testing.expectEqualStrings("flare", name.?.string);
}

test "parser table" {
    const testing = std.testing;

    const source =
        \\[package]
        \\name = "flare"
        \\version = 1
    ;

    var table = try parseToml(testing.allocator, source);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    const package = table.get("package");
    try testing.expect(package != null);
    try testing.expect(package.?.table.get("name") != null);
}

test "parser array" {
    const testing = std.testing;

    const source = "numbers = [1, 2, 3]";
    var table = try parseToml(testing.allocator, source);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    const numbers = table.get("numbers");
    try testing.expect(numbers != null);
    try testing.expectEqual(@as(usize, 3), numbers.?.array.items.items.len);
}

test "parser nested table" {
    const testing = std.testing;

    const source =
        \\[database]
        \\host = "localhost"
        \\port = 5432
        \\
        \\[database.connection]
        \\timeout = 30
    ;

    var table = try parseToml(testing.allocator, source);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    const db = table.get("database");
    try testing.expect(db != null);
    try testing.expect(db.?.table.get("host") != null);
    try testing.expect(db.?.table.get("connection") != null);
}

test "parser inline table" {
    const testing = std.testing;

    const source = "point = { x = 1, y = 2 }";
    var table = try parseToml(testing.allocator, source);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    const point = table.get("point");
    try testing.expect(point != null);
    try testing.expect(point.?.table.get("x") != null);
    try testing.expect(point.?.table.get("y") != null);
}

test "parser array of tables" {
    const testing = std.testing;

    const source =
        \\[[products]]
        \\name = "Hammer"
        \\
        \\[[products]]
        \\name = "Nail"
    ;

    var table = try parseToml(testing.allocator, source);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    const products = table.get("products");
    try testing.expect(products != null);
    try testing.expectEqual(@as(usize, 2), products.?.array.items.items.len);
}

test "parser datetime" {
    const testing = std.testing;

    const source = "created = 2024-01-15T10:30:00Z";
    var table = try parseToml(testing.allocator, source);
    defer {
        table.deinit();
        testing.allocator.destroy(table);
    }

    const created = table.get("created");
    try testing.expect(created != null);
    try testing.expect(created.? == .datetime);
    try testing.expectEqual(@as(u16, 2024), created.?.datetime.year);
    try testing.expectEqual(@as(u8, 1), created.?.datetime.month);
    try testing.expectEqual(@as(u8, 15), created.?.datetime.day);
}
