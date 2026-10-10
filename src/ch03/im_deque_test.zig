const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ImDeque = @import("im_deque.zig").ImDeque;
const Deque = ImDeque(i32);

fn expectItems(comptime T: type, deque: ImDeque(T), expected: []const T) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var it = try deque.iterator(arena.allocator());
    for (expected) |item| try testing.expectEqualDeep(item, it.next() orelse return error.TestUnexpectedResult);
    try testing.expectEqual(@as(?T, null), it.next());
    try testing.expectEqual(@as(?T, null), it.next());
}

fn dequeOf(allocator: Allocator, items: []const i32) !Deque {
    var deque = Deque.empty;
    for (items) |item| deque = try deque.pushRight(allocator, item);
    return deque;
}

fn expectPoppedItems(comptime T: type, deque: ImDeque(T), expected: []const T) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    for ([_]bool{ false, true }) |pop_left| {
        var remaining = deque;
        for (0..expected.len) |i| {
            const items = if (pop_left) expected[i..] else expected[0 .. expected.len - i];
            try testing.expect(!remaining.isEmpty());
            try testing.expectEqualDeep(items[0], try remaining.left());
            try testing.expectEqualDeep(items[items.len - 1], try remaining.right());
            remaining = if (pop_left)
                try remaining.popLeft(arena.allocator())
            else
                try remaining.popRight(arena.allocator());
        }
        try testing.expect(remaining.isEmpty());
    }
}

test "ImDeque: runtime nodes handle deep overflow, refill and persistent branches without iteration" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var values: [1024]i32 = undefined;
    for (&values, 0..) |*value, i| value.* = @intCast(i);
    for ([_]usize{ 0, 1, 2, 4, 5, 8, 9, 21, 22, 64, 1024 }) |n| {
        for ([_]bool{ false, true }) |build_left| {
            var deque = Deque.empty;
            for (0..n) |i| deque = if (build_left)
                try deque.pushLeft(a, values[n - 1 - i])
            else
                try deque.pushRight(a, values[i]);
            const original = deque;
            deque = try (try (try (try deque.pushLeft(a, -1)).pushRight(a, 1024)).popLeft(a)).popRight(a);
            try expectPoppedItems(i32, deque, values[0..n]);
            try expectPoppedItems(i32, original, values[0..n]);
        }
    }
    try testing.expectError(error.EmptyDeque, Deque.empty.popLeft(testing.failing_allocator));
    try testing.expectError(error.EmptyDeque, Deque.empty.popRight(testing.failing_allocator));
    try testing.expect((try Deque.single(7).popLeft(testing.failing_allocator)).isEmpty());
    try testing.expect((try Deque.single(7).popRight(testing.failing_allocator)).isEmpty());
}

test "ImDeque: runtime nodes keep non-integer leaves distinct from middle chunks" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Words = ImDeque([]const u8);
    const expected = [_][]const u8{ "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l" };
    var words = Words.single(expected[0]);
    for (expected[1..]) |word| words = try words.pushRight(a, word);
    try expectPoppedItems([]const u8, words, &expected);
}

test "ImDeque: runtime node allocation failures preserve source versions without iteration" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var values: [128]i32 = undefined;
    for (&values, 0..) |*value, i| value.* = @intCast(i);
    for ([_]usize{ 1, 5, 23, 128 }) |n| {
        const deque = try dequeOf(a, values[0..n]);
        for (0..4) |operation| {
            for (0..128) |fail_index| {
                var failing: testing.FailingAllocator = .init(a, .{ .fail_index = fail_index });
                const gpa = failing.allocator();
                const result = switch (operation) {
                    0 => deque.pushLeft(gpa, -1),
                    1 => deque.pushRight(gpa, 128),
                    2 => deque.popLeft(gpa),
                    3 => deque.popRight(gpa),
                    else => unreachable,
                };
                try expectPoppedItems(i32, deque, values[0..n]);
                if (result) |_| break else |err| try testing.expectEqual(error.OutOfMemory, err);
            } else return error.TestUnexpectedResult;
        }
    }
}

fn expectEnds(deque: Deque, expected: []const i32) !void {
    try testing.expectEqual(expected.len == 0, deque.isEmpty());
    if (expected.len == 0) {
        try testing.expectError(error.EmptyDeque, deque.left());
        try testing.expectError(error.EmptyDeque, deque.right());
    } else {
        try testing.expectEqual(expected[0], try deque.left());
        try testing.expectEqual(expected[expected.len - 1], try deque.right());
    }
}

