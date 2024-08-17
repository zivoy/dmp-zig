# dmp-zig
Zig port of the [diff-match-patch](https://github.com/google/diff-match-patch/) algorithm
for comparing and updating and patching texts

## Uses
can be used as a zig library in other zig projcets
but can also be compiled into freestanding wasm, a static, or a shared library for use with other languages

### Using in zig
first add it to your `build.zig.zon` file 
you can use this command to add the url and hash automatically
```sh 
zig fetch --save https://github.com/zivoy/dmp-zig/archive/refs/tags/v1.0.0.tar.gz
```

or you can add 
```zig
.diffmatchpatch = .{
    .url = "https://github.com/zivoy/dmp-zig/archive/refs/tags/v1.0.0.tar.gz",
    .hash = "122038ddef173a3bc24e0a2e8a95614eb73107f21889ad9cb1080d45f5641b484b10",
},
```
under the dependancies section yourself
another option is to have the files locally (either by copying them or by using gitsubmodules) and use `.path = ` in the `build.zig.zon` file

you can then add it to the imports by doing
```zig
const dmp = b.dependency("diffmatchpatch", .{});
exe.root_module.addImport("diffmatchpatch", dmp.module("root"));
```

### Using with other languages
you can use `zig build` to build a static library
and if you do `zig build -Ddynamic` it will build a dynamic library

you can also build for wasm by doing `zig build -Dtarget=wasm32-freestanding`

## Notes:
the api follows the [common API](https://github.com/google/diff-match-patch/wiki/API), but there might be diffrences

### Contributing
just make a pr

### Zig Version
0.13.0

