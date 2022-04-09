const std = @import("std");
const wren = @import("wren.zig");

pub fn main() anyerror!void {
    var config: wren.WrenConfiguration = undefined;
    wren.wrenInitConfiguration(&config);
    config.write_fn = writeFn;
    config.error_fn = errorFn;
    var vm = wren.wrenNewVM(&config);
    defer vm.free();

    _ = vm.interpret("main", "System.print(\"Hello, world!\")");

    const print_handle = vm.makeCallHandle("print(_)");
    vm.ensureSlots(2);
    vm.getVariable("main", "System", 0);
    vm.setSlotString(1, "Hello from zig!");
    const result = vm.call(print_handle);
    std.debug.print("Result: {}\n", .{ result });
}

pub fn writeFn(vm: *wren.WrenVM, text: [*:0]const u8) callconv(.C) void {
    _ = vm;
    const stdout = std.io.getStdOut().writer();
    stdout.print("{s}", .{ text }) catch unreachable;
}

pub fn errorFn(vm: *wren.WrenVM, error_type: wren.WrenErrorType, module: [*:0]const u8, line: c_int, msg: [*:0]const u8) callconv(.C) void {
    _ = vm;
    const stderr = std.io.getStdErr().writer();
    switch (error_type) {
        .WREN_ERROR_COMPILE => stderr.print("[{s} line {d}] [Error] {s}\n", .{ module, line, msg }) catch unreachable,
        .WREN_ERROR_STACK_TRACE => stderr.print("[{s} line {d}] in {s}\n", .{ module, line, msg }) catch unreachable,
        .WREN_ERROR_RUNTIME => stderr.print("[Runtime Error] {s}\n", .{ msg }) catch unreachable,
    }
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}

test "ref all" {
    std.testing.refAllDecls(wren);
    std.testing.refAllDecls(wren.WrenVM);
}
