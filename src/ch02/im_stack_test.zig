const std = @import("std");
const testing = std.testing;
const ImStack = @import("im_stack.zig").ImStack;

const Stack = ImStack(i32);

/// Collects at most `expected.len + 1` items so a non-terminating iterator fails instead of hanging.
fn expectItems(comptime T: type, stack: ImStack(T), expected: []const T) !void {
    var actual: std.ArrayList(T) = .empty;
    defer actual.deinit(testing.allocator);
    var it = stack.iterator();
    while (actual.items.len <= expected.len) {
        const item = it.next() orelse break;
        try actual.append(testing.allocator, item);
    }
    try testing.expectEqualSlices(T, expected, actual.items);
}

test "ImStack: empty stack is empty and has no items" {
    try testing.expect(Stack.empty.isEmpty());
    try expectItems(i32, Stack.empty, &.{});
}

test "ImStack: peek and pop on the empty stack fail" {
    try testing.expectError(error.EmptyStack, Stack.empty.peek());
    try testing.expectError(error.EmptyStack, Stack.empty.pop());
}

test "ImStack: push puts the item on top" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const s = try Stack.empty.push(a, 10);
    try testing.expect(!s.isEmpty());
    try testing.expectEqual(10, try s.peek());
    try expectItems(i32, s, &.{10});
}

test "ImStack: pop returns the stack below the top" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const s = try (try Stack.empty.push(a, 1)).push(a, 2);
    const popped = try s.pop();
    try testing.expectEqual(1, try popped.peek());
    try testing.expect((try popped.pop()).isEmpty());
}

test "ImStack: items are enumerated from top to bottom" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var s = Stack.empty;
    for (1..6) |i| s = try s.push(a, @intCast(i));
    try expectItems(i32, s, &.{ 5, 4, 3, 2, 1 });
}

test "ImStack: push and pop leave the original stack unchanged" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const s1 = Stack.empty;
    const s2 = try s1.push(a, 10);
    const s3 = try s2.push(a, 20);
    _ = try s3.pop();

    try expectItems(i32, s1, &.{});
    try expectItems(i32, s2, &.{10});
    try expectItems(i32, s3, &.{ 20, 10 });
}

test "ImStack: book example s1..s6" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const s1 = Stack.empty;
    const s2 = try s1.push(a, 10);
    const s3 = try s2.push(a, 20);
    const s4 = try s2.push(a, 30);
    const s5 = try s4.pop();
    const s6 = try s5.pop();

    try expectItems(i32, s1, &.{});
    try expectItems(i32, s2, &.{10});
    try expectItems(i32, s3, &.{ 20, 10 });
    try expectItems(i32, s4, &.{ 30, 10 });
    try expectItems(i32, s5, &.{10});
    try expectItems(i32, s6, &.{});
}

test "ImStack: iterating does not consume the stack, and iterators are independent" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const s = try (try (try Stack.empty.push(a, 1)).push(a, 2)).push(a, 3);
    var it1 = s.iterator();
    var it2 = s.iterator();
    try testing.expectEqual(3, it1.next());
    try testing.expectEqual(2, it1.next());
    try testing.expectEqual(3, it2.next());
    try testing.expectEqual(1, it1.next());
    try testing.expectEqual(null, it1.next());
    try testing.expectEqual(2, it2.next());
    try expectItems(i32, s, &.{ 3, 2, 1 });
}

test "ImStack: push is persistent, with cost independent of stack size" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    var big = Stack.empty;
    for (0..1000) |i| big = try big.push(arena.allocator(), @intCast(i));

    var on_empty: testing.FailingAllocator = .init(arena.allocator(), .{});
    _ = try Stack.empty.push(on_empty.allocator(), 42);

    var on_big: testing.FailingAllocator = .init(arena.allocator(), .{});
    _ = try big.push(on_big.allocator(), 42);
    _ = try big.push(on_big.allocator(), 43);

    try testing.expect(on_empty.allocations > 0);
    try testing.expectEqual(2 * on_empty.allocations, on_big.allocations);
    try testing.expectEqual(2 * on_empty.allocated_bytes, on_big.allocated_bytes);
}

