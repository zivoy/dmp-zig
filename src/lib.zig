// TODO: finish ffi bindings (see build file)
const std = @import("std");
const builtin = @import("builtin");
const DMP = @import("diffmatchpatch.zig");

const allocator = if (builtin.cpu.arch.isWasm()) std.heap.wasm_allocator else std.heap.c_allocator;

export fn freePatchList(patches: [*c]Patch, patches_len: c_int) callconv(.C) void {
    const patch_slice = patches[0..@intCast(patches_len)];
    defer allocator.free(patch_slice);
    for (patch_slice) |patch| {
        freePatch(patch);
    }
}

export fn freeDiffList(diffs: [*c]Diff, diffs_len: c_int) callconv(.C) void {
    const diffs_slice = diffs[0..@intCast(diffs_len)];
    defer allocator.free(diffs_slice);
    for (diffs_slice) |diff| {
        freeDiff(diff);
    }
}

export fn freePatch(patch: Patch) callconv(.C) void {
    freeDiffList(patch.diffs, patch.diffs_len);
}

export fn freeDiff(diff: Diff) callconv(.C) void {
    allocator.free(std.mem.span(diff.text));
}

pub const DiffMatchPatch = extern struct {
    diff_timeout: f32 = 1.0,
    diff_edit_cost: c_ushort = 4,
    match_threshold: f32 = 0.5,
    match_distance: c_uint = 1000,
    patch_delete_threshold: f32 = 0.5,
    patch_margin: c_ushort = 4,
};

pub const DiffOperation = enum(c_int) {
    delete = @intFromEnum(DMP.DiffOperation.delete),
    equal = @intFromEnum(DMP.DiffOperation.equal),
    insert = @intFromEnum(DMP.DiffOperation.insert),
};

pub const Diff = extern struct {
    operation: DiffOperation,
    text: [*c]const u8,
};

pub const Patch = extern struct {
    start1: c_int,
    start2: c_int,
    length1: c_int,
    length2: c_int,
    diffs_len: c_int,
    diffs: [*c]Diff,
};

// diff ------------------

export fn diffXIndex(dmp: DiffMatchPatch, diffs: [*c]const Diff, diffs_len: c_int, loc: c_int) callconv(.C) c_int {
    const i_dmp = dmpFromExtern(dmp);

    var i_diffs = dmpDiffListFromExtern(diffs[0..@intCast(diffs_len)]) catch @panic("OOM");
    defer i_diffs.deinit(allocator);
    defer for (i_diffs.items) |diff| diff.deinit(allocator);

    const location = i_dmp.diffXIndex(i_diffs.items, @intCast(loc));
    return @intCast(location);
}

export fn diffPrettyHtml(dmp: DiffMatchPatch, diffs: [*c]const Diff, diffs_len: c_int) callconv(.C) [*c]const u8 {
    const i_dmp = dmpFromExtern(dmp);

    var i_diffs = dmpDiffListFromExtern(diffs[0..@intCast(diffs_len)]) catch @panic("OOM");
    defer i_diffs.deinit(allocator);
    defer for (i_diffs.items) |diff| diff.deinit(allocator);

    const text = i_dmp.diffPrettyHtml(i_diffs.items) catch @panic("OOM");
    return text.ptr;
}

export fn diffPrettyText(dmp: DiffMatchPatch, diffs: [*c]const Diff, diffs_len: c_int) callconv(.C) [*c]const u8 {
    const i_dmp = dmpFromExtern(dmp);

    var i_diffs = dmpDiffListFromExtern(diffs[0..@intCast(diffs_len)]) catch @panic("OOM");
    defer i_diffs.deinit(allocator);
    defer for (i_diffs.items) |diff| diff.deinit(allocator);

    const text = i_dmp.diffPrettyText(i_diffs.items) catch @panic("OOM");
    return text.ptr;
}

export fn diffText1(dmp: DiffMatchPatch, diffs: [*c]const Diff, diffs_len: c_int) callconv(.C) [*c]const u8 {
    const i_dmp = dmpFromExtern(dmp);

    var i_diffs = dmpDiffListFromExtern(diffs[0..@intCast(diffs_len)]) catch @panic("OOM");
    defer i_diffs.deinit(allocator);
    defer for (i_diffs.items) |diff| diff.deinit(allocator);

    const text1 = i_dmp.diffText1(i_diffs.items) catch @panic("OOM");
    return text1.ptr;
}

