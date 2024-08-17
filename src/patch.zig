const DMP = @import("diffmatchpatch.zig");
const std = @import("std");
const diff_funcs = @import("diff.zig");
const Diff = @import("diff.zig").Diff;
const match_funcs = @import("match.zig");

const Allocator = std.mem.Allocator;

const utils = @import("utils.zig");

pub const Error = error{
    InvalidPatchMode,
    InvalidPatchString,
};

pub const PatchList = struct {
    items: []Patch,
    allocator: std.mem.Allocator,
    pub fn deinit(self: *PatchList) void {
        for (self.items) |*patch| patch.deinit(self.allocator);
        self.allocator.free(self.items);
        self.* = undefined;
    }
};

pub const PatchDiffsArrayList = std.ArrayListUnmanaged(Diff);
pub const Patch = struct {
    diffs: *PatchDiffsArrayList,
    start1: usize, // TODO: find other u32s that should be usizes
    start2: usize,
    length1: usize,
    length2: usize,

    ///Emulates GNU diff's format.
    ///Header: @@ -382,8 +481,9 @@
    ///Indices are printed as 1-based, not 0-based.
    pub fn format(
        self: Patch,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.writeAll("@@ -");

        if (self.length1 == 0) {
            try writer.print("{d},0", .{self.start1});
        } else if (self.length1 == 1) {
            try writer.print("{d}", .{self.start1 + 1});
        } else {
            try writer.print("{d},{d}", .{ self.start1 + 1, self.length1 });
        }

        try writer.writeAll(" +");

        if (self.length2 == 0) {
            try writer.print("{d},0", .{self.start2});
        } else if (self.length2 == 1) {
            try writer.print("{d}", .{self.start2 + 1});
        } else {
            try writer.print("{d},{d}", .{ self.start2 + 1, self.length2 });
        }

        try writer.writeAll(" @@\n");

        // Escape the body of the patch with %xx notation.
        for (self.diffs.items) |diff| {
            switch (diff.operation) {
                .insert => try writer.writeAll("+"),
                .delete => try writer.writeAll("-"),
                .equal => try writer.writeAll(" "),
            }

            try utils.encodeURI(writer, diff.text);
            try writer.writeAll("\n");
        }
    }

    pub fn init(allocator: std.mem.Allocator, start1: usize, start2: usize, length1: usize, length2: usize) !Patch {
        const diffs = try allocator.create(PatchDiffsArrayList); // TODO: make this like diffs
        diffs.* = .{};
        return Patch{
            .start1 = start1,
            .start2 = start2,
            .length1 = length1,
            .length2 = length2,
            .diffs = diffs,
        };
    }

    pub fn deinit(self: *Patch, allocator: std.mem.Allocator) void {
        for (self.diffs.items) |*diff| {
            diff.deinit(allocator);
        }
        self.diffs.deinit(allocator);
        allocator.destroy(self.diffs);
        self.* = undefined;
    }
};

///Increase the context until it is unique,
///but don't let the pattern expand beyond match_max_bits.
pub fn addContext(comptime MatchMaxContainer: type, allocator: Allocator, patch_margin: u16, patch: *Patch, text: []const u8) Allocator.Error!void {
    const match_max_bits = @bitSizeOf(MatchMaxContainer);

    if (text.len == 0) return;

    var pattern = text[patch.start2 .. patch.start2 + patch.length1];
    var padding: usize = 0;

    // Look for the first and last matches of pattern in text. If two different
    // matches are found, increase the pattern length.
    while (std.mem.indexOf(u8, text, pattern) != std.mem.lastIndexOf(u8, text, pattern) and
        pattern.len < match_max_bits - 2 * patch_margin)
    {
        padding += patch_margin;
        const pattern_start = if (patch.start2 < padding) 0 else patch.start2 - padding;
        const pattern_end = @min(text.len, patch.start2 + patch.length1 + padding);
        pattern = text[pattern_start..pattern_end];
    }
    padding += patch_margin;

    // add the prefix
    const prefix_start = if (patch.start2 < padding) 0 else patch.start2 - padding;
    const prefix_end = patch.start2;
    const prefix = text[prefix_start..prefix_end];
    if (prefix.len != 0) {
        try patch.diffs.insert(allocator, 0, try Diff.fromSlice(allocator, prefix, .equal));
    }

    // add the suffix
    const suffix_start = patch.start2 + patch.length1;
    const suffix_end = @min(text.len, patch.start2 + patch.length1 + padding);
    const suffix = text[suffix_start..suffix_end];
    if (suffix.len != 0) {
        try patch.diffs.append(allocator, try Diff.fromSlice(allocator, suffix, .equal));
    }

    // Roll back the start points.
    patch.start1 -= prefix.len;
    patch.start2 -= prefix.len;
    // Extend the lengths.
    patch.length1 += prefix.len + suffix.len;
    patch.length2 += prefix.len + suffix.len;
}

