const std = @import("std");
const testing = std.testing;
const ImQueue = @import("im_queue.zig").ImQueue;

const Queue = ImQueue(i32);

/// Collects at most `expected.len + 1` items so a non-terminating iterator fails instead of hanging.
fn expectItems(comptime T: type, queue: ImQueue(T), expected: []const T) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var actual: std.ArrayList(T) = .empty;
    var it = try queue.iterator(a);
    while (actual.items.len <= expected.len) {
        const item = it.next() orelse break;
        try actual.append(a, item);
    }
    try testing.expectEqualSlices(T, expected, actual.items);
}

fn enqueueAll(allocator: std.mem.Allocator, items: []const i32) !Queue {
    var q = Queue.empty;
    for (items) |item| q = try q.enqueue(allocator, item);
    return q;
}

test "ImQueue: empty queue is empty and has no items" {
    try testing.expect(Queue.empty.isEmpty());
    try expectItems(i32, Queue.empty, &.{});
}

test "ImQueue: peek and dequeue on the empty queue fail without allocating" {
    try testing.expectError(error.EmptyQueue, Queue.empty.peek());
    try testing.expectError(error.EmptyQueue, Queue.empty.dequeue(testing.failing_allocator));
}

test "ImQueue: a single item can be peeked and dequeued" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const q = try Queue.empty.enqueue(a, 10);
    try testing.expect(!q.isEmpty());
    try testing.expectEqual(10, try q.peek());
    try testing.expect((try q.dequeue(a)).isEmpty());
}

test "ImQueue: items come out in the order they went in" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var q = try enqueueAll(a, &.{ 1, 2, 3, 4, 5 });
    try expectItems(i32, q, &.{ 1, 2, 3, 4, 5 });
    for (1..6) |expected| {
        try testing.expectEqual(@as(i32, @intCast(expected)), try q.peek());
        q = try q.dequeue(a);
    }
    try testing.expect(q.isEmpty());
}

test "ImQueue: book example q1..q7 (listing 2.8)" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const q1 = Queue.empty;
    const q2 = try q1.enqueue(a, 10);
    const q3 = try q2.enqueue(a, 20);
    const q4 = try q3.enqueue(a, 30);
    const q5 = try q4.dequeue(a);
    const q6 = try q5.dequeue(a);
    const q7 = try q6.dequeue(a);

    try expectItems(i32, q1, &.{});
    try expectItems(i32, q2, &.{10});
    try expectItems(i32, q3, &.{ 10, 20 });
    try expectItems(i32, q4, &.{ 10, 20, 30 });
    try expectItems(i32, q5, &.{ 20, 30 });
    try expectItems(i32, q6, &.{30});
    try expectItems(i32, q7, &.{});
    try testing.expect(q7.isEmpty());
}

test "ImQueue: enqueue and dequeue leave the original queue unchanged" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const q2 = try enqueueAll(a, &.{ 10, 20 });
    const left = try q2.enqueue(a, 30);
    const right = try q2.enqueue(a, 99);
    try expectItems(i32, q2, &.{ 10, 20 });
    try expectItems(i32, left, &.{ 10, 20, 30 });
    try expectItems(i32, right, &.{ 10, 20, 99 });

    const once = try left.dequeue(a);
    const again = try left.dequeue(a);
    try expectItems(i32, left, &.{ 10, 20, 30 });
    try expectItems(i32, once, &.{ 20, 30 });
    try expectItems(i32, again, &.{ 20, 30 });
    try expectItems(i32, try once.enqueue(a, 40), &.{ 20, 30, 40 });
    try expectItems(i32, once, &.{ 20, 30 });
}

test "ImQueue: interleaved enqueues and dequeues keep FIFO order" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var q = try enqueueAll(a, &.{ 1, 2 });
    q = try q.dequeue(a);
    q = try (try q.enqueue(a, 3)).enqueue(a, 4);
    try expectItems(i32, q, &.{ 2, 3, 4 });
    q = try q.dequeue(a);
    q = try q.dequeue(a);
    q = try q.enqueue(a, 5);
    try expectItems(i32, q, &.{ 4, 5 });
    try testing.expectEqual(4, try q.peek());
}

test "ImQueue: matches a simple model over random operations" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var prng: std.Random.DefaultPrng = .init(0x2_4);
    const random = prng.random();

    var model: std.ArrayList(i32) = .empty;
    var front: usize = 0;
    var next_item: i32 = 0;
    var q = Queue.empty;

    for (0..20_000) |step| {
        if (front == model.items.len or random.uintLessThan(u8, 3) != 0) {
            q = try q.enqueue(a, next_item);
            try model.append(a, next_item);
            next_item += 1;
        } else {
            q = try q.dequeue(a);
            front += 1;
        }

        try testing.expectEqual(front == model.items.len, q.isEmpty());
        if (front < model.items.len) try testing.expectEqual(model.items[front], try q.peek());
        if (step % 1000 == 0) try expectItems(i32, q, model.items[front..]);
    }
}

