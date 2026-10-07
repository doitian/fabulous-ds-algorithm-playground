pub const ch02 = struct {
    pub const ImStack = @import("ch02/im_stack.zig").ImStack;
    pub const ImQueue = @import("ch02/im_queue.zig").ImQueue;
};

test {
    _ = @import("ch02/im_stack_test.zig");
    _ = @import("ch02/im_queue_test.zig");
}
