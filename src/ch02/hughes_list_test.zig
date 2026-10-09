const std = @import("std");
const testing = std.testing;
const HList = @import("hughes_list.zig").HList;
const ImStack = @import("im_stack.zig").ImStack;

const List = HList(i32);
const Stack = ImStack(i32);

/// Collects at most `expected.len + 1` items so a non-terminating iterator fails instead of hanging.
fn expectItems(comptime T: type, list: HList(T), expected: []const T) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var actual: std.ArrayList(T) = .empty;
    var it = try list.iterator(a);
    while (actual.items.len <= expected.len) {
        const item = it.next() orelse break;
        try actual.append(a, item);
    }
    try testing.expectEqualSlices(T, expected, actual.items);
}

/// A stack whose top-to-bottom order is `items`.
fn stackOf(allocator: std.mem.Allocator, items: []const i32) !Stack {
    var s = Stack.empty;
    var i = items.len;
    while (i > 0) {
        i -= 1;
        s = try s.push(allocator, items[i]);
    }
    return s;
}

/// Passes allocations through to `child` until `remaining` bytes have been
/// handed out, then reports OutOfMemory. Freed bytes are not given back.
const BudgetAllocator = struct {
    child: std.mem.Allocator,
    remaining: usize,

    fn allocator(self: *BudgetAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free },
        };
    }

    fn take(self: *BudgetAllocator, bytes: usize) bool {
        if (bytes > self.remaining) return false;
        self.remaining -= bytes;
        return true;
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *BudgetAllocator = @ptrCast(@alignCast(ctx));
        if (!self.take(len)) return null;
        return self.child.rawAlloc(len, alignment, ret_addr);
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *BudgetAllocator = @ptrCast(@alignCast(ctx));
        if (new_len > memory.len and !self.take(new_len - memory.len)) return false;
        return self.child.rawResize(memory, alignment, new_len, ret_addr);
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *BudgetAllocator = @ptrCast(@alignCast(ctx));
        if (new_len > memory.len and !self.take(new_len - memory.len)) return null;
        return self.child.rawRemap(memory, alignment, new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *BudgetAllocator = @ptrCast(@alignCast(ctx));
        self.child.rawFree(memory, alignment, ret_addr);
    }
};

test "HList: empty list is empty and has no items" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    try testing.expect(List.empty.isEmpty());
    try expectItems(i32, List.empty, &.{});
    try testing.expect((try List.empty.toStack(arena.allocator())).isEmpty());
}

test "HList: peek and pop on the empty list fail" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    try testing.expectError(error.EmptyList, List.empty.peek(arena.allocator()));
    try testing.expectError(error.EmptyList, List.empty.pop(arena.allocator()));
}

test "HList: single, push and append put items at the right ends" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const one = List.single(1);
    try expectItems(i32, one, &.{1});
    try expectItems(i32, try one.push(a, 0), &.{ 0, 1 });
    try expectItems(i32, try one.append(a, 2), &.{ 1, 2 });
    try expectItems(i32, try (try (try one.push(a, 0)).append(a, 2)).append(a, 3), &.{ 0, 1, 2, 3 });
    try expectItems(i32, try List.empty.push(a, 7), &.{7});
    try expectItems(i32, try List.empty.append(a, 7), &.{7});
}

test "HList: fromStack keeps the stack's order" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const s = try stackOf(a, &.{ 4, 3, 2 });
    try expectItems(i32, List.fromStack(s), &.{ 4, 3, 2 });
    try testing.expect(List.fromStack(.empty).isEmpty());
}

test "HList: fromStackReversed reverses the stack (section 2.7.7)" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const s = try stackOf(a, &.{ 4, 3, 2 });
    try expectItems(i32, List.fromStackReversed(s), &.{ 2, 3, 4 });
    try testing.expect(List.fromStackReversed(.empty).isEmpty());
}

test "HList: book example (section 2.7.5)" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const s = try stackOf(a, &.{ 4, 3, 2 });
    const hl432 = List.fromStack(s);
    const hl = try (try (try (try hl432.push(a, 5)).append(a, 1)).concatenate(a, hl432)).append(a, 0);
    try expectItems(i32, hl, &.{ 5, 4, 3, 2, 1, 4, 3, 2, 0 });
}

test "HList: concatenate joins lists, with the empty list on either side" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const left = List.fromStack(try stackOf(a, &.{ 1, 2 }));
    const right = List.fromStack(try stackOf(a, &.{ 3, 4 }));
    try expectItems(i32, try left.concatenate(a, right), &.{ 1, 2, 3, 4 });
    try expectItems(i32, try right.concatenate(a, left), &.{ 3, 4, 1, 2 });
    try expectItems(i32, try left.concatenate(a, left), &.{ 1, 2, 1, 2 });
    try expectItems(i32, try List.empty.concatenate(a, right), &.{ 3, 4 });
    try expectItems(i32, try left.concatenate(a, .empty), &.{ 1, 2 });
    try testing.expect((try List.empty.concatenate(a, .empty)).isEmpty());
}

