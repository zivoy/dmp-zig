const DMP = @import("diffmatchpatch.zig");
const std = @import("std");
const utils = @import("utils.zig");

const Allocator = std.mem.Allocator;

const DiffPrivate = @import("diff_private.zig");

pub const diff_max_duration = std.math.maxInt(u64);

pub const DiffError = error{
    DeltaContainsIlligalOperation,
    DeltaContainsInvalidUTF8,
    DeltaContainsNegetiveNumber,
    DeltaLongerThenSource,
    DeltaShorterThenSource,
};

pub const DiffOperation = enum(i2) {
    delete = -1,
    equal = 0,
    insert = 1,
};

pub const Diff = struct {
    operation: DiffOperation,
    text: []u8,

    pub fn fromString(allocator: std.mem.Allocator, text: [:0]const u8, operation: DiffOperation) std.mem.Allocator.Error!Diff {
        return Diff.fromSlice(allocator, text, operation);
    }
    pub fn fromSlice(allocator: std.mem.Allocator, text: []const u8, operation: DiffOperation) std.mem.Allocator.Error!Diff {
        const owned_text = try allocator.alloc(u8, text.len);
        @memcpy(owned_text.ptr, text);
        return .{
            .text = owned_text,
            .operation = operation,
        };
    }

    pub fn copy(self: Diff, allocator: std.mem.Allocator) std.mem.Allocator.Error!Diff {
        return Diff.fromSlice(allocator, self.text, self.operation);
    }

    pub fn deinit(self: *Diff, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
        self.* = undefined;
    }
};

///Find the differences between two texts.
///Run a faster, slightly less optimal diff.
///This method allows the 'checklines' of `diffMainStringStringBool` to be optional.
///Most of the time checklines is wanted, so default to true.
pub fn diffMainStringString(allocator: Allocator, diff_timeout: f32, text1: []const u8, text2: []const u8) ![]Diff {
    return diffMainStringStringBool(allocator, diff_timeout, text1, text2, true);
}

///Find the differences between two texts.
pub fn diffMainStringStringBool(allocator: Allocator, diff_timeout: f32, text1: []const u8, text2: []const u8, check_lines: bool) ![]Diff {
    var deadline: u64 = undefined;
    if (diff_timeout > 0) {
        deadline = @intFromFloat(diff_timeout * std.time.ns_per_s);
    } else {
        deadline = diff_max_duration;
    }
    return DiffPrivate.diffMainStringStringBoolTimeout(allocator, diff_timeout, text1, text2, check_lines, deadline);
}

///Determine the common prefix of two strings.
pub fn diffCommonPrefix(text1: []const u8, text2: []const u8) usize {
    const n = @min(text1.len, text2.len);
    for (0..n) |i| {
        if (text1[i] != text2[i]) {
            return i;
        }
    }
    return n;
}

///Determine the common suffix of two strings.
pub fn diffCommonSuffix(text1: []const u8, text2: []const u8) usize {
    const n = @min(text1.len, text2.len);
    for (1..n + 1) |i| {
        if (text1[text1.len - i] != text2[text2.len - i]) {
            return i - 1;
        }
    }
    return n;
}

