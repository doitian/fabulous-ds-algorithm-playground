//! 3.3-3.5 An immutable deque based on a finger tree (listing 3.5)
//!
//! A persistent deque with empty, singleton, and deep cases. A deep deque has nonempty
//! left/right minis of one to four items and a recursive middle of chunks.
//! Initially, each middle chunk contains three items. On overflow, move three
//! inward and retain two at the edge; on underflow, refill from the middle.
//! When the middle is empty, handle the opposite mini and singleton cases.
//!
//! Updates preserve every earlier version and share untouched subtrees.
//! Push/pop: amortized O(1), worst-case O(log n) time and additional memory.
//! End queries and isEmpty: O(1). Traversal: O(n) total time.
//!
//! All nodes in a recursive Tree have the same height. The outer digits hold
//! leaves; each middle level holds chunks of the previous level's nodes.
//! Reusing Node and Tree at every level keeps their layouts independent of depth.
//!
//! 3.7: concatenation joins boundary digits into two- and three-item chunks
//! and stitches the middles recursively in O(log n) time and extra memory.
//! Untouched outer digits and interior subtrees are shared.
//!
//! Allocated nodes belong to the caller's arena. Do not free shared nodes
//! individually. An allocation failure must leave the source deque usable.

const std = @import("std");
const Allocator = std.mem.Allocator;
const MiniDeque = @import("mini_deque.zig").MiniDeque;

pub const Error = error{EmptyDeque};

