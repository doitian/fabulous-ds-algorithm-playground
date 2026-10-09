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
        const Pair = struct { Self, Self };

        const Capture = union(enum) {
            stack: Stack,
            single: T,
            h_list_pair: *const Pair,
            empty,
        };
        const Concat = struct {
            capture: Capture,
            apply: *const fn (Capture, Allocator, Stack) Allocator.Error!Stack,

            fn call(self: Concat, allocator: Allocator, stack: Stack) Allocator.Error!Stack {
                return self.apply(self.capture, allocator, stack);
            }
        };

        c: Concat,

        pub const empty: Self = .{ .c = .{
            .capture = .empty,
            .apply = struct {
                fn lambda(_: Capture, _: Allocator, tail: Stack) Allocator.Error!Stack {
                    return tail;
                }
            }.lambda,
        } };

        /// O(1). True for every empty list, however it was built.
        pub fn isEmpty(self: Self) bool {
            return self.c.apply == empty.c.apply;
        }

        /// The list holding `stack`'s items in the same order.
        /// O(1), regardless of the size of `stack`.
        pub fn fromStack(stack: Stack) Self {
            if (stack.isEmpty()) return .empty;

            return .{
                .c = .{
                    .capture = .{ .stack = stack },
                    .apply = struct {
                        fn lambda(capture: Capture, allocator: Allocator, tail: Stack) Allocator.Error!Stack {
                            return capture.stack.concatenate(allocator, tail);
                        }
                    }.lambda,
                },
            };
        }

        /// 2.7.7: the list holding `stack`'s items in reverse order.
        /// O(1), regardless of the size of `stack`.
        pub fn fromStackReversed(stack: Stack) Self {
            if (stack.isEmpty()) return .empty;

            return .{
                .c = .{
                    .capture = .{ .stack = stack },
                    .apply = struct {
                        fn lambda(capture: Capture, allocator: Allocator, tail: Stack) Allocator.Error!Stack {
                            return capture.stack.reverseOnto(allocator, tail);
                        }
                    }.lambda,
                },
            };
        }

        /// A one-item list. O(1).
        pub fn single(item: T) Self {
            return .{ .c = .{
                .capture = .{ .single = item },
                .apply = struct {
                    fn lambda(capture: Capture, allocator: Allocator, tail: Stack) Allocator.Error!Stack {
                        return tail.push(allocator, capture.single);
                    }
                }.lambda,
            } };
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
            if (self.isEmpty()) return other;

            const pair = try allocator.create(Pair);
            pair.* = .{ self, other };

            return .{ .c = .{
                .capture = .{ .h_list_pair = pair },
                .apply = struct {
                    fn lambda(capture: Capture, gpa: Allocator, tail: Stack) Allocator.Error!Stack {
                        const front, const back = capture.h_list_pair.*;
                        const back_stack = try back.c.call(gpa, tail);
                        return front.c.call(gpa, back_stack);
                    }
                }.lambda,
            } };
        }

        /// The represented list as a stack, first item on top. O(n).
        pub fn toStack(self: Self, allocator: Allocator) Allocator.Error!Stack {
            return self.c.call(allocator, .empty);
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