export fn diffText2(dmp: DiffMatchPatch, diffs: [*c]const Diff, diffs_len: c_int) callconv(.C) [*c]const u8 {
    const i_dmp = dmpFromExtern(dmp);

    var i_diffs = dmpDiffListFromExtern(diffs[0..@intCast(diffs_len)]) catch @panic("OOM");
    defer i_diffs.deinit(allocator);
    defer for (i_diffs.items) |diff| diff.deinit(allocator);

    const text2 = i_dmp.diffText2(i_diffs.items) catch @panic("OOM");
    return text2.ptr;
}

export fn diffLevenshtein(dmp: DiffMatchPatch, diffs: [*c]const Diff, diffs_len: c_int) callconv(.C) c_int {
    const i_dmp = dmpFromExtern(dmp);

    var i_diffs = dmpDiffListFromExtern(diffs[0..@intCast(diffs_len)]) catch @panic("OOM");
    defer i_diffs.deinit(allocator);
    defer for (i_diffs.items) |diff| diff.deinit(allocator);

    const distance = i_dmp.diffLevenshtein(i_diffs.items);
    return @intCast(distance);
}

export fn diffToDelta(dmp: DiffMatchPatch, diffs: [*c]const Diff, diffs_len: c_int) callconv(.C) [*c]const u8 {
    const i_dmp = dmpFromExtern(dmp);

    var i_diffs = dmpDiffListFromExtern(diffs[0..@intCast(diffs_len)]) catch @panic("OOM");
    defer i_diffs.deinit(allocator);
    defer for (i_diffs.items) |diff| diff.deinit(allocator);

    const delta = i_dmp.diffToDelta(i_diffs.items) catch @panic("OOM");
    return delta.ptr;
}

export fn diffFromDelta(dmp: DiffMatchPatch, text: [*c]const u8, delta: [*c]const u8, out_diffs_len: *c_int) callconv(.C) [*c]Diff {
    out_diffs_len.* = -1;
    const i_dmp = dmpFromExtern(dmp);

    const diffs = i_dmp.diffFromDelta(std.mem.span(text), std.mem.span(delta)) catch @panic("OOM");

    const o_diffs = dmpDifflistToExtern(diffs) catch @panic("OOM");
    out_diffs_len.* = @intCast(o_diffs.len);
    return o_diffs.ptr;
}

// match -----------------

export fn matchMain(dmp: DiffMatchPatch, text: [*c]const u8, pattern: [*c]const u8, loc: c_int) callconv(.C) c_int {
    const i_dmp = dmpFromExtern(dmp);
    if (text == null or pattern == null) return -1;
    const res = i_dmp.matchMain(std.mem.span(text), std.mem.span(pattern), @intCast(loc)) catch null orelse return -1;
    return @intCast(res);
}

// patch -----------------

///Compute a list of patches to turn text1 into text2.
///Use diffs if provided, otherwise compute it ourselves.
///There are four ways to call this function, depending on what data is
///available to the caller:
///Method 1:
///a = text1, b = text2
///Method 2:
///a = diffs, b = diffs_len
///Method 3 (optimal):
///a = text1, b = diffs, c = diffs_len
///Method 4 (deprecated, use method 3):
///a = text1, b = text2, c = diffs, d = diffs_len
///
///returns pointer and len in out_patches_len
// export
fn patchMake(dmp: DiffMatchPatch, out_patches_len: *c_int, mode: c_int, ...) callconv(.C) [*c]Patch {
    const i_dmp = dmpFromExtern(dmp);
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    out_patches_len.* = -1;

    const res: DMP.PatchList = switch (mode) {
        1 => blk: {
            const text1: [*c]const u8 = @cVaArg(&ap, [*c]const u8);
            const text2: [*c]const u8 = @cVaArg(&ap, [*c]const u8);
            if (text1 == null or text2 == null) break :blk error.NullInputs;
            break :blk i_dmp.patchMakeStringString(std.mem.span(text1), std.mem.span(text2));
        },
        2 => blk: {
            const diffs: [*c]const Diff = @cVaArg(&ap, [*c]const Diff);
            const diffs_len: usize = @intCast(@cVaArg(&ap, c_int));
            const diff_int = dmpDiffListFromExtern(diffs[0..diffs_len]) catch @panic("OOM");
            break :blk i_dmp.patchMakeDiffs(diff_int.items);
        },
        3 => blk: {
            const text1: [*c]const u8 = @cVaArg(&ap, [*c]const u8);
            if (text1 == null) break :blk error.NullInputs;
            const diffs: [*c]const Diff = @cVaArg(&ap, [*c]const Diff);
            const diffs_len: usize = @intCast(@cVaArg(&ap, c_int));
            const diff_int = dmpDiffListFromExtern(diffs[0..diffs_len]) catch @panic("OOM");
            break :blk i_dmp.patchMakeStringDiffs(std.mem.span(text1), diff_int.items);
        },
        4 => blk: {
            const text1: [*c]const u8 = @cVaArg(&ap, [*c]const u8);
            const text2: [*c]const u8 = @cVaArg(&ap, [*c]const u8);
            if (text1 == null or text2 == null) break :blk error.NullInputs;
            const diffs: [*c]const Diff = @cVaArg(&ap, [*c]const Diff);
            const diffs_len: usize = @intCast(@cVaArg(&ap, c_int));
            const diff_int = dmpDiffListFromExtern(diffs[0..diffs_len]) catch @panic("OOM");
            break :blk i_dmp.patchMakeStringStringDiffs(std.mem.span(text1), std.mem.span(text2), diff_int.items);
        },
        else => error.InvalidMode,
    } catch return null;

    const e_patches = dmpPatchlistToExtern(res) catch @panic("OOM");
    out_patches_len.* = @intCast(e_patches.len);
    return e_patches.ptr;
}

