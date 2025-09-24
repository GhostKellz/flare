const std = @import("std");
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test various initialization methods
    const ListType = std.ArrayList(i32);

    // Try direct initialization
    var list: ListType = .{
        .items = &[_]i32{},
        .capacity = 0,
        .allocator = allocator,
    };

    defer if (@sizeOf(i32) > 0) {
        allocator.free(list.allocatedSlice());
    };

    try list.append(42);
    std.debug.print("Success: {any}\n", .{list.items});
}
