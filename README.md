# dmp-zig
Zig port of the [diff-match-patch](https://github.com/google/diff-match-patch/) algorithm
for comparing and updating and patching texts

## Zig Version
0.13.0

## Example
```zig
const DiffMatchPatch = @import("diffmatchpatch").DiffMatchPatch;
const dmp = DiffMatchPatch.init(testing.allocator);

const str1 = "here is a string one it is a string and string and it strings the string with string and string";
const str2 = "string two is slightly different it also strings but it strings and strings but might not string";

var patches = try dmp.patchMakeStringString(str1, str2);
defer patches.deinit();

for (patches.items) |patch| std.debug.print("{any}\n", .{patch});
```

## Uses
dmp-zig can be used as a zig library in other zig projects
but can also be compiled into freestanding wasm, a static, or a shared library for use with other languages

### Using in zig
First add it to your `build.zig.zon` file 
you can use this command to add the URL and hash automatically
```sh 
zig fetch --save https://github.com/zivoy/dmp-zig/archive/refs/tags/v1.1.1.tar.gz
```

or you can add 
```zig
.diffmatchpatch = .{
    .url = "https://github.com/zivoy/dmp-zig/archive/refs/tags/v1.1.1.tar.gz",
    .hash = "1220b6fe0c783bdeaff719f62a010351b190724172e72a8ea424f0cc42c23a45082c",
},
```
under the dependencies section yourself

Another option is to have the files locally (either by copying them or by using git submodules) and use `.path = ` in the `build.zig.zon` file


You can then add it to the imports by adding to your `build.zig` file
```zig
const dmp = b.dependency("diffmatchpatch", .{});
exe.root_module.addImport("diffmatchpatch", dmp.module("root"));
```

### Using with other languages
you can use `zig build` to build a static library.
And if you do `zig build -Ddynamic` it will build a dynamic library

You can also build for WASM by doing `zig build -Dtarget=wasm32-freestanding`

## Notes:
The API follows the [Common API](https://github.com/google/diff-match-patch/wiki/API), but there might be differences

# Contributing
Just make a pr

# Acknowledgments
This project is a port of Google's [diff-match-patch](https://github.com/google/diff-match-patch) library, originally developed by [Neil Fraser](https://neil.fraser.name/) and licensed under [Apache License 2.0](https://github.com/google/diff-match-patch/blob/master/LICENSE).

Additionally, this project references code from [go-diff](https://github.com/sergi/go-diff/), which is licensed under the [MIT License](https://github.com/sergi/go-diff/blob/master/LICENSE).

# License
This project is licensed under the [MIT License](./LICENSE).

