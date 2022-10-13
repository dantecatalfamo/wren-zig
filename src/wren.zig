// Copyright (c) 2022 Dante Catalfamo
// SPDX-License-Identifier: MIT

const std = @import("std");
const mem = std.mem;

/// A single virtual machine for executing Wren code.
///
/// Wren has no global state, so all state stored by a running interpreter lives
/// here.
pub const WrenVM = opaque{
    const Self = @This();

    /// Disposes of all resources is use by [vm], which was previously created by a
    /// call to [wrenNewVM].
    pub fn free(self: *Self) void {
        return wrenFreeVM(self);
    }

    /// Immediately run the garbage collector to free unused memory.
    pub fn collectGarbage(self: *Self) void {
        return wrenCollectGarbage(self);
    }

    /// Runs [source], a string of Wren source code in a new fiber in [vm] in the
    /// context of resolved [module].
    pub fn interpret(self: *Self, module: [*:0]const u8, source: [*:0]const u8) !void {
        const value = wrenInterpret(self, module, source);
        switch (value) {
            .WREN_RESULT_COMPILE_ERROR => return error.CompileError,
            .WREN_RESULT_RUNTIME_ERROR => return error.RuntimeError,
            else => {}
        }
    }

    /// Creates a handle that can be used to invoke a method with [signature] on
    /// using a receiver and arguments that are set up on the stack.
    ///
    /// This handle can be used repeatedly to directly invoke that method from C
    /// code using [wrenCall].
    ///
    /// When you are done with this handle, it must be released using
    /// [wrenReleaseHandle].
    pub fn makeCallHandle(self: *Self, signature: [*:0]const u8) *WrenHandle {
        return wrenMakeCallHandle(self, signature);
    }

    /// Calls [method], using the receiver and arguments previously set up on the
    /// stack.
    ///
    /// [method] must have been created by a call to [wrenMakeCallHandle]. The
    /// arguments to the method must be already on the stack. The receiver should be
    /// in slot 0 with the remaining arguments following it, in order. It is an
    /// error if the number of arguments provided does not match the method's
    /// signature.
    ///
    /// After this returns, you can access the return value from slot 0 on the stack.
    pub fn call(self: *Self, method: *WrenHandle) !void {
        const value = wrenCall(self, method);
        switch (value) {
            .WREN_RESULT_COMPILE_ERROR => return error.CompileError,
            .WREN_RESULT_RUNTIME_ERROR => return error.RuntimeError,
            else => {}
        }
    }

    /// Releases the reference stored in [handle]. After calling this, [handle] can
    /// no longer be used.
    pub fn releaseHandle(self: *Self, handle: *WrenHandle) void {
        return wrenReleaseHandle(self, handle);
    }

    // The following functions are intended to be called from foreign methods or
    // finalizers. The interface Wren provides to a foreign method is like a
    // register machine: you are given a numbered array of slots that values can be
    // read from and written to. Values always live in a slot (unless explicitly
    // captured using wrenGetSlotHandle(), which ensures the garbage collector can
    // find them.
    //
    // When your foreign function is called, you are given one slot for the receiver
    // and each argument to the method. The receiver is in slot 0 and the arguments
    // are in increasingly numbered slots after that. You are free to read and
    // write to those slots as you want. If you want more slots to use as scratch
    // space, you can call wrenEnsureSlots() to add more.
    //
    // When your function returns, every slot except slot zero is discarded and the
    // value in slot zero is used as the return value of the method. If you don't
    // store a return value in that slot yourself, it will retain its previous
    // value, the receiver.
    //
    // While Wren is dynamically typed, C is not. This means the C interface has to
    // support the various types of primitive values a Wren variable can hold: bool,
    // double, string, etc. If we supported this for every operation in the C API,
    // there would be a combinatorial explosion of functions, like "get a
    // double-valued element from a list", "insert a string key and double value
    // into a map", etc.
    //
    // To avoid that, the only way to convert to and from a raw C value is by going
    // into and out of a slot. All other functions work with values already in a
    // slot. So, to add an element to a list, you put the list in one slot, and the
    // element in another. Then there is a single API function wrenInsertInList()
    // that takes the element out of that slot and puts it into the list.
    //
    // The goal of this API is to be easy to use while not compromising performance.
    // The latter means it does not do type or bounds checking at runtime except
    // using assertions which are generally removed from release builds. C is an
    // unsafe language, so it's up to you to be careful to use it correctly. In
    // return, you get a very fast FFI.

    /// Returns the number of slots available to the current foreign method.
    pub fn getSlotCount(self: *Self) c_int {
        return wrenGetSlotCount(self);
    }

    /// Ensures that the foreign method stack has at least [numSlots] available for
    /// use, growing the stack if needed.
    ///
    /// Does not shrink the stack if it has more than enough slots.
    ///
    /// It is an error to call this from a finalizer.
    pub fn ensureSlots(self: *Self, num_slots: c_int) void {
        return wrenEnsureSlots(self, num_slots);
    }

    /// Gets the type of the object in [slot].
    pub fn getSlotType(self: *Self, slot: c_int) WrenType {
        return wrenGetSlotType(self, slot);
    }

    /// Reads a boolean value from [slot].
    ///
    /// It is an error to call this if the slot does not contain a boolean value.
    pub fn getSlotBool(self: *Self, slot: c_int) bool {
        return wrenGetSlotBool(self, slot);
    }

    /// Reads a byte array from [slot].
    ///
    /// The memory for the returned string is owned by Wren. You can inspect it
    /// while in your foreign method, but cannot keep a pointer to it after the
    /// function returns, since the garbage collector may reclaim it.
    ///
    /// Returns a pointer to the first byte of the array and fill [length] with the
    /// number of bytes in the array.
    ///
    /// It is an error to call this if the slot does not contain a string.
    pub fn getSlotBytes(self: *Self, slot: c_int) []const u8 {
        var len: c_int = 0;
        const ptr = wrenGetSlotBytes(self, slot, &len);
        const ptr_len = @intCast(usize, len);
        return ptr[0..ptr_len];
    }

    /// Reads a number from [slot].
    ///
    /// It is an error to call this if the slot does not contain a number.
    pub fn getSlotDouble(self: *Self, slot: c_int) f64 {
        return wrenGetSlotDouble(self, slot);
    }

    /// Reads a foreign object from [slot] and returns a pointer to the foreign data
    /// stored with it.
    ///
    /// It is an error to call this if the slot does not contain an instance of a
    /// foreign class.
    pub fn getSlotForeign(self: *Self, slot: c_int) void {
        return wrenGetSlotForeign(self, slot);
    }

    /// Reads a string from [slot].
    ///
    /// The memory for the returned string is owned by Wren. You can inspect it
    /// while in your foreign method, but cannot keep a pointer to it after the
    /// function returns, since the garbage collector may reclaim it.
    ///
    /// It is an error to call this if the slot does not contain a string.
    pub fn getSlotString(self: *Self, slot: c_int) [*:0]const u8 {
        return wrenGetSlotString(self, slot);
    }

    /// Creates a handle for the value stored in [slot].
    ///
    /// This will prevent the object that is referred to from being garbage collected
    /// until the handle is released by calling [wrenReleaseHandle()].
    pub fn getSlotHandle(self: *Self, slot: c_int) *WrenHandle {
        return wrenGetSlotHandle(self, slot);
    }

    /// Stores the boolean [value] in [slot].
    pub fn setSlotBool(self: *Self, slot: c_int, value: bool) void {
        return wrenSetSlotBool(self, slot, value);
    }

    /// Stores the array [length] of [bytes] in [slot].
    ///
    /// The bytes are copied to a new string within Wren's heap, so you can free
    /// memory used by them after this is called.
    pub fn setSlotBytes(self: *Self, slot: c_int, bytes: []const u8) void {
        return wrenSetSlotBytes(self, slot, bytes.ptr, bytes.len);
    }

    /// Stores the numeric [value] in [slot].
    pub fn setSlotDouble(self: *Self, slot: c_int, value: f64) void {
        return wrenSetSlotDouble(self, slot, value);
    }

    /// Creates a new instance of the foreign class stored in [classSlot] with [size]
    /// bytes of raw storage and places the resulting object in [slot].
    ///
    /// This does not invoke the foreign class's constructor on the new instance. If
    /// you need that to happen, call the constructor from Wren, which will then
    /// call the allocator foreign method. In there, call this to create the object
    /// and then the constructor will be invoked when the allocator returns.
    ///
    /// Returns a pointer to the foreign object's data.
    pub fn setSlotNewForeign(self: *Self, slot: c_int, class_slot: c_int, size: usize) ?*anyopaque {
        return wrenSetSlotNewForeign(self, slot, class_slot, size);
    }

    /// Stores a new empty list in [slot].
    pub fn setSlotNewList(self: *Self, slot: c_int) void {
        return wrenSetSlotNewList(self, slot);
    }

    /// Stores a new empty map in [slot].
    pub fn setSlotNewMap(self: *Self, slot: c_int) void {
        return wrenSetSlotNewMap(self, slot);
    }

    /// Stores null in [slot].
    pub fn setSlotNull(self: *Self, slot: c_int) void {
        return wrenSetSlotNull(self, slot);
    }

    /// Stores the string [text] in [slot].
    ///
    /// The [text] is copied to a new string within Wren's heap, so you can free
    /// memory used by it after this is called. The length is calculated using
    /// [strlen()]. If the string may contain any null bytes in the middle, then you
    /// should use [wrenSetSlotBytes()] instead.
    pub fn setSlotString(self: *Self, slot: c_int, text: [*:0]const u8) void {
        return wrenSetSlotString(self, slot, text);
    }

    /// Stores the value captured in [handle] in [slot].
    ///
    /// This does not release the handle for the value.
    pub fn setSlotHandle(self: *Self, slot: c_int, handle: *WrenHandle) void {
        return wrenSetSlotHandle(self, slot, handle);
    }

    /// Returns the number of elements in the list stored in [slot].
    pub fn getListCount(self: *Self, slot: c_int) c_int {
        return wrenGetListCount(self, slot);
    }

    /// Reads element [index] from the list in [listSlot] and stores it in
    /// [elementSlot].
    pub fn getListElement(self: *Self, list_slot: c_int, index: c_int, element_slot: c_int) void {
        return wrenGetListElement(self, list_slot, index, element_slot);
    }

    /// Sets the value stored at [index] in the list at [listSlot],
    /// to the value from [elementSlot].
    pub fn setListElement(self: *Self, list_slot: c_int, index: c_int, element_slot: c_int) void {
        return wrenSetListElement(self, list_slot, index, element_slot);
    }

    /// Takes the value stored at [elementSlot] and inserts it into the list stored
    /// at [listSlot] at [index].
    ///
    /// As in Wren, negative indexes can be used to insert from the end. To append
    /// an element, use `-1` for the index.
    pub fn insertInList(self: *Self, list_slot: c_int, index: c_int, element_slot: c_int) void {
        return wrenInsertInList(self, list_slot, index, element_slot);
    }

    /// Returns the number of entries in the map stored in [slot].
    pub fn getMapCount(self: *Self, slot: c_int) c_int {
        return wrenGetMapCount(self, slot);
    }

    /// Returns true if the key in [keySlot] is found in the map placed in [mapSlot].
    pub fn getMapContainsKey(self: *Self, map_slot: c_int, key_slot: c_int) bool {
        return wrenGetMapContainsKey(self, map_slot, key_slot);
    }

    /// Retrieves a value with the key in [keySlot] from the map in [mapSlot] and
    /// stores it in [valueSlot].
    pub fn getMapValue(self: *Self, map_slot: c_int, key_slot: c_int, value_slot: c_int) void {
        return wrenGetMapValue(self, map_slot, key_slot, value_slot);
    }

    /// Takes the value stored at [valueSlot] and inserts it into the map stored
    /// at [mapSlot] with key [keySlot].
    pub fn setMapValue(self: *Self, map_slot: c_int, key_slot: c_int, value_slot: c_int) void {
        return wrenSetMapValue(self, map_slot, key_slot, value_slot);
    }

    /// Removes a value from the map in [mapSlot], with the key from [keySlot],
    /// and place it in [removedValueSlot]. If not found, [removedValueSlot] is
    /// set to null, the same behaviour as the Wren Map API.
    pub fn removeMapValue(self: *Self, map_slot: c_int, key_slot: c_int, removed_value_slot: c_int) void {
        return wrenRemoveMapValue(self, map_slot, key_slot, removed_value_slot);
    }

    /// Looks up the top level variable with [name] in resolved [module] and stores
    /// it in [slot].
    pub fn getVariable(self: *Self, module: [*:0]const u8, name: [*:0]const u8, slot: c_int) void {
        return wrenGetVariable(self, module, name, slot);
    }

    /// Looks up the top level variable with [name] in resolved [module],
    /// returns false if not found. The module must be imported at the time,
    /// use wrenHasModule to ensure that before calling.
    pub fn hasVariable(self: *Self, module: [*:0]const u8, name: [*:0]const u8) bool {
        return wrenHasVariable(self, module, name);
    }

    /// Returns true if [module] has been imported/resolved before, false if not.
    pub fn hasModule(self: *Self, module: [*:0]const u8) bool {
        return wrenHasModule(self, module);
    }

    /// Sets the current fiber to be aborted, and uses the value in [slot] as the
    /// runtime error object.
    pub fn abortFiber(self: *Self, slot: c_int) void {
        return wrenAbortFiber(self, slot);
    }

    /// Returns the user data associated with the WrenVM.
    pub fn getUserData(self: *Self) ?*anyopaque {
        return wrenGetUserData(self);
    }

    /// Sets user data associated with the WrenVM.
    pub fn setUserData(self: *Self, user_data: ?*anyopaque) void {
        return wrenSetUserData(self, user_data);
    }
};