// patch make parts
///Compute a list of patches to turn text1 into text2.
///A set of diffs will be computed.
pub fn makeStringString(comptime MatchMaxContainer: type, allocator: Allocator, patch_margin: u16, diff_edit_cost: u16, diff_timeout: f32, text1: [:0]const u8, text2: [:0]const u8) Allocator.Error!PatchList {
    var diffs = try diff_funcs.mainStringStringBool(allocator, diff_timeout, text1, text2, true);
    defer allocator.free(diffs);
    errdefer for (diffs) |*diff| diff.deinit(allocator);
    if (diffs.len > 2) {
        try diff_funcs.cleanupSemantic(allocator, &diffs);
        try diff_funcs.cleanupEfficiency(allocator, diff_edit_cost, &diffs);
    }

    return makeStringDiffs(MatchMaxContainer, allocator, patch_margin, text1, diffs);
}

///Compute a list of patches to turn text1 into text2.
///text1 will be derived from the provided diffs.
pub fn makeDiffs(comptime MatchMaxContainer: type, allocator: Allocator, patch_margin: u16, diffs: []Diff) !PatchList {
    const text1 = try diff_funcs.text1(allocator, diffs);
    defer allocator.free(text1);
    return makeStringDiffs(MatchMaxContainer, allocator, patch_margin, text1, diffs);
}

///Compute a list of patches to turn text1 into text2.
///text2 is ignored, diffs are the delta between text1 and text2.
///Depricated, use patchStringDiffs
pub fn makeStringStringDiffs(comptime MatchMaxContainer: type, allocator: Allocator, patch_margin: u16, text1: [:0]const u8, text2: [:0]const u8, diffs: []Diff) !PatchList {
    _ = text2;
    return makeStringDiffs(MatchMaxContainer, allocator, patch_margin, text1, diffs);
}

