//! 3.3.1 The mini-deque (listing 3.4)
//!
//! Implement an immutable buffer containing one to four items. There is no
//! empty mini: popping a One or pushing a Four returns an error.
//! Choose the representation; all operations must take O(1) time and no allocator.

pub const Error = error{ EmptyMini, FullMini };

pub fn MiniDeque(comptime T: type) type {
    return struct {
        const Self = @This();

        data: union(enum) {
            one: [1]T,
            two: [2]T,
            three: [3]T,
            four: [4]T,
        },

        pub fn one(item: T) Self {
            return .{ .data = .{ .one = .{item} } };
        }
        pub fn two(a: T, b: T) Self {
            return .{ .data = .{ .two = .{ a, b } } };
        }
        pub fn tree(a: T, b: T, c: T) Self {
            return .{ .data = .{ .three = .{ a, b, c } } };
        }
        pub fn four(a: T, b: T, c: T, d: T) Self {
            return .{ .data = .{ .four = .{ a, b, c, d } } };
        }

        pub fn size(self: Self) usize {
            return switch (self.data) {
                inline else => |items| items.len,
            };
        }

        pub fn left(self: Self) T {
            return switch (self.data) {
                inline else => |items| items[0],
            };
        }

        pub fn right(self: Self) T {
            return switch (self.data) {
                inline else => |items| items[items.len - 1],
            };
        }

        pub fn pushLeft(self: Self, item: T) Error!Self {
            return switch (self.data) {
                .one => |items| .{ .data = .{ .two = .{ item, items[0] } } },
                .two => |items| .{ .data = .{ .three = .{ item, items[0], items[1] } } },
                .three => |items| .{ .data = .{ .four = .{ item, items[0], items[1], items[2] } } },
                .four => error.FullMini,
            };
        }

        pub fn pushRight(self: Self, item: T) Error!Self {
            return switch (self.data) {
                .one => |items| .{ .data = .{ .two = .{ items[0], item } } },
                .two => |items| .{ .data = .{ .three = .{ items[0], items[1], item } } },
                .three => |items| .{ .data = .{ .four = .{ items[0], items[1], items[2], item } } },
                .four => error.FullMini,
            };
        }

        pub fn popLeft(self: Self) Error!Self {
            return switch (self.data) {
                .one => error.EmptyMini,
                .two => |items| .{ .data = .{ .one = .{items[1]} } },
                .three => |items| .{ .data = .{ .two = .{ items[1], items[2] } } },
                .four => |items| .{ .data = .{ .three = .{ items[1], items[2], items[3] } } },
            };
        }

        pub fn popRight(self: Self) Error!Self {
            return switch (self.data) {
                .one => error.EmptyMini,
                .two => |items| .{ .data = .{ .one = .{items[0]} } },
                .three => |items| .{ .data = .{ .two = .{ items[0], items[1] } } },
                .four => |items| .{ .data = .{ .three = .{ items[0], items[1], items[2] } } },
            };
        }
    };
}
