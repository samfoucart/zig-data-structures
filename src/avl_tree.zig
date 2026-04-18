const std = @import("std");

const ArrayStack = @import("./array_stack.zig").ArrayStack;

const Allocator = std.mem.Allocator;

pub fn AvlTree(
    comptime T: type,
    comptime compareFn: fn (a: T, b: T) std.math.Order,
) type {
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
            height: i32,
            left: ?*AvlNode,
            right: ?*AvlNode,
        };

        pub const ForwardIterator = struct {
            const TraversalRecursionStates = enum { first, second, third };
            const TraversalRecursionState = struct {
                state: TraversalRecursionStates,
                node: ?*AvlNode,
            };

            internal_stack: ArrayStack(TraversalRecursionState),
            tree: *AvlTree,

            const ItrSelf = @This();

            pub fn deinit(self: *ItrSelf, gpa: Allocator) void {
                self.internal_stack.deinit(gpa);
            }

            pub fn next(self: *ItrSelf, gpa: Allocator) !?T {
                if (self.internal_stack.size == 0) {
                    try self.internal_stack.push(gpa, .{ .state = TraversalRecursionState.first, .node = self.tree.root });
                }

                while (self.internal_stack.size > 0) {
                    const current = try self.internal_stack.pop();

                    if (current.node) |node_nn| {
                        if (current.state == TraversalRecursionState.first) {
                            try self.internal_stack.push(gpa, .{ .state = TraversalRecursionState.second, .node = current.node });
                            try self.internal_stack.push(gpa, .{ .state = TraversalRecursionState.first, .node = node_nn.left });
                        } else if (current.state == TraversalRecursionState.second) {
                            try self.internal_stack.push(gpa, .{ .state = TraversalRecursionState.first, .node = node_nn.right });

                            return node_nn.val;
                        }
                    }
                }

                return null;
            }
        };

        pub fn iter(self: *Self) ForwardIterator {
            return .{
                .internal_stack = ArrayStack(ForwardIterator.TraversalRecursionState).empty,
                .tree = self,
            };
        }

        pub fn deinit(self: *Self, gpa: Allocator) void {
            // This is a "Morris Traveral". Google Gemini first told me that this was possible,
            // and I read the wikipedia article. It's also called "Threaded Binary Trees",
            // not to be confused with multithreading.
            //
            // If you make each node's predecessor, (the right most child to the first left child)
            // point back to the successor, then you can delete them without using any recursion or stack space.
            //
            // If a node has a left child, make the right most child point back to the node. Then traverse left.
            //
            // Once you hit a node without a left child, get a pointer to it's right child, then free it. Then traverse right.
            //
            // It's hard to prove with words, but if you draw a picture of a binary tree, it's somewhat easy to visually prove that
            // this works.

            var current = self.root;
            while (current) |node| {
                if (node.left) |left| {
                    // Get right most predecessor

                    var pred = left;

                    // I don't think that
                    // `pred.right == node`
                    // can ever come true. I think that this is something
                    // Gemini made up that applies to a real threaded tree,
                    // but not to this use case.
                    while (pred.right != null and pred.right != node) {
                        pred = pred.right.?;
                    }

                    if (pred.right == null) {
                        // Make the predecessor point back to our current traversal node.
                        // This only really makes sense if you draw a picture of this.
                        //
                        // Create a "thread"
                        pred.right = current;
                        current = left;
                    } else {
                        // I don't know if this branch is actually reachable.
                        // Gemini says:
                        // Link already exists: we are returning from the left side.
                        // Restore the tree (unlink) so we can proceed to the right side safely.
                        //
                        // I can't figure out how to come up with an example where we hit this.
                        // Maybe this only applies to real threaded trees, but not ours right now.

                        pred.right = null;
                        const right = node.right;
                        gpa.destroy(node);
                        current = right;
                    }
                } else {
                    // Actually free the left-most node
                    const right = node.right;
                    gpa.destroy(node);
                    current = right;
                }
            }

            self.* = undefined;
        }

        fn rotateLeft(node: ?*AvlNode) !?*AvlNode {
            if (node) |node_nn| {
                std.debug.assert(node_nn.right != null);
                if (node_nn.right) |right| {
                    node_nn.right = right.left;
                    right.left = node_nn;
                    return right;
                } else {
                    return error.InvalidInternalState;
                }
            } else {
                return null;
            }
        }

        fn rotateRight(self: *Self, node: ?*AvlNode) !?*AvlNode {
            if (node) |node_nn| {
                std.debug.assert(node_nn.left != null);
                if (node_nn.left) |left| {
                    node_nn.left = left.right;
                    left.right = node_nn;

                    node_nn.height = self.calculateHeight(node_nn);
                    left.height = self.calculateHeight(left);

                    return left;
                } else {
                    return error.InvalidInternalState;
                }
            } else {
                return null;
            }
        }

        fn calculateHeight(self: *Self, node: *AvlNode) i32 {
            const height_left = self.getHeight(node.left);
            const height_right = self.getHeight(node.right);

            return if (height_left > height_right) height_left + 1 else height_right + 1;
        }

        fn getHeight(node: ?*AvlNode) i32 {
            if (node) |node_nn| {
                return node_nn.height;
            }

            return -1;
        }

        fn fixAvlProperty(self: *Self, node: ?*AvlNode) !?*AvlNode {
            if (node) |node_nn| {
                node_nn.height = self.calculateHeight(node_nn);

                const balance = self.getHeight(node_nn.right) - self.getHeight(node_nn.left);

                // Right Imbalance
                if (balance == 2) {
                    std.debug.assert(node_nn.right != null);
                    if (node_nn.right) |right| {
                        const right_balance = self.getHeight(right.right) - self.getHeight(right.left);
                        std.debug.assert(right_balance == 1 or right_balance == -1);

                        // Right Right Imbalance
                        if (right_balance == 1) {
                            return try self.rotateLeft(node_nn);
                        }

                        // Right Left Imabalance
                        if (right_balance == -1) {
                            node_nn.right = try self.rotateRight(right);
                            return try self.rotateLeft(node_nn);
                        }

                        return error.InvalidInternalState;
                    } else {
                        return error.InvalidInternalState;
                    }
                }

                // Left Imbalance
                if (balance == -2) {
                    std.debug.assert(node_nn.left != null);
                    if (node_nn.left) |left| {
                        const left_balance = self.getHeight(left.right) - self.getHeight(left.left);
                        std.debug.assert(left_balance == 1 or left_balance == -1);

                        // Left Right Imbalance
                        if (left_balance == 1) {
                            node_nn.left = try self.rotateLeft(left);
                            return try self.rotateRight(node_nn);
                        }

                        // Left Left Imabalance
                        if (left_balance == -1) {
                            return try self.rotateRight(node_nn);
                        }

                        return error.InvalidInternalState;
                    } else {
                        return error.InvalidInternalState;
                    }
                }

                if (balance > 2 or balance < -2) {
                    return error.InvalidInternalState;
                }

                return node_nn;
            } else {
                return null;
            }
        }

        pub fn add(self: *Self, gpa: Allocator, val: T) !void {
            if (self.root != null) {
                const TraversalPosition = enum { initial, addNode };

                const RecursionState = struct {
                    traversal_position: TraversalPosition,
                    node: ?*AvlNode,
                };

                var recursion = ArrayStack(RecursionState).empty;
                defer recursion.deinit(gpa);

                recursion.push(.{ .traversal_position = TraversalPosition.initial, .node = self.root });

                var last_touched_node: ?*AvlNode = null;

                while (recursion.size > 0) {
                    const current = try recursion.pop();
                    if (current.node) |node| {
                        if (current.traversal_position == TraversalPosition.initial) {
                            try recursion.push(.{ .traversal_position = TraversalPosition.addNode, .node = current.node });

                            const comparison = compareFn(val, node.val);
                            if (comparison == std.math.Order.lt or comparison == std.math.Order.eq) {
                                try recursion.push(.{ .traversal_position = TraversalPosition.initial, .node = node.left });
                            } else {
                                try recursion.push(.{ .traversal_position = TraversalPosition.initial, .node = node.right });
                            }
                        } else if (current.traversal_position == TraversalPosition.addNode) {
                            const comparison = compareFn(val, node.val);

                            if (comparison == std.math.Order.lt or comparison == std.math.Order.eq) {
                                node.left = last_touched_node;
                                node.left = try fixAvlProperty(node.left);
                            } else {
                                node.right = last_touched_node;
                                node.right = try fixAvlProperty(node.right);
                            }

                            node.height = self.calculateHeight(node);

                            last_touched_node = current.node;
                        }
                    } else {
                        const new_node = try gpa.create(AvlNode);
                        new_node = .{
                            .val = val,
                            .height = 0,
                            .left = null,
                            .right = null,
                        };

                        last_touched_node = new_node;
                    }
                }

                self.root = last_touched_node;
            } else {
                std.debug.assert(self.size == 0);

                const new_node = try gpa.create(AvlNode);
                new_node = .{
                    .val = val,
                    .height = 0,
                    .left = null,
                    .right = null,
                };

                self.root = new_node;
            }

            self.size += 1;
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