///Reduce the number of edits by eliminating semantically trivial equalities.
pub fn diffCleanupSemantic(allocator: Allocator, diffs: *[]Diff) !void {
    if (diffs.len == 0) return;
    var diff_list = std.ArrayList(Diff).fromOwnedSlice(allocator, diffs.*);
    defer diff_list.deinit();
    errdefer if (diff_list.toOwnedSlice()) |diff_o| {
        diffs.* = diff_o;
    } else |_| {};

    var changes = false;

    // Stack of indices where equalities are found.
    var equalities = try std.ArrayList(usize).initCapacity(allocator, diffs.len);
    defer equalities.deinit();

    var pointer: usize = 0;
    var last_equality: ?[]const u8 = null;

    // Number of characters that changed prior to the equality.
    var length_insertions1: usize = 0;
    var length_deletions1: usize = 0;

    // Number of characters that changed after the equality.
    var length_insertions2: usize = 0;
    var length_deletions2: usize = 0;

    while (pointer < diff_list.items.len) {
        const diff = diff_list.items[pointer];
        if (diff.operation == .equal) {
            // Equalitfound.
            equalities.appendAssumeCapacity(pointer);
            length_insertions1 = length_insertions2;
            length_deletions1 = length_deletions2;
            length_insertions2 = 0;
            length_deletions2 = 0;
            last_equality = diff.text;

            pointer += 1;
            continue;
        }

        // An insertion or deletion.
        if (diff.operation == .insert) {
            length_insertions2 += utils.utf8CountCodepointsPanic(diff.text);
        } else {
            length_deletions2 += utils.utf8CountCodepointsPanic(diff.text);
        }

        // Eliminate an equality that is smaller or equal to the edits on both sides of it.
        const difference1 = @max(length_insertions1, length_deletions1);
        const difference2 = @max(length_insertions2, length_deletions2);

        if (blk: {
            if (last_equality == null) break :blk false;
            const last_equality_count = utils.utf8CountCodepointsPanic(last_equality.?);
            break :blk last_equality_count <= difference1 and last_equality_count <= difference2;
        }) {
            // Duplicate record
            try diff_list.insert(equalities.getLast(), try Diff.fromSlice(allocator, last_equality.?, .delete));

            // Change second copy to insert.
            diff_list.items[equalities.getLast() + 1].operation = .insert;
            // Thow away the equality that was deleted.
            equalities.items.len -= 1;

            if (equalities.items.len > 0) {
                // Throw away the previous equality (it needs to be reevaluated).
                equalities.items.len -= 1;
            }

            if (equalities.items.len > 0) {
                pointer = equalities.getLast() + 1;
            } else {
                pointer = 0;
            }

            // reset the counters
            length_insertions1 = 0;
            length_deletions1 = 0;
            length_insertions2 = 0;
            length_deletions2 = 0;
            last_equality = null;
            changes = true;
            continue;
        }

        pointer += 1;
    }

    // Normalize the diff.
    diffs.* = try diff_list.toOwnedSlice();
    if (changes) {
        try diffCleanupMerge(allocator, diffs);
    }
    try diffCleanupSemanticLossless(allocator, diffs);
    diff_list.capacity = diffs.len;
    diff_list.items = diffs.*;

    // Find any overlaps between deletions and insertions.
    // e.g: <del>abcxxx</del><ins>xxxdef</ins>
    //   -> <del>abc</del>xxx<ins>def</ins>
    // e.g: <del>xxxabc</del><ins>defxxx</ins>
    //   -> <ins>def</ins>xxx<del>abc</del>
    // Only extract an overlap if it is as big as the edit ahead or behind it.
    pointer = 1;
    while (pointer < diff_list.items.len) {
        var last_diff = diff_list.items[pointer - 1];
        var diff = diff_list.items[pointer];
        if (last_diff.operation == .delete and diff.operation == .insert) {
            const overlap_length1 = DiffPrivate.diffCommonOverlap(last_diff.text, diff.text);
            const overlap_length2 = DiffPrivate.diffCommonOverlap(diff.text, last_diff.text);
            if (overlap_length1 >= overlap_length2) {
                if (@as(f64, @floatFromInt(overlap_length1)) >= @as(f64, @floatFromInt(utils.utf8CountCodepointsPanic(last_diff.text))) / 2 or
                    @as(f64, @floatFromInt(overlap_length1)) >= @as(f64, @floatFromInt(utils.utf8CountCodepointsPanic(diff.text))) / 2)
                {
                    // Overlap found. Insert an equality and trim the surrounding edits.
                    try diff_list.insert(pointer, try Diff.fromSlice(allocator, diff.text[0..overlap_length1], .equal));

                    _ = try utils.resize(u8, allocator, &diff_list.items[pointer - 1].text, last_diff.text.len - overlap_length1);

                    std.mem.copyForwards(u8, diff.text[0 .. diff.text.len - overlap_length1], diff.text[overlap_length1..]);
                    _ = try utils.resize(u8, allocator, &diff_list.items[pointer + 1].text, diff.text.len - overlap_length1);

                    pointer += 1;
                }
            } else {
                if (@as(f64, @floatFromInt(overlap_length2)) >= @as(f64, @floatFromInt(utils.utf8CountCodepointsPanic(last_diff.text))) / 2 or
                    @as(f64, @floatFromInt(overlap_length2)) >= @as(f64, @floatFromInt(utils.utf8CountCodepointsPanic(diff.text))) / 2)
                {
                    // Reverse overlap found. Insert an equality and swap and trim the surrounding edits.
                    try diff_list.insert(pointer, try Diff.fromSlice(allocator, last_diff.text[0..overlap_length2], .equal));
                    diff_list.items[pointer - 1].operation = .insert;
                    diff_list.items[pointer - 1].text = diff.text;
                    diff_list.items[pointer + 1].operation = .delete;
                    diff_list.items[pointer + 1].text = last_diff.text;

                    _ = try utils.resize(u8, allocator, &diff_list.items[pointer - 1].text, diff.text.len - overlap_length2);

                    std.mem.copyForwards(
                        u8,
                        diff_list.items[pointer + 1].text[0 .. last_diff.text.len - overlap_length2],
                        last_diff.text[overlap_length2..],
                    );
                    _ = try utils.resize(u8, allocator, &diff_list.items[pointer + 1].text, last_diff.text.len - overlap_length2);

                    pointer += 1;
                }
            }
            pointer += 1;
        }
        pointer += 1;
    }

    diffs.* = try diff_list.toOwnedSlice();
}

