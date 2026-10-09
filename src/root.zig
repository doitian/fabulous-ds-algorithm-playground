pub const ch02 = struct {
    pub const ImStack = @import("ch02/im_stack.zig").ImStack;
    pub const ImQueue = @import("ch02/im_queue.zig").ImQueue;
    pub const HList = @import("ch02/hughes_list.zig").HList;
};

test {
    _ = @import("ch02/im_stack_test.zig");
    _ = @import("ch02/im_queue_test.zig");
    _ = @import("ch02/hughes_list_test.zig");
}