test "ImStack: push reports OutOfMemory and leaves the stack usable" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const s = try Stack.empty.push(arena.allocator(), 1);
    var failing: testing.FailingAllocator = .init(arena.allocator(), .{ .fail_index = 0 });
    try testing.expectError(error.OutOfMemory, s.push(failing.allocator(), 2));
    try expectItems(i32, s, &.{1});
}

test "ImStack: deep stacks iterate and pop without recursion" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const n = 200_000;
    var s = Stack.empty;
    for (0..n) |i| s = try s.push(a, @intCast(i));

    var count: usize = 0;
    var it = s.iterator();
    while (it.next()) |item| : (count += 1) {
        try testing.expectEqual(@as(i32, @intCast(n - 1 - count)), item);
    }
    try testing.expectEqual(n, count);

    var pops: usize = 0;
    while (!s.isEmpty()) : (pops += 1) s = try s.pop();
    try testing.expectEqual(n, pops);
}

test "ImStack: works with non-integer items" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const Point = struct { x: f64, y: f64 };
    const points = try (try ImStack(Point).empty.push(a, .{ .x = 1, .y = 2 })).push(a, .{ .x = 3, .y = 4 });
    try testing.expectEqual(Point{ .x = 3, .y = 4 }, try points.peek());

    const Words = ImStack([]const u8);
    const words = try (try Words.empty.push(a, "tiger")).push(a, "giraffe");
    try testing.expectEqualStrings("giraffe", try words.peek());
    try testing.expectEqualStrings("tiger", try (try words.pop()).peek());
}

/// Pushes `items` in order, so the last one ends up on top.
fn pushAll(allocator: std.mem.Allocator, items: []const i32) !Stack {
    var s = Stack.empty;
    for (items) |item| s = try s.push(allocator, item);
    return s;
}

test "ImStack.reverse: reversing the empty stack gives the empty stack without allocating" {
    var failing: testing.FailingAllocator = .init(testing.allocator, .{ .fail_index = 0 });
    const r = try Stack.empty.reverse(failing.allocator());
    try testing.expect(r.isEmpty());
}

test "ImStack.reverse: reverses the order and leaves the original unchanged" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const s = try pushAll(a, &.{ 1, 2, 3 });
    const r = try s.reverse(a);
    try expectItems(i32, r, &.{ 1, 2, 3 });
    try expectItems(i32, s, &.{ 3, 2, 1 });
    try expectItems(i32, try r.reverse(a), &.{ 3, 2, 1 });

    try expectItems(i32, try (try Stack.empty.push(a, 7)).reverse(a), &.{7});
}

test "ImStack.reverse: reports OutOfMemory at any allocation and leaves the stack usable" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const s = try pushAll(arena.allocator(), &.{ 1, 2, 3 });
    var fail_index: usize = 0;
    while (fail_index < 100) : (fail_index += 1) {
        var failing: testing.FailingAllocator = .init(arena.allocator(), .{ .fail_index = fail_index });
        const result = s.reverse(failing.allocator());
        try expectItems(i32, s, &.{ 3, 2, 1 });
        if (result) |r| {
            try expectItems(i32, r, &.{ 1, 2, 3 });
            break;
        } else |err| try testing.expectEqual(error.OutOfMemory, err);
    } else return error.TestUnexpectedResult;
    try testing.expect(fail_index > 0);
}

test "ImStack.reverse: deep stacks reverse without recursion" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const n = 200_000;
    var s = Stack.empty;
    for (0..n) |i| s = try s.push(a, @intCast(i));

    const r = try s.reverse(a);
    var expected: i32 = 0;
    var it = r.iterator();
    while (it.next()) |item| : (expected += 1) try testing.expectEqual(expected, item);
    try testing.expectEqual(n, expected);
}