///Look for single edits surrounded on both sides by equalities
///which can be shifted sideways to align the edit to a word boundary.
///e.g: The c<ins>at c</ins>ame. -> The <ins>cat </ins>came.
pub fn diffCleanupSemanticLossless(allocator: Allocator, diffs: *[]Diff) !void {
    if (diffs.len == 0) return;

    var diff_list = std.ArrayList(Diff).fromOwnedSlice(allocator, diffs.*);
    defer diff_list.deinit();
    errdefer if (diff_list.toOwnedSlice()) |diff_o| {
        diffs.* = diff_o;
    } else |_| {};

    // Intentionally ignore the first and last element (don't need checking).
    var pointer: usize = 1;
    while (pointer < diff_list.items.len - 1) {
        if (diff_list.items[pointer - 1].operation == .equal and
            diff_list.items[pointer + 1].operation == .equal)
        {
            // This is a single edit surrounded by equalities.
            var equality1 = std.ArrayList(u8).init(allocator);
            defer equality1.deinit();
            try equality1.appendSlice(diff_list.items[pointer - 1].text);

            var edit = std.ArrayList(u8).init(allocator);
            defer edit.deinit();
            try edit.appendSlice(diff_list.items[pointer].text);

            var equality2 = std.ArrayList(u8).init(allocator);
            defer equality2.deinit();
            try equality2.appendSlice(diff_list.items[pointer + 1].text);

            // First, shift the edit as far left as possible.
            const common_offset = diffCommonSuffix(equality1.items, edit.items);
            if (common_offset > 0) {
                equality1.items.len -= common_offset;

                try equality2.insertSlice(0, edit.items[edit.items.len - common_offset ..]);

                std.mem.copyBackwards(u8, edit.items[common_offset..], edit.items[0 .. edit.items.len - common_offset]);
                std.mem.copyForwards(u8, edit.items[0..common_offset], equality2.items[0..common_offset]);
            }

            // Second, step character by character right, looking for the best fit.
            // these are used to chop up the lists
            var best_equality1_len = equality1.items.len;
            var edit_start: usize = 0;
            var equality2_start: usize = 0;
            var best_score = DiffPrivate.diffCleanupSemanticScore(equality1.items, edit.items) +
                DiffPrivate.diffCleanupSemanticScore(edit.items, equality2.items);

            while (edit.items.len - edit_start != 0 and
                equality2.items.len - equality2_start != 0)
            {
                const cp_len = std.unicode.utf8ByteSequenceLength(edit.items[edit_start]) catch break;
                if (equality2.items.len - equality2_start < cp_len or
                    !std.mem.eql(u8, edit.items[edit_start .. edit_start + cp_len], equality2.items[equality2_start .. equality2_start + cp_len]))
                {
                    break;
                }

                try equality1.appendSlice(edit.items[edit_start .. edit_start + cp_len]);

                try edit.appendSlice(equality2.items[equality2_start .. equality2_start + cp_len]);
                edit_start += cp_len;

                equality2_start += cp_len;

                const score = DiffPrivate.diffCleanupSemanticScore(equality1.items, edit.items[edit_start..]) +
                    DiffPrivate.diffCleanupSemanticScore(edit.items[edit_start..], equality2.items[equality2_start..]);
                // The >= encourages trailing rather than leading whitespace on edits.
                if (score >= best_score) {
                    best_score = score;
                    best_equality1_len = equality1.items.len;

                    std.mem.copyForwards(u8, edit.items[0 .. edit.items.len - edit_start], edit.items[edit_start..]);
                    edit.items.len -= edit_start;
                    edit_start = 0;

                    std.mem.copyForwards(u8, equality2.items[0 .. equality2.items.len - equality2_start], equality2.items[equality2_start..]);
                    equality2.items.len -= equality2_start;
                    equality2_start = 0;
                }
            }

            if (!std.mem.eql(u8, diff_list.items[pointer - 1].text, equality1.items[0..best_equality1_len])) {
                // We have an improvement, save it back to the diff.
                if (best_equality1_len != 0) {
                    allocator.free(diff_list.items[pointer - 1].text);
                    equality1.items.len = best_equality1_len;
                    diff_list.items[pointer - 1].text = try equality1.toOwnedSlice();
                } else {
                    var last_diff = diff_list.orderedRemove(pointer - 1);
                    last_diff.deinit(allocator);
                    pointer -= 1;
                }

                allocator.free(diff_list.items[pointer].text);
                edit.items.len -= edit_start;
                diff_list.items[pointer].text = try edit.toOwnedSlice();

                if (equality2.items.len - equality2_start != 0) {
                    allocator.free(diff_list.items[pointer + 1].text);
                    diff_list.items[pointer + 1].text = try equality2.toOwnedSlice();
                } else {
                    var next_diff = diff_list.orderedRemove(pointer + 1);
                    next_diff.deinit(allocator);
                    pointer -= 1;
                }
            }
        }
        pointer += 1;
    }

    diffs.* = try diff_list.toOwnedSlice();
}

