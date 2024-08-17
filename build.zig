const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSafe,
    });

    const dynamic = b.option(bool, "dynamic", "build lib as a dynamic lib");

    const wasm = target.result.cpu.arch.isWasm() and target.result.os.tag == .freestanding;
    const options = .{
        .name = "dmp-zig",
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = !wasm,
    };
    const lib = if (wasm)
        b.addExecutable(options)
    else if (dynamic == true) b.addSharedLibrary(options) else b.addStaticLibrary(options);
    if (wasm) {
        lib.root_module.export_symbol_names = exports;
        lib.entry = .disabled;
    }

    b.installArtifact(lib);

    _ = b.addModule("root", .{ .root_source_file = b.path("src/root.zig") });

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/diffmatchpatch.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}

const exports: []const []const u8 = &.{
    "freePatchList",
    "freeDiffList",
    "freePatch",
    "freeDiff",
    "freeString",

    // "DiffMatchPatch",
    // "Diff",
    // "Patch",
    // "DiffOperation",

    "matchMain",

    "patchMake",
    "patchDeepCopy",
    "patchApply",
    "patchAddPadding",
    "patchSplitMax",
    "patchToText",
    "patchFromText",
    "patchObjToString",

    "diffDiffMain",
    "diffCommonPrefix",
    "diffCommonSuffix",
    "diffCleanupSemantic",
    "diffCleanupSemanticLossless",
    "diffCleanupEfficiency",
    "diffCleanupMerge",
    "diffXIndex",
    "diffPrettyHtml",
    "diffPrettyText",
    "diffText1",
    "diffText2",
    "diffLevenshtein",
    "diffToDelta",
    "diffFromDelta",
};
