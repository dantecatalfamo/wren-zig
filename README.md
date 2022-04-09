# wren-zig
Wren bindings for zig!

Still a work in progress. Details on how embedding wren works [here](https://wren.io/embedding/).

## Bindings

In `src/wren.zig`

Contains both bare bindings and a zig wrapper

```zig
wrenGetSlotDouble(vm, 0);

vm.getSlotDouble(0);
```

## Building

Just run `zig build`, automatically pulls in git submodule if not already done

## Example

Check out `src/main.zig`