test "ImQueue: iterating does not consume the queue" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const q = try (try enqueueAll(a, &.{ 1, 2, 3, 4 })).dequeue(a);
    try expectItems(i32, q, &.{ 2, 3, 4 });
    try expectItems(i32, q, &.{ 2, 3, 4 });
    try testing.expectEqual(2, try q.peek());
}

test "ImQueue: enqueue cost does not depend on queue size" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    var big = Queue.empty;
    for (0..1000) |i| big = try big.enqueue(arena.allocator(), @intCast(i));
    const small = try Queue.empty.enqueue(arena.allocator(), 0);

    var on_small: testing.FailingAllocator = .init(arena.allocator(), .{});
    _ = try small.enqueue(on_small.allocator(), 42);

    var on_big: testing.FailingAllocator = .init(arena.allocator(), .{});
    _ = try big.enqueue(on_big.allocator(), 42);

    try testing.expect(on_small.allocations > 0);
    try testing.expectEqual(on_small.allocations, on_big.allocations);
    try testing.expectEqual(on_small.allocated_bytes, on_big.allocated_bytes);
}

test "ImQueue: dequeueing everything is amortized O(1) per item" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const n = 1000;
    var q = Queue.empty;
    for (0..n) |i| q = try q.enqueue(arena.allocator(), @intCast(i));

    var counting: testing.FailingAllocator = .init(arena.allocator(), .{});
    while (!q.isEmpty()) q = try q.dequeue(counting.allocator());

    // A queue that rebuilt its contents on every dequeue would need ~n²/2.
    try testing.expect(counting.allocations <= 2 * n);
}

test "ImQueue: enqueue reports OutOfMemory and leaves the queue usable" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const q = try enqueueAll(arena.allocator(), &.{ 1, 2 });
    var failing: testing.FailingAllocator = .init(arena.allocator(), .{ .fail_index = 0 });
    try testing.expectError(error.OutOfMemory, q.enqueue(failing.allocator(), 3));
    try expectItems(i32, q, &.{ 1, 2 });
}

test "ImQueue: dequeue fails cleanly with OutOfMemory at any allocation" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const q = try enqueueAll(arena.allocator(), &.{ 10, 20, 30 });
    var fail_index: usize = 0;
    while (fail_index < 100) : (fail_index += 1) {
        var failing: testing.FailingAllocator = .init(arena.allocator(), .{ .fail_index = fail_index });
        const result = q.dequeue(failing.allocator());
        try expectItems(i32, q, &.{ 10, 20, 30 });
        if (result) |rest| {
            try expectItems(i32, rest, &.{ 20, 30 });
            break;
        } else |err| try testing.expectEqual(error.OutOfMemory, err);
    } else return error.TestUnexpectedResult;
}

test "ImQueue: deep queues enqueue, iterate and dequeue without recursion" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const n = 200_000;
    var q = Queue.empty;
    for (0..n) |i| q = try q.enqueue(a, @intCast(i));

    var expected: i32 = 0;
    var it = try q.iterator(a);
    while (it.next()) |item| : (expected += 1) try testing.expectEqual(expected, item);
    try testing.expectEqual(n, expected);

    expected = 0;
    while (!q.isEmpty()) : (expected += 1) {
        try testing.expectEqual(expected, try q.peek());
        q = try q.dequeue(a);
    }
    try testing.expectEqual(n, expected);
}

test "ImQueue: works with non-integer items" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const Words = ImQueue([]const u8);
    const words = try (try (try Words.empty.enqueue(a, "bank")).enqueue(a, "queue")).enqueue(a, "gesundheit");
    try testing.expectEqualStrings("bank", try words.peek());
    try testing.expectEqualStrings("queue", try (try words.dequeue(a)).peek());
    try expectItems([]const u8, try words.dequeue(a), &.{ "queue", "gesundheit" });
}

/// Queues whose items sit in different internal states: freshly enqueued,
/// partly dequeued, and dequeued down to their last enqueued items.
fn sampleQueues(allocator: std.mem.Allocator) ![3]Queue {
    return .{
        try enqueueAll(allocator, &.{ 1, 2, 3 }),
        try (try enqueueAll(allocator, &.{ 0, 1, 2, 3 })).dequeue(allocator),
        try (try (try enqueueAll(allocator, &.{ -1, 0, 1, 2, 3 })).dequeue(allocator)).dequeue(allocator),
    };
}

test "ImQueue.concatenate: joins two queues in order" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const lefts = try sampleQueues(a);
    const right = try (try (try enqueueAll(a, &.{ 3, 4, 5, 6 })).dequeue(a)).enqueue(a, 7);
    for (lefts) |left| {
        try expectItems(i32, left, &.{ 1, 2, 3 });
        try expectItems(i32, try left.concatenate(a, right), &.{ 1, 2, 3, 4, 5, 6, 7 });
        try expectItems(i32, try right.concatenate(a, left), &.{ 4, 5, 6, 7, 1, 2, 3 });
        try expectItems(i32, try left.concatenate(a, left), &.{ 1, 2, 3, 1, 2, 3 });
    }
}

