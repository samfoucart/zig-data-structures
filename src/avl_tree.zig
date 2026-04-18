const std = @import("std");
const expectEqual = std.testing.expectEqual;

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
            const TraversalRecursionStates = enum { first, second };
            const TraversalRecursionState = struct {
                state: TraversalRecursionStates,
                node: ?*AvlNode,
            };

            internal_stack: ?ArrayStack(TraversalRecursionState),
            tree: *AvlTree(T, compareFn),

            const ItrSelf = @This();

            pub fn deinit(self: *ItrSelf, gpa: Allocator) void {
                if (self.internal_stack) |*internal_stack| {
                    internal_stack.deinit(gpa);
                }
            }

            pub fn next(self: *ItrSelf, gpa: Allocator) !?T {
                if (self.internal_stack) |*internal_stack| {
                    if (internal_stack.size == 0) {
                        std.debug.print("AvlTree.ForwardIterator.next() - returning null because stack existed and was empty\n", .{});
                        return null;
                    }
                } else {
                    self.internal_stack = ArrayStack(TraversalRecursionState).empty;

                    std.debug.print("AvlTree.ForwardIterator.next() - Adding root node to stack\n", .{});
                    try self.internal_stack.?.push(gpa, .{ .state = TraversalRecursionStates.first, .node = self.tree.root });
                }

                if (self.internal_stack) |*internal_stack| {
                    while (internal_stack.size > 0) {
                        std.debug.print("AvlTree.ForwardIterator.next() - popping new node\n", .{});
                        const current = try internal_stack.pop(gpa);

                        if (current.node) |node_nn| {
                            if (current.state == TraversalRecursionStates.first) {
                                try internal_stack.push(gpa, .{ .state = TraversalRecursionStates.second, .node = current.node });
                                try internal_stack.push(gpa, .{ .state = TraversalRecursionStates.first, .node = node_nn.left });

                                std.debug.print("AvlTree.ForwardIterator.next() - adding left node to stack\n", .{});
                            } else if (current.state == TraversalRecursionStates.second) {
                                try internal_stack.push(gpa, .{ .state = TraversalRecursionStates.first, .node = node_nn.right });
                                std.debug.print("AvlTree.ForwardIterator.next() - adding right node to stack and returning current\n", .{});

                                return node_nn.val;
                            }
                        } else {
                            std.debug.print("AvlTree.ForwardIterator.next() - continuing past null node\n", .{});
                        }
                    }

                    std.debug.print("AvlTree.ForwardIterator.next() - exhausted all nodes\n", .{});
                    return null;
                } else {
                    return error.InvalidInternalState;
                }
            }
        };

        pub fn iter(self: *Self) ForwardIterator {
            return .{
                .internal_stack = null,
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

        fn rotateLeft(self: *Self, node: ?*AvlNode) !?*AvlNode {
            if (node) |node_nn| {
                std.debug.assert(node_nn.right != null);
                if (node_nn.right) |right| {
                    node_nn.right = right.left;
                    right.left = node_nn;

                    node_nn.height = self.calculateHeight(node_nn);
                    right.height = self.calculateHeight(right);

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

        fn getHeight(self: *Self, node: ?*AvlNode) i32 {
            _ = self;
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
                            std.debug.print("AvlTree.fixAvlProperty(self, {d}) - Right Right Imbalance - Rotating Left {d}\n", .{ node_nn.val, node_nn.val });
                            return try self.rotateLeft(node_nn);
                        }

                        // Right Left Imabalance
                        if (right_balance == -1) {
                            std.debug.print("AvlTree.fixAvlProperty(self, {d}) - Right Left Imbalance - Rotating Right {d}\n", .{ node_nn.val, right.val });
                            node_nn.right = try self.rotateRight(right);
                            std.debug.print("AvlTree.fixAvlProperty(self, {d}) - Right Left Imbalance - Rotating Left {d}\n", .{ node_nn.val, node_nn.val });
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
                            std.debug.print("AvlTree.fixAvlProperty(self, {d}) - Left Right Imbalance - Rotating Left {d}\n", .{ node_nn.val, left.val });
                            node_nn.left = try self.rotateLeft(left);
                            std.debug.print("AvlTree.fixAvlProperty(self, {d}) - Left Right Imbalance - Rotating Right {d}\n", .{ node_nn.val, node_nn.val });
                            return try self.rotateRight(node_nn);
                        }

                        // Left Left Imabalance
                        if (left_balance == -1) {
                            std.debug.print("AvlTree.fixAvlProperty(self, {d}) - Left Left Imbalance - Rotating Right {d}\n", .{ node_nn.val, node_nn.val });
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

                std.debug.print("AvlTree.add(self, gpa, {d}) - adding root to stack\n", .{val});
                try recursion.push(gpa, .{ .traversal_position = TraversalPosition.initial, .node = self.root });

                var last_touched_node: ?*AvlNode = null;

                while (recursion.size > 0) {
                    std.debug.print("AvlTree.add(self, gpa, {d}) - popping off of stack\n", .{val});
                    const current = try recursion.pop(gpa);
                    if (current.node) |node| {
                        if (current.traversal_position == TraversalPosition.initial) {
                            std.debug.print("AvlTree.add(self, gpa, {d}) - popped {d} off initially\n", .{ val, node.val });
                            try recursion.push(gpa, .{ .traversal_position = TraversalPosition.addNode, .node = current.node });

                            const comparison = compareFn(val, node.val);
                            if (comparison == std.math.Order.lt or comparison == std.math.Order.eq) {
                                std.debug.print("AvlTree.add(self, gpa, {d}) - going left from {d}\n", .{ val, node.val });
                                try recursion.push(gpa, .{ .traversal_position = TraversalPosition.initial, .node = node.left });
                            } else {
                                std.debug.print("AvlTree.add(self, gpa, {d}) - going right from {d}\n", .{ val, node.val });
                                try recursion.push(gpa, .{ .traversal_position = TraversalPosition.initial, .node = node.right });
                            }
                        } else if (current.traversal_position == TraversalPosition.addNode) {
                            std.debug.print("AvlTree.add(self, gpa, {d}) - popped {d} off second time\n", .{ val, node.val });
                            const comparison = compareFn(val, node.val);

                            if (comparison == std.math.Order.lt or comparison == std.math.Order.eq) {
                                std.debug.print("AvlTree.add(self, gpa, {d}) - fixing avl left from {d}\n", .{ val, node.val });
                                node.left = last_touched_node;
                                node.left = try self.fixAvlProperty(node.left);
                            } else {
                                std.debug.print("AvlTree.add(self, gpa, {d}) - fixing avl right from {d}\n", .{ val, node.val });
                                node.right = last_touched_node;
                                node.right = try self.fixAvlProperty(node.right);
                            }

                            node.height = self.calculateHeight(node);

                            last_touched_node = current.node;
                        }
                    } else {
                        std.debug.print("AvlTree.add(self, gpa, {d}) - creating new node\n", .{val});
                        const new_node = try gpa.create(AvlNode);
                        new_node.* = .{
                            .val = val,
                            .height = 0,
                            .left = null,
                            .right = null,
                        };

                        last_touched_node = new_node;
                    }
                }

                self.root = last_touched_node;
                self.root = try self.fixAvlProperty(self.root);
            } else {
                std.debug.assert(self.size == 0);

                const new_node = try gpa.create(AvlNode);
                new_node.* = .{
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

    try my_avl_tree.add(gpa, 5);

    try expectEqual(5, my_avl_tree.root.?.val);
    try expectEqual(0, my_avl_tree.root.?.height);

    try my_avl_tree.add(gpa, 2);

    try expectEqual(5, my_avl_tree.root.?.val);
    try expectEqual(1, my_avl_tree.root.?.height);
    try expectEqual(2, my_avl_tree.root.?.left.?.val);
    try expectEqual(0, my_avl_tree.root.?.left.?.height);

    {
        var iter = my_avl_tree.iter();
        defer iter.deinit(gpa);

        try expectEqual(2, try iter.next(gpa));
        try expectEqual(5, try iter.next(gpa));
    }

    try expectEqual(5, my_avl_tree.root.?.val);
    try expectEqual(1, my_avl_tree.root.?.height);
    try expectEqual(2, my_avl_tree.root.?.left.?.val);
    try expectEqual(0, my_avl_tree.root.?.left.?.height);

    try my_avl_tree.add(gpa, 1);

    try expectEqual(2, my_avl_tree.root.?.val);
    try expectEqual(1, my_avl_tree.root.?.height);
    try expectEqual(1, my_avl_tree.root.?.left.?.val);
    try expectEqual(0, my_avl_tree.root.?.left.?.height);
    try expectEqual(5, my_avl_tree.root.?.right.?.val);
    try expectEqual(0, my_avl_tree.root.?.right.?.height);

    {
        var iter = my_avl_tree.iter();
        defer iter.deinit(gpa);

        try expectEqual(1, try iter.next(gpa));
        try expectEqual(2, try iter.next(gpa));
        try expectEqual(5, try iter.next(gpa));
    }

    try expectEqual(2, my_avl_tree.root.?.val);
    try expectEqual(1, my_avl_tree.root.?.height);
    try expectEqual(1, my_avl_tree.root.?.left.?.val);
    try expectEqual(0, my_avl_tree.root.?.left.?.height);
    try expectEqual(5, my_avl_tree.root.?.right.?.val);
    try expectEqual(0, my_avl_tree.root.?.right.?.height);
}
