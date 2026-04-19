const std = @import("std");

const Allocator = std.mem.Allocator;

/// Generic Linked List used internally by the LRUCache.
/// This list is generic, so it technically could be used outside of the cache
/// for general purposes.
pub fn LRUCacheLinkedList(
    comptime T: type,
) type {
    return struct {
        ends: ?NodePair,
        size: usize,

        const Self = @This();

        const Node = struct {
            val: T,
            next: ?*Node,
            prev: ?*Node,
        };

        const NodePair = struct {
            head: *Node,
            tail: *Node,
        };

        /// A Linked List containing no elements
        pub const empty: Self = .{
            .ends = null,
            .size = 0,
        };

        /// Free the memory used by the linked list
        pub fn deinit(self: *Self, gpa: Allocator) void {
            const ends = self.ends orelse return;

            var cursor: ?*Node = ends.head;
            while (cursor) |cursor_nn| {
                const delete_node = cursor_nn;
                cursor = cursor_nn.next;

                gpa.destroy(delete_node);
            }

            self.* = undefined;
        }

        /// Add an element to the front of the list.
        pub fn pushFront(self: *Self, gpa: Allocator, val: T) !void {
            var new_node = try gpa.create(Node);
            new_node.* = .{
                .val = val,
                .next = null,
                .prev = null,
            };

            if (self.ends) |*ends| {
                ends.head.prev = new_node;
                new_node.next = ends.head;
                ends.head = new_node;
            } else {
                self.ends = .{
                    .head = new_node,
                    .tail = new_node,
                };
            }

            self.size += 1;
        }

        /// Remove an element from the front of the list
        /// and free the memory to store it.
        pub fn popFront(self: *Self, gpa: Allocator) !T {
            if (self.ends) |*ends| {
                const delete_node = ends.head;
                defer gpa.destroy(delete_node);

                const result: T = delete_node.val;

                if (delete_node.next) |next| {
                    ends.head = next;
                    ends.head.prev = null;
                } else {
                    self.ends = null;
                }

                self.size -= 1;

                return result;
            } else {
                return error.EmptyListAccess;
            }
        }

        /// Get the front of the list without removing it.
        pub fn peekFront(self: *Self) !T {
            if (self.ends) |ends| {
                return ends.head.val;
            } else {
                return error.EmptyListAccess;
            }
        }

        /// Add an element to the back of the list.
        pub fn pushBack(self: *Self, gpa: Allocator, val: T) !void {
            var new_node = try gpa.create(Node);
            new_node.* = .{
                .val = val,
                .next = null,
                .prev = null,
            };

            if (self.ends) |*ends| {
                ends.tail.next = new_node;
                new_node.prev = ends.tail;
                ends.tail = new_node;
            } else {
                self.ends = .{
                    .head = new_node,
                    .tail = new_node,
                };
            }

            self.size += 1;
        }

        /// Get the last element of the list,
        /// and free the memory used to store it.
        pub fn popBack(self: *Self, gpa: Allocator) !T {
            if (self.ends) |*ends| {
                const delete_node = ends.tail;
                defer gpa.destroy(delete_node);

                const result: T = delete_node.val;

                if (delete_node.prev) |prev| {
                    ends.tail = prev;
                    ends.tail.next = null;
                } else {
                    self.ends = null;
                }

                self.size -= 1;

                return result;
            } else {
                return error.EmptyListAccess;
            }
        }

        /// Get the last element of the list without removing it.
        pub fn peekBack(self: *Self) !T {
            if (self.ends) |ends| {
                return ends.tail.val;
            } else {
                return error.EmptyListAccess;
            }
        }

        /// Insert a value before the chosen node.
        /// This function returns the newly inserted node.
        pub fn insertBefore(self: *Self, gpa: Allocator, node: *Node, val: T) !*Node {
            if (self.ends) |*ends| {
                self.size += 1;

                if (node.prev) |prev| {
                    const new_node = gpa.create(Node);

                    new_node.* = .{
                        .val = val,
                        .next = node,
                        .prev = prev,
                    };

                    prev.next = new_node;
                    node.prev = new_node;

                    return new_node;
                } else {
                    std.debug.assert(ends.head == node);

                    const new_node = gpa.create(Node);
                    new_node.* = .{
                        .val = val,
                        .next = node,
                        .prev = null,
                    };

                    node.prev = new_node;
                    ends.head = new_node;

                    return new_node;
                }
            } else {
                return error.EmptyListAccess;
            }
        }

        /// Remove the chosen node from the list.
        /// If the list contains one node, the function returns null, otherwise
        /// if the front of the list is removed, this function returns the new head.
        /// If any other node is removed, the previous node is returned.
        pub fn removeNode(self: *Self, gpa: Allocator, node: *Node) !?*Node {
            if (self.ends) |*ends| {
                defer gpa.destroy(node);

                self.size -= 1;

                if (node.prev) |prev| {
                    if (node.next) |next| {
                        std.debug.assert(ends.head != node);
                        std.debug.assert(ends.tail != node);

                        prev.next = next;
                        next.prev = prev;

                        return prev;
                    } else {
                        std.debug.assert(ends.head != node);
                        std.debug.assert(ends.tail == node);

                        ends.tail = prev;
                        prev.next = null;

                        return prev;
                    }
                } else {
                    if (node.next) |next| {
                        std.debug.assert(ends.head == node);
                        std.debug.assert(ends.tail != node);

                        ends.head = next;
                        next.prev = null;

                        return next;
                    } else {
                        std.debug.assert(ends.head == node);
                        std.debug.assert(ends.tail == node);

                        self.ends = null;

                        return null;
                    }
                }
            } else {
                return error.EmptyListAccess;
            }
        }
    };
}

