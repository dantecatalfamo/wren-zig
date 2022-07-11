const std = @import("std");
const path = std.fs.path;

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("wren-zig", "src/main.zig");
    addWren(exe);
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    addWren(exe_tests);
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}

pub fn addWren(exe: *std.build.LibExeObjStep) void {
    var allocator = exe.builder.allocator;
    const src_path = path.dirname(@src().file) orelse ".";
    const include_path = path.join(allocator, &.{ src_path, "wren", "src", "include" }) catch unreachable;
    const vm_path = path.join(allocator, &.{ src_path, "wren", "src", "vm" }) catch unreachable;
    const optional_path = path.join(allocator, &.{ src_path, "wren", "src", "optional" }) catch unreachable;
    const package_path = path.join(allocator, &.{ src_path, "src", "wren.zig" }) catch unreachable;

    exe.addIncludePath(include_path);
    exe.addIncludePath(vm_path);
    exe.addIncludePath(optional_path);
    exe.linkSystemLibrary("m");
    exe.addPackagePath("wren", package_path);

    for (vm_c_files) |vm_c_file| {
        const c_path = path.join(allocator, &.{ vm_path, vm_c_file }) catch unreachable;
        exe.addCSourceFile(c_path, &.{});
    }

    for (optional_c_files) |opt_c_file| {
        const c_path = path.join(allocator, &.{ optional_path, opt_c_file }) catch unreachable;
        exe.addCSourceFile(c_path, &.{});
    }
}

const optional_c_files = [_][]const u8 {
    "wren_opt_meta.c",
    "wren_opt_random.c",
};

const vm_c_files = [_][]const u8 {
    "wren_compiler.c",
    "wren_core.c",
    "wren_debug.c",
    "wren_primitive.c",
    "wren_utils.c",
    "wren_value.c",
    "wren_vm.c",
};