pub const WrenAllocator = struct {
    allocator: mem.Allocator,
    ptr_size_map: std.AutoHashMap(usize, usize),

    const Self = @This();

    pub fn init(allocator: mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .ptr_size_map = std.AutoHashMap(usize, usize).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.ptr_size_map.iterator();
        while (iter.next()) |entry| {
            const ptr = @intToPtr([*]u8, entry.key_ptr.*);
            const size = entry.value_ptr.*;
            const memory = ptr[0..size];
            self.allocator.free(memory);
        }
        self.ptr_size_map.deinit();
    }

    pub fn alloc(self: *Self, size: usize) ?*anyopaque {
        const new_memory = self.allocator.alloc(u8, size) catch return null;
        self.ptr_size_map.put(@ptrToInt(new_memory.ptr), new_memory.len) catch return null;
        return new_memory.ptr;
    }

    pub fn realloc(self: *Self, old_ptr: *anyopaque, new_size: usize) ?*anyopaque {
        const old_size = self.ptr_size_map.get(@ptrToInt(old_ptr)) orelse return null;
        const old_memory = @ptrCast([*]u8, old_ptr)[0..old_size];
        const new_memory = self.allocator.realloc(old_memory, new_size) catch return null;
        _ = self.ptr_size_map.remove(@ptrToInt(old_ptr));
        self.ptr_size_map.put(@ptrToInt(new_memory.ptr), new_memory.len) catch return null;
        return new_memory.ptr;
    }

    pub fn free(self: *Self, ptr: *anyopaque) void {
        const size = self.ptr_size_map.get(@ptrToInt(ptr)) orelse unreachable;
        const memory = @ptrCast([*]u8, ptr)[0..size];
        self.allocator.free(memory);
        _ = self.ptr_size_map.remove(@ptrToInt(ptr));
    }
};

