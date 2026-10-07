pub const ch02 = struct {
    pub const ImStack = @import("ch02/im_stack.zig").ImStack;
};

test {
    _ = @import("ch02/im_stack_test.zig");
}
