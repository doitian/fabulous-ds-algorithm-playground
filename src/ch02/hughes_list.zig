//! 2.7 The Hughes list (listing 2.14, plus the reversing factory from 2.7.7)
//!
//! A list that is cheap to build and expensive to read: `push`, `append` and
//! `concatenate` are O(1) however long the lists are, while reading it
//! (`toStack`, `peek`, `pop`, iteration) is O(n).
//!
//! The book's Hughes list is a single delegate. Zig has no closures, so you
//! choose an explicit representation for what that delegate captures.
//!
//! Memory: as with `ImStack`, building shares structure between lists, so the
//! caller owns the lifetime of everything allocated (the tests use an arena).

const std = @import("std");
const Allocator = std.mem.Allocator;
const ImStack = @import("im_stack.zig").ImStack;

pub const Error = error{EmptyList};

pub fn HList(comptime T: type) type {
    return struct {
        const Self = @This();
        const Stack = ImStack(T);

        const Capture = union(enum) {
            stack: Stack,
            single: T,
            empty,
        };
        const Leaf = struct {
            capture: Capture,
            apply: *const fn (Capture, Allocator, Stack) Allocator.Error!Stack,

            fn call(self: Leaf, gpa: Allocator, stack: Stack) Allocator.Error!Stack {
                return self.apply(self.capture, gpa, stack);
            }

            const empty: Leaf = .{ .capture = .empty, .apply = struct {
                fn lambda(_: Capture, _: Allocator, s: Stack) Allocator.Error!Stack {
                    return s;
                }
            }.lambda };
        };
        const Pair = struct { Self, Self };
        const Tree = union(enum) {
            leaf: Leaf,
            /// Pair is never empty
            pair: *const Pair,
        };

        tree: Tree,

        pub const empty: Self = .{ .tree = .{ .leaf = Leaf.empty } };

        /// O(1). True for every empty list, however it was built.
        pub fn isEmpty(self: Self) bool {
            return switch (self.tree) {
                .leaf => |leaf| leaf.capture == Capture.empty and leaf.apply == Leaf.empty.apply,
                .pair => false,
            };
        }

        fn makeLeaf(leaf: Leaf) Self {
            return .{ .tree = .{ .leaf = leaf } };
        }
        fn makePair(allocator: Allocator, left: Self, right: Self) Allocator.Error!Self {
            const pair = try allocator.create(Pair);
            pair.* = .{ left, right };
            return .{ .tree = .{ .pair = pair } };
        }

        /// The list holding `stack`'s items in the same order.
        /// O(1), regardless of the size of `stack`.
        pub fn fromStack(stack: Stack) Self {
            if (stack.isEmpty()) return .empty;

            return makeLeaf(.{
                .capture = .{ .stack = stack },
                .apply = struct {
                    fn lambda(capture: Capture, gpa: Allocator, tail: Stack) Allocator.Error!Stack {
                        return capture.stack.concatenate(gpa, tail);
                    }
                }.lambda,
            });
        }

        /// 2.7.7: the list holding `stack`'s items in reverse order.
        /// O(1), regardless of the size of `stack`.
        pub fn fromStackReversed(stack: Stack) Self {
            if (stack.isEmpty()) return .empty;

            return makeLeaf(.{
                .capture = .{ .stack = stack },
                .apply = struct {
                    fn lambda(capture: Capture, gpa: Allocator, tail: Stack) Allocator.Error!Stack {
                        return capture.stack.reverseOnto(gpa, tail);
                    }
                }.lambda,
            });
        }

        /// A one-item list. O(1).
        pub fn single(item: T) Self {
            return makeLeaf(.{
                .capture = .{ .single = item },
                .apply = struct {
                    fn lambda(capture: Capture, gpa: Allocator, tail: Stack) Allocator.Error!Stack {
                        return tail.push(gpa, capture.single);
                    }
                }.lambda,
            });
        }

        /// `item` followed by `self`. O(1).
        pub fn push(self: Self, allocator: Allocator, item: T) Allocator.Error!Self {
            return single(item).concatenate(allocator, self);
        }

        /// `self` followed by `item`. O(1).
        pub fn append(self: Self, allocator: Allocator, item: T) Allocator.Error!Self {
            return self.concatenate(allocator, single(item));
        }

        /// `self` followed by `other`. O(1), regardless of either size.
        pub fn concatenate(self: Self, allocator: Allocator, other: Self) Allocator.Error!Self {
            if (other.isEmpty()) return self;
            if (self.isEmpty()) return other;
            return makePair(allocator, self, other);
        }

        /// The represented list as a stack, first item on top. O(n).
        pub fn toStack(self: Self, allocator: Allocator) Allocator.Error!Stack {
            var pending: std.ArrayList(Self) = .empty;
            defer pending.deinit(allocator);

            var out_stack: Stack = .empty;
            var node = self;
            while (true) {
                switch (node.tree) {
                    .leaf => |leaf| {
                        out_stack = try leaf.call(allocator, out_stack);
                        node = pending.pop() orelse return out_stack;
                    },
                    .pair => |pair| {
                        const left, const right = pair.*;
                        try pending.append(allocator, left);
                        node = right;
                    },
                }
            }
        }

        /// The first item. Fails with `error.EmptyList` on the empty list. O(n).
        pub fn peek(self: Self, allocator: Allocator) (Error || Allocator.Error)!T {
            const stack = try self.toStack(allocator);
            return stack.peek() catch error.EmptyList;
        }

        /// Everything after the first item. Fails with `error.EmptyList` on
        /// the empty list. O(n).
        pub fn pop(self: Self, allocator: Allocator) (Error || Allocator.Error)!Self {
            const stack = try self.toStack(allocator);
            const stack_did_pop = stack.pop() catch return error.EmptyList;
            return fromStack(stack_did_pop);
        }

        /// Yields items from first to last. O(n) time and memory.
        pub fn iterator(self: Self, allocator: Allocator) Allocator.Error!Stack.Iterator {
            const stack = try self.toStack(allocator);
            return stack.iterator();
        }
    };
}