pub export fn zigWrenAlloc(ptr: ?*anyopaque, size: usize, user_data: ?*anyopaque) ?*anyopaque {
    const zig_wren_alloc = @ptrCast(*WrenAllocator, @alignCast(@alignOf(WrenAllocator), user_data));
    if (ptr == null and size == 0) {
        return null;
    } else if (ptr == null) {
        return zig_wren_alloc.alloc(size);
    } else if (size == 0) {
        zig_wren_alloc.free(ptr.?);
        return null;
    } else {
        return zig_wren_alloc.realloc(ptr.?, size);
    }
}

// Return an initialized wren configuration
pub fn newConfig() WrenConfiguration {
    var config: WrenConfiguration = undefined;
    wrenInitConfiguration(&config);
    return config;
}

/// A handle to a Wren object.
///
/// This lets code outside of the VM hold a persistent reference to an object.
/// After a handle is acquired, and until it is released, this ensures the
/// garbage collector will not reclaim the object it references.
pub const WrenHandle = opaque{};

/// A generic allocation function that handles all explicit memory management
/// used by Wren. It's used like so:
///
/// - To allocate new memory, [memory] is NULL and [newSize] is the desired
///   size. It should return the allocated memory or NULL on failure.
///
/// - To attempt to grow an existing allocation, [memory] is the memory, and
///   [newSize] is the desired size. It should return [memory] if it was able to
///   grow it in place, or a new pointer if it had to move it.
///
/// - To shrink memory, [memory] and [newSize] are the same as above but it will
///   always return [memory].
///
/// - To free memory, [memory] will be the memory to free and [newSize] will be
///   zero. It should return NULL.
pub const WrenReallocateFn = *const fn (memory: ?*anyopaque, new_size: usize, user_data: ?*anyopaque) callconv(.C) ?*anyopaque;

