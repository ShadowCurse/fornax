# Fornax

# IN DEVELOPMENT

Some parts are based on the original [Fossilize](https://github.com/ValveSoftware/Fossilize) project.

## Build

```bash
$ zig build replay_build
```
or in `ReleaseFast` mode
```bash
$ zig build -Doptimize=ReleaseFast -Duse_llvm replay_build
```

## Run

```bash
$ ./zig-out/bin/replay ./database.foz
```