/// A "Least Recently Used" Cache for storing generic data.
/// Initialize with `withMaxCapacity`.
/// This cache will have a maximum capacity set at initialization.
/// If more keys are inserted to the cache than the maximum capacity,
/// the least recently used key will be evicted.
///
/// When either putting or getting a key from the cache,
/// that key is promoted to the most recently used.
pub fn AutoLRUCache(
    comptime K: type,
    comptime V: type,
) type {
    return struct {
        internal_map: std.AutoHashMapUnmanaged(K, *LRUCacheLinkedList(KeyVal).Node),
        internal_list: LRUCacheLinkedList(KeyVal),
        max_capacity: usize,

        const Self = @This();

        const KeyVal = struct {
            key: K,
            val: V,
        };

        /// Initializes an empty cache with a maximum capacity.
        pub fn withMaxCapacity(max_capacity: usize) Self {
            return .{
                .internal_map = std.AutoHashMapUnmanaged(K, *LRUCacheLinkedList(KeyVal).Node).empty,
                .internal_list = LRUCacheLinkedList(KeyVal).empty,
                .max_capacity = max_capacity,
            };
        }

        /// Free the memory used by the cache.
        pub fn deinit(self: *Self, gpa: Allocator) void {
            self.internal_map.deinit(gpa);
            self.internal_list.deinit(gpa);
        }

        /// Insert or Update a key-value pair in the cache.
        /// The key-value pair selected will be promoted to most recently used.
        pub fn put(self: *Self, gpa: Allocator, key: K, val: V) !void {
            if (self.internal_map.get(key)) |node| {
                _ = try self.internal_list.removeNode(gpa, node);
                try self.internal_list.pushBack(gpa, .{ .key = key, .val = val });

                if (self.internal_list.ends) |ends| {
                    try self.internal_map.put(gpa, key, ends.tail);
                } else {
                    return error.InvalidInternalState;
                }
            } else {
                if (self.internal_list.size == self.max_capacity) {
                    if (self.internal_list.ends) |ends| {
                        _ = self.internal_map.remove(ends.head.val.key);
                    } else {
                        return error.InvalidInternalState;
                    }
                    _ = try self.internal_list.popFront(gpa);
                }

                try self.internal_list.pushBack(gpa, .{ .val = val, .key = key });
                if (self.internal_list.ends) |ends| {
                    try self.internal_map.put(gpa, key, ends.tail);
                } else {
                    return error.InvalidInternalState;
                }
            }
        }

        /// Get a value from the cache by its key.
        /// The key-value pair chosen will be promoted to most recently used.
        pub fn get(self: *Self, gpa: Allocator, key: K) !?V {
            if (self.internal_map.get(key)) |node| {
                const result = node.val.val;

                _ = try self.internal_list.removeNode(gpa, node);
                try self.internal_list.pushBack(gpa, .{ .key = key, .val = result });

                if (self.internal_list.ends) |ends| {
                    try self.internal_map.put(gpa, key, ends.tail);
                } else {
                    return error.InvalidInternalState;
                }

                return result;
            } else {
                return null;
            }
        }
    };
}

test "linked list simple" {
    const gpa = std.testing.allocator;
    var my_list = LRUCacheLinkedList(i32).empty;
    defer my_list.deinit(gpa);

    try std.testing.expect(my_list.size == 0);
}

test "linked list only push" {
    const gpa = std.testing.allocator;
    var my_list = LRUCacheLinkedList(i32).empty;
    defer my_list.deinit(gpa);

    try std.testing.expect(my_list.size == 0);

    try my_list.pushFront(gpa, 1);
    try std.testing.expect(my_list.size == 1);
}

test "linked list only push and pop" {
    const gpa = std.testing.allocator;
    var my_list = LRUCacheLinkedList(i32).empty;
    defer my_list.deinit(gpa);

    try std.testing.expect(my_list.size == 0);

    try my_list.pushFront(gpa, 1);
    try std.testing.expect(my_list.size == 1);

    try std.testing.expect(try my_list.popFront(gpa) == 1);

    try std.testing.expect(my_list.size == 0);
}