/// A function callable from Wren code, but implemented in C.
pub const WrenForeignMethodFn = *const fn (vm: *WrenVM) callconv(.C) void;

/// A finalizer function for freeing resources owned by an instance of a foreign
/// class. Unlike most foreign methods, finalizers do not have access to the VM
/// and should not interact with it since it's in the middle of a garbage
/// collection.
pub const WrenFinalizerFn = fn (data: *anyopaque) callconv(.C) void;

/// Gives the host a chance to canonicalize the imported module name,
/// potentially taking into account the (previously resolved) name of the module
/// that contains the import. Typically, this is used to implement relative
/// imports.
pub const WrenResolveModuleFn = *const fn (vm: *WrenVM, importer: [*:0]const u8, name: [*:0]const u8) callconv(.C) [*:0]const u8;

/// Called after loadModuleFn is called for module [name]. The original returned result
/// is handed back to you in this callback, so that you can free
/// memory if appropriate.
pub const WrenLoadModuleCompleteFn = *const fn (vm: *WrenVM, name: [*:0]const u8, result: WrenLoadModuleResult) callconv(.C) void;

/// The result of a loadModuleFn call.
/// [source] is the source code for the module, or NULL if the module is not found.
/// [onComplete] an optional callback that will be called once Wren is
/// done with the result.
pub const WrenLoadModuleResult = extern struct {
    name: [*:0]const u8,
    on_complete: WrenLoadModuleCompleteFn,
    user_data: *anyopaque,
};

/// Loads and returns the source code for the module [name].
pub const WrenLoadModuleFn = *const fn (vm: *WrenVM, name: [*:0]const u8) callconv(.C) *WrenLoadModuleResult;