///Compute a list of patches to turn text1 into text2.
///text2 is not provided, diffs are the delta between text1 and text2.
pub fn makeStringDiffs(comptime MatchMaxContainer: type, allocator: Allocator, patch_margin: u16, text1: [:0]const u8, diffs: []Diff) Allocator.Error!PatchList {
    var patches = std.ArrayList(Patch).init(allocator);
    defer patches.deinit();
    if (diffs.len == 0) {
        return .{ .items = try patches.toOwnedSlice(), .allocator = allocator };
    }

    var patch = try Patch.init(allocator, 0, 0, 0, 0);

    var char_count1: usize = 0; // Number of characters into the text1 string.
    var char_count2: usize = 0; // Number of characters into the text2 string.

    // Start with text1 (prepatch_text) and apply the diffs until we arrive at
    // text2 (postpatch_text). We recreate the patches one by one to determine
    // context info.
    var prepatch_text = try std.ArrayList(u8).initCapacity(allocator, text1.len);
    defer prepatch_text.deinit();
    try prepatch_text.appendSlice(text1);

    var postpatch_text = try std.ArrayList(u8).initCapacity(allocator, text1.len);
    defer postpatch_text.deinit();
    try postpatch_text.appendSlice(text1);

    for (diffs, 0..) |diff, loc| {
        if (patch.diffs.items.len == 0 and diff.operation != .equal) {
            // new patch starts here
            patch.start1 = char_count1;
            patch.start2 = char_count2;
        }

        switch (diff.operation) {
            .insert => {
                try patch.diffs.append(allocator, diff);
                patch.length2 += diff.text.len;
                try postpatch_text.insertSlice(char_count2, diff.text);
            },
            .delete => {
                patch.length1 += diff.text.len;
                try patch.diffs.append(allocator, diff);
                try postpatch_text.replaceRange(char_count2, diff.text.len, &.{});
            },
            .equal => {
                if (diff.text.len <= 2 * patch_margin and
                    patch.diffs.items.len != 0 and loc != diffs.len - 1)
                {
                    // Small equality inside a patch.
                    try patch.diffs.append(allocator, diff);
                    patch.length1 += diff.text.len;
                    patch.length2 += diff.text.len;
                } else {
                    allocator.free(diff.text);
                }
                if (diff.text.len >= 2 * patch_margin) {
                    // Time for a new patch.
                    if (patch.diffs.items.len != 0) {
                        try addContext(MatchMaxContainer, allocator, patch_margin, &patch, prepatch_text.items);
                        try patches.append(patch);
                        patch.diffs.shrinkAndFree(allocator, patch.diffs.items.len);

                        patch = try Patch.init(allocator, 0, 0, 0, 0);
                        // Unlike Unidiff, our patch lists have a rolling context.
                        // http://code.google.com/p/google-diff-match-patch/wiki/Unidiff
                        // Update prepatch text & pos to reflect the application of the
                        // just completed patch.
                        prepatch_text.clearRetainingCapacity();
                        try prepatch_text.appendSlice(postpatch_text.items);
                        char_count1 = char_count2;
                    }
                }
            },
        }

        // Update the current character count.
        if (diff.operation != .insert) {
            char_count1 += diff.text.len;
        }
        if (diff.operation != .delete) {
            char_count2 += diff.text.len;
        }
    }
    // Pick up the leftover patch if not empty.
    if (patch.diffs.items.len != 0) {
        try addContext(MatchMaxContainer, allocator, patch_margin, &patch, prepatch_text.items);
        patch.diffs.shrinkAndFree(allocator, patch.diffs.items.len);
        try patches.append(patch);
    } else {
        patch.deinit(allocator);
    }

    return .{ .items = try patches.toOwnedSlice(), .allocator = allocator };
}

///Given an array of patches, return another array that is identical.
pub fn deepCopy(allocator: Allocator, patches: PatchList) Allocator.Error!PatchList {
    const patches_copy = try allocator.alloc(Patch, patches.items.len);
    errdefer allocator.free(patches_copy);
    for (patches.items, patches_copy) |patch, *patch_copy| {
        patch_copy.* = try Patch.init(allocator, patch.start1, patch.start2, patch.length1, patch.length2);
        errdefer patch_copy.deinit(allocator);

        try patch_copy.diffs.ensureTotalCapacityPrecise(allocator, patch.diffs.items.len);
        for (patch.diffs.items) |diff| {
            patch_copy.diffs.appendAssumeCapacity(try Diff.fromSlice(allocator, diff.text, diff.operation));
        }
    }
    return .{ .items = patches_copy, .allocator = allocator };
}