///Reduce the number of edits by eliminating operationally trivial equalities.
pub fn diffCleanupEfficiency(allocator: Allocator, diff_edit_cost: u16, diffs: *[]Diff) !void {
    if (diffs.len == 0) return;

    var diff_list = std.ArrayList(Diff).fromOwnedSlice(allocator, diffs.*);
    defer diff_list.deinit();
    errdefer if (diff_list.toOwnedSlice()) |diff_o| {
        diffs.* = diff_o;
    } else |_| {};

    var changes = false;

    var equalities = try std.ArrayList(usize).initCapacity(allocator, diff_list.items.len);
    defer equalities.deinit();

    var last_equality: ?[]const u8 = null;
    var pointer: usize = 0;
    // Is there an insertion operation before the last equality.
    var pre_insert = false;
    // Is there a deletion operation before the last equality.
    var pre_delete = false;
    // Is there an insertion operation after the last equality.
    var post_insert = false;
    // Is there a deletion operation after the last equality.
    var post_delete = false;

    while (pointer < diff_list.items.len) {
        const diff = diff_list.items[pointer];
        if (diff.operation == .equal) {
            // Equality found.
            if (diff.text.len < diff_edit_cost and (post_insert or post_delete)) {
                // Candidate found.
                equalities.appendAssumeCapacity(pointer);
                pre_insert = post_insert;
                pre_delete = post_delete;
                last_equality = diff.text;
            } else {
                // Not a candidate and can never become one.
                equalities.clearRetainingCapacity();
                last_equality = null;
            }
            post_insert = false;
            post_delete = false;

            pointer += 1;
            continue;
        }

        // An insertion or deletion.
        if (diff.operation == .delete) {
            post_delete = true;
        } else {
            post_insert = true;
        }

        // Five types to be split:
        // <ins>A</ins><del>B</del>XY<ins>C</ins><del>D</del>
        // <ins>A</ins>X<ins>C</ins><del>D</del>
        // <ins>A</ins><del>B</del>X<ins>C</ins>
        // <ins>A</del>X<ins>C</ins><del>D</del>
        // <ins>A</ins><del>B</del>X<del>C</del>
        const sum_pres = blk: {
            var int: u3 = 0;
            if (pre_insert) int += 1;
            if (pre_delete) int += 1;
            if (post_insert) int += 1;
            if (post_delete) int += 1;
            break :blk int;
        };
        if (last_equality != null and
            ((pre_insert and pre_delete and post_insert and post_delete) or
            ((last_equality.?.len < diff_edit_cost / 2) and sum_pres == 3)))
        {
            // Duplocate record.
            try diff_list.insert(equalities.getLast(), try Diff.fromSlice(allocator, last_equality.?, .delete));

            // Change second copy to insert.
            diff_list.items[equalities.getLast() + 1].operation = .insert;
            // Throw away equality that was just deleted.
            equalities.items.len -= 1;
            last_equality = null;

            if (pre_insert and pre_delete) {
                // No changes made which could affect previous entry, keep going.
                post_insert = true;
                post_delete = true;
                equalities.clearRetainingCapacity();
                pointer += 1;
            } else {
                if (equalities.items.len > 0) {
                    equalities.items.len -= 1;
                }
                if (equalities.items.len > 0) {
                    pointer = equalities.getLast() + 1;
                } else {
                    pointer = 0;
                }
                post_insert = false;
                post_delete = false;
            }
            changes = true;
            continue;
        }

        pointer += 1;
    }

    if (changes) {
        diffs.* = try diff_list.toOwnedSlice();
        try diffCleanupMerge(allocator, diffs);
        diff_list.capacity = diffs.len;
        diff_list.items = diffs.*;
    }

    diffs.* = try diff_list.toOwnedSlice();
}