/// Returns a pointer to a foreign method on [className] in [module] with
/// [signature].
pub const WrenBindForeignMethodFn = *const fn (vm: *WrenVM, module: [*:0]const u8, class_name: [*:0]const u8, is_static: bool, signature: [*:0]const u8) callconv(.C) ?WrenForeignMethodFn;

/// Displays a string of text to the user.
pub const WrenWriteFn = *const fn (vm: *WrenVM, text: [*:0]const u8) callconv(.C) void;

pub const WrenErrorType = enum(c_int) {
    /// A syntax or resolution error detected at compile time.
    WREN_ERROR_COMPILE,

    /// The error message for a runtime error.
    WREN_ERROR_RUNTIME,

    /// One entry of a runtime error's stack trace.
    WREN_ERROR_STACK_TRACE
};

/// Reports an error to the user.
///
/// An error detected during compile time is reported by calling this once with
/// [type] `WREN_ERROR_COMPILE`, the resolved name of the [module] and [line]
/// where the error occurs, and the compiler's error [message].
///
/// A runtime error is reported by calling this once with [type]
/// `WREN_ERROR_RUNTIME`, no [module] or [line], and the runtime error's
/// [message]. After that, a series of [type] `WREN_ERROR_STACK_TRACE` calls are
/// made for each line in the stack trace. Each of those has the resolved
/// [module] and [line] where the method or function is defined and [message] is
/// the name of the method or function.
pub const WrenErrorFn = *const fn (vm: *WrenVM, err_type: WrenErrorType, module: [*:0]const u8, line: c_int, message: [*:0]const u8) callconv(.C) void;

pub const WrenForeignClassMethods = extern struct {
    /// The callback invoked when the foreign object is created.
    ///
    /// This must be provided. Inside the body of this, it must call
    /// [wrenSetSlotNewForeign()] exactly once.
    allocate: WrenForeignMethodFn,

    /// The callback invoked when the garbage collector is about to collect a
    /// foreign object's memory.
    ///
    /// This may be `NULL` if the foreign class does not need to finalize.
    finalize: WrenFinalizerFn,
};

/// Returns a pair of pointers to the foreign methods used to allocate and
/// finalize the data for instances of [className] in resolved [module].
pub const WrenBindForeignClassFn = *const fn (vm: *WrenVM, module: [*:0]const u8, class_name: [*:0]const u8) callconv(.C) *WrenForeignClassMethods;

pub const WrenConfiguration = extern struct {
    /// The callback Wren will use to allocate, reallocate, and deallocate memory.
    ///
    /// If `NULL`, defaults to a built-in function that uses `realloc` and `free`.
    reallocate_fn: WrenReallocateFn,

    /// The callback Wren uses to resolve a module name.
    ///
    /// Some host applications may wish to support "relative" imports, where the
    /// meaning of an import string depends on the module that contains it. To
    /// support that without baking any policy into Wren itself, the VM gives the
    /// host a chance to resolve an import string.
    ///
    /// Before an import is loaded, it calls this, passing in the name of the
    /// module that contains the import and the import string. The host app can
    /// look at both of those and produce a new "canonical" string that uniquely
    /// identifies the module. This string is then used as the name of the module
    /// going forward. It is what is passed to [loadModuleFn], how duplicate
    /// imports of the same module are detected, and how the module is reported in
    /// stack traces.
    ///
    /// If you leave this function NULL, then the original import string is
    /// treated as the resolved string.
    ///
    /// If an import cannot be resolved by the embedder, it should return NULL and
    /// Wren will report that as a runtime error.
    ///
    /// Wren will take ownership of the string you return and free it for you, so
    /// it should be allocated using the same allocation function you provide
    /// above.
    resolve_module_fn: WrenResolveModuleFn,

    /// The callback Wren uses to load a module.
    ///
    /// Since Wren does not talk directly to the file system, it relies on the
    /// embedder to physically locate and read the source code for a module. The
    /// first time an import appears, Wren will call this and pass in the name of
    /// the module being imported. The method will return a result, which contains
    /// the source code for that module. Memory for the source is owned by the
    /// host application, and can be freed using the onComplete callback.
    ///
    /// This will only be called once for any given module name. Wren caches the
    /// result internally so subsequent imports of the same module will use the
    /// previous source and not call this.
    ///
    /// If a module with the given name could not be found by the embedder, it
    /// should return NULL and Wren will report that as a runtime error.
    load_module_fn: WrenLoadModuleFn,

    /// The callback Wren uses to find a foreign method and bind it to a class.
    ///
    /// When a foreign method is declared in a class, this will be called with the
    /// foreign method's module, class, and signature when the class body is
    /// executed. It should return a pointer to the foreign function that will be
    /// bound to that method.
    ///
    /// If the foreign function could not be found, this should return NULL and
    /// Wren will report it as runtime error.
    bind_foreign_method_fn: WrenBindForeignMethodFn,

    /// The callback Wren uses to find a foreign class and get its foreign methods.
    ///
    /// When a foreign class is declared, this will be called with the class's
    /// module and name when the class body is executed. It should return the
    /// foreign functions uses to allocate and (optionally) finalize the bytes
    /// stored in the foreign object when an instance is created.
    bind_foreign_class_fn: WrenBindForeignClassFn,

    /// The callback Wren uses to display text when `System.print()` or the other
    /// related functions are called.
    ///
    /// If this is `NULL`, Wren discards any printed text.
    write_fn: WrenWriteFn,

    /// The callback Wren uses to report errors.
    ///
    /// When an error occurs, this will be called with the module name, line
    /// number, and an error message. If this is `NULL`, Wren doesn't report any
    /// errors.
    error_fn: WrenErrorFn,

    /// The number of bytes Wren will allocate before triggering the first garbage
    /// collection.
    ///
    /// If zero, defaults to 10MB.
    initial_heap_size: usize,

    /// After a collection occurs, the threshold for the next collection is
    /// determined based on the number of bytes remaining in use. This allows Wren
    /// to shrink its memory usage automatically after reclaiming a large amount
    /// of memory.
    ///
    /// This can be used to ensure that the heap does not get too small, which can
    /// in turn lead to a large number of collections afterwards as the heap grows
    /// back to a usable size.
    ///
    /// If zero, defaults to 1MB.
    min_heap_size: usize,

    /// Wren will resize the heap automatically as the number of bytes
    /// remaining in use after a collection changes. This number determines the
    /// amount of additional memory Wren will use after a collection, as a
    /// percentage of the current heap size.
    ///
    /// For example, say that this is 50. After a garbage collection, when there
    /// are 400 bytes of memory still in use, the next collection will be triggered
    /// after a total of 600 bytes are allocated (including the 400 already in
    /// use.)
    ///
    /// Setting this to a smaller number wastes less memory, but triggers more
    /// frequent garbage collections.
    ///
    /// If zero, defaults to 50.
    heap_growth_percent: c_int,

    /// User-defined data associated with the VM.
    user_data: ?*anyopaque
};