pub fn ImDeque(comptime T: type) type {
    return struct {
        const Self = @This();
        const Node = union(enum) {
            item: T,
            two: [2]*const Node,
            three: [3]*const Node,

            fn digit(self: Node) Mini {
                return switch (self) {
                    .item => unreachable,
                    .two => |children| Mini.two(children[0], children[1]),
                    .three => |children| .{ .data = .{ .three = children } },
                };
            }
        };
        const Mini = MiniDeque(*const Node);
        const Deep = struct {
            left: Mini,
            middle: *const Tree,
            right: Mini,
        };

        const Tree = union(enum) {
            empty,
            one: *const Node,
            deep: Deep,

            fn isEmpty(self: Tree) bool {
                return switch (self) {
                    .empty => true,
                    else => false,
                };
            }
        };

        const empty_tree: Tree = .empty;

        // Keeping the outer singleton inline preserves single(item)'s
        // allocation-free interface; recursive trees always hold node pointers.
        const Root = union(enum) {
            empty,
            one: T,
            deep: Deep,
        };

        root: Root,

        pub const empty: Self = .{ .root = .empty };

        pub fn single(item: T) Self {
            return .{ .root = .{ .one = item } };
        }

        fn makeDeep(left_mini: Mini, middle: *const Tree, right_mini: Mini) Self {
            return .{ .root = .{ .deep = .{ .left = left_mini, .middle = middle, .right = right_mini } } };
        }

        fn makeNode(allocator: Allocator, value: Node) Allocator.Error!*const Node {
            const node = try allocator.create(Node);
            node.* = value;
            return node;
        }

        fn storeTree(allocator: Allocator, value: Tree) Allocator.Error!*const Tree {
            const tree = try allocator.create(Tree);
            tree.* = value;
            return tree;
        }

        fn asTree(self: Self, allocator: Allocator) Allocator.Error!Tree {
            return switch (self.root) {
                .empty => .empty,
                .one => |item| .{ .one = try makeNode(allocator, .{ .item = item }) },
                .deep => |deep| .{ .deep = deep },
            };
        }

        fn fromTree(tree: Tree) Self {
            return switch (tree) {
                .empty => .empty,
                .one => |node| single(node.item),
                .deep => |deep| .{ .root = .{ .deep = deep } },
            };
        }

        fn treeLeft(tree: Tree) Error!*const Node {
            return switch (tree) {
                .empty => error.EmptyDeque,
                .one => |node| node,
                .deep => |deep| deep.left.left(),
            };
        }

        fn treeRight(tree: Tree) Error!*const Node {
            return switch (tree) {
                .empty => error.EmptyDeque,
                .one => |node| node,
                .deep => |deep| deep.right.right(),
            };
        }

        fn pushTreeLeft(tree: Tree, allocator: Allocator, node: *const Node) Allocator.Error!Tree {
            return switch (tree) {
                .empty => .{ .one = node },
                .one => |existing| .{ .deep = .{
                    .left = Mini.one(node),
                    .middle = &empty_tree,
                    .right = Mini.one(existing),
                } },
                .deep => |deep| blk: {
                    if (deep.left.size() < 4) break :blk .{ .deep = .{
                        .left = deep.left.pushLeft(node) catch unreachable,
                        .middle = deep.middle,
                        .right = deep.right,
                    } };
                    const tail = deep.left.popLeft() catch unreachable;
                    const chunk = try makeNode(allocator, .{ .three = tail.data.three });
                    const middle = try storeTree(allocator, try pushTreeLeft(deep.middle.*, allocator, chunk));
                    break :blk .{ .deep = .{
                        .left = Mini.two(node, deep.left.left()),
                        .middle = middle,
                        .right = deep.right,
                    } };
                },
            };
        }

        fn pushTreeRight(tree: Tree, allocator: Allocator, node: *const Node) Allocator.Error!Tree {
            return switch (tree) {
                .empty => .{ .one = node },
                .one => |existing| .{ .deep = .{
                    .left = Mini.one(existing),
                    .middle = &empty_tree,
                    .right = Mini.one(node),
                } },
                .deep => |deep| blk: {
                    if (deep.right.size() < 4) break :blk .{ .deep = .{
                        .left = deep.left,
                        .middle = deep.middle,
                        .right = deep.right.pushRight(node) catch unreachable,
                    } };
                    const front = deep.right.popRight() catch unreachable;
                    const chunk = try makeNode(allocator, .{ .three = front.data.three });
                    const middle = try storeTree(allocator, try pushTreeRight(deep.middle.*, allocator, chunk));
                    break :blk .{ .deep = .{
                        .left = deep.left,
                        .middle = middle,
                        .right = Mini.two(deep.right.right(), node),
                    } };
                },
            };
        }

        fn popTreeLeft(tree: Tree, allocator: Allocator) (Error || Allocator.Error)!Tree {
            return switch (tree) {
                .empty => error.EmptyDeque,
                .one => .empty,
                .deep => |deep| blk: {
                    if (deep.left.size() > 1) break :blk .{ .deep = .{
                        .left = deep.left.popLeft() catch unreachable,
                        .middle = deep.middle,
                        .right = deep.right,
                    } };
                    if (!deep.middle.isEmpty()) {
                        const chunk = treeLeft(deep.middle.*) catch unreachable;
                        const middle = try storeTree(allocator, try popTreeLeft(deep.middle.*, allocator));
                        break :blk .{ .deep = .{
                            .left = chunk.digit(),
                            .middle = middle,
                            .right = deep.right,
                        } };
                    }
                    if (deep.right.size() > 1) break :blk .{ .deep = .{
                        .left = Mini.one(deep.right.left()),
                        .middle = deep.middle,
                        .right = deep.right.popLeft() catch unreachable,
                    } };
                    break :blk .{ .one = deep.right.left() };
                },
            };
        }

        fn popTreeRight(tree: Tree, allocator: Allocator) (Error || Allocator.Error)!Tree {
            return switch (tree) {
                .empty => error.EmptyDeque,
                .one => .empty,
                .deep => |deep| blk: {
                    if (deep.right.size() > 1) break :blk .{ .deep = .{
                        .left = deep.left,
                        .middle = deep.middle,
                        .right = deep.right.popRight() catch unreachable,
                    } };
                    if (!deep.middle.isEmpty()) {
                        const chunk = treeRight(deep.middle.*) catch unreachable;
                        const middle = try storeTree(allocator, try popTreeRight(deep.middle.*, allocator));
                        break :blk .{ .deep = .{
                            .left = deep.left,
                            .middle = middle,
                            .right = chunk.digit(),
                        } };
                    }
                    if (deep.left.size() > 1) break :blk .{ .deep = .{
                        .left = deep.left.popRight() catch unreachable,
                        .middle = deep.middle,
                        .right = Mini.one(deep.left.right()),
                    } };
                    break :blk .{ .one = deep.left.right() };
                },
            };
        }

        fn appendDigit(buffer: [](*const Node), len: *usize, digit: Mini) void {
            switch (digit.data) {
                inline else => |nodes| {
                    @memcpy(buffer[len.*..][0..nodes.len], &nodes);
                    len.* += nodes.len;
                },
            }
        }

        fn prependNodes(tree: Tree, allocator: Allocator, nodes: []const *const Node) Allocator.Error!Tree {
            var result = tree;
            var i = nodes.len;
            while (i > 0) {
                i -= 1;
                result = try pushTreeLeft(result, allocator, nodes[i]);
            }
            return result;
        }

        fn appendNodes(tree: Tree, allocator: Allocator, nodes: []const *const Node) Allocator.Error!Tree {
            var result = tree;
            for (nodes) |node| result = try pushTreeRight(result, allocator, node);
            return result;
        }

        fn concatenateTrees(left_tree: Tree, allocator: Allocator, between: []const *const Node, right_tree: Tree) Allocator.Error!Tree {
            std.debug.assert(between.len <= 4);
            return switch (left_tree) {
                .empty => prependNodes(right_tree, allocator, between),
                .one => |node| pushTreeLeft(try prependNodes(right_tree, allocator, between), allocator, node),
                .deep => |left_deep| switch (right_tree) {
                    .empty => appendNodes(left_tree, allocator, between),
                    .one => |node| pushTreeRight(try appendNodes(left_tree, allocator, between), allocator, node),
                    .deep => |right_deep| blk: {
                        // At most four nodes arrive from above, plus four from
                        // each boundary digit. Packing them produces at most four chunks.
                        var boundary: [12]*const Node = undefined;
                        var len: usize = 0;
                        appendDigit(&boundary, &len, left_deep.right);
                        @memcpy(boundary[len..][0..between.len], between);
                        len += between.len;
                        appendDigit(&boundary, &len, right_deep.left);

                        var chunks: [4]*const Node = undefined;
                        var count: usize = 0;
                        var i: usize = 0;
                        while (i < len) : (count += 1) {
                            // A remainder of four must become two pairs to avoid a singleton.
                            const size: usize = if (len - i == 2 or len - i == 4) 2 else 3;
                            chunks[count] = try makeNode(allocator, if (size == 2)
                                .{ .two = .{ boundary[i], boundary[i + 1] } }
                            else
                                .{ .three = .{ boundary[i], boundary[i + 1], boundary[i + 2] } });
                            i += size;
                        }
                        const middle = try storeTree(allocator, try concatenateTrees(
                            left_deep.middle.*,
                            allocator,
                            chunks[0..count],
                            right_deep.middle.*,
                        ));
                        break :blk .{ .deep = .{
                            .left = left_deep.left,
                            .middle = middle,
                            .right = right_deep.right,
                        } };
                    },
                },
            };
        }

        pub fn isEmpty(self: Self) bool {
            return switch (self.root) {
                .empty => true,
                else => false,
            };
        }

        pub fn left(self: Self) Error!T {
            return switch (self.root) {
                .empty => error.EmptyDeque,
                .one => |item| item,
                .deep => |deep| deep.left.left().item,
            };
        }

        pub fn right(self: Self) Error!T {
            return switch (self.root) {
                .empty => error.EmptyDeque,
                .one => |item| item,
                .deep => |deep| deep.right.right().item,
            };
        }

        pub fn pushLeft(self: Self, allocator: Allocator, item: T) Allocator.Error!Self {
            if (self.isEmpty()) return single(item);
            const tree = try self.asTree(allocator);
            const node = try makeNode(allocator, .{ .item = item });
            return fromTree(try pushTreeLeft(tree, allocator, node));
        }

        pub fn pushRight(self: Self, allocator: Allocator, item: T) Allocator.Error!Self {
            if (self.isEmpty()) return single(item);
            const tree = try self.asTree(allocator);
            const node = try makeNode(allocator, .{ .item = item });
            return fromTree(try pushTreeRight(tree, allocator, node));
        }

        pub fn popLeft(self: Self, allocator: Allocator) (Error || Allocator.Error)!Self {
            return switch (self.root) {
                .empty => error.EmptyDeque,
                .one => .empty,
                .deep => |deep| fromTree(try popTreeLeft(.{ .deep = deep }, allocator)),
            };
        }

        pub fn popRight(self: Self, allocator: Allocator) (Error || Allocator.Error)!Self {
            return switch (self.root) {
                .empty => error.EmptyDeque,
                .one => .empty,
                .deep => |deep| fromTree(try popTreeRight(.{ .deep = deep }, allocator)),
            };
        }

        /// Left-to-right traversal; independent iterators can coexist.
        /// Scratch storage, if allocated, shares the caller's arena lifetime.
        pub fn iterator(self: Self, allocator: Allocator) Allocator.Error!Iterator {
            return switch (self.root) {
                .empty => .{},
                .one => |item| .{ .inline_item = item },
                .deep => |deep| blk: {
                    var depth: usize = 1;
                    var middle = deep.middle;
                    while (middle.* == .deep) {
                        depth += 1;
                        middle = middle.deep.middle;
                    }
                    // A deep tree adds at most eight pending tasks, a chunk at
                    // most two. Both nesting depths are bounded by the middle spine.
                    var it: Iterator = .{ .pending = try allocator.alloc(Iterator.Task, 10 * (depth + 1)) };
                    it.pushDeep(deep);
                    break :blk it;
                },
            };
        }

        pub const Iterator = struct {
            const Task = union(enum) {
                tree: *const Tree,
                node: *const Node,
            };

            pending: []Task = &.{},
            len: usize = 0,
            inline_item: ?T = null,

            fn push(it: *Iterator, task: Task) void {
                it.pending[it.len] = task;
                it.len += 1;
            }

            fn pushDigit(it: *Iterator, digit: Mini) void {
                switch (digit.data) {
                    inline else => |nodes| {
                        var i = nodes.len;
                        while (i > 0) {
                            i -= 1;
                            it.push(.{ .node = nodes[i] });
                        }
                    },
                }
            }

            fn pushDeep(it: *Iterator, deep: Deep) void {
                it.pushDigit(deep.right);
                it.push(.{ .tree = deep.middle });
                it.pushDigit(deep.left);
            }

            pub fn next(it: *Iterator) ?T {
                if (it.inline_item) |item| {
                    it.inline_item = null;
                    return item;
                }
                while (it.len > 0) {
                    it.len -= 1;
                    switch (it.pending[it.len]) {
                        .tree => |tree| switch (tree.*) {
                            .empty => {},
                            .one => |node| it.push(.{ .node = node }),
                            .deep => |deep| it.pushDeep(deep),
                        },
                        .node => |node| switch (node.*) {
                            .item => |item| return item,
                            inline else => |children| {
                                var i = children.len;
                                while (i > 0) {
                                    i -= 1;
                                    it.push(.{ .node = children[i] });
                                }
                            },
                        },
                    }
                }
                return null;
            }
        };

        /// 3.7: self's items followed by other's; both inputs stay usable.
        pub fn concatenate(self: Self, allocator: Allocator, other: Self) Allocator.Error!Self {
            if (self.isEmpty()) return other;
            if (other.isEmpty()) return self;
            return switch (self.root) {
                .empty => unreachable,
                .one => |item| other.pushLeft(allocator, item),
                .deep => |left_deep| switch (other.root) {
                    .empty => unreachable,
                    .one => |item| self.pushRight(allocator, item),
                    .deep => |right_deep| fromTree(try concatenateTrees(
                        .{ .deep = left_deep },
                        allocator,
                        &.{},
                        .{ .deep = right_deep },
                    )),
                },
            };
        }
    };
}