///Merge a set of patches onto the text.  Return a patched text, as well
///as an array of true/false values indicating which patches were applied.
pub fn apply(comptime MatchMaxContainer: type, allocator: Allocator, diff_timeout: f32, match_distance: u32, match_threshold: f32, patch_margin: u16, patch_delete_threshold: f32, patches: PatchList, text: [:0]const u8) (match_funcs.MatchError || Allocator.Error)!struct { []const u8, []bool } {
    const match_max_bits = @bitSizeOf(MatchMaxContainer);

    if (patches.items.len == 0) {
        const result = try allocator.alloc(u8, text.len);
        @memcpy(result, text);
        return .{ result, try allocator.alloc(bool, 0) };
    }

    // Deep copy the patches so that no changes are made to originals.
    var patchesCopy = try deepCopy(allocator, patches);
    defer patchesCopy.deinit();

    const null_padding = try addPadding(allocator, patch_margin, &patchesCopy);
    defer allocator.free(null_padding);

    var working_text = try std.ArrayList(u8).initCapacity(allocator, text.len + 2 * null_padding.len);
    defer working_text.deinit();
    try working_text.appendSlice(null_padding);
    try std.unicode.fmtUtf8(text).format(undefined, undefined, working_text.writer());
    // try working_text.appendSlice(text);
    try working_text.appendSlice(null_padding);

    try splitMax(MatchMaxContainer, allocator, patch_margin, &patchesCopy);

    var applied = try allocator.alloc(bool, patchesCopy.items.len);
    errdefer allocator.free(applied);

    var x: usize = 0;
    // delta keeps track of the offset between the expected and actual location
    // of the previous patch.  If there are patches expected at positions 10 and
    // 20, but the first patch was found at 12, delta is 2 and the second patch
    // has an effective expected position of 22.
    var delta: isize = 0;
    for (patchesCopy.items) |patch| {
        const expected_loc: usize = @intCast(@as(isize, @intCast(patch.start2)) + delta);

        const text1 = try diff_funcs.text1(allocator, patch.diffs.items);
        defer allocator.free(text1);

        var start_loc: ?usize = null;
        var end_loc: ?usize = null;
        if (text1.len > match_max_bits) {
            // `patchSplitMax` will only provide an oversized pattern in the case of
            // a monster delete.
            start_loc = try match_funcs.main(MatchMaxContainer, allocator, match_distance, match_threshold, working_text.items, text1[0..match_max_bits], expected_loc);
            if (start_loc != null) {
                end_loc = try match_funcs.main(MatchMaxContainer, allocator, match_distance, match_threshold, working_text.items, text1[text1.len - match_max_bits ..], expected_loc + text1.len - match_max_bits);
                if (end_loc == null or start_loc.? >= end_loc.?) {
                    // Can't find valid trailing context.  Drop this patch.
                    start_loc = null;
                }
            }
        } else {
            start_loc = try match_funcs.main(MatchMaxContainer, allocator, match_distance, match_threshold, working_text.items, text1, expected_loc);
        }
        if (start_loc == null) {
            // No match found.  :(
            applied[x] = false;
            // Subtract the delta for this failed patch from subsequent patches.
            delta -= @as(isize, @intCast(patch.length2)) - @as(isize, @intCast(patch.length1));
        } else {
            // Found a match.  :)
            applied[x] = true;
            delta = @as(isize, @intCast(start_loc.?)) - @as(isize, @intCast(expected_loc));

            var text2: []const u8 = undefined;
            if (end_loc == null) {
                text2 = working_text.items[start_loc.?..@min(start_loc.? + text1.len, working_text.items.len)];
            } else {
                text2 = working_text.items[start_loc.?..@min(end_loc.? + match_max_bits, working_text.items.len)];
            }

            if (std.mem.eql(u8, text1, text2)) {
                // Perfect match, just shove the Replacement text in.
                const replacement = try diff_funcs.text2(allocator, patch.diffs.items);
                defer allocator.free(replacement);
                try working_text.replaceRange(start_loc.?, text1.len, replacement);
            } else {
                // Imperfect match.  Run a diff to get a framework of equivalent indices.
                var diffs = try diff_funcs.mainStringStringBool(allocator, diff_timeout, text1, text2, false);
                defer allocator.free(diffs);
                defer for (diffs) |*diff| diff.deinit(allocator);

                if (text1.len > match_max_bits and
                    @as(f64, @floatFromInt(diff_funcs.levenshtein(diffs))) / @as(f64, @floatFromInt(text1.len)) > patch_delete_threshold)
                {
                    // The end points match, but the content is unacceptably bad.
                    applied[x] = false;
                } else {
                    try diff_funcs.cleanupSemanticLossless(allocator, &diffs);
                    var index1: usize = 0;
                    for (patch.diffs.items) |diff| {
                        if (diff.operation != .equal) blk: {
                            const index2 = diff_funcs.xIndex(diffs, index1);
                            if (diff.operation == .insert) {
                                // Insertion
                                try working_text.insertSlice(start_loc.? + index2, diff.text);
                                break :blk;
                            }
                            std.debug.assert(diff.operation == .delete);
                            // Deletion

                            const rem_len = diff_funcs.xIndex(diffs, index1 + diff.text.len);
                            std.debug.assert(rem_len > index2);
                            working_text.replaceRangeAssumeCapacity(start_loc.? + index2, rem_len - index2, &.{});
                        }
                        if (diff.operation != .delete) {
                            index1 += diff.text.len;
                        }
                    }
                }
            }
        }
        x += 1;
    }
    // Strip the padding off.
    const new_len = working_text.items.len - 2 * null_padding.len;
    std.mem.copyForwards(u8, working_text.items[0..new_len], working_text.items[null_padding.len .. working_text.items.len - null_padding.len]);
    working_text.items.len = new_len;
    return .{ try working_text.toOwnedSlice(), applied };
}

