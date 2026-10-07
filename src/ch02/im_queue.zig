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
        const Stack = ImStack(T);

        enqueues: Stack,
        /// dequeues is never empty in an non-empty ImQueue
        dequeues: Stack,

        /// The single empty queue. Every queue is built by enqueueing onto this.
        pub const empty: Self = .{ .enqueues = .empty, .dequeues = .empty };

        /// O(1) time and memory, regardless of the size of `self`.
        pub fn enqueue(self: Self, allocator: Allocator, item: T) Allocator.Error!Self {
            return if (self.isEmpty())
                .{ .enqueues = self.enqueues, .dequeues = try self.dequeues.push(allocator, item) }
            else
                .{ .enqueues = try self.enqueues.push(allocator, item), .dequeues = self.dequeues };
        }

        /// The front (least recently enqueued) item.
        /// Fails with `error.EmptyQueue` on the empty queue.
        pub fn peek(self: Self) Error!T {
            return self.dequeues.peek() catch error.EmptyQueue;
        }

        /// Everything after the front item. Fails with `error.EmptyQueue` on
        /// the empty queue. Amortized O(1); an occasional call is O(n).
        pub fn dequeue(self: Self, allocator: Allocator) (Error || Allocator.Error)!Self {
            const tail = self.dequeues.pop() catch return error.EmptyQueue;
            return if (!tail.isEmpty())
                .{ .enqueues = self.enqueues, .dequeues = tail }
            else
                .{ .enqueues = .empty, .dequeues = try self.enqueues.reverse(allocator) };
        }

        pub fn isEmpty(self: Self) bool {
            return self.dequeues.isEmpty();
        }

        /// Yields items from front to back. O(n) time; may allocate O(n) memory.
        pub fn iterator(self: Self, allocator: Allocator) Allocator.Error!Iterator {
            const back = (try self.enqueues.reverse(allocator)).iterator();
            return .{ .front = self.dequeues.iterator(), .back = back };
        }

        pub const Iterator = struct {
            front: Stack.Iterator,
            back: Stack.Iterator,

            pub fn next(it: *Iterator) ?T {
                return it.front.next() orelse it.back.next();
            }
        };
    };
}
