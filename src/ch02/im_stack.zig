//! 2.2 An immutable stack (listings 2.1 and 2.2)
//!
//! A persistent stack: `push` and `pop` never change the stack they are
//! called on. They return a new stack that shares structure with the old one.
//!
//! The book's separate empty-stack class becomes a null `head`. Unlike C#
//! null, a Zig optional can't be dereferenced until it is unwrapped, so the
//! compiler makes every operation handle the empty case.
//!
//! Memory: `push` allocates from the allocator it is given. Because tails are
//! shared between stacks, nodes are never freed one by one; the caller owns
//! their lifetime (the tests use an arena).

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Error = error{EmptyStack};

pub fn ImStack(comptime T: type) type {
    return struct {
        const Self = @This();

        head: ?*const Node,

        /// The single empty stack. Every stack is built by pushing onto this.
        pub const empty: Self = .{ .head = null };

        const Node = struct {
            item: T,
            tail: Self,
        };

        /// O(1) time and memory, regardless of the size of `self`.
        pub fn push(self: Self, allocator: Allocator, item: T) Allocator.Error!Self {
            const node = try allocator.create(Node);
            node.* = .{ .item = item, .tail = self };
            return .{ .head = node };
        }

        /// The top item. Fails with `error.EmptyStack` on the empty stack.
        pub fn peek(self: Self) Error!T {
            const node = self.head orelse return error.EmptyStack;
            return node.item;
        }

        /// Everything below the top item. Fails with `error.EmptyStack` on the empty stack.
        pub fn pop(self: Self) Error!Self {
            const node = self.head orelse return error.EmptyStack;
            return node.tail;
        }

        pub fn isEmpty(self: Self) bool {
            return self.head == null;
        }

        /// 2.4, listing 2.7: the same items in the opposite order.
        /// O(n) time and memory, without recursion; `self` is unchanged.
        pub fn reverse(self: Self, allocator: Allocator) Allocator.Error!Self {
            return self.reverseOnto(allocator, .empty);
        }

        /// 2.7.1, listing 2.13: `self` reversed, on top of `tail`.
        /// O(n) in the size of `self`; `tail` is shared, not copied.
        pub fn reverseOnto(self: Self, allocator: Allocator, tail: Self) Allocator.Error!Self {
            var it = self.iterator();
            var result = tail;
            while (it.next()) |item| {
                result = try result.push(allocator, item);
            }
            return result;
        }

        /// 2.7.1, listing 2.13: `self`'s items followed by `other`'s.
        /// O(n) in the size of `self`; `other` is shared, not copied.
        pub fn concatenate(self: Self, allocator: Allocator, other: Self) Allocator.Error!Self {
            if (other.isEmpty()) return self;
            const front = try self.reverse(allocator);
            return front.reverseOnto(allocator, other);
        }

        /// 2.7.1, listing 2.13: `self` with `item` added at the bottom. O(n).
        pub fn append(self: Self, allocator: Allocator, item: T) Allocator.Error!Self {
            const single = try empty.push(allocator, item);
            return self.concatenate(allocator, single);
        }

        /// Yields items from top to bottom without recursion or allocation.
        pub fn iterator(self: Self) Iterator {
            return .{ .current = self };
        }

        pub const Iterator = struct {
            current: Self,

            pub fn next(it: *Iterator) ?T {
                const node = it.current.head orelse return null;
                it.current = node.tail;
                return node.item;
            }
        };
    };
}