///Add some padding on text start and end so that edges can match something.
///Intended to be called only from within `patchApply`.
pub fn addPadding(allocator: Allocator, patch_margin: u16, patches: *PatchList) Allocator.Error![:0]const u8 {
    const padding_length = patch_margin;
    const null_padding = try allocator.allocSentinel(u8, padding_length, 0);
    for (0..padding_length) |i| {
        null_padding[i] = @intCast(i + 1);
    }

    // Bump all the patches forward.
    for (patches.items) |*patch| {
        patch.start1 += padding_length;
        patch.start2 += padding_length;
    }

    // Add some padding on start of first diff.
    if (patches.items[0].diffs.items.len == 0 or patches.items[0].diffs.items[0].operation != .equal) {
        // Add null_padding equality.
        try patches.items[0].diffs.insert(allocator, 0, try Diff.fromSlice(allocator, null_padding, .equal));

        patches.items[0].start1 -= padding_length; // Should be 0.
        patches.items[0].start2 -= padding_length; // Should be 0.
        patches.items[0].length1 += padding_length;
        patches.items[0].length2 += padding_length;
    } else if (padding_length > patches.items[0].diffs.items[0].text.len) {
        // Grow first equality.
        const extra_length = padding_length - patches.items[0].diffs.items[0].text.len;
        const old_len = try utils.resize(u8, allocator, &patches.items[0].diffs.items[0].text, padding_length);

        std.mem.copyBackwards(u8, patches.items[0].diffs.items[0].text[extra_length..], patches.items[0].diffs.items[0].text[0..old_len]);
        @memcpy(patches.items[0].diffs.items[0].text[0..extra_length], null_padding[old_len..]);

        patches.items[0].start1 -= extra_length;
        patches.items[0].start2 -= extra_length;
        patches.items[0].length1 += extra_length;
        patches.items[0].length2 += extra_length;
    }

    // Add some padding on end of last diff.
    const last_idx = patches.items.len - 1;
    if (patches.items[last_idx].diffs.items.len == 0 or
        patches.items[last_idx].diffs.getLast().operation != .equal)
    {
        // Add nullPadding equality.
        try patches.items[last_idx].diffs.append(allocator, try Diff.fromSlice(allocator, null_padding, .equal));
        patches.items[last_idx].length1 += padding_length;
        patches.items[last_idx].length2 += padding_length;
    } else if (padding_length > patches.items[last_idx].diffs.getLast().text.len) {
        // Grow last equality.
        const extra_length = padding_length - patches.items[last_idx].diffs.getLast().text.len;

        _ = try utils.resize(
            u8,
            allocator,
            &patches.items[last_idx].diffs.items[patches.items[last_idx].diffs.items.len - 1].text,
            padding_length,
        );
        @memcpy(patches.items[last_idx].diffs.getLast().text[padding_length - extra_length ..], null_padding[0..extra_length]);

        patches.items[last_idx].length1 += extra_length;
        patches.items[last_idx].length2 += extra_length;
    }

    return null_padding;
}

