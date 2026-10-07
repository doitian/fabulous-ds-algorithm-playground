//! 2.4 A queue, a queue, an immutable queue (listings 2.6 and 2.7)
//!
//! A persistent FIFO queue: `enqueue` and `dequeue` never change the queue
//! they are called on. They return a new queue that shares structure with the
//! old one.
//!
//! Memory: as with `ImStack`, nodes are shared between queues, so the caller
//! owns their lifetime (the tests use an arena). `dequeue` and `iterator` may
//! need to allocate, so they take an allocator too.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ImStack = @import("im_stack.zig").ImStack;

pub const Error = error{EmptyQueue};

pub fn ImQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        // TODO: add the fields of your representation, then make `empty` match.

        /// The single empty queue. Every queue is built by enqueueing onto this.
        pub const empty: Self = .{};

        /// O(1) time and memory, regardless of the size of `self`.
        pub fn enqueue(self: Self, allocator: Allocator, item: T) Allocator.Error!Self {
            _ = self;
            _ = allocator;
            _ = item;
            @panic("TODO: ImQueue.enqueue");
        }

        /// The front (least recently enqueued) item.
        /// Fails with `error.EmptyQueue` on the empty queue.
        pub fn peek(self: Self) Error!T {
            _ = self;
            @panic("TODO: ImQueue.peek");
        }

        /// Everything after the front item. Fails with `error.EmptyQueue` on
        /// the empty queue. Amortized O(1); an occasional call is O(n).
        pub fn dequeue(self: Self, allocator: Allocator) (Error || Allocator.Error)!Self {
            _ = self;
            _ = allocator;
            @panic("TODO: ImQueue.dequeue");
        }

        pub fn isEmpty(self: Self) bool {
            _ = self;
            @panic("TODO: ImQueue.isEmpty");
        }

        /// Yields items from front to back. O(n) time; may allocate O(n) memory.
        pub fn iterator(self: Self, allocator: Allocator) Allocator.Error!Iterator {
            _ = self;
            _ = allocator;
            @panic("TODO: ImQueue.iterator");
        }

        pub const Iterator = struct {
            // TODO: add the fields your iterator needs.

            pub fn next(it: *Iterator) ?T {
                _ = it;
                @panic("TODO: ImQueue.Iterator.next");
            }
        };
    };
}
