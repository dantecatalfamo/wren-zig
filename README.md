# wren-zig
Wren bindings for zig!

Still a work in progress

## Bindings

In `src/wren.zig`

Contains both bare bindings and a zig wrapper

```zig
wrenGetSlotDouble(vm, 0);

vm.getSlotDouble(0);
```

## Example

Check out `src/main.zig`