test "ImStack.reverseOnto: puts the reversed stack on top of the tail" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const s = try pushAll(a, &.{ 1, 2, 3 });
    const tail = try pushAll(a, &.{ 8, 9 });
    try expectItems(i32, try s.reverseOnto(a, tail), &.{ 1, 2, 3, 9, 8 });
    try expectItems(i32, try s.reverseOnto(a, .empty), &.{ 1, 2, 3 });
    try expectItems(i32, s, &.{ 3, 2, 1 });
    try expectItems(i32, tail, &.{ 9, 8 });

    var failing: testing.FailingAllocator = .init(testing.allocator, .{ .fail_index = 0 });
    try expectItems(i32, try Stack.empty.reverseOnto(failing.allocator(), tail), &.{ 9, 8 });
}

test "ImStack.concatenate: joins two stacks in order" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const xs = try pushAll(a, &.{ 1, 2, 3 });
    const ys = try pushAll(a, &.{ 8, 9 });
    try expectItems(i32, try xs.concatenate(a, ys), &.{ 3, 2, 1, 9, 8 });
    try expectItems(i32, try ys.concatenate(a, xs), &.{ 9, 8, 3, 2, 1 });
    try expectItems(i32, try Stack.empty.concatenate(a, ys), &.{ 9, 8 });
    try expectItems(i32, xs, &.{ 3, 2, 1 });
    try expectItems(i32, ys, &.{ 9, 8 });
}

test "ImStack.concatenate: an empty right-hand stack returns the left one without allocating" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const xs = try pushAll(arena.allocator(), &.{ 1, 2, 3 });
    var failing: testing.FailingAllocator = .init(arena.allocator(), .{ .fail_index = 0 });
    try expectItems(i32, try xs.concatenate(failing.allocator(), .empty), &.{ 3, 2, 1 });
}

test "ImStack.concatenate: cost does not depend on the right-hand stack" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const xs = try pushAll(arena.allocator(), &.{ 1, 2, 3 });
    const small = try pushAll(arena.allocator(), &.{0});
    var big = Stack.empty;
    for (0..1000) |i| big = try big.push(arena.allocator(), @intCast(i));

    var onto_small: testing.FailingAllocator = .init(arena.allocator(), .{});
    _ = try xs.concatenate(onto_small.allocator(), small);

    var onto_big: testing.FailingAllocator = .init(arena.allocator(), .{});
    _ = try xs.concatenate(onto_big.allocator(), big);

    try testing.expectEqual(onto_small.allocations, onto_big.allocations);
    try testing.expectEqual(onto_small.allocated_bytes, onto_big.allocated_bytes);
}

test "ImStack.concatenate: reports OutOfMemory at any allocation and leaves both stacks usable" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const xs = try pushAll(arena.allocator(), &.{ 1, 2, 3 });
    const ys = try pushAll(arena.allocator(), &.{ 8, 9 });
    var fail_index: usize = 0;
    while (fail_index < 100) : (fail_index += 1) {
        var failing: testing.FailingAllocator = .init(arena.allocator(), .{ .fail_index = fail_index });
        const result = xs.concatenate(failing.allocator(), ys);
        try expectItems(i32, xs, &.{ 3, 2, 1 });
        try expectItems(i32, ys, &.{ 9, 8 });
        if (result) |joined| {
            try expectItems(i32, joined, &.{ 3, 2, 1, 9, 8 });
            break;
        } else |err| try testing.expectEqual(error.OutOfMemory, err);
    } else return error.TestUnexpectedResult;
    try testing.expect(fail_index > 0);
}

test "ImStack.append: adds an item at the bottom" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const s = try pushAll(a, &.{ 1, 2, 3 });
    try expectItems(i32, try s.append(a, 0), &.{ 3, 2, 1, 0 });
    try expectItems(i32, try Stack.empty.append(a, 5), &.{5});
    try expectItems(i32, s, &.{ 3, 2, 1 });
}

test "ImStack.single: a one-item stack" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const s = try Stack.single(a, 7);
    try testing.expect(!s.isEmpty());
    try testing.expectEqual(7, try s.peek());
    try testing.expect((try s.pop()).isEmpty());
    try expectItems(i32, s, &.{7});
}

test "ImStack.single: reports OutOfMemory" {
    var failing: testing.FailingAllocator = .init(testing.allocator, .{ .fail_index = 0 });
    try testing.expectError(error.OutOfMemory, Stack.single(failing.allocator(), 7));
}