test "ImDeque: empty queries and pops fail without allocating" {
    try expectEnds(.empty, &.{});
    try expectItems(i32, Deque.empty, &.{});
    try testing.expectError(error.EmptyDeque, Deque.empty.popLeft(testing.failing_allocator));
    try testing.expectError(error.EmptyDeque, Deque.empty.popRight(testing.failing_allocator));
}

test "ImDeque: singleton can be created from either end and popped from either end" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const singles = [_]Deque{
        Deque.single(7),
        try Deque.empty.pushLeft(a, 7),
        try Deque.empty.pushRight(a, 7),
    };
    for (singles) |one| {
        try expectEnds(one, &.{7});
        try expectItems(i32, one, &.{7});
        try testing.expect((try one.popLeft(a)).isEmpty());
        try testing.expect((try one.popRight(a)).isEmpty());
        try expectItems(i32, one, &.{7});
    }
}

test "ImDeque: pushes and pops address the requested end" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const middle = try dequeOf(a, &.{ 2, 3 });
    const deque = try (try middle.pushLeft(a, 1)).pushRight(a, 4);
    try expectEnds(deque, &.{ 1, 2, 3, 4 });
    try expectItems(i32, deque, &.{ 1, 2, 3, 4 });
    try expectItems(i32, try deque.popLeft(a), &.{ 2, 3, 4 });
    try expectItems(i32, try deque.popRight(a), &.{ 1, 2, 3 });
    try expectItems(i32, middle, &.{ 2, 3 });
}

test "ImDeque: all small sizes handle overflow, refill and an empty middle" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var values: [64]i32 = undefined;
    for (&values, 0..) |*value, i| value.* = @intCast(i);

    for (0..65) |n| {
        for ([_]bool{ false, true }) |build_left| {
            var original = Deque.empty;
            for (0..n) |i| {
                original = if (build_left)
                    try original.pushLeft(a, values[n - 1 - i])
                else
                    try original.pushRight(a, values[i]);
            }
            try expectItems(i32, original, values[0..n]);
            for ([_]bool{ false, true }) |pop_left| {
                var deque = original;
                for (0..n) |i| {
                    const remaining = if (pop_left) values[i..n] else values[0 .. n - i];
                    try expectEnds(deque, remaining);
                    try expectItems(i32, deque, remaining);
                    deque = if (pop_left) try deque.popLeft(a) else try deque.popRight(a);
                }
                try expectEnds(deque, &.{});
            }
            try expectItems(i32, original, values[0..n]);
        }
    }
}

test "ImDeque: book figures 3.2 through 3.5 preserve order across cascading overflows" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Characters = ImDeque(u8);
    var deque = Characters.empty;
    deque = try deque.pushRight(a, 'U');
    deque = try deque.pushRight(a, 'V');
    for ("TSR") |item| deque = try deque.pushLeft(a, item);
    for ("WXY") |item| deque = try deque.pushRight(a, item);
    const eight = deque;
    try expectItems(u8, eight, "RSTUVWXY");
    deque = try deque.pushLeft(a, 'Q');
    try expectItems(u8, deque, "QRSTUVWXY");
    deque = try deque.pushRight(a, 'Z');
    try expectItems(u8, deque, "QRSTUVWXYZ");
    for ("PONMLKJIHGF") |item| deque = try deque.pushLeft(a, item);
    const twenty_one = deque;
    try expectItems(u8, twenty_one, "FGHIJKLMNOPQRSTUVWXYZ");
    deque = try deque.pushLeft(a, 'E');
    try expectItems(u8, deque, "EFGHIJKLMNOPQRSTUVWXYZ");
    try expectItems(u8, eight, "RSTUVWXY");
    try expectItems(u8, twenty_one, "FGHIJKLMNOPQRSTUVWXYZ");
}

test "ImDeque: alternating pushes and pops preserve the original full edge" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var values: [256]i32 = undefined;
    for (&values, 0..) |*value, i| value.* = @intCast(i);
    var deque = try dequeOf(a, &values);
    const original = deque;
    for (0..128) |_| {
        deque = try (try deque.pushLeft(a, -1)).popLeft(a);
        deque = try (try deque.pushRight(a, 256)).popRight(a);
        try expectItems(i32, deque, &values);
    }
    try expectItems(i32, original, &values);
}

