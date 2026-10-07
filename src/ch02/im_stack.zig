//! 2.2 An immutable stack (listings 2.1 and 2.2)
//!
//! A persistent stack: `push` and `pop` never change the stack they are
//! called on. They return a new stack that shares structure with the old one.
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

        // TODO: add the fields of your representation, then make `empty` match.

        /// The single empty stack. Every stack is built by pushing onto this.
        pub const empty: Self = .{};

        /// O(1) time and memory, regardless of the size of `self`.
        pub fn push(self: Self, allocator: Allocator, item: T) Allocator.Error!Self {
            _ = self;
            _ = allocator;
            _ = item;
            @panic("TODO: ImStack.push");
        }

        /// The top item. Fails with `error.EmptyStack` on the empty stack.
        pub fn peek(self: Self) Error!T {
            _ = self;
            @panic("TODO: ImStack.peek");
        }

        /// Everything below the top item. Fails with `error.EmptyStack` on the empty stack.
        pub fn pop(self: Self) Error!Self {
            _ = self;
            @panic("TODO: ImStack.pop");
        }

        pub fn isEmpty(self: Self) bool {
            _ = self;
            @panic("TODO: ImStack.isEmpty");
        }

        /// Yields items from top to bottom without recursion or allocation.
        pub fn iterator(self: Self) Iterator {
            _ = self;
            @panic("TODO: ImStack.iterator");
        }

        pub const Iterator = struct {
            // TODO: add the fields your iterator needs.

            pub fn next(it: *Iterator) ?T {
                _ = it;
                @panic("TODO: ImStack.Iterator.next");
            }
        };
    };
}