///Reorder and merge like edit sections.  Merge equalities.
///Any edit section can move as long as it doesn't cross an equality.
pub fn diffCleanupMerge(allocator: Allocator, diffs: *[]Diff) !void {
    if (diffs.len == 0) return;
    var diff_list = std.ArrayList(Diff).fromOwnedSlice(allocator, diffs.*);
    defer diff_list.deinit();
    errdefer if (diff_list.toOwnedSlice()) |diff_o| {
        diffs.* = diff_o;
    } else |_| {};

    // Add a dummy entry at the end.
    try diff_list.append(try Diff.fromString(allocator, "", .equal));
    var pointer: usize = 0;
    var count_delete: usize = 0;
    var count_insert: usize = 0;
    var common_length: usize = 0;

    var text_insert = std.ArrayList(u8).init(allocator);
    defer text_insert.deinit();
    var text_delete = std.ArrayList(u8).init(allocator);
    defer text_delete.deinit();

    while (pointer < diff_list.items.len) {
        var diff = diff_list.items[pointer];
        switch (diff.operation) {
            .insert => {
                count_insert += 1;
                try text_insert.appendSlice(diff.text);
                pointer += 1;
            },
            .delete => {
                count_delete += 1;
                try text_delete.appendSlice(diff.text);
                pointer += 1;
            },
            .equal => {
                // Upon reaching an equality, check for prior redundancies.
                if (count_delete + count_insert > 1) {
                    if (count_delete != 0 and count_insert != 0) {
                        // Factor out any common prefixies.
                        common_length = diffCommonPrefix(text_insert.items, text_delete.items);
                        if (common_length != 0) {
                            const x = pointer - count_delete - count_insert;
                            const common_text = text_insert.items[0..common_length];
                            if (x > 0 and diff_list.items[x - 1].operation == .equal) {
                                const old_len = try utils.resize(u8, allocator, &diff_list.items[x - 1].text, diff_list.items[x - 1].text.len + common_length);
                                std.mem.copyForwards(u8, diff_list.items[x - 1].text[old_len .. old_len + common_length], common_text);
                            } else {
                                try diff_list.insert(0, try Diff.fromSlice(allocator, common_text, .equal));
                                pointer += 1;
                            }

                            std.mem.copyForwards(u8, text_insert.items[0 .. text_insert.items.len - common_length], text_insert.items[common_length..]);
                            text_insert.items.len -= common_length;
                            std.mem.copyForwards(u8, text_delete.items[0 .. text_delete.items.len - common_length], text_delete.items[common_length..]);
                            text_delete.items.len -= common_length;
                        }

                        // Factor out any common suffixies.
                        common_length = diffCommonSuffix(text_insert.items, text_delete.items);
                        if (common_length != 0) {
                            const old_len = try utils.resize(u8, allocator, &diff.text, diff.text.len + common_length);
                            std.mem.copyBackwards(u8, diff.text[common_length..], diff.text[0..old_len]);
                            std.mem.copyForwards(u8, diff.text[0..common_length], text_insert.items[text_insert.items.len - common_length ..]);

                            text_insert.items.len -= common_length;
                            text_delete.items.len -= common_length;
                            diff_list.items[pointer] = diff;
                        }
                    }

                    // Delete the offending records and add the merged ones.
                    const del_count = count_delete + count_insert;
                    if (count_delete == 0) {
                        const delete_loc = pointer - count_insert;
                        for (diff_list.items[delete_loc .. delete_loc + del_count]) |*d| d.deinit(allocator);
                        try diff_list.replaceRange(delete_loc, del_count, &.{try Diff.fromSlice(allocator, text_insert.items, .insert)});
                    } else if (count_insert == 0) {
                        const delete_loc = pointer - count_delete;
                        for (diff_list.items[delete_loc .. delete_loc + del_count]) |*d| d.deinit(allocator);
                        try diff_list.replaceRange(delete_loc, del_count, &.{try Diff.fromSlice(allocator, text_delete.items, .delete)});
                    } else {
                        const delete_loc = pointer - count_delete - count_insert;
                        for (diff_list.items[delete_loc .. delete_loc + del_count]) |*d| d.deinit(allocator);
                        try diff_list.replaceRange(delete_loc, del_count, &.{
                            try Diff.fromSlice(allocator, text_delete.items, .delete),
                            try Diff.fromSlice(allocator, text_insert.items, .insert),
                        });
                    }

                    pointer = pointer - count_delete - count_insert + 1;
                    if (count_delete != 0) {
                        pointer += 1;
                    }
                    if (count_insert != 0) {
                        pointer += 1;
                    }
                } else if (pointer != 0 and diff_list.items[pointer - 1].operation == .equal) {
                    // Merge this equality with the previous one.
                    var last_diff = diff_list.items[pointer - 1];
                    const old_len = try utils.resize(u8, allocator, &last_diff.text, last_diff.text.len + diff.text.len);
                    std.mem.copyForwards(u8, last_diff.text[old_len..], diff.text);

                    diff_list.items[pointer - 1] = last_diff;

                    diff.deinit(allocator);
                    _ = diff_list.orderedRemove(pointer);
                } else {
                    pointer += 1;
                }
                count_insert = 0;
                count_delete = 0;
                text_insert.clearRetainingCapacity();
                text_delete.clearRetainingCapacity();
            },
        }
    }

    if (diff_list.getLast().text.len == 0) {
        // Remove the dummy entry at the end.
        diff_list.items[diff_list.items.len - 1].deinit(allocator);
        _ = diff_list.orderedRemove(diff_list.items.len - 1);
    }

    //Second pass: look for single edits surrounded on both sides by equalities
    //which can be shifted sideways to eliminate an equality.
    //e.g: A<ins>BA</ins>C -> <ins>AB</ins>AC
    var changes = false;
    pointer = 1;
    // Intentionally ignore the first and last element (don't need checking).
    while (diff_list.items.len > 2 and pointer < diff_list.items.len - 1) {
        var diff = diff_list.items[pointer];
        var last_diff = diff_list.items[pointer - 1];
        var next_diff = diff_list.items[pointer + 1];
        if (last_diff.operation == .equal and next_diff.operation == .equal) {
            // This is a single edit surrounded by equalities.
            if (std.mem.endsWith(u8, diff.text, last_diff.text)) {
                // Shift the edit over the previous equality.
                std.mem.copyBackwards(u8, diff.text[last_diff.text.len..diff.text.len], diff.text[0 .. diff.text.len - last_diff.text.len]);
                std.mem.copyForwards(u8, diff.text[0..last_diff.text.len], last_diff.text);

                const old_len = try utils.resize(u8, allocator, &next_diff.text, last_diff.text.len + next_diff.text.len);
                std.mem.copyBackwards(u8, next_diff.text[last_diff.text.len..], next_diff.text[0..old_len]);
                std.mem.copyForwards(u8, next_diff.text[0..last_diff.text.len], last_diff.text);

                diff_list.items[pointer + 1] = next_diff;

                last_diff.deinit(allocator);
                _ = diff_list.orderedRemove(pointer - 1);
                changes = true;
            } else if (std.mem.startsWith(u8, diff.text, next_diff.text)) {
                // Shift the edit over the next equality.
                // diffs[pointer-1].Text += next_diff.text
                const old_len = try utils.resize(u8, allocator, &last_diff.text, last_diff.text.len + next_diff.text.len);
                std.mem.copyForwards(u8, last_diff.text[old_len..], next_diff.text);

                std.mem.copyForwards(u8, diff.text[0 .. diff.text.len - next_diff.text.len], diff.text[next_diff.text.len..]);
                std.mem.copyForwards(u8, diff.text[diff.text.len - next_diff.text.len ..], next_diff.text);

                diff_list.items[pointer - 1] = last_diff;

                next_diff.deinit(allocator);
                _ = diff_list.orderedRemove(pointer + 1);
                changes = true;
            }
        }
        pointer += 1;
    }

    diffs.* = try diff_list.toOwnedSlice();

    // If shifts were made, the diff needs reordering and another shift sweep.
    if (changes) {
        try diffCleanupMerge(allocator, diffs);
    }
}