test "ImQueue.concatenate: the empty queue on either side changes nothing and allocates nothing" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const q = try enqueueAll(arena.allocator(), &.{ 1, 2, 3 });
    var failing: testing.FailingAllocator = .init(arena.allocator(), .{ .fail_index = 0 });
    try expectItems(i32, try q.concatenate(failing.allocator(), .empty), &.{ 1, 2, 3 });
    try expectItems(i32, try Queue.empty.concatenate(failing.allocator(), q), &.{ 1, 2, 3 });
    try testing.expect((try Queue.empty.concatenate(failing.allocator(), .empty)).isEmpty());
}

test "ImQueue.concatenate: leaves both queues unchanged" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const left = try enqueueAll(a, &.{ 1, 2 });
    const right = try (try enqueueAll(a, &.{ 2, 3, 4 })).dequeue(a);
    _ = try left.concatenate(a, right);
    _ = try right.concatenate(a, left);
    try expectItems(i32, left, &.{ 1, 2 });
    try expectItems(i32, right, &.{ 3, 4 });
}

test "ImQueue.concatenate: the result keeps working as a queue" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var q = try (try enqueueAll(a, &.{ 1, 2 })).concatenate(a, try enqueueAll(a, &.{ 3, 4 }));
    q = try q.enqueue(a, 5);
    for (1..6) |expected| {
        try testing.expectEqual(@as(i32, @intCast(expected)), try q.peek());
        q = try q.dequeue(a);
    }
    try testing.expect(q.isEmpty());
}

test "ImQueue.concatenate: matches a simple model over random operations" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var prng: std.Random.DefaultPrng = .init(0x2_4_c);
    const random = prng.random();

    var model: std.ArrayList(i32) = .empty;
    var next_item: i32 = 0;
    var q = Queue.empty;

    for (0..5_000) |step| {
        switch (random.uintLessThan(u8, 4)) {
            0 => {
                q = try q.enqueue(a, next_item);
                try model.append(a, next_item);
                next_item += 1;
            },
            1 => if (model.items.len > 0) {
                q = try q.dequeue(a);
                _ = model.orderedRemove(0);
            },
            else => |op| {
                const len = random.uintLessThan(usize, 5);
                var part = Queue.empty;
                var items: std.ArrayList(i32) = .empty;
                for (0..len) |_| {
                    part = try part.enqueue(a, next_item);
                    try items.append(a, next_item);
                    next_item += 1;
                }
                if (op == 2) {
                    q = try q.concatenate(a, part);
                    try model.appendSlice(a, items.items);
                } else {
                    q = try part.concatenate(a, q);
                    try model.insertSlice(a, 0, items.items);
                }
            },
        }

        try testing.expectEqual(model.items.len == 0, q.isEmpty());
        if (model.items.len > 0) try testing.expectEqual(model.items[0], try q.peek());
        if (step % 250 == 0) try expectItems(i32, q, model.items);
    }
    try expectItems(i32, q, model.items);
}

test "ImQueue.concatenate: reports OutOfMemory at any allocation and leaves both queues usable" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const left = try enqueueAll(a, &.{ 1, 2 });
    const right = try (try enqueueAll(a, &.{ 2, 3, 4, 5 })).dequeue(a);
    var fail_index: usize = 0;
    while (fail_index < 100) : (fail_index += 1) {
        var failing: testing.FailingAllocator = .init(a, .{ .fail_index = fail_index });
        const result = left.concatenate(failing.allocator(), right);
        try expectItems(i32, left, &.{ 1, 2 });
        try expectItems(i32, right, &.{ 3, 4, 5 });
        if (result) |joined| {
            try expectItems(i32, joined, &.{ 1, 2, 3, 4, 5 });
            break;
        } else |err| try testing.expectEqual(error.OutOfMemory, err);
    } else return error.TestUnexpectedResult;
}

test "ImQueue.concatenate: long queues join without recursion" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const n = 100_000;
    var left = Queue.empty;
    var right = Queue.empty;
    for (0..n) |i| {
        left = try left.enqueue(a, @intCast(i));
        right = try right.enqueue(a, @intCast(n + i));
    }
    right = try (try right.enqueue(a, 2 * n)).dequeue(a);

    var q = try left.concatenate(a, right);
    var expected: i32 = 0;
    while (!q.isEmpty()) : (expected += 1) {
        if (expected == n) expected += 1;
        try testing.expectEqual(expected, try q.peek());
        q = try q.dequeue(a);
    }
    try testing.expectEqual(2 * n + 1, expected);
}

test "ImQueue.single: a one-item queue" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const q = try Queue.single(a, 7);
    try testing.expect(!q.isEmpty());
    try testing.expectEqual(7, try q.peek());
    try testing.expect((try q.dequeue(a)).isEmpty());
    try expectItems(i32, q, &.{7});
    try expectItems(i32, try (try q.enqueue(a, 8)).enqueue(a, 9), &.{ 7, 8, 9 });
}

test "ImQueue.single: reports OutOfMemory" {
    var failing: testing.FailingAllocator = .init(testing.allocator, .{ .fail_index = 0 });
    try testing.expectError(error.OutOfMemory, Queue.single(failing.allocator(), 7));
}
