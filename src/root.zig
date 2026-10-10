pub const ch02 = struct {
    pub const ImStack = @import("ch02/im_stack.zig").ImStack;
    pub const ImQueue = @import("ch02/im_queue.zig").ImQueue;
    pub const HList = @import("ch02/hughes_list.zig").HList;
};

pub const ch03 = struct {
    pub const MiniDeque = @import("ch03/mini_deque.zig").MiniDeque;
    pub const ImDeque = @import("ch03/im_deque.zig").ImDeque;
};

test {
    _ = @import("ch02/im_stack_test.zig");
    _ = @import("ch02/im_queue_test.zig");
    _ = @import("ch02/hughes_list_test.zig");
    _ = @import("ch03/mini_deque_test.zig");
    _ = @import("ch03/im_deque_test.zig");
}