///loc is a location in text1, compute and return the equivalent location in text2.
///e.g. "The cat" vs "The big cat", 1->1, 5->8
pub fn diffXIndex(diffs: []Diff, loc: usize) usize {
    var chars1: usize = 0;
    var chars2: usize = 0;
    var last_chars1: usize = 0;
    var last_chars2: usize = 0;
    var last_diff: ?Diff = undefined;
    for (diffs) |diff| {
        if (diff.operation != .insert) {
            // Equality or deletion.
            chars1 += diff.text.len;
        }
        if (diff.operation != .delete) {
            // Equality or insertion.
            chars2 += diff.text.len;
        }
        if (chars1 > loc) {
            // Overshot the location.
            last_diff = diff;
            break;
        }
        last_chars1 = chars1;
        last_chars2 = chars2;
    }

    if (last_diff != null and last_diff.?.operation == .delete) {
        // The location was deleted.
        return last_chars2;
    }
    // Add the remaining character length.
    return last_chars2 + (loc - last_chars1);
}

///Convert a Diff list into a pretty HTML report.
pub fn diffPrettyHtml(allocator: Allocator, diffs: []Diff) Allocator.Error![:0]const u8 {
    var text = std.ArrayList(u8).init(allocator);
    defer text.deinit();
    try diffPrettyHtmlWriter(text.writer(), diffs);
    return text.toOwnedSliceSentinel(0);
}
pub fn diffPrettyHtmlWriter(writer: anytype, diffs: []Diff) @TypeOf(writer).Error!void {
    for (diffs) |diff|
        switch (diff.operation) {
            .equal => {
                try writer.writeAll("<span>");
                try writeHtmlSanitized(writer, diff.text);
                try writer.writeAll("</span>");
            },
            .delete => {
                try writer.writeAll("<del style=\"background:#ffe6e6;\">");
                try writeHtmlSanitized(writer, diff.text);
                try writer.writeAll("</del>");
            },
            .insert => {
                try writer.writeAll("<ins style=\"background:#e6ffe6;\">");
                try writeHtmlSanitized(writer, diff.text);
                try writer.writeAll("</ins>");
            },
        };
}
fn writeHtmlSanitized(writer: anytype, text: []const u8) @TypeOf(writer).Error!void {
    var start: usize = 0;
    for (text, 0..) |char, i| {
        const replacement: []const u8 = switch (char) {
            '\n' => "&para;<br>",
            '<' => "&lt;",
            '>' => "&gt;",
            '&' => "&amp;",
            else => continue,
        };
        try writer.print("{s}{s}", .{ text[start..i], replacement });
        start = i + 1;
    }
    try writer.writeAll(text[start..]);
}

