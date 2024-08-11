const Self = @import("diffmatchpatch.zig");
const std = @import("std");

///Increase the context until it is unique,
///but don't let the pattern expand beyond match_max_bits.
pub fn patchAddContext(self: Self, patch: *Self.Patch, text: []const u8) std.mem.Allocator.Error!void {
    if (text.len == 0) return;

    var pattern = text[patch.start2 .. patch.start2 + patch.length1];
    var padding: u32 = 0;

    // Look for the first and last matches of pattern in text. If two different
    // matches are found, increase the pattern length.
    while (std.mem.indexOf(u8, text, pattern) != std.mem.lastIndexOf(u8, text, pattern) and pattern.len < Self.match_max_bits - 2 * self.patch_margin) {
        padding += self.patch_margin;
        pattern = text[@max(0, patch.start2 - padding)..@min(text.len, patch.start2 + patch.length1 + padding)];
    }
    padding += self.patch_margin;

    // add the prefix
    const prefix = text[@max(0, patch.start2 - padding)..patch.start2];
    if (prefix.len != 0) {
        try patch.diffs.append(self.allocator, try Self.Diff.fromSlice(self.allocator, prefix, .equal));
    }

    // add the suffix
    const suffix = text[patch.start2 + patch.length1 .. @min(text.len, patch.start2 + patch.length1 + padding)];
    if (suffix.len != 0) {
        try patch.diffs.append(self.allocator, try Self.Diff.fromSlice(self.allocator, suffix, .equal));
    }

    // Roll back the start points.
    patch.*.start1 -= prefix.len;
    patch.*.start2 -= prefix.len;
    // Extend the lengths.
    patch.*.length1 += prefix.len + suffix.len;
    patch.*.length2 += prefix.len + suffix.len;
}

// patch make parts
///Compute a list of patches to turn text1 into text2.
///A set of diffs will be computed.
pub fn patchMakeStringString(self: Self, text1: [:0]const u8, text2: [:0]const u8) !Self.PatchList {
    var diffs = self.diffMainStringStringBool(text1, text2, true);
    if (diffs.len > 2) {
        self.diffCleanupSemantic(&diffs);
        self.diffCleanupEfficiency(&diffs);
    }

    return self.patchMakeStringDiffs(text1, diffs);
}

///Compute a list of patches to turn text1 into text2.
///text1 will be derived from the provided diffs.
pub fn patchMakeDiffs(self: Self, diffs: []Self.Diff) !Self.PatchList {
    const text1 = try self.diffText1(diffs);
    defer self.allocator.free(text1);
    return self.patchMakeStringDiffs(text1, diffs);
}

///Compute a list of patches to turn text1 into text2.
///text2 is ignored, diffs are the delta between text1 and text2.
///Depricated, use patchStringDiffs
pub fn patchMakeStringStringDiffs(self: Self, text1: [:0]const u8, text2: [:0]const u8, diffs: []Self.Diff) !Self.PatchList {
    _ = text2;
    return self.patchMakeStringDiffs(text1, diffs);
}