export fn patchDeepCopy(dmp: DiffMatchPatch, patches: [*c]const Patch, patches_len: c_int) callconv(.C) [*c]Patch {
    const i_dmp = dmpFromExtern(dmp);

    const i_patches = dmpPatchListFromExtern(patches[0..@intCast(patches_len)]) catch @panic("OOM");
    defer i_patches.deinit();

    const p_copy = i_dmp.patchDeepCopy(i_patches) catch @panic("OOM");

    const o_patches = dmpPatchlistToExtern(p_copy) catch @panic("OOM");
    return o_patches.ptr;
}

//export
fn patchApply(dmp: DiffMatchPatch, patches: [*c]const Patch, patches_len: c_int, text: [*c]const u8, out_applied: *[*c]bool) callconv(.C) [*c]const u8 {
    const i_dmp = dmpFromExtern(dmp);

    const i_patches = dmpPatchListFromExtern(patches[0..@intCast(patches_len)]) catch @panic("OOM");
    defer i_patches.deinit();

    const result, const applied = i_dmp.patchApply(i_patches, std.mem.span(text)) catch @panic("ERR");
    out_applied.* = applied.ptr;
    return result.ptr;
}

export fn patchAddPadding(dmp: DiffMatchPatch, patches: [*c]const Patch, patches_len: c_int, out_patches: *[*c]Patch, out_patches_len: *c_int) callconv(.C) [*c]const u8 {
    out_patches_len.* = -1;
    out_patches.* = null;
    const i_dmp = dmpFromExtern(dmp);

    var i_patches = dmpPatchListFromExtern(patches[0..@intCast(patches_len)]) catch @panic("OOM");

    const padding = i_dmp.patchAddPadding(&i_patches) catch @panic("OOM");

    const o_patches = dmpPatchlistToExtern(i_patches) catch @panic("OOM");
    out_patches.* = o_patches.ptr;
    out_patches_len.* = @intCast(o_patches.len);
    return padding.ptr;
}

export fn patchSplitMax(dmp: DiffMatchPatch, patches: [*c]const Patch, patches_len: c_int, out_patches: *[*c]Patch, out_patches_len: *c_int) callconv(.C) void {
    out_patches_len.* = -1;
    out_patches.* = null;
    const i_dmp = dmpFromExtern(dmp);

    var i_patches = dmpPatchListFromExtern(patches[0..@intCast(patches_len)]) catch @panic("OOM");

    i_dmp.patchSplitMax(&i_patches) catch @panic("OOM");

    const o_patches = dmpPatchlistToExtern(i_patches) catch @panic("OOM");
    out_patches.* = o_patches.ptr;
    out_patches_len.* = @intCast(o_patches.len);
    return;
}

export fn patchToText(dmp: DiffMatchPatch, patches: [*c]const Patch, patches_len: c_int) callconv(.C) [*c]const u8 {
    const i_dmp = dmpFromExtern(dmp);

    const i_patches = dmpPatchListFromExtern(patches[0..@intCast(patches_len)]) catch @panic("OOM");
    defer i_patches.deinit();

    const text = i_dmp.patchToText(i_patches) catch @panic("OOM");
    return text.ptr;
}