///Converts a []Diff into a colored text report.
pub fn diffPrettyText(allocator: Allocator, diffs: []Diff) Allocator.Error![:0]const u8 {
    var text = std.ArrayList(u8).init(allocator);
    defer text.deinit();
    try diffPrettyTextWriter(text.writer(), diffs);
    return text.toOwnedSliceSentinel(0);
}
pub fn diffPrettyTextWriter(writer: anytype, diffs: []Diff) @TypeOf(writer).Error!void {
    for (diffs) |diff|
        switch (diff.operation) {
            .equal => try writer.writeAll(diff.text),
            .insert => try writer.print("\x1b[32m{s}\x1b[0m", .{diff.text}),
            .delete => try writer.print("\x1b[31m{s}\x1b[0m", .{diff.text}),
        };
}

///Compute and return the source text (all equalities and deletions).
pub fn diffText1(allocator: Allocator, diffs: []Diff) Allocator.Error![:0]const u8 {
    var len: usize = 0;
    for (diffs) |diff| if (diff.operation != .insert) {
        len += diff.text.len;
    };

    var string = try allocator.allocSentinel(u8, len, 0);
    errdefer allocator.free(string);

    var ptr: usize = 0;
    for (diffs) |diff| if (diff.operation != .insert) {
        @memcpy(string[ptr .. ptr + diff.text.len], diff.text);
        ptr += diff.text.len;
    };
    std.debug.assert(ptr == len and len == string.len);

    return string;
}

///Compute and return the destination text (all equalities and insertions).
pub fn diffText2(allocator: Allocator, diffs: []Diff) Allocator.Error![:0]const u8 {
    var len: usize = 0;
    for (diffs) |diff| if (diff.operation != .delete) {
        len += diff.text.len;
    };

    var string = try allocator.allocSentinel(u8, len, 0);
    errdefer allocator.free(string);

    var ptr: usize = 0;
    for (diffs) |diff| if (diff.operation != .delete) {
        @memcpy(string[ptr .. ptr + diff.text.len], diff.text);
        ptr += diff.text.len;
    };
    std.debug.assert(ptr == len and len == string.len);

    return string;
}

