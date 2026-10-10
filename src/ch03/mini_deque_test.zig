const std = @import("std");
const testing = std.testing;
const MiniDeque = @import("mini_deque.zig").MiniDeque;
const Mini = MiniDeque(i32);

fn expectItems(mini: Mini, expected: []const i32) !void {
    try testing.expectEqual(expected.len, mini.size());
    var from_left = mini;
    var from_right = mini;
    for (expected, 0..) |item, i| {
        try testing.expectEqual(item, from_left.left());
        try testing.expectEqual(expected[expected.len - 1 - i], from_right.right());
        if (i + 1 < expected.len) {
            from_left = try from_left.popLeft();
            from_right = try from_right.popRight();
        }
    }
}

test "MiniDeque: One has the same item at both ends and cannot be popped" {
    const one = Mini.one(7);
    try expectItems(one, &.{7});
    try testing.expectError(error.EmptyMini, one.popLeft());
    try testing.expectError(error.EmptyMini, one.popRight());
    try expectItems(one, &.{7});
}

test "MiniDeque: direct constructors preserve sizes and item order" {
    try expectItems(Mini.one(1), &.{1});
    try expectItems(Mini.two(1, 2), &.{ 1, 2 });
    try expectItems(Mini.tree(1, 2, 3), &.{ 1, 2, 3 });
    try expectItems(Mini.four(1, 2, 3, 4), &.{ 1, 2, 3, 4 });
}

test "MiniDeque: pushes at either end build sizes Two through Four" {
    var left = Mini.one(4);
    var right = Mini.one(1);
    for (2..5) |n| {
        left = try left.pushLeft(@intCast(5 - n));
        right = try right.pushRight(@intCast(n));
        const values = [_]i32{ 1, 2, 3, 4 };
        try expectItems(left, values[4 - n ..]);
        try expectItems(right, values[0..n]);
    }
    try testing.expectError(error.FullMini, left.pushLeft(0));
    try testing.expectError(error.FullMini, left.pushRight(5));
    try expectItems(left, &.{ 1, 2, 3, 4 });
}

test "MiniDeque: every push direction and pop direction preserves order" {
    for (0..8) |mask| {
        var mini = Mini.one(0);
        var expected: std.ArrayList(i32) = .empty;
        defer expected.deinit(testing.allocator);
        try expected.append(testing.allocator, 0);
        for (1..4) |i| {
            const value: i32 = @intCast(i);
            if (mask & (@as(usize, 1) << @intCast(i - 1)) == 0) {
                mini = try mini.pushLeft(value);
                try expected.insert(testing.allocator, 0, value);
            } else {
                mini = try mini.pushRight(value);
                try expected.append(testing.allocator, value);
            }
            try expectItems(mini, expected.items);
        }
        const before = mini;
        try expectItems(try mini.popLeft(), expected.items[1..]);
        try expectItems(try mini.popRight(), expected.items[0..3]);
        try expectItems(before, expected.items);
    }
}

test "MiniDeque: works with non-integer items" {
    const Words = MiniDeque([]const u8);
    const words = try (try Words.one("finger").pushLeft("immutable")).pushRight("tree");
    try testing.expectEqualStrings("immutable", words.left());
    try testing.expectEqualStrings("tree", words.right());
    try testing.expectEqualStrings("finger", (try words.popLeft()).left());
}