test "HList: building leaves the original lists unchanged" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const hl = try List.single(1).append(a, 2);
    _ = try hl.push(a, 0);
    _ = try hl.append(a, 3);
    _ = try hl.concatenate(a, hl);
    _ = try hl.pop(a);
    try expectItems(i32, hl, &.{ 1, 2 });
}

test "HList: peek and pop read the front of the list" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const hl = try (try List.single(2).push(a, 1)).append(a, 3);
    try testing.expectEqual(1, try hl.peek(a));
    const rest = try hl.pop(a);
    try expectItems(i32, rest, &.{ 2, 3 });
    try testing.expectEqual(2, try rest.peek(a));

    const last = try (try rest.pop(a)).pop(a);
    try testing.expect(last.isEmpty());
    try testing.expectError(error.EmptyList, last.peek(a));
}

test "HList: isEmpty is right however the list was built" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    try testing.expect(!List.single(1).isEmpty());
    try testing.expect(!(try List.empty.push(a, 1)).isEmpty());
    try testing.expect(!(try List.empty.append(a, 1)).isEmpty());
    try testing.expect(!(try List.single(1).concatenate(a, .empty)).isEmpty());
    try testing.expect(!(try List.empty.concatenate(a, List.single(1))).isEmpty());
    try testing.expect((try List.single(1).pop(a)).isEmpty());
}

test "HList: push, append and concatenate cost O(1) regardless of list size" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const small = List.single(0);
    var big = small;
    for (1..1000) |i| big = try big.append(a, @intCast(i));

    var on_small: testing.FailingAllocator = .init(a, .{});
    _ = try small.push(on_small.allocator(), 1);
    _ = try small.append(on_small.allocator(), 1);
    _ = try small.concatenate(on_small.allocator(), small);

    var on_big: testing.FailingAllocator = .init(a, .{});
    _ = try big.push(on_big.allocator(), 1);
    _ = try big.append(on_big.allocator(), 1);
    _ = try big.concatenate(on_big.allocator(), big);

    try testing.expectEqual(on_small.allocations, on_big.allocations);
    try testing.expectEqual(on_small.allocated_bytes, on_big.allocated_bytes);
}

test "HList: toStack is O(n) for lists built by pushes and appends" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const n = 1000;
    var hl = List.empty;
    for (0..n) |i| {
        hl = if (i % 2 == 0) try hl.append(a, @intCast(i)) else try hl.push(a, @intCast(i));
    }

    var counting: testing.FailingAllocator = .init(a, .{});
    const s = try hl.toStack(counting.allocator());

    var count: usize = 0;
    var it = s.iterator();
    while (it.next()) |_| count += 1;
    try testing.expectEqual(n, count);

    // Linear means a few allocations per item, depending on how the walk keeps
    // its pending work. Concatenating the parts eagerly at every level would
    // need ~n²/4.
    try testing.expect(counting.allocations <= 4 * n);
}

test "HList: toStack reports OutOfMemory at any allocation and leaves the list usable" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const hl = try (try List.fromStack(try stackOf(a, &.{ 2, 3 })).push(a, 1)).append(a, 4);
    var fail_index: usize = 0;
    while (fail_index < 100) : (fail_index += 1) {
        var failing: testing.FailingAllocator = .init(a, .{ .fail_index = fail_index });
        const result = hl.toStack(failing.allocator());
        try expectItems(i32, hl, &.{ 1, 2, 3, 4 });
        if (result) |_| break else |err| try testing.expectEqual(error.OutOfMemory, err);
    } else return error.TestUnexpectedResult;
    try testing.expect(fail_index > 0);
}

test "HList: works with non-integer items" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const Words = HList([]const u8);
    const words = try (try Words.single("build").append(a, "cheap")).push(a, "pay later,");
    try testing.expectEqualStrings("pay later,", try words.peek(a));
    try testing.expectEqualStrings("build", try (try words.pop(a)).peek(a));
}

test "HList: stretch goal (section 2.7.6): toStack on a deep list doesn't overflow the call stack" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    // A linear implementation needs well under 256 MiB here. One that copies the
    // list on every append fails with OutOfMemory within a few thousand items
    // instead of exhausting the machine's memory.
    var budget: BudgetAllocator = .{ .child = arena.allocator(), .remaining = 256 << 20 };
    const a = budget.allocator();

    const n = 1_000_000;
    var hl = List.empty;
    for (0..n) |i| hl = try hl.append(a, @intCast(i));

    var expected: i32 = 0;
    var it = try hl.iterator(a);
    while (it.next()) |item| : (expected += 1) try testing.expectEqual(expected, item);
    try testing.expectEqual(n, expected);
}
