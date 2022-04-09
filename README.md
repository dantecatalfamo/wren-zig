# wren-zig
[Wren](https://wren.io/embedding/) bindings for [zig](https://ziglang.org/)!

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

## Example

Check out `src/main.zig`
