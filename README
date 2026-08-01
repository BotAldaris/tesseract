# Tesseract

This is [tesseract](https://github.com/tesseract-ocr/tesseract/) packaged for [Zig](https://ziglang.org/).

This lib has some implementations incomplete, but is enough to read png and jpeg. 

## How to use it

First, update your `build.zig.zon`:

```
zig fetch --save git+https://github.com/BotAldaris/tesseract.git
```

Next, add this snippet to your `build.zig` script:

```zig
const tesseract_dep = b.dependency("tesseract", .{
    .target = target,
    .optimize = optimize,
});
your_compilation.linkLibrary(tesseract_dep.artifact("tesseract"));
```

This will provide tesseract as a static library to `your_compilation`.