///Look through the patches and break up any which are longer than the
///maximum limit of the match algorithm.
///Intended to be called only from within `patchApply`.
pub fn splitMax(comptime MatchMaxContainer: type, allocator: Allocator, patch_margin: u16, patches: *PatchList) !void {
    const patch_size = @bitSizeOf(MatchMaxContainer);

    var precontext = try std.ArrayList(u8).initCapacity(allocator, patch_margin);
    defer precontext.deinit();
    var postcontext: []const u8 = undefined;

    var patchlist = std.ArrayList(Patch).fromOwnedSlice(allocator, patches.items);
    defer patchlist.deinit();

    var x: ?usize = 0;
    while (utils.getIdxOrNull(Patch, patchlist, x.?)) |*big_patch| {
        defer if (x == null) {
            x = 0;
        } else {
            x = x.? + 1;
        };

        if (big_patch.length1 <= patch_size) continue;

        // Remove the big old patch.
        _ = patchlist.orderedRemove(x.?);
        defer @constCast(big_patch).deinit(allocator);
        if (x.? > 0) {
            x = x.? - 1;
        } else {
            x = null;
        }

        var start1 = big_patch.start1;
        var start2 = big_patch.start2;
        precontext.clearRetainingCapacity();
        while (big_patch.diffs.items.len != 0) {
            // Create one of several smaller patches.
            var patch = try Patch.init(
                allocator,
                start1 - precontext.items.len,
                start2 - precontext.items.len,
                0,
                0,
            );
            var empty = true;
            if (precontext.items.len != 0) {
                patch.length1 = precontext.items.len;
                patch.length2 = precontext.items.len;
                try patch.diffs.append(allocator, try Diff.fromSlice(allocator, precontext.items, .equal));
            }
            while (big_patch.diffs.items.len != 0 and patch.length1 < patch_size - patch_margin) {
                const diff_type = big_patch.diffs.items[0].operation;
                var diff_text = big_patch.diffs.items[0].text;
                if (diff_type == .insert) {
                    // Insertions are harmless.
                    patch.length2 += diff_text.len;
                    start2 += diff_text.len;
                    try patch.diffs.append(allocator, big_patch.diffs.orderedRemove(0));
                    empty = false;
                } else if (diff_type == .delete and
                    patch.diffs.items.len == 1 and
                    patch.diffs.items[0].operation == .equal and
                    diff_text.len > 2 * patch_size)
                {
                    // This is a large deletion.  Let it pass in one chunk.
                    patch.length1 += diff_text.len;
                    start1 += diff_text.len;
                    try patch.diffs.append(allocator, big_patch.diffs.orderedRemove(0));
                    empty = false;
                } else {
                    // Deletion or equality.  Only take as much as we can stomach.
                    const diff_text_len = @min(
                        diff_text.len,
                        patch_size - patch.length1 - patch_margin,
                    );
                    diff_text = diff_text[0..diff_text_len];

                    patch.length1 += diff_text_len;
                    start1 += diff_text_len;
                    if (diff_type == .equal) {
                        patch.length2 += diff_text_len;
                        start2 += diff_text_len;
                    } else {
                        empty = false;
                    }
                    try patch.diffs.append(allocator, try Diff.fromSlice(allocator, diff_text, diff_type));
                    if (std.mem.eql(u8, diff_text, big_patch.diffs.items[0].text)) {
                        big_patch.diffs.items[0].deinit(allocator);
                        _ = big_patch.diffs.orderedRemove(0);
                    } else {
                        const len = big_patch.diffs.items[0].text.len - diff_text_len;
                        std.mem.copyForwards(u8, big_patch.diffs.items[0].text[0..len], big_patch.diffs.items[0].text[diff_text_len..]);
                        _ = try utils.resize(u8, allocator, &big_patch.diffs.items[0].text, len);
                    }
                }
            }
            // Compute the head context for the next patch.
            {
                const text2 = try diff_funcs.text2(allocator, patch.diffs.items);
                defer allocator.free(text2);

                precontext.clearRetainingCapacity(); // TODO: see if can be done with less allocs
                try precontext.appendSlice(if (text2.len <= patch_margin)
                    text2
                else
                    text2[text2.len - patch_margin ..]);
            }

            postcontext = undefined;
            // Append the end context for this patch.
            const dt1 = try diff_funcs.text1(allocator, big_patch.diffs.items);
            defer allocator.free(dt1);
            if (dt1.len > patch_margin) {
                postcontext = dt1[0..patch_margin];
            } else {
                postcontext = dt1;
            }

            if (postcontext.len != 0) {
                patch.length1 += postcontext.len;
                patch.length2 += postcontext.len;
                if (patch.diffs.items.len != 0 and
                    patch.diffs.getLast().operation == .equal)
                {
                    const old_len = try utils.resize(
                        u8,
                        allocator,
                        &patch.diffs.items[patch.diffs.items.len - 1].text,
                        patch.diffs.items[patch.diffs.items.len - 1].text.len + postcontext.len,
                    );
                    std.mem.copyForwards(u8, patch.diffs.items[patch.diffs.items.len - 1].text[old_len..], postcontext);
                } else {
                    try patch.diffs.append(allocator, try Diff.fromSlice(allocator, postcontext, .equal));
                }
            }

            if (empty) {
                patch.deinit(allocator);
            } else {
                x = if (x == null) 0 else x.? + 1;
                try patchlist.insert(x.?, patch);
            }
        }
    }

    patches.items = try patchlist.toOwnedSlice();
}