pub const WrenInterpretResult = enum(c_int) {
    WREN_RESULT_SUCCESS,
    WREN_RESULT_COMPILE_ERROR,
    WREN_RESULT_RUNTIME_ERROR
};

/// The type of an object stored in a slot.
///
/// This is not necessarily the object's *class*, but instead its low level
/// representation type.
pub const WrenType = enum(c_int) {
    WREN_TYPE_BOOL,
    WREN_TYPE_NUM,
    WREN_TYPE_FOREIGN,
    WREN_TYPE_LIST,
    WREN_TYPE_MAP,
    WREN_TYPE_NULL,
    WREN_TYPE_STRING,

    /// The object is of a type that isn't accessible by the C API.
    WREN_TYPE_UNKNOWN
};

/// Get the current wren version number.
///
/// Can be used to range checks over versions.
pub extern fn wrenGetVersionNumber() c_int;

/// Initializes [configuration] with all of its default values.
///
/// Call this before setting the particular fields you care about.
pub extern fn wrenInitConfiguration(configuration: *WrenConfiguration) void;

/// Creates a new Wren virtual machine using the given [configuration]. Wren
/// will copy the configuration data, so the argument passed to this can be
/// freed after calling this. If [configuration] is `NULL`, uses a default
/// configuration.
pub extern fn wrenNewVM(configuration: ?*WrenConfiguration) *WrenVM;

/// Disposes of all resources is use by [vm], which was previously created by a
/// call to [wrenNewVM].
pub extern fn wrenFreeVM(vm: *WrenVM) void;

/// Immediately run the garbage collector to free unused memory.
pub extern fn wrenCollectGarbage(vm: *WrenVM) void;

/// Runs [source], a string of Wren source code in a new fiber in [vm] in the
/// context of resolved [module].
pub extern fn wrenInterpret(vm: *WrenVM, module: [*:0]const u8, source: [*:0]const u8) WrenInterpretResult;

/// Creates a handle that can be used to invoke a method with [signature] on
/// using a receiver and arguments that are set up on the stack.
///
/// This handle can be used repeatedly to directly invoke that method from C
/// code using [wrenCall].
///
/// When you are done with this handle, it must be released using
/// [wrenReleaseHandle].
pub extern fn wrenMakeCallHandle(vm: *WrenVM, signature: [*:0]const u8) *WrenHandle;

/// Calls [method], using the receiver and arguments previously set up on the
/// stack.
///
/// [method] must have been created by a call to [wrenMakeCallHandle]. The
/// arguments to the method must be already on the stack. The receiver should be
/// in slot 0 with the remaining arguments following it, in order. It is an
/// error if the number of arguments provided does not match the method's
/// signature.
///
/// After this returns, you can access the return value from slot 0 on the stack.
pub extern fn wrenCall(vm: *WrenVM, method: *WrenHandle) WrenInterpretResult;