test "linked list multiple" {
    const gpa = std.testing.allocator;
    var my_list = LRUCacheLinkedList(i32).empty;
    defer my_list.deinit(gpa);

    try std.testing.expect(my_list.size == 0);

    try my_list.pushFront(gpa, 5);
    try my_list.pushFront(gpa, 4);

    try std.testing.expect(my_list.size == 2);

    if (my_list.ends) |ends| {
        try std.testing.expect(ends.head.val == 4);
    }

    try std.testing.expect(try my_list.popFront(gpa) == 4);
    try std.testing.expect(my_list.size == 1);

    if (my_list.ends) |ends| {
        try std.testing.expect(ends.head.val == 5);
    }

    try std.testing.expect(try my_list.popFront(gpa) == 5);
    try std.testing.expect(my_list.size == 0);
}

test "linked list pushFront popFront full" {
    const gpa = std.testing.allocator;
    var my_list = LRUCacheLinkedList(i32).empty;
    defer my_list.deinit(gpa);

    try std.testing.expect(my_list.size == 0);

    try my_list.pushFront(gpa, 1);
    try std.testing.expect(my_list.size == 1);
    try std.testing.expect(try my_list.popFront(gpa) == 1);
    try std.testing.expect(my_list.size == 0);
    try std.testing.expect(my_list.popFront(gpa) == error.EmptyListAccess);

    try my_list.pushFront(gpa, 5);
    try my_list.pushFront(gpa, 4);
    try my_list.pushFront(gpa, 3);
    try my_list.pushFront(gpa, 5);
    try my_list.pushFront(gpa, 5);
    try std.testing.expect(try my_list.popFront(gpa) == 5);
    try std.testing.expect(my_list.size == 4);

    try std.testing.expect(try my_list.popFront(gpa) == 5);
    try std.testing.expect(my_list.size == 3);

    try std.testing.expect(try my_list.popFront(gpa) == 3);
    try std.testing.expect(my_list.size == 2);

    try std.testing.expect(try my_list.popFront(gpa) == 4);
    try std.testing.expect(my_list.size == 1);

    try std.testing.expect(try my_list.popFront(gpa) == 5);
    try std.testing.expect(my_list.size == 0);
}

test "init" {
    var my_cache = AutoLRUCache(i32, i32).withMaxCapacity(10);
    defer my_cache.deinit(std.heap.page_allocator);
    try std.testing.expect(my_cache.internal_map.count() == 0);
}

test "Auto LRU Cache full" {
    const gpa = std.testing.allocator;

    var my_cache = AutoLRUCache(i32, i32).withMaxCapacity(5);
    defer my_cache.deinit(gpa);

    try std.testing.expect(try my_cache.get(gpa, 5) == null);
    try my_cache.put(gpa, 1, 100);

    try std.testing.expect(try my_cache.get(gpa, 1) == 100);
    try std.testing.expect(try my_cache.get(gpa, 1) == 100);
    try std.testing.expect(try my_cache.get(gpa, 1) == 100);

    try my_cache.put(gpa, 1, 200);

    try std.testing.expect(try my_cache.get(gpa, 1) == 200);
    try std.testing.expect(try my_cache.get(gpa, 1) == 200);
    try std.testing.expect(try my_cache.get(gpa, 1) == 200);

    try my_cache.put(gpa, 2, 100);

    try std.testing.expect(try my_cache.get(gpa, 1) == 200);
    try std.testing.expect(try my_cache.get(gpa, 2) == 100);
    try std.testing.expect(try my_cache.get(gpa, 1) == 200);
    try std.testing.expect(try my_cache.get(gpa, 2) == 100);

    try my_cache.put(gpa, 2, 300);

    try std.testing.expect(try my_cache.get(gpa, 2) == 300);

    try std.testing.expect(try my_cache.get(gpa, 3) == null);

    try my_cache.put(gpa, 3, 456);
    try my_cache.put(gpa, 4, 567);
    try my_cache.put(gpa, 5, 987);

    try std.testing.expect(try my_cache.get(gpa, 1) == 200);
    try std.testing.expect(try my_cache.get(gpa, 2) == 300);
    try std.testing.expect(try my_cache.get(gpa, 3) == 456);
    try std.testing.expect(try my_cache.get(gpa, 4) == 567);
    try std.testing.expect(try my_cache.get(gpa, 5) == 987);

    try my_cache.put(gpa, 6, 1234);

    try std.testing.expect(try my_cache.get(gpa, 2) == 300);
    try std.testing.expect(try my_cache.get(gpa, 3) == 456);
    try std.testing.expect(try my_cache.get(gpa, 4) == 567);
    try std.testing.expect(try my_cache.get(gpa, 5) == 987);
    try std.testing.expect(try my_cache.get(gpa, 6) == 1234);

    _ = try my_cache.get(gpa, 3);

    try my_cache.put(gpa, 7, 5555);
    try my_cache.put(gpa, 8, 9876);

    try std.testing.expect(try my_cache.get(gpa, 5) == 987);
    try std.testing.expect(try my_cache.get(gpa, 6) == 1234);
    try std.testing.expect(try my_cache.get(gpa, 3) == 456);
    try std.testing.expect(try my_cache.get(gpa, 7) == 5555);
    try std.testing.expect(try my_cache.get(gpa, 8) == 9876);
}