///Take a list of patches and return a textual representation.
pub fn toText(allocator: Allocator, patches: PatchList) ![:0]const u8 {
    var text = std.ArrayList(u8).init(allocator);
    defer text.deinit();
    const text_writer = text.writer();
    for (patches.items) |patch| {
        try patch.format(undefined, undefined, text_writer);
    }
    return text.toOwnedSliceSentinel(0);
}

///Parse a textual representation of patches and return a List of Patch objects.
pub fn fromText(allocator: Allocator, textline: [:0]const u8) (Error || Allocator.Error)!PatchList {
    var patches = std.ArrayList(Patch).init(allocator);
    defer patches.deinit();
    errdefer for (patches.items) |*patch| patch.deinit(allocator);

    if (textline.len == 0) {
        return .{ .items = try patches.toOwnedSlice(), .allocator = allocator };
    }

    var patch: Patch = undefined;

    var texts = std.mem.splitScalar(u8, textline, '\n');
    while (texts.next()) |text| {
        const header = utils.matchPatchHeader(text) orelse return Error.InvalidPatchString;

        patch = try Patch.init(allocator, header[0], header[2], undefined, undefined);
        errdefer patch.deinit(allocator);
        if (header[1] == 0) {
            patch.length1 = 0;
        } else {
            patch.start1 -= 1;
            patch.length1 = header[1] orelse 1;
        }

        if (header[3] == 0) {
            patch.length2 = 0;
        } else {
            patch.start2 -= 1;
            patch.length2 = header[3] orelse 1;
        }

        while (texts.next()) |change| {
            if (change.len == 0) continue;

            const line_encoded = try allocator.alloc(u8, change.len - 1);
            defer allocator.free(line_encoded);
            @memcpy(line_encoded, change[1..]);

            const line = std.Uri.percentDecodeInPlace(line_encoded);
            std.debug.assert(std.unicode.utf8ValidateSlice(line));

            switch (change[0]) {
                '-' => {
                    // Deletion.
                    try patch.diffs.append(allocator, try Diff.fromSlice(allocator, line, .delete));
                },
                '+' => {
                    // Insertion.
                    try patch.diffs.append(allocator, try Diff.fromSlice(allocator, line, .insert));
                },
                ' ' => {
                    // Minor equality.
                    try patch.diffs.append(allocator, try Diff.fromSlice(allocator, line, .equal));
                },
                '@' => {
                    // Start of next patch.
                    // walk back index
                    texts.index = (texts.index orelse texts.buffer.len) - text.len - 1;
                    break;
                },
                else => return error.InvalidPatchMode, // WTF?
            }
        }
        try patches.append(patch);
    }
    return .{ .items = try patches.toOwnedSlice(), .allocator = allocator };
}
