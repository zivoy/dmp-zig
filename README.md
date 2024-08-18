# dmp-zig
Zig port of the [diff-match-patch](https://github.com/google/diff-match-patch/) algorithm
for comparing and updating and patching texts

## Example
```zig
const dmp = @import("diffmatchpatch");

const d = dmp.DiffMatchPatch.init(testing.allocator);

const str1 = "here is a string one it is a string and string and it strings the string with string and string";
const str2 = "string two is slightly different it also strings but it strings and strings but might not string";

var patches = try d.patchMakeStringString(str1, str2);
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
zig fetch --save https://github.com/zivoy/dmp-zig/archive/refs/tags/v1.0.1.tar.gz
```

or you can add 
```zig
.diffmatchpatch = .{
    .url = "https://github.com/zivoy/dmp-zig/archive/refs/tags/v1.0.1.tar.gz",
    .hash = "12202234ff332ab054fcb962bbaaa892791172ed072d0b69fe24c1bc5473f984f2c1",
},
```
under the dependencies section yourself

Another option is to have the files locally (either by copying them or by using git submodules) and use `.path = ` in the `build.zig.zon` file


You can then add it to the imports by doing
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

### Contributing
Just make a pr

### Zig Version
0.13.0

