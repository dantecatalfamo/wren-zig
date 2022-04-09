# wren-zig
[Wren](https://wren.io/embedding/) bindings for [zig](https://ziglang.org/)!

Wren is a fast lua-sized scripting language with classes and concurrency.

Details on how embedding wren works [here](https://wren.io/embedding/).

## Bindings

In `src/wren.zig`

Contains both bare bindings and a zig wrapper

```zig
wrenGetSlotDouble(vm, 0);

vm.getSlotDouble(0);
```

## Building

Just run `zig build`, automatically pulls in git submodule if not already done

## Embedding

Add the following to your `build.zig`, with the paths changed to match the correct location

```zig
exe.addIncludePath("wren/src/include");
exe.addIncludePath("wren/src/vm");
exe.addIncludePath("wren/src/optional");
exe.addCSourceFiles(&c_files, &.{});
exe.linkSystemLibrary("m");

const c_files = [_][]const u8 {
    "wren/src/optional/wren_opt_meta.c",
    "wren/src/optional/wren_opt_random.c",
    "wren/src/vm/wren_compiler.c",
    "wren/src/vm/wren_core.c",
    "wren/src/vm/wren_debug.c",
    "wren/src/vm/wren_primitive.c",
    "wren/src/vm/wren_utils.c",
    "wren/src/vm/wren_value.c",
    "wren/src/vm/wren_vm.c",
};
```

## Example

A very basic example

```zig
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
}

pub export fn writeFn(vm: *wren.WrenVM, text: [*:0]const u8) void {
    _ = vm;
    const stdout = std.io.getStdOut().writer();
    stdout.print("{s}", .{ text }) catch unreachable;
}

pub export fn errorFn(vm: *wren.WrenVM, error_type: wren.WrenErrorType, module: [*:0]const u8, line: c_int, msg: [*:0]const u8) void {
    _ = vm;
    const stderr = std.io.getStdErr().writer();
    switch (error_type) {
        .WREN_ERROR_COMPILE => stderr.print("[{s} line {d}] [Error] {s}\n", .{ module, line, msg }) catch unreachable,
        .WREN_ERROR_STACK_TRACE => stderr.print("[{s} line {d}] in {s}\n", .{ module, line, msg }) catch unreachable,
        .WREN_ERROR_RUNTIME => stderr.print("[Runtime Error] {s}\n", .{ msg }) catch unreachable,
    }
}
```

See `src/main.zig` for more advanced use cases