/// Releases the reference stored in [handle]. After calling this, [handle] can
/// no longer be used.
pub extern fn wrenReleaseHandle(vm: *WrenVM, handle: *WrenHandle) void;

// The following functions are intended to be called from foreign methods or
// finalizers. The interface Wren provides to a foreign method is like a
// register machine: you are given a numbered array of slots that values can be
// read from and written to. Values always live in a slot (unless explicitly
// captured using wrenGetSlotHandle(), which ensures the garbage collector can
// find them.
//
// When your foreign function is called, you are given one slot for the receiver
// and each argument to the method. The receiver is in slot 0 and the arguments
// are in increasingly numbered slots after that. You are free to read and
// write to those slots as you want. If you want more slots to use as scratch
// space, you can call wrenEnsureSlots() to add more.
//
// When your function returns, every slot except slot zero is discarded and the
// value in slot zero is used as the return value of the method. If you don't
// store a return value in that slot yourself, it will retain its previous
// value, the receiver.
//
// While Wren is dynamically typed, C is not. This means the C interface has to
// support the various types of primitive values a Wren variable can hold: bool,
// double, string, etc. If we supported this for every operation in the C API,
// there would be a combinatorial explosion of functions, like "get a
// double-valued element from a list", "insert a string key and double value
// into a map", etc.
//
// To avoid that, the only way to convert to and from a raw C value is by going
// into and out of a slot. All other functions work with values already in a
// slot. So, to add an element to a list, you put the list in one slot, and the
// element in another. Then there is a single API function wrenInsertInList()
// that takes the element out of that slot and puts it into the list.
//
// The goal of this API is to be easy to use while not compromising performance.
// The latter means it does not do type or bounds checking at runtime except
// using assertions which are generally removed from release builds. C is an
// unsafe language, so it's up to you to be careful to use it correctly. In
// return, you get a very fast FFI.

/// Returns the number of slots available to the current foreign method.
pub extern fn wrenGetSlotCount(vm: *WrenVM) c_int;

/// Ensures that the foreign method stack has at least [numSlots] available for
/// use, growing the stack if needed.
///
/// Does not shrink the stack if it has more than enough slots.
///
/// It is an error to call this from a finalizer.
pub extern fn wrenEnsureSlots(vm: *WrenVM, num_slots: c_int) void;

/// Gets the type of the object in [slot].
pub extern fn wrenGetSlotType(vm: *WrenVM, slot: c_int) WrenType;

/// Reads a boolean value from [slot].
///
/// It is an error to call this if the slot does not contain a boolean value.
pub extern fn wrenGetSlotBool(vm: *WrenVM, slot: c_int) bool;

/// Reads a byte array from [slot].
///
/// The memory for the returned string is owned by Wren. You can inspect it
/// while in your foreign method, but cannot keep a pointer to it after the
/// function returns, since the garbage collector may reclaim it.
///
/// Returns a pointer to the first byte of the array and fill [length] with the
/// number of bytes in the array.
///
/// It is an error to call this if the slot does not contain a string.
pub extern fn wrenGetSlotBytes(vm: *WrenVM, slot: c_int, length: *c_int) [*]const u8;

/// Reads a number from [slot].
///
/// It is an error to call this if the slot does not contain a number.
pub extern fn wrenGetSlotDouble(vm: *WrenVM, slot: c_int) f64;

/// Reads a foreign object from [slot] and returns a pointer to the foreign data
/// stored with it.
///
/// It is an error to call this if the slot does not contain an instance of a
/// foreign class.
pub extern fn wrenGetSlotForeign(vm: *WrenVM, slot: c_int) void;

/// Reads a string from [slot].
///
/// The memory for the returned string is owned by Wren. You can inspect it
/// while in your foreign method, but cannot keep a pointer to it after the
/// function returns, since the garbage collector may reclaim it.
///
/// It is an error to call this if the slot does not contain a string.
pub extern fn wrenGetSlotString(vm: *WrenVM, slot: c_int) [*:0]const u8;

/// Creates a handle for the value stored in [slot].
///
/// This will prevent the object that is referred to from being garbage collected
/// until the handle is released by calling [wrenReleaseHandle()].
pub extern fn wrenGetSlotHandle(vm: *WrenVM, slot: c_int) *WrenHandle;

/// Stores the boolean [value] in [slot].
pub extern fn wrenSetSlotBool(wm: *WrenVM, slot: c_int, value: bool) void;

/// Stores the array [length] of [bytes] in [slot].
///
/// The bytes are copied to a new string within Wren's heap, so you can free
/// memory used by them after this is called.
pub extern fn wrenSetSlotBytes(vm: *WrenVM, slot: c_int, bytes: [*]const u8, length: usize) void;

/// Stores the numeric [value] in [slot].
pub extern fn wrenSetSlotDouble(vm: *WrenVM, slot: c_int, value: f64) void;