test "ImDeque: deterministic mixed operations agree with an array model" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var model: std.ArrayList(i32) = .empty;
    var deque = Deque.empty;
    var state: u32 = 0x12345678;
    for (0..2000) |step| {
        const old = deque;
        const old_items = try a.dupe(i32, model.items);
        state = state *% 1664525 +% 1013904223;
        var operation = (state >> 16) % 4;
        if (model.items.len == 0) operation %= 2;
        if (model.items.len >= 128) operation = 2 + operation % 2;
        const value: i32 = @intCast(step);
        switch (operation) {
            0 => {
                deque = try deque.pushLeft(a, value);
                try model.insert(a, 0, value);
            },
            1 => {
                deque = try deque.pushRight(a, value);
                try model.append(a, value);
            },
            2 => {
                deque = try deque.popLeft(a);
                _ = model.orderedRemove(0);
            },
            3 => {
                deque = try deque.popRight(a);
                _ = model.pop();
            },
            else => unreachable,
        }
        try expectEnds(deque, model.items);
        if (step % 17 == 0) {
            try expectItems(i32, deque, model.items);
            try expectItems(i32, old, old_items);
        }
    }
    try expectItems(i32, deque, model.items);
}

test "ImDeque: independent branches and iterators coexist" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const original = try dequeOf(a, &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9 });
    const left_branch = try (try original.popRight(a)).pushLeft(a, 0);
    const right_branch = try (try original.popLeft(a)).pushRight(a, 10);
    try expectItems(i32, left_branch, &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8 });
    try expectItems(i32, right_branch, &.{ 2, 3, 4, 5, 6, 7, 8, 9, 10 });
    var first = try original.iterator(a);
    var second = try original.iterator(a);
    try testing.expectEqual(@as(?i32, 1), first.next());
    try testing.expectEqual(@as(?i32, 2), first.next());
    try testing.expectEqual(@as(?i32, 1), second.next());
    try expectItems(i32, original, &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9 });
}

test "ImDeque: works with non-integer items" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Words = ImDeque([]const u8);
    const words = try (try (try Words.empty.pushRight(a, "finger")).pushLeft(a, "immutable")).pushRight(a, "tree");
    try testing.expectEqualStrings("immutable", try words.left());
    try testing.expectEqualStrings("tree", try words.right());
    try expectItems([]const u8, words, &.{ "immutable", "finger", "tree" });
}

test "ImDeque: iterator distinguishes optional null items from exhaustion" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Optional = ImDeque(?i32);
    var single_it = try Optional.single(null).iterator(testing.failing_allocator);
    const null_item = single_it.next() orelse return error.TestUnexpectedResult;
    try testing.expectEqual(@as(?i32, null), null_item);
    try testing.expectEqual(@as(??i32, null), single_it.next());
    const expected = [_]?i32{ null, 1, null, 3, 4, null, 6, 7, null, 9, 10, null };
    var deque = Optional.empty;
    for (expected) |item| deque = try deque.pushRight(a, item);
    try expectItems(?i32, deque, &expected);
}

test "ImDeque: iterator uses logarithmic scratch space and allocates nothing while advancing" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const n = 8192;
    var deque = Deque.empty;
    for (0..n) |i| deque = try deque.pushRight(a, @intCast(i));
    var counting: testing.FailingAllocator = .init(a, .{});
    var it = try deque.iterator(counting.allocator());
    try testing.expectEqual(1, counting.allocations);
    try testing.expect(counting.allocated_bytes <= 4096);
    for (0..n) |i| try testing.expectEqual(@as(?i32, @intCast(i)), it.next());
    try testing.expectEqual(@as(?i32, null), it.next());
    try testing.expectEqual(1, counting.allocations);

    var empty_it = try Deque.empty.iterator(testing.failing_allocator);
    var single_it = try Deque.single(7).iterator(testing.failing_allocator);
    try testing.expectEqual(@as(?i32, null), empty_it.next());
    try testing.expectEqual(@as(?i32, 7), single_it.next());
    try testing.expectEqual(@as(?i32, null), single_it.next());
}

// Allocation counts and bytes catch rebuilding the entire deque without fixing
// a particular node layout. These bounds are regression checks, not proofs.
fn expectLinearBudget(counting: testing.FailingAllocator, n: usize) !void {
    try testing.expect(counting.allocations <= 64 * n);
    try testing.expect(counting.allocated_bytes <= 2048 * n);
}