///Compute a list of patches to turn text1 into text2.
///text2 is not provided, diffs are the delta between text1 and text2.
pub fn patchMakeStringDiffs(self: Self, text1: [:0]const u8, diffs: []Self.Diff) std.mem.Allocator.Error!Self.PatchList {
    var patches = std.ArrayList(Self.Patch).init(self.allocator);
    defer patches.deinit();
    if (diffs.len == 0) {
        return .{ .items = try patches.toOwnedSlice(), .allocator = self.allocator };
    }

    var patch = try Self.Patch.init(self.allocator, 0, 0, 0, 0);
    // patch.diffs = try PatchDiffsArrayList.initCapacity(self.allocator, diffs.len);

    var char_count1: usize = 0; // Number of characters into the text1 string.
    var char_count2: usize = 0; // Number of characters into the text2 string.
    // Start with text1 (prepatch_text) and apply the diffs until we arrive at
    // text2 (postpatch_text). We recreate the patches one by one to determine
    // context info.
    var prepatch_text = try std.ArrayList(u8).initCapacity(self.allocator, text1.len);
    defer prepatch_text.deinit();
    try prepatch_text.appendSlice(text1);
    var postpatch_text = try std.ArrayList(u8).initCapacity(self.allocator, text1.len);
    defer postpatch_text.deinit();
    try postpatch_text.appendSlice(text1);

    for (diffs, 1..) |diff, loc| {
        if (patch.diffs.items.len == 0 and diff.operation == .equal) {
            // new patch starts here
            patch.start1 = @intCast(char_count1);
            patch.start2 = @intCast(char_count2);
        }

        switch (diff.operation) {
            .insert => {
                try patch.diffs.append(self.allocator, diff);
                patch.length2 += @intCast(diff.text.len);

                try postpatch_text.ensureUnusedCapacity(diff.text.len);
                var slice = postpatch_text.allocatedSlice();
                std.mem.copyBackwards(u8, slice[char_count2 + diff.text.len ..], slice[char_count2..postpatch_text.items.len]);
                @memcpy(slice[char_count2 .. char_count2 + diff.text.len], diff.text);
                postpatch_text.items.len += diff.text.len;
            },
            .delete => {
                patch.length1 += diff.text.len;
                try patch.diffs.append(self.allocator, diff);

                @memcpy(postpatch_text.items[char_count2..], postpatch_text.items[char_count2 + diff.text.len ..]);
                postpatch_text.items.len -= diff.text.len;
            },
            .equal => {
                if (diff.text.len <= 2 * self.patch_margin and patch.diffs.items.len != 0 and loc != diffs.len) {
                    // Small equality inside a patch.
                    try patch.diffs.append(self.allocator, diff);
                    patch.length1 += diff.text.len;
                    patch.length2 += diff.text.len;
                }
                if (diff.text.len >= 2 * self.patch_margin) {
                    // Time for a new patch.
                    if (patch.diffs.items.len != 0) {
                        try self.patchAddContext(&patch, prepatch_text.items);
                        try patches.append(patch);
                        patch = try Self.Patch.init(self.allocator, 0, 0, 0, 0);
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
        try self.patchAddContext(&patch, prepatch_text.items);
        try patches.append(patch);
    }

    return .{ .items = try patches.toOwnedSlice(), .allocator = self.allocator };
}

///Given an array of patches, return another array that is identical.
pub fn patchDeepCopy(self: Self, patches: Self.PatchList) std.mem.Allocator.Error!Self.PatchList {
    var patches_copy = try self.allocator.alloc(Self.Patch, patches.items.len);
    for (patches.items, 0..) |patch, i| {
        var patch_copy = try Self.Patch.init(self.allocator, patch.start1, patch.start2, patch.length1, patch.length2);
        try patch.diffs.ensureTotalCapacity(self.allocator, patch.diffs.items.len);
        for (patch.diffs.items) |diff| {
            patch_copy.diffs.appendAssumeCapacity(try diff.copy(self.allocator));
        }
        patches_copy[i] = patch_copy;
    }
    return .{ .items = patches_copy, .allocator = self.allocator };
}

///Merge a set of patches onto the text.  Return a patched text, as well
///as an array of true/false values indicating which patches were applied.
pub fn patchApply(self: Self, patches: Self.PatchList, text: [:0]const u8) !struct { []const u8, []bool } {
    var applied = try self.allocator.alloc(bool, patches.items.len);
    errdefer self.allocator.free(applied);
    if (patches.items.len == 0) {
        const result = try self.allocator.alloc(u8, text.len);
        @memcpy(result.ptr, text);
        return .{ result, applied };
    }

    // Deep copy the patches so that no changes are made to originals.
    var patchesCopy = try self.patchDeepCopy(patches);
    defer patchesCopy.deinit();

    const null_padding = try self.patchAddPadding(&patchesCopy);

    var working_text = try std.ArrayList(u8).initCapacity(self.allocator, text.len + 2 * null_padding.len);
    defer working_text.deinit();
    try working_text.appendSlice(null_padding);
    try working_text.appendSlice(text);
    try working_text.appendSlice(null_padding);

    try self.patchSplitMax(&patchesCopy);

    var x: usize = 0;
    // delta keeps track of the offset between the expected and actual location
    // of the previous patch.  If there are patches expected at positions 10 and
    // 20, but the first patch was found at 12, delta is 2 and the second patch
    // has an effective expected position of 22.
    var delta: isize = 0;
    for (patchesCopy.items) |patch| {
        const expected_loc: usize = @intCast(@as(isize, @intCast(patch.start2)) + delta);
        const text1 = try self.diffText1(patch.diffs.items);
        var start_loc: ?usize = null;
        var end_loc: ?usize = null;
        if (text1.len > Self.match_max_bits) {
            // `patchSplitMax` will only provide an oversized pattern in the case of
            // a monster delete.
            start_loc = try self.matchMain(working_text.items, text1[0..Self.match_max_bits], expected_loc);
            if (start_loc != null) {
                end_loc = try self.matchMain(working_text.items, text1[Self.match_max_bits..], expected_loc + text1.len - Self.match_max_bits);
                if (end_loc == null or start_loc.? >= end_loc.?) {
                    // Can't find valid trailing context.  Drop this patch.
                    start_loc = null;
                }
            }
        } else {
            start_loc = try self.matchMain(working_text.items, text1, expected_loc);
        }
        if (start_loc == null) {
            // No match found.  :(
            applied[x] = false;
            // Subtract the delta for this failed patch from subsequent patches.
            delta -= @intCast(patch.length2 - patch.length1);
        } else {
            // Found a match.  :)
            applied[x] = true;
            delta = @intCast(start_loc.? - expected_loc);
            var text2: []const u8 = undefined;
            if (end_loc == null) {
                text2 = working_text.items[start_loc.?..@min(start_loc.? + text1.len, working_text.items.len)];
            } else {
                text2 = working_text.items[start_loc.?..@min(end_loc.? + Self.match_max_bits, working_text.items.len)];
            }
            if (std.mem.eql(u8, text1, text2)) {
                // Perfect match, just shove the Replacement text in.
                const replacement = try self.diffText2(patch.diffs.items);
                const len = replacement.len + working_text.items.len - text1.len;
                try working_text.ensureTotalCapacity(len);
                const slice = working_text.allocatedSlice();
                std.debug.assert(replacement.len > text1.len); // INFO: needs to be debugged if replacement is always bigger then text1
                std.mem.copyBackwards(u8, slice[start_loc.? + replacement.len ..], slice[start_loc.? + text1.len .. working_text.items.len]);
                @memcpy(slice[start_loc.? .. start_loc.? + replacement.len], replacement);
                working_text.items.len = len;
            } else {
                // Imperfect match.  Run a diff to get a framework of equivalent indices.
                var diffs = self.diffMainStringStringBool(text1, text2[0.. :0], false);
                if (text1.len > Self.match_max_bits and @as(f32, @floatFromInt(self.diffLevenshtein(diffs))) / @as(f32, @floatFromInt(text1.len)) > self.patch_delete_threshold) {
                    // The end points match, but the content is unacceptably bad.
                    applied[x] = false;
                } else {
                    self.diffCleanupSemanticLossless(&diffs);
                    var index1: usize = 0;
                    for (patch.diffs.items) |diff| {
                        if (diff.operation != .equal) {
                            const index2 = self.diffXIndex(diffs, index1);
                            if (diff.operation == .insert) {
                                // Insertion
                                try working_text.insertSlice(start_loc.? + index2, diff.text);
                            } else if (diff.operation == .delete) {
                                const idxText2 = self.diffXIndex(diffs, index1 + diff.text.len);
                                std.debug.assert(idxText2 > index2);
                                @memcpy(working_text.items[start_loc.? + index2 ..], working_text.items[start_loc.? + idxText2 ..]);
                                working_text.items.len = working_text.items.len - (idxText2 - index2);
                            }
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
    @memcpy(working_text.items, working_text.items[null_padding.len .. working_text.items.len - null_padding.len]);
    working_text.items.len -= working_text.items.len - 2 * null_padding.len;
    return .{ try working_text.toOwnedSlice(), applied };
}

const null_padding_str = blk: {
    const n_items = 255;
    var np: [n_items]u8 = undefined;
    for (0..n_items) |i| {
        np[i] = i + 1;
    }
    break :blk np;
};

///Add some padding on text start and end so that edges can match something.
///Intended to be called only from within `patchApply`.
pub fn patchAddPadding(self: Self, patches: *Self.PatchList) std.mem.Allocator.Error![:0]const u8 {
    const padding_length = self.patch_margin;
    // const null_padding = try self.allocator.alloc(u8, padding_length);
    // for (0..padding_length) |i| {
    //     null_padding[i] = i + 1;
    // }
    const null_padding = null_padding_str[0..padding_length :0];

    // Bump all the patches forward.
    for (patches.items) |*patch| {
        patch.*.start1 += padding_length;
        patch.*.start2 += padding_length;
    }

    // Add some padding on start of first diff.
    var first_patch = patches.items[0];
    if (first_patch.diffs.items.len == 0 or first_patch.diffs.items[0].operation != .equal) {
        // Add null_padding equality.
        try first_patch.diffs.insert(self.allocator, 0, try Self.Diff.fromSlice(self.allocator, null_padding, .equal));

        first_patch.start1 -= padding_length; // Should be 0.
        first_patch.start2 -= padding_length; // Should be 0.
        first_patch.length1 += padding_length;
        first_patch.length2 += padding_length;
    } else if (padding_length > first_patch.diffs.items[0].text.len) {
        // Grow first equality.
        const extra_length = padding_length - first_patch.diffs.items[0].text.len;

        const old_text_len = first_patch.diffs.items[0].text.len;

        if (!self.allocator.resize(first_patch.diffs.items[0].text, padding_length)) {
            const new_first_text = try self.allocator.alloc(u8, padding_length);
            @memcpy(new_first_text[padding_length - old_text_len ..], first_patch.diffs.items[0].text);
            @memset(first_patch.diffs.items[0].text, undefined);
            self.allocator.free(first_patch.diffs.items[0].text);
            first_patch.diffs.items[0].text = new_first_text;
        } else {
            std.mem.copyBackwards(u8, first_patch.diffs.items[0].text[padding_length - old_text_len ..], first_patch.diffs.items[0].text[0..old_text_len]);
        }

        @memcpy(first_patch.diffs.items[0].text, null_padding[old_text_len..]);

        first_patch.start1 -= @intCast(extra_length);
        first_patch.start2 -= @intCast(extra_length);
        first_patch.length1 += @intCast(extra_length);
        first_patch.length2 += @intCast(extra_length);
    }

    // Add some padding on end of last diff.
    var last_patch = patches.items[patches.items.len - 1];
    if (last_patch.diffs.items.len == 0 or last_patch.diffs.getLast().operation != .equal) {
        // Add nullPadding equality.
        try last_patch.diffs.append(self.allocator, try Self.Diff.fromSlice(self.allocator, null_padding, .equal));
        last_patch.length1 += padding_length;
        last_patch.length2 += padding_length;
    } else if (padding_length > last_patch.diffs.getLast().text.len) {
        // Grow last equality.
        const extra_length = padding_length - last_patch.diffs.getLast().text.len;

        if (!self.allocator.resize(last_patch.diffs.getLast().text, padding_length)) {
            const new_last_text = try self.allocator.alloc(u8, padding_length);
            @memcpy(new_last_text, last_patch.diffs.getLast().text);
            @memset(last_patch.diffs.getLast().text, undefined);
            self.allocator.free(last_patch.diffs.getLast().text);
            last_patch.diffs.items[last_patch.diffs.items.len - 1].text = new_last_text;
        }

        @memcpy(last_patch.diffs.getLast().text[padding_length - extra_length ..], null_padding[0..extra_length]);

        last_patch.length1 += @intCast(extra_length);
        last_patch.length2 += @intCast(extra_length);
    }

    return null_padding;
}

fn getIdxOrNull(comptime T: type, arrayList: std.ArrayList(T), idx: usize) ?T {
    if (idx >= arrayList.items.len) return null;
    return arrayList.items[idx];
}

///Look through the patches and break up any which are longer than the
///maximum limit of the match algorithm.
///Intended to be called only from within `patchApply`.
pub fn patchSplitMax(self: Self, patches: *Self.PatchList) !void {
    const patch_size = Self.match_max_bits;
    var empty: bool = undefined;
    var patch: Self.Patch = undefined;
    var start1: usize = undefined;
    var start2: usize = undefined;
    var diff_type: Self.DiffOperation = undefined;
    var diff_text: []u8 = undefined;
    var precontext = std.ArrayList(u8).init(self.allocator);
    defer precontext.deinit();
    var postcontext: []const u8 = undefined;

    var patchlist = std.ArrayList(Self.Patch).fromOwnedSlice(self.allocator, patches.items);
    defer patchlist.deinit();
    var x: usize = 0;
    while (getIdxOrNull(Self.Patch, patchlist, x)) |big_patch| {
        defer x += 1;
        if (big_patch.length1 <= patch_size) continue;

        // Remove the big old patch.
        _ = patchlist.orderedRemove(x);
        defer big_patch.deinit(self.allocator);
        x -= 1;

        start1 = big_patch.start1;
        start2 = big_patch.start2;
        precontext.clearRetainingCapacity();
        while (big_patch.diffs.items.len != 0) {
            // Create one of several smaller patches.
            patch = try Self.Patch.init(self.allocator, start1 - precontext.items.len, start2 - precontext.items.len, 0, 0);
            empty = true;
            if (precontext.items.len != 0) {
                patch.length1 = @intCast(precontext.items.len);
                patch.length2 = @intCast(precontext.items.len);
                try patch.diffs.append(self.allocator, try Self.Diff.fromSlice(self.allocator, precontext.items, .equal));
            }
            while (big_patch.diffs.items.len != 0 and patch.length1 < patch_size - self.patch_margin) {
                diff_type = big_patch.diffs.items[0].operation;
                diff_text = big_patch.diffs.items[0].text;
                if (diff_type == .insert) {
                    // Insertions are harmless.
                    patch.length2 += @intCast(diff_text.len);
                    start2 += diff_text.len;
                    try patch.diffs.append(self.allocator, big_patch.diffs.items[0]);
                    _ = big_patch.diffs.orderedRemove(0);
                    empty = false;
                } else if (diff_type == .delete and patch.diffs.items.len == 1 and patch.diffs.items[0].operation == .equal and diff_text.len > 2 * patch_size) {
                    // This is a large deletion.  Let it pass in one chunk.
                    patch.length1 += @intCast(diff_text.len);
                    start1 += diff_text.len;
                    try patch.diffs.append(self.allocator, big_patch.diffs.items[0]);
                    _ = big_patch.diffs.orderedRemove(0);
                    empty = false;
                } else {
                    // Deletion or equality.  Only take as much as we can stomach.
                    const diff_text_len = @min(diff_text.len, patch_size - patch.length1 - self.patch_margin);
                    patch.length1 += @intCast(diff_text_len);
                    start1 += diff_text_len;
                    if (diff_type == .equal) {
                        patch.length2 += @intCast(diff_text_len);
                        start2 += diff_text_len;
                    } else {
                        empty = false;
                    }
                    try patch.diffs.append(self.allocator, try Self.Diff.fromSlice(self.allocator, diff_text[0..diff_text_len], diff_type));
                    if (std.mem.eql(u8, diff_text, big_patch.diffs.items[0].text)) {
                        big_patch.diffs.items[0].deinit(self.allocator);
                        _ = big_patch.diffs.orderedRemove(0);
                    } else {
                        big_patch.diffs.items[0].text = big_patch.diffs.items[0].text[diff_text_len..]; // TODO: check for leaks
                    }
                }
            }
            // Compute the head context for the next patch.
            precontext.clearRetainingCapacity();
            try precontext.appendSlice(try self.diffText2(patch.diffs.items));
            precontext.items = precontext.items[@max(0, precontext.items.len - self.patch_margin)..];

            // Append the end context for this patch.
            const dt1 = try self.diffText1(big_patch.diffs.items);
            if (dt1.len > self.patch_margin) {
                postcontext = dt1[0..self.patch_margin];
            } else {
                postcontext = dt1;
            }

            if (postcontext.len != 0) {
                patch.length1 += @intCast(postcontext.len);
                patch.length2 += @intCast(postcontext.len);
                if (patch.diffs.items.len != 0 and patch.diffs.getLast().operation == .equal) {
                    var last_diff = patch.diffs.getLast();
                    const old_diff_text_len = last_diff.text.len;
                    if (!self.allocator.resize(last_diff.text, old_diff_text_len + postcontext.len)) {
                        const new_text = try self.allocator.alloc(u8, old_diff_text_len + postcontext.len);
                        @memcpy(new_text, last_diff.text);
                        @memset(last_diff.text, undefined);
                        self.allocator.free(last_diff.text);
                        last_diff.text = new_text;
                    }
                    @memcpy(last_diff.text[old_diff_text_len..], postcontext);
                } else {
                    try patch.diffs.append(self.allocator, try Self.Diff.fromSlice(self.allocator, postcontext, .equal));
                }
            }

            if (!empty) {
                x += 1;
                try patchlist.insert(x, patch);
            }
        }
    }

    patches.items = try patchlist.toOwnedSlice();
}

///Take a list of patches and return a textual representation.
pub fn patchToText(self: Self, patches: Self.PatchList) ![:0]const u8 {
    var text = std.ArrayList(u8).init(self.allocator);
    defer text.deinit();
    const text_writer = text.writer();
    for (patches.items) |patch| {
        try patch.format("", .{}, text_writer);
    }
    return text.toOwnedSliceSentinel(0);
}

///Parse a textual representation of patches and return a List of Patch objects.
pub fn patchFromText(self: Self, textline: [:0]const u8) (Self.PatchError || std.mem.Allocator.Error)!Self.PatchList {
    var patches = std.ArrayList(Self.Patch).init(self.allocator);
    defer patches.deinit();
    if (textline.len == 0) {
        return .{ .items = try patches.toOwnedSlice(), .allocator = self.allocator };
    }

    var patch: Self.Patch = undefined;

    var texts = std.mem.splitScalar(u8, textline, '\n');
    var first = true;
    while (if (first) @as(?[]const u8, texts.first()) else texts.next()) |text| {
        first = false;

        const header = matchPatchHeader(text) catch null orelse return Self.PatchError.InvalidPatchString;

        patch = try Self.Patch.init(self.allocator, header[0], header[2], undefined, undefined);
        if (header[1] == null) {
            patch.start1 -= 1;
            patch.length1 = 1;
        } else if (header[1] == 0) {
            patch.length1 = 0;
        } else {
            patch.start1 -= 1;
            patch.length1 = @intCast(header[1].?);
        }

        if (header[3] == null) {
            patch.start2 -= 1;
            patch.length2 = 1;
        } else if (header[3] == 0) {
            patch.length2 = 0;
        } else {
            patch.start2 -= 1;
            patch.length2 = @intCast(header[3].?);
        }

        while (texts.next()) |change| {
            if (change.len == 0) continue;

            // const rep_size = std.mem.replacementSize(u8, change[1..], "+", "%2B");
            // const line_encoded = try self.allocator.alloc(u8, rep_size);
            // defer self.allocator.free(line_encoded);
            // _ = std.mem.replace(u8, change[1..], "+", "%2B", line_encoded);

            const line_encoded = try self.allocator.alloc(u8, change.len - 1);
            defer self.allocator.free(line_encoded);
            @memcpy(line_encoded, change[1..]);
            const line = std.Uri.percentDecodeInPlace(line_encoded);

            switch (change[0]) {
                '-' => {
                    // Deletion.
                    try patch.diffs.append(self.allocator, try Self.Diff.fromSlice(self.allocator, line, .delete));
                },
                '+' => {
                    // Insertion.
                    try patch.diffs.append(self.allocator, try Self.Diff.fromSlice(self.allocator, line, .insert));
                },
                ' ' => {
                    // Minor equality.
                    try patch.diffs.append(self.allocator, try Self.Diff.fromSlice(self.allocator, line, .equal));
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
    return .{ .items = try patches.toOwnedSlice(), .allocator = self.allocator };
}

///Emulates the regex
///`^@@ -(\d+),?(\d*) \+(\d+),?(\d*) @@$`
fn matchPatchHeader(text: []const u8) !?struct { usize, ?usize, usize, ?usize } {
    if (!std.mem.startsWith(u8, text, "@@ -") or
        !std.mem.endsWith(u8, text, " @@"))
        return null;

    // strip '@@ -'
    var pointer: usize = 4;

    const digits: []const u8 = "0123456789";

    const digit1_end_index = std.mem.indexOfNonePos(u8, text, pointer, digits) orelse return null;
    const digit1 = try std.fmt.parseInt(u8, text[pointer..digit1_end_index], 10);
    pointer = digit1_end_index;

    var digit2: ?usize = null;
    switch (text[pointer]) {
        ',' => {
            pointer += 1;
            const digit2_end_index = std.mem.indexOfNonePos(u8, text, pointer, digits) orelse return null;
            digit2 = try std.fmt.parseInt(u8, text[pointer..digit2_end_index], 10);
            pointer = digit2_end_index;
        },
        ' ' => {},
        else => return null,
    }

    // check ` +`
    if (!std.mem.eql(u8, text[pointer .. pointer + 2], " +")) return null;
    pointer += 2;

    const digit3_end_index = std.mem.indexOfNonePos(u8, text, pointer, digits) orelse return null;
    const digit3 = try std.fmt.parseInt(u8, text[pointer..digit3_end_index], 10);
    pointer = digit3_end_index;

    var digit4: ?usize = null;
    switch (text[pointer]) {
        ',' => {
            pointer += 1;
            const digit4_end_index = std.mem.indexOfNonePos(u8, text, pointer, digits) orelse return null;
            digit4 = try std.fmt.parseInt(u8, text[pointer..digit4_end_index], 10);
            pointer = digit4_end_index;
        },
        ' ' => {},
        else => return null,
    }

    // make sure that we are at the end only the ` @@` should be left
    if (pointer + 3 != text.len) return null;

    return .{ digit1, digit2, digit3, digit4 };
}

const testing = std.testing;

test "patch regex header" {
    var result = try matchPatchHeader("Some string");
    try testing.expect(result == null);

    result = try matchPatchHeader("@@ -32,0 +53 @@");
    try testing.expect(result != null);
    try testing.expect(result.?[0] == 32);
    try testing.expect(result.?[1] == 0);
    try testing.expect(result.?[2] == 53);
    try testing.expect(result.?[3] == null);

    result = try matchPatchHeader("@@ -15 +20,42 @@");
    try testing.expect(result != null);
    try testing.expect(result.?[0] == 15);
    try testing.expect(result.?[1] == null);
    try testing.expect(result.?[2] == 20);
    try testing.expect(result.?[3] == 42);
}

comptime {
    _ = @import("patch_tests.zig");
}