export fn patchFromText(dmp: DiffMatchPatch, text: [*c]const u8, out_patches: *[*c]Patch, out_patches_len: *c_int) callconv(.C) void {
    out_patches_len.* = -1;
    out_patches.* = null;
    const i_dmp = dmpFromExtern(dmp);

    const i_patches = i_dmp.patchFromText(std.mem.span(text)) catch @panic("OOM");

    const o_patches = dmpPatchlistToExtern(i_patches) catch @panic("OOM");
    out_patches.* = o_patches.ptr;
    out_patches_len.* = @intCast(o_patches.len);
    return;
}

export fn patchObjToString(patch: Patch) callconv(.C) [*c]const u8 {
    var arraylist = std.ArrayList(u8).init(allocator);
    defer arraylist.deinit();

    const i_patch = dmpPatchFromExtern(patch) catch @panic("OOM");
    defer i_patch.deinit(allocator);

    i_patch.format(undefined, undefined, arraylist.writer()) catch @panic("OOM");
    const text = arraylist.toOwnedSlice() catch @panic("OOM");

    return text.ptr;
}

// utils ---------------

fn dmpFromExtern(dmp: DiffMatchPatch) DMP {
    return DMP{
        .allocator = allocator,
        .diff_timeout = dmp.diff_timeout,
        .diff_edit_cost = dmp.diff_edit_cost,
        .match_threshold = dmp.match_threshold,
        .patch_delete_threshold = dmp.patch_delete_threshold,
        .patch_margin = dmp.patch_margin,
    };
}

fn dmpDiffListFromExtern(diffs: []const Diff) std.mem.Allocator.Error!DMP.PatchDiffsArrayList {
    var arraylist = try DMP.PatchDiffsArrayList.initCapacity(allocator, diffs.len);
    for (diffs) |diff| {
        arraylist.appendAssumeCapacity(DMP.Diff{ .text = std.mem.span(@constCast(diff.text)), .operation = @enumFromInt(@intFromEnum(diff.operation)) });
    }
    return arraylist;
}

fn dmpPatchListFromExtern(patches: []const Patch) std.mem.Allocator.Error!DMP.PatchList {
    var i_patches = try allocator.alloc(DMP.Patch, patches.len);
    for (patches, 0..) |patch, i| {
        i_patches[i] = try dmpPatchFromExtern(patch);
    }

    return DMP.PatchList{
        .allocator = allocator,
        .items = i_patches,
    };
}
fn dmpPatchFromExtern(patch: Patch) std.mem.Allocator.Error!DMP.Patch {
    const i_patch = try DMP.Patch.init(allocator, @intCast(patch.start1), @intCast(patch.start2), @intCast(patch.length1), @intCast(patch.length2));
    try i_patch.diffs.ensureTotalCapacityPrecise(allocator, @intCast(patch.diffs_len));
    for (patch.diffs[0..@intCast(patch.diffs_len)]) |diff| {
        i_patch.diffs.appendAssumeCapacity(DMP.Diff{
            .operation = @enumFromInt(@intFromEnum(diff.operation)),
            .text = @constCast(std.mem.span(diff.text)),
        });
    }
    return i_patch;
}

fn dmpPatchlistToExtern(patchlist: DMP.PatchList) std.mem.Allocator.Error![]Patch {
    defer {
        for (patchlist.items) |patch| {
            patch.diffs.deinit(allocator);
            allocator.destroy(patch.diffs);
        }
        patchlist.allocator.free(patchlist.items);
    }

    const patches = try allocator.alloc(Patch, patchlist.items.len);
    var diffs: []Diff = undefined;
    for (patchlist.items, 0..) |patch, i| {
        diffs = try allocator.alloc(Diff, patch.diffs.items.len);
        for (patch.diffs.items, 0..) |diff, j| {
            diffs[j] = Diff{
                .operation = @enumFromInt(@intFromEnum(diff.operation)),
                .text = (diff.text[0.. :0]).ptr,
            };
        }

        patches[i] = Patch{
            .start1 = @intCast(patch.start1),
            .start2 = @intCast(patch.start2),
            .length1 = @intCast(patch.length1),
            .length2 = @intCast(patch.length2),
            .diffs_len = @intCast(diffs.len),
            .diffs = diffs.ptr,
        };
    }

    return patches;
}

fn dmpDifflistToExtern(diffs: []DMP.Diff) std.mem.Allocator.Error![]Diff {
    defer allocator.free(diffs);

    var o_diffs = try allocator.alloc(Diff, diffs.len);
    for (diffs, 0..) |diff, j| {
        o_diffs[j] = Diff{
            .operation = @enumFromInt(@intFromEnum(diff.operation)),
            .text = (diff.text[0.. :0]).ptr,
        };
    }

    return o_diffs;
}