/// Creates a new instance of the foreign class stored in [classSlot] with [size]
/// bytes of raw storage and places the resulting object in [slot].
///
/// This does not invoke the foreign class's constructor on the new instance. If
/// you need that to happen, call the constructor from Wren, which will then
/// call the allocator foreign method. In there, call this to create the object
/// and then the constructor will be invoked when the allocator returns.
///
/// Returns a pointer to the foreign object's data.
pub extern fn wrenSetSlotNewForeign(vm: *WrenVM, slot: c_int, class_slot: c_int, size: usize) ?*anyopaque;

/// Stores a new empty list in [slot].
pub extern fn wrenSetSlotNewList(vm: *WrenVM, slot: c_int) void;

/// Stores a new empty map in [slot].
pub extern fn wrenSetSlotNewMap(vm: *WrenVM, slot: c_int) void;

/// Stores null in [slot].
pub extern fn wrenSetSlotNull(vm: *WrenVM, slot: c_int) void;

/// Stores the string [text] in [slot].
///
/// The [text] is copied to a new string within Wren's heap, so you can free
/// memory used by it after this is called. The length is calculated using
/// [strlen()]. If the string may contain any null bytes in the middle, then you
/// should use [wrenSetSlotBytes()] instead.
pub extern fn wrenSetSlotString(vm: *WrenVM, slot: c_int, text: [*:0]const u8) void;

/// Stores the value captured in [handle] in [slot].
///
/// This does not release the handle for the value.
pub extern fn wrenSetSlotHandle(vm: *WrenVM, slot: c_int, handle: *WrenHandle) void;

/// Returns the number of elements in the list stored in [slot].
pub extern fn wrenGetListCount(vm: *WrenVM, slot: c_int) c_int;

/// Reads element [index] from the list in [listSlot] and stores it in
/// [elementSlot].
pub extern fn wrenGetListElement(vm: *WrenVM, list_slot: c_int, index: c_int, element_slot: c_int) void;

/// Sets the value stored at [index] in the list at [listSlot],
/// to the value from [elementSlot].
pub extern fn wrenSetListElement(vm: *WrenVM, list_slot: c_int, index: c_int, element_slot: c_int) void;

/// Takes the value stored at [elementSlot] and inserts it into the list stored
/// at [listSlot] at [index].
///
/// As in Wren, negative indexes can be used to insert from the end. To append
/// an element, use `-1` for the index.
pub extern fn wrenInsertInList(vm: *WrenVM, list_slot: c_int, index: c_int, element_slot: c_int) void;

/// Returns the number of entries in the map stored in [slot].
pub extern fn wrenGetMapCount(vm: *WrenVM, slot: c_int) c_int;

/// Returns true if the key in [keySlot] is found in the map placed in [mapSlot].
pub extern fn wrenGetMapContainsKey(vm: *WrenVM, map_slot: c_int, key_slot: c_int) bool;

/// Retrieves a value with the key in [keySlot] from the map in [mapSlot] and
/// stores it in [valueSlot].
pub extern fn wrenGetMapValue(vm: *WrenVM, map_slot: c_int, key_slot: c_int, value_slot: c_int) void;

/// Takes the value stored at [valueSlot] and inserts it into the map stored
/// at [mapSlot] with key [keySlot].
pub extern fn wrenSetMapValue(vm: *WrenVM, map_slot: c_int, key_slot: c_int, value_slot: c_int) void;

/// Removes a value from the map in [mapSlot], with the key from [keySlot],
/// and place it in [removedValueSlot]. If not found, [removedValueSlot] is
/// set to null, the same behaviour as the Wren Map API.
pub extern fn wrenRemoveMapValue(vm: *WrenVM, map_slot: c_int, key_slot: c_int, removed_value_slot: c_int) void;

/// Looks up the top level variable with [name] in resolved [module] and stores
/// it in [slot].
pub extern fn wrenGetVariable(vm: *WrenVM, module: [*:0]const u8, name: [*:0]const u8, slot: c_int) void;

/// Looks up the top level variable with [name] in resolved [module],
/// returns false if not found. The module must be imported at the time,
/// use wrenHasModule to ensure that before calling.
pub extern fn wrenHasVariable(vm: *WrenVM, module: [*:0]const u8, name: [*:0]const u8) bool;

/// Returns true if [module] has been imported/resolved before, false if not.
pub extern fn wrenHasModule(vm: *WrenVM, module: [*:0]const u8) bool;

/// Sets the current fiber to be aborted, and uses the value in [slot] as the
/// runtime error object.
pub extern fn wrenAbortFiber(vm: *WrenVM, slot: c_int) void;

/// Returns the user data associated with the WrenVM.
pub extern fn wrenGetUserData(vm: *WrenVM) ?*anyopaque;

/// Sets user data associated with the WrenVM.
pub extern fn wrenSetUserData(vm: *WrenVM, user_data: ?*anyopaque) void;
