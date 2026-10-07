//! 2.2 An immutable stack (listings 2.1 and 2.2)
//!
//! A persistent stack: `push` and `pop` never change the stack they are
//! called on. They return a new stack that shares structure with the old one.
//!
//! As in the book, the empty and non-empty stacks are separate
//! implementations: the variants of a tagged union, each with its own methods.
//!
//! Memory: `push` allocates from the allocator it is given. Because tails are
//! shared between stacks, nodes are never freed one by one; the caller owns
//! their lifetime (the tests use an arena).

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Error = error{EmptyStack};

pub fn ImStack(comptime T: type) type {
    return union(enum) {
        const Self = @This();

        none: Empty,
        some: NonEmpty,

        /// The single empty stack. Every stack is built by pushing onto this.
        pub const empty: Self = .{ .none = .{} };

        const Node = struct {
            item: T,
            tail: Self,
        };

        /// The book's private `EmptyStack` class.
        const Empty = struct {
            fn peek(_: Empty) Error!T {
                return error.EmptyStack;
            }

            fn pop(_: Empty) Error!Self {
                return error.EmptyStack;
            }

            fn isEmpty(_: Empty) bool {
                return true;
            }
        };

        const NonEmpty = struct {
            node: *const Node,

            fn peek(s: NonEmpty) Error!T {
                return s.node.item;
            }

            fn pop(s: NonEmpty) Error!Self {
                return s.node.tail;
            }

            fn isEmpty(_: NonEmpty) bool {
                return false;
            }
        };

        /// O(1) time and memory, regardless of the size of `self`.
        pub fn push(self: Self, allocator: Allocator, item: T) Allocator.Error!Self {
            const node = try allocator.create(Node);
            node.* = .{ .item = item, .tail = self };
            return .{ .some = NonEmpty{ .node = node } };
        }

        /// The top item. Fails with `error.EmptyStack` on the empty stack.
        pub fn peek(self: Self) Error!T {
            return switch (self) {
                .none => |inner| inner.peek(),
                .some => |inner| inner.peek(),
            };
        }

        /// Everything below the top item. Fails with `error.EmptyStack` on the empty stack.
        pub fn pop(self: Self) Error!Self {
            return switch (self) {
                .none => |inner| inner.pop(),
                .some => |inner| inner.pop(),
            };
        }

        pub fn isEmpty(self: Self) bool {
            return switch (self) {
                .none => true,
                .some => false,
            };
        }

        /// Yields items from top to bottom without recursion or allocation.
        pub fn iterator(self: Self) Iterator {
            return .{ .current = self };
        }

        pub const Iterator = struct {
            current: Self,

            pub fn next(it: *Iterator) ?T {
                return switch (it.current) {
                    .none => null,
                    .some => |inner| blk: {
                        it.current = inner.node.tail;
                        break :blk inner.node.item;
                    },
                };
            }
        };
    };
}