///Compute the Levenshtein distance; the number of inserted, deleted or substituted characters.
pub fn diffLevenshtein(diffs: []Diff) usize {
    var levenshtein: usize = 0;
    var insertions: usize = 0;
    var deletions: usize = 0;

    for (diffs) |diff| switch (diff.operation) {
        .insert => insertions += utils.utf8CountCodepointsPanic(diff.text),
        .delete => deletions += utils.utf8CountCodepointsPanic(diff.text),
        .equal => {
            // A deletion and an insertion is one substitution.
            levenshtein += @max(insertions, deletions);
            insertions = 0;
            deletions = 0;
        },
    };
    levenshtein += @max(insertions, deletions);
    return levenshtein;
}

///Crush the diff into an encoded string which describes the operations
///required to transform text1 into text2.
///E.g. =3\t-2\t+ing  -> Keep 3 chars, delete 2 chars, insert 'ing'.
///Operations are tab-separated.  Inserted text is escaped using %xx notation.
pub fn diffToDelta(allocator: Allocator, diffs: []Diff) Allocator.Error![:0]const u8 {
    var text = std.ArrayList(u8).init(allocator);
    defer text.deinit();
    try diffToDeltaWriter(text.writer(), diffs);
    return text.toOwnedSliceSentinel(0);
}
pub fn diffToDeltaWriter(writer: anytype, diffs: []Diff) @TypeOf(writer).Error!void {
    for (diffs, 1..) |diff, i| {
        switch (diff.operation) {
            .equal => try writer.print("={d}", .{utils.utf8CountCodepointsPanic(diff.text)}),
            .delete => try writer.print("-{d}", .{utils.utf8CountCodepointsPanic(diff.text)}),
            .insert => {
                try writer.writeByte('+');
                try utils.encodeURI(writer, diff.text);
            },
        }
        if (diffs.len != i) try writer.writeByte('\t');
    }
}

///Given the original text1, and an encoded string which describes the
///operations required to transform text1 into text2, compute the full diff.
pub fn diffFromDelta(allocator: Allocator, text1: []const u8, delta: []const u8) (DiffError || std.fmt.ParseIntError || Allocator.Error)![]Diff {
    var diffs = std.ArrayList(Diff).init(allocator);
    defer diffs.deinit();
    errdefer for (diffs.items) |*diff| diff.deinit(allocator);

    var pointer: usize = 0;
    var tokens = std.mem.splitScalar(u8, delta, '\t');
    while (tokens.next()) |token| {
        if (token.len == 0) {
            // Blank tokens are ok (from a trailing \t).
            continue;
        }

        // Each token begins with a one character parameter which specifies the
        // operation of this token (delete, insert, equality).
        const param = token[1..];
        switch (token[0]) {
            '+' => {
                const param_encoded = try allocator.alloc(u8, param.len);
                defer allocator.free(param_encoded);
                @memcpy(param_encoded, param);
                const line = std.Uri.percentDecodeInPlace(param_encoded);
                if (!std.unicode.utf8ValidateSlice(line)) return DiffError.DeltaContainsInvalidUTF8;
                try diffs.append(try Diff.fromSlice(allocator, line, .insert));
            },
            '-', '=' => {
                const count = try std.fmt.parseInt(isize, param, 10);
                if (count < 0) return DiffError.DeltaContainsNegetiveNumber;

                if (pointer > text1.len) return DiffError.DeltaLongerThenSource;

                var len: usize = 0;
                for (0..@intCast(count)) |_| {
                    if (pointer + len >= text1.len) return DiffError.DeltaLongerThenSource;
                    len += std.unicode.utf8ByteSequenceLength(text1[pointer + len]) catch return DiffError.DeltaContainsInvalidUTF8;
                }
                if (pointer + len > text1.len) return DiffError.DeltaLongerThenSource;

                const line = text1[pointer .. pointer + len];
                pointer += len;
                if (token[0] == '=') {
                    try diffs.append(try Diff.fromSlice(allocator, line, .equal));
                } else {
                    try diffs.append(try Diff.fromSlice(allocator, line, .delete));
                }
            },
            else => return DiffError.DeltaContainsIlligalOperation,
        }
    }
    if (pointer > text1.len) return DiffError.DeltaLongerThenSource;
    if (pointer < text1.len) return DiffError.DeltaShorterThenSource;
    return diffs.toOwnedSlice();
}