test "ImDeque: long push and pop sequences use linear total allocations" {
    const n = 4096;
    for ([_]bool{ false, true }) |push_left| {
        for ([_]bool{ false, true }) |pop_left| {
            var arena: std.heap.ArenaAllocator = .init(testing.allocator);
            defer arena.deinit();
            var counting: testing.FailingAllocator = .init(arena.allocator(), .{});
            const a = counting.allocator();
            var deque = Deque.empty;
            for (0..n) |i| {
                deque = if (push_left) try deque.pushLeft(a, @intCast(i)) else try deque.pushRight(a, @intCast(i));
                try expectLinearBudget(counting, i + 1);
            }
            for (0..n) |i| {
                const expected: i32 = @intCast(if (push_left == pop_left) n - 1 - i else i);
                try testing.expectEqual(expected, if (pop_left) try deque.left() else try deque.right());
                deque = if (pop_left) try deque.popLeft(a) else try deque.popRight(a);
                try expectLinearBudget(counting, n + i + 1);
            }
            try testing.expect(deque.isEmpty());
        }
    }
}

test "ImDeque: each update on a deep deque uses at most logarithmic allocation space" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const n = 16384;
    var deque = Deque.empty;
    var building: testing.FailingAllocator = .init(a, .{});
    for (0..n) |i| {
        deque = try deque.pushRight(building.allocator(), @intCast(i));
        try expectLinearBudget(building, i + 1);
    }
    var levels: usize = 1;
    var capacity: usize = 1;
    while (capacity < n) : (levels += 1) capacity *= 2;
    var changing: testing.FailingAllocator = .init(a, .{});
    const gpa = changing.allocator();
    for (0..256) |i| {
        const before_allocations = changing.allocations;
        const before_bytes = changing.allocated_bytes;
        deque = switch (i % 4) {
            0 => try deque.pushLeft(gpa, -1),
            1 => try deque.pushRight(gpa, n),
            2 => try deque.popLeft(gpa),
            3 => try deque.popRight(gpa),
            else => unreachable,
        };
        try testing.expect(changing.allocations - before_allocations <= 32 * levels);
        try testing.expect(changing.allocated_bytes - before_bytes <= 2048 * levels);
    }
    var it = try deque.iterator(a);
    for (0..n) |i| try testing.expectEqual(@as(?i32, @intCast(i)), it.next());
    try testing.expectEqual(@as(?i32, null), it.next());
}

const Operation = enum { push_left, push_right, pop_left, pop_right, iterator, concatenate };

fn attempt(deque: Deque, allocator: Allocator, operation: Operation) !void {
    switch (operation) {
        .push_left => _ = try deque.pushLeft(allocator, -1),
        .push_right => _ = try deque.pushRight(allocator, 99),
        .pop_left => _ = try deque.popLeft(allocator),
        .pop_right => _ = try deque.popRight(allocator),
        .iterator => _ = try deque.iterator(allocator),
        .concatenate => _ = try deque.concatenate(allocator, deque),
    }
}

fn expectFailureRecovery(deque: Deque, items: []const i32, operation: Operation) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    for (0..256) |fail_index| {
        var failing: testing.FailingAllocator = .init(arena.allocator(), .{ .fail_index = fail_index });
        const result = attempt(deque, failing.allocator(), operation);
        try expectItems(i32, deque, items);
        if (result) |_| return else |err| try testing.expectEqual(error.OutOfMemory, err);
    }
    return error.TestUnexpectedResult;
}

test "ImDeque: failed updates and iterator construction leave source versions usable" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var values: [64]i32 = undefined;
    for (&values, 0..) |*value, i| value.* = @intCast(i);
    for ([_]usize{ 1, 2, 4, 5, 8, 9, 21, 22, 64 }) |n| {
        const deque = try dequeOf(arena.allocator(), values[0..n]);
        for ([_]Operation{ .push_left, .push_right, .pop_left, .pop_right, .iterator }) |operation|
            try expectFailureRecovery(deque, values[0..n], operation);
    }
}

