const std = @import("std");

const Allocator = std.mem.Allocator;

pub fn AvlTree(
    comptime T: type,
    comptime compareFn: fn (a: T, b: T) std.math.Order,
) type {
    _ = compareFn;

    return struct {
        root: ?*AvlNode,
        size: usize,

        const Self = @This();

        pub const empty: Self = .{
            .root = null,
            .size = 0,
        };

        const AvlNode = struct {
            val: T,
            height: usize,
            left: ?*AvlNode,
            right: ?*AvlNode,
        };

        pub fn deinit(self: *Self, gpa: Allocator) void {
            deinitRecursinve(self, gpa, self.root);

            self.* = undefined;
        }

        pub fn deinitRecursinve(self: *Self, gpa: Allocator, root: ?*AvlNode) void {
            if (root) |root_nn| {
                self.deinitRecursive(self, gpa, root_nn.left);
                self.deinitRecursive(self, gpa, root_nn.right);

                gpa.destroy(root_nn);
            }
        }
    };
}

fn order_i32(a: i32, b: i32) std.math.Order {
    return std.math.order(a, b);
}

test "init" {
    const gpa = std.testing.allocator;

    var my_avl_tree = AvlTree(i32, order_i32).empty;
    defer my_avl_tree.deinit(gpa);
}
