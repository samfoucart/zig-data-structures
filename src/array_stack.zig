const std = @import("std");

const Allocator = std.mem.Allocator;

pub fn ArrayStack(
    comptime T: type,
) type {
    return struct {
        internal_items: ?[]T,
        size: usize,
        public_items: []T,

        const Self = @This();

        const empty: Self = .{
            .internal_items = null,
            .size = 0,
            .public_items = &.{},
        };

        pub fn deinit(self: *Self, gpa: Allocator) void {
            if (self.internal_items) |internal_items| {
                gpa.free(internal_items);
                self.internal_items = null;
            }
            self.size = 0;

            self.* = undefined;
        }

        pub fn push(self: *Self, gpa: Allocator, val: T) !void {
            if (self.internal_items) |internal_items| {
                if (self.size == internal_items.len) {
                    self.internal_items = try gpa.realloc(internal_items, internal_items.len * 2);
                }
            } else {
                self.internal_items = try gpa.alloc(T, 128);
            }

            if (self.internal_items) |internal_items| {
                internal_items[self.size] = val;
                self.size += 1;
                self.public_items = internal_items[0..self.size];
            }
        }

        pub fn pop(self: *Self, gpa: Allocator) !T {
            _ = gpa;
            if (self.internal_items) |internal_items| {
                const result = internal_items[self.size - 1];
                self.size -= 1;
                // TODO - shrink array
                self.public_items = internal_items[0..self.size];
                return result;
            }
            return error.EmptyListAccess;
        }

        pub fn peek(self: *Self) !T {
            if (self.internal_items) |internal_items| {
                return internal_items[self.size - 1];
            }

            return error.EmptyListAccess;
        }
    };
}

test "stack tests" {
    const gpa = std.testing.allocator;
    var my_stack = ArrayStack(i32).empty;
    defer my_stack.deinit(gpa);

    try std.testing.expect(my_stack.size == 0);

    try my_stack.push(gpa, 1);
    try std.testing.expect(my_stack.size == 1);
    try std.testing.expect(my_stack.public_items.len == 1);
    try std.testing.expect(try my_stack.peek() == 1);

    try my_stack.push(gpa, 3);
    try std.testing.expect(my_stack.size == 2);
    try std.testing.expect(my_stack.public_items.len == 2);
    try std.testing.expect(try my_stack.peek() == 3);

    try my_stack.push(gpa, 5);
    try std.testing.expect(my_stack.size == 3);
    try std.testing.expect(my_stack.public_items.len == 3);
    try std.testing.expect(try my_stack.peek() == 5);

    try std.testing.expect(try my_stack.pop(gpa) == 5);
    try std.testing.expect(try my_stack.pop(gpa) == 3);

    try std.testing.expect(my_stack.public_items.len == 1);
    try std.testing.expect(try my_stack.pop(gpa) == 1);

    try std.testing.expect(my_stack.public_items.len == 0);
    try std.testing.expect(my_stack.size == 0);
}