test "ImDeque concatenate: stretch goal handles empty, singleton and self-concatenation" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const deque = try dequeOf(a, &.{ 1, 2, 3 });
    const one = Deque.single(0);
    try testing.expect((try Deque.empty.concatenate(testing.failing_allocator, .empty)).isEmpty());
    try expectItems(i32, try deque.concatenate(testing.failing_allocator, .empty), &.{ 1, 2, 3 });
    try expectItems(i32, try Deque.empty.concatenate(testing.failing_allocator, deque), &.{ 1, 2, 3 });
    try expectItems(i32, try one.concatenate(a, deque), &.{ 0, 1, 2, 3 });
    try expectItems(i32, try deque.concatenate(a, one), &.{ 1, 2, 3, 0 });
    try expectItems(i32, try deque.concatenate(a, deque), &.{ 1, 2, 3, 1, 2, 3 });
    try expectItems(i32, deque, &.{ 1, 2, 3 });
}

test "ImDeque concatenate: stretch goal joins every small size and supports subsequent updates" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var values: [64]i32 = undefined;
    for (&values, 0..) |*value, i| value.* = @intCast(i);
    for (0..33) |left_size| {
        for (0..33) |right_size| {
            const n = left_size + right_size;
            const left = try dequeOf(a, values[0..left_size]);
            const right = try dequeOf(a, values[left_size..n]);
            const joined = try left.concatenate(a, right);
            try expectItems(i32, joined, values[0..n]);
            var deque = try (try joined.pushLeft(a, -1)).pushRight(a, 64);
            deque = try (try deque.popLeft(a)).popRight(a);
            for (0..n) |i| {
                try testing.expectEqual(values[i], try deque.left());
                deque = try deque.popLeft(a);
            }
            try testing.expect(deque.isEmpty());
            try expectItems(i32, left, values[0..left_size]);
            try expectItems(i32, right, values[left_size..n]);
        }
    }
}

test "ImDeque concatenate: stretch goal recursively joins deep deques without copying all items" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const n = 8192;
    var building: testing.FailingAllocator = .init(a, .{});
    var left = Deque.empty;
    var right = Deque.empty;
    for (0..n) |i| {
        left = try left.pushRight(building.allocator(), @intCast(i));
        right = try right.pushLeft(building.allocator(), @intCast(2 * n - 1 - i));
        try expectLinearBudget(building, 2 * (i + 1));
    }
    var counting: testing.FailingAllocator = .init(a, .{});
    const joined = try left.concatenate(counting.allocator(), right);
    try testing.expect(counting.allocations <= 512);
    try testing.expect(counting.allocated_bytes <= 24 * 1024);
    var it = try joined.iterator(a);
    for (0..2 * n) |i| try testing.expectEqual(@as(?i32, @intCast(i)), it.next());
    try testing.expectEqual(@as(?i32, null), it.next());
    try testing.expectEqual(0, try left.left());
    try testing.expectEqual(n - 1, try left.right());
    try testing.expectEqual(n, try right.left());
    try testing.expectEqual(2 * n - 1, try right.right());
}

test "ImDeque concatenate: stretch goal recovers from allocation failure" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const items = [_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 };
    const deque = try dequeOf(arena.allocator(), &items);
    try expectFailureRecovery(deque, &items, .concatenate);
}

test "ImDeque concatenate: repeated joins preserve mixed chunk heights through iteration and pops" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var values: [4096]i32 = undefined;
    for (&values, 0..) |*value, i| value.* = @intCast(i);
    var chunks: [32]Deque = undefined;
    var len: usize = 0;
    for (&chunks, 0..) |*chunk, i| {
        const size = 1 + i * 37 % 127;
        chunk.* = try dequeOf(a, values[len .. len + size]);
        len += size;
    }
    var joined = chunks;
    var count = joined.len;
    while (count > 1) {
        for (0..count / 2) |i| joined[i] = try joined[2 * i].concatenate(a, joined[2 * i + 1]);
        count /= 2;
    }
    try expectItems(i32, joined[0], values[0..len]);
    try expectPoppedItems(i32, joined[0], values[0..len]);

    var accumulated = Deque.empty;
    for (chunks) |chunk| accumulated = try accumulated.concatenate(a, chunk);
    try expectItems(i32, accumulated, values[0..len]);
    try expectPoppedItems(i32, accumulated, values[0..len]);
    try expectItems(i32, chunks[0], values[0..1]);
    try expectItems(i32, chunks[1], values[1..39]);
    try expectItems(i32, joined[0], values[0..len]);
}

test "ImDeque concatenate: allocation failure during deep recursive joins preserves the input" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var values: [1024]i32 = undefined;
    for (&values, 0..) |*value, i| value.* = @intCast(i);
    const deque = try dequeOf(arena.allocator(), &values);
    try expectFailureRecovery(deque, &values, .concatenate);
}
