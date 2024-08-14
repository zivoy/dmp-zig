const std = @import("std");
const utils = @import("utils.zig");
const DMP = @import("diffmatchpatch.zig");
const diff_funcs = @import("diff.zig");

const Allocator = std.mem.Allocator;

pub const LineArray = struct {
    const S = @This();
    items: *[][]const u8,
    array_list: *std.ArrayListUnmanaged([]const u8),
    allocator: Allocator,
    pub fn init(allocator: Allocator) !S {
        var array_list = try allocator.create(std.ArrayListUnmanaged([]const u8));
        array_list.* = try std.ArrayListUnmanaged([]const u8).initCapacity(allocator, 0);
        return .{
            .items = &array_list.items,
            .array_list = array_list,
            .allocator = allocator,
        };
    }
    pub fn fromSlice(allocator: Allocator, slice: [][]const u8) !S {
        var s = try S.init(allocator);
        for (slice) |item| try s.append(item);
        return s;
    }
    pub fn deinit(self: *S) void {
        for (self.array_list.items) |item| self.allocator.free(item);
        self.array_list.deinit(self.allocator);
        self.allocator.destroy(self.array_list);
        self.items = undefined;
    }
    pub fn append(self: S, text: []const u8) Allocator.Error!void {
        const text_copy = try self.allocator.alloc(u8, text.len);
        @memcpy(text_copy, text);
        try self.array_list.append(self.allocator, text_copy);
    }
};

///Find the differences between two texts.  Simplifies the problem by
///stripping any common prefix or suffix off the texts before diffing.
pub fn diffMainStringStringBoolTimeout(allocator: Allocator, diff_timeout: f32, text1: []const u8, text2: []const u8, check_lines: bool, ns_time_limit: u64) ![]DMP.Diff {
    var timer = try std.time.Timer.start();
    return diffMainStringStringBoolTimeoutTimer(allocator, diff_timeout, text1, text2, check_lines, ns_time_limit, &timer);
}
fn diffMainStringStringBoolTimeoutTimer(allocator: Allocator, diff_timeout: f32, text1: []const u8, text2: []const u8, check_lines: bool, ns_time_limit: u64, timer: *std.time.Timer) ![]DMP.Diff {
    var diffs = std.ArrayList(DMP.Diff).init(allocator);
    defer diffs.deinit();
    errdefer for (diffs.items) |diff| diff.deinit(allocator);

    // Check for equality (speedup).
    if (std.mem.eql(u8, text1, text2)) {
        if (text1.len != 0) {
            try diffs.append(try DMP.Diff.fromSlice(allocator, text1, .equal));
        }
        return diffs.toOwnedSlice();
    }

    // Trim off common prefix (speedup).
    var common_length = diff_funcs.diffCommonPrefix(text1, text2);
    const common_prefix = text1[0..common_length];
    var text_chopped1 = text1[common_length..];
    var text_chopped2 = text2[common_length..];

    // Trim off common suffix (speedup).
    common_length = diff_funcs.diffCommonSuffix(text_chopped1, text_chopped2);
    const common_suffix = text_chopped1[text_chopped1.len - common_length ..];
    text_chopped1 = text_chopped1[0 .. text_chopped1.len - common_length];
    text_chopped2 = text_chopped2[0 .. text_chopped2.len - common_length];

    // Compute the diff on the middle block.
    {
        const computed_diffs = try diffComputeTimer(allocator, diff_timeout, text_chopped1, text_chopped2, check_lines, ns_time_limit, timer);
        defer allocator.free(computed_diffs);
        try diffs.appendSlice(computed_diffs);
    }

    // Restore the prefix and suffix.
    if (common_prefix.len != 0) {
        try diffs.insert(0, try DMP.Diff.fromSlice(allocator, common_prefix, .equal));
    }
    if (common_suffix.len != 0) {
        try diffs.append(try DMP.Diff.fromSlice(allocator, common_suffix, .equal));
    }

    var res = try diffs.toOwnedSlice();
    try diff_funcs.diffCleanupMerge(allocator, &res);

    return res;
}

///Find the differences between two texts.  Assumes that the texts do not
///have any common prefix or suffix.
pub fn diffCompute(allocator: Allocator, diff_timeout: f32, text1: []const u8, text2: []const u8, checklines: bool, ns_time_limit: u64) ![]DMP.Diff {
    var timer = try std.time.Timer.start();
    return diffComputeTimer(allocator, diff_timeout, text1, text2, checklines, ns_time_limit, &timer);
}
fn diffComputeTimer(allocator: Allocator, diff_timeout: f32, text1: []const u8, text2: []const u8, checklines: bool, ns_time_limit: u64, timer: *std.time.Timer) Allocator.Error![]DMP.Diff {
    var diffs = std.ArrayList(DMP.Diff).init(allocator);
    defer diffs.deinit();
    errdefer for (diffs.items) |diff| diff.deinit(allocator);

    if (text1.len == 0) {
        // Just add some text (speedup).
        try diffs.append(try DMP.Diff.fromSlice(allocator, text2, .insert));
        return diffs.toOwnedSlice();
    }

    if (text2.len == 0) {
        // Just delete some text (speedup).
        try diffs.append(try DMP.Diff.fromSlice(allocator, text1, .delete));
        return diffs.toOwnedSlice();
    }

    const text1_longer = text1.len > text2.len;
    const long_text = if (text1_longer) text1 else text2;
    const short_text = if (text1_longer) text2 else text1;
    if (std.mem.indexOf(u8, long_text, short_text)) |idx| {
        // Shorter text is inside the longer text (speedup).
        const op = if (text1_longer) DMP.DiffOperation.delete else DMP.DiffOperation.insert;
        try diffs.append(try DMP.Diff.fromSlice(allocator, long_text[0..idx], op));
        try diffs.append(try DMP.Diff.fromSlice(allocator, short_text, .equal));
        try diffs.append(try DMP.Diff.fromSlice(allocator, long_text[idx + short_text.len ..], op));
        return diffs.toOwnedSlice();
    }

    if (short_text.len == 1) {
        // Single character string.
        // After the previous speedup, the character can't be an equality.
        try diffs.append(try DMP.Diff.fromSlice(allocator, text1, .delete));
        try diffs.append(try DMP.Diff.fromSlice(allocator, text2, .insert));
        return diffs.toOwnedSlice();
    }

    // Check to see if the problem can be split in two.
    if (try diffHalfMatch(allocator, diff_timeout, text1, text2)) |hm| {
        errdefer allocator.free(hm.common);
        // A half-match was found, sort out the return data.
        // Send both pairs off for separate processing.
        const diffs_a = try diffMainStringStringBoolTimeoutTimer(allocator, diff_timeout, hm.text1_prefix, hm.text2_prefix, checklines, ns_time_limit, timer);
        defer allocator.free(diffs_a);
        const diffs_b = try diffMainStringStringBoolTimeoutTimer(allocator, diff_timeout, hm.text1_suffix, hm.text2_suffix, checklines, ns_time_limit, timer);
        defer allocator.free(diffs_b);

        // Merge the results.
        try diffs.appendSlice(diffs_a);
        try diffs.append(DMP.Diff{ .text = hm.common, .operation = .equal });
        try diffs.appendSlice(diffs_b);

        return diffs.toOwnedSlice();
    }

    // Perform a real diff.
    if (checklines and text1.len > 100 and text2.len > 100) {
        return diffLineModeTimer(allocator, text1, text2, ns_time_limit, timer);
    }
    return diffBisectTimer(allocator, text1, text2, ns_time_limit, timer);
}

///Do a quick line-level diff on both strings, then rediff the parts for
///greater accuracy.
///This speedup can produce non-minimal diffs.
pub fn diffLineMode(allocator: Allocator, text1: []const u8, text2: []const u8, ns_time_limit: u64) ![]DMP.Diff {
    var timer = try std.time.Timer.start();
    return diffLineModeTimer(allocator, text1, text2, ns_time_limit, &timer);
}
fn diffLineModeTimer(allocator: Allocator, text1: []const u8, text2: []const u8, ns_time_limit: u64, timer: *std.time.Timer) ![]DMP.Diff {
    _ = allocator;
    _ = text1;
    _ = text2;
    _ = ns_time_limit;
    _ = timer;

    @compileError("Not Implemented");
}

///Find the 'middle snake' of a diff, split the problem in two
///and return the recursively constructed diff.
///See Myers 1986 paper: An O(ND) Difference Algorithm and Its Variations.
pub fn diffBisect(allocator: Allocator, text1: []const u8, text2: []const u8, ns_time_limit: u64) ![]DMP.Diff {
    var timer = try std.time.Timer.start();
    return diffBisectTimer(allocator, text1, text2, ns_time_limit, &timer);
}
fn diffBisectTimer(allocator: Allocator, text1: []const u8, text2: []const u8, ns_time_limit: u64, timer: *std.time.Timer) ![]DMP.Diff {
    _ = allocator;
    _ = text1;
    _ = text2;
    _ = ns_time_limit;
    _ = timer;

    @compileError("Not Implemented");
}

///Given the location of the 'middle snake', split the diff in two parts
///and recurse.
pub fn diffBisectSplit(allocator: Allocator, diff_timeout: f32, text1: []const u8, text2: []const u8, x: usize, y: usize, ns_time_limit: u64) ![]DMP.Diff {
    var timer = try std.time.Timer.start();
    return diffBisectSplitTimer(allocator, diff_timeout, text1, text2, x, y, ns_time_limit, &timer);
}
fn diffBisectSplitTimer(allocator: Allocator, diff_timeout: f32, text1: []const u8, text2: []const u8, x: usize, y: usize, ns_time_limit: u64, timer: *std.time.Timer) ![]DMP.Diff {
    const text1a = text1[0..x];
    const text2a = text2[0..y];
    const text1b = text1[x..];
    const text2b = text2[y..];

    var diffs1 = try diffMainStringStringBoolTimeoutTimer(allocator, diff_timeout, text1a, text2a, false, ns_time_limit, timer);
    const diffs2 = try diffMainStringStringBoolTimeoutTimer(allocator, diff_timeout, text1b, text2b, false, ns_time_limit, timer);

    const len_start = diffs1.len;
    const new_len = diffs1.len + diffs2.len;
    if (!allocator.resize(diffs1, new_len)) {
        //failed to resize
        const new_diffs = try allocator.alloc(DMP.Diff, new_len);
        @memcpy(new_diffs[0..len_start], diffs1);
        @memset(diffs1, undefined);
        allocator.free(new_diffs);
        diffs1 = new_diffs;
    }
    diffs1.len = new_len;
    @memcpy(diffs1.ptr[len_start..new_len], diffs2);

    return diffs1;
}

///Split two texts into a list of strings.  Reduce the texts to a string of
///hashes where each Unicode character represents one line.
pub fn diffLinesToChars(allocator: Allocator, text1: *[]u8, text2: *[]u8) Allocator.Error!LineArray {
    var line_array = try LineArray.init(allocator);
    errdefer line_array.deinit();
    var line_hash = std.StringHashMap(usize).init(allocator);
    defer line_hash.deinit();
    // e.g. linearray[4] == "Hello\n"
    // e.g. linehash.get("Hello\n") == 4

    // "\x00" is a valid character, but various debuggers don't like it.
    // So we'll insert a junk entry to avoid generating a null character.
    try line_array.append("");

    try diffLinesToCharsMunge(allocator, text1, &line_array, &line_hash);
    try diffLinesToCharsMunge(allocator, text2, &line_array, &line_hash);

    return line_array;
}

///Split a text into a list of strings.  Reduce the texts to a string of
///hashes where each Unicode character represents one line.
pub fn diffLinesToCharsMunge(allocator: Allocator, text_ref: *[]u8, line_array: *LineArray, line_hash: *std.StringHashMap(usize)) Allocator.Error!void {
    var text = text_ref.*;
    // changing the implementation to modify the string
    var lines = std.mem.splitScalar(u8, text, '\n');

    var codes_len: usize = 0;

    while (lines.next()) |hl| {
        if (hl.len == 0 and lines.index == null) continue; // skip empty end
        const idx = lines.index orelse (text.len - hl.len);
        const length = if (idx + hl.len == text.len) hl.len else hl.len + 1;
        const line = hl.ptr[0..length]; // include newline
        var line_value = line_hash.get(line);
        if (line_value == null) {
            try line_array.append(line);
            line_value = line_array.items.len - 1;
            try line_hash.put(line_array.items.*[line_value.?], line_value.?);
        }

        const len = std.unicode.utf8CodepointSequenceLength(@intCast(line_value.?)) catch unreachable;
        // TODO: resize less often by doing capacity
        if (codes_len + len > idx + line.len) {
            const old_len = text.len;
            const new_len = text.len + (len - ((idx + line.len) - codes_len));
            text.len = new_len;
            // std.debug.print("\nresizing {d} -> {d} ---- \n", .{ lines.buffer.len, new_len });
            if (!allocator.resize(text.ptr[0..old_len], new_len)) {
                //failed to resize
                const new_text = try allocator.alloc(u8, new_len);
                @memcpy(new_text, text.ptr[0..old_len]);
                @memset(text.ptr[0..old_len], undefined);
                allocator.free(text[0..old_len]);
                text = new_text;
            }
            if (codes_len + len > old_len) std.mem.copyBackwards(u8, text[codes_len + len .. new_len], text[codes_len + 1 .. old_len]);
        }
        _ = std.unicode.utf8Encode(@intCast(line_value.?), text[codes_len .. codes_len + len]) catch @panic("couldent write codepoint for some reason");
        codes_len += len;
    }

    if (codes_len != text.len) {
        const len_start = text.len;
        text.len = codes_len;
        // std.debug.print("\nresizing {d} -> {d} ---- \n", .{ lines.buffer.len, codes_len });
        if (!allocator.resize(text.ptr[0..len_start], codes_len)) {
            //failed to resize
            // std.debug.print("failed to resize\n", .{});
            const new_text = try allocator.alloc(u8, codes_len);
            @memcpy(new_text, text.ptr[0..codes_len]);
            @memset(text.ptr[0..len_start], undefined);
            allocator.free(text.ptr[0..len_start]);
            text = new_text;
        }
    }
    text_ref.* = text;
}
pub fn diffCharsToLinesLineArray(allocator: Allocator, diffs: *[]DMP.Diff, line_array: LineArray) Allocator.Error!void {
    return diffCharsToLines(allocator, diffs, line_array.items.*);
}

///Rehydrate the text in a diff from a string of line hashes to real lines of text.
pub fn diffCharsToLines(allocator: Allocator, diffs: *[]DMP.Diff, line_array: [][]const u8) Allocator.Error!void {
    var text = std.ArrayList(u21).init(allocator);
    defer text.deinit();
    for (diffs.*) |*diff| {
        text.clearRetainingCapacity();
        try text.ensureTotalCapacity(diff.text.len); // will most likly be shorter but this is the max needed to hold it
        var len: usize = 0;
        var i: usize = 0;
        while (i < diff.text.len) : (i += 1) {
            const length = std.unicode.utf8ByteSequenceLength(diff.text[i]) catch continue;
            const codepoint = std.unicode.utf8Decode(diff.text[i .. i + @as(usize, @intCast(length))]) catch @panic("problem decoding utf8");
            i += @intCast(length - 1);
            text.appendAssumeCapacity(codepoint);
            len += line_array[codepoint].len;
        }

        if (!allocator.resize(diff.text, len)) {
            //failed to resize
            const new_text = try allocator.alloc(u8, len);
            @memset(diff.text, undefined);
            allocator.free(diff.text);
            diff.*.text = new_text;
        }
        diff.text.len = len;

        i = 0;
        for (text.items) |codepoint| {
            const line = line_array[codepoint];
            @memcpy(diff.text[i .. i + line.len], line);
            i += line.len;
        }
        std.debug.assert(i == diff.text.len);
    }
}

///Determine if the suffix of one string is the prefix of another.
pub fn diffCommonOverlap(text1: []const u8, text2: []const u8) usize {
    _ = text1;
    _ = text2;

    @compileError("Not Implemented");
}

///Do the two texts share a substring which is at least half the length of the longer text?
///This speedup can produce non-minimal diffs.
pub fn diffHalfMatch(allocator: Allocator, diff_timeout: f32, text1: []const u8, text2: []const u8) Allocator.Error!?struct {
    text1_prefix: []const u8,
    text1_suffix: []const u8,
    text2_prefix: []const u8,
    text2_suffix: []const u8,
    common: []const u8, // needs to be freed
} {
    if (diff_timeout <= 0) {
        // Don't risk returning a non-optimal diff if we have unlimited time.
        return null;
    }

    const text1_longer = text1.len > text2.len;
    const longtext = if (text1_longer) text1 else text2;
    const shorttext = if (text1_longer) text2 else text1;
    if (longtext.len < 4 or shorttext.len * 2 < longtext.len) {
        return null; // Pointless.
    }

    // First check if the second quarter is the seed for a half-match.
    var hm1 = try diffHalfMatchI(allocator, longtext, shorttext, (longtext.len + 3) / 4);
    errdefer if (hm1) |hm| allocator.free(hm.common);
    // Check again based on the third quarter.
    var hm2 = try diffHalfMatchI(allocator, longtext, shorttext, (longtext.len + 1) / 2);
    errdefer if (hm2) |hm| allocator.free(hm.common);

    if (hm1 == null and hm2 == null) return null;
    if (hm1 != null and hm2 != null) {
        // Both matched.  Select the longest.
        if (hm1.?.common.len > hm2.?.common.len) {
            allocator.free(hm2.?.common);
        } else {
            allocator.free(hm1.?.common);
            hm1 = hm2;
        }

        // leave only one
        hm2 = null;
    }

    std.debug.assert((hm1 != null or hm2 != null) and !(hm1 != null and hm2 != null));
    if (if (hm1 != null) hm1 else hm2) |hm| {
        return .{
            .common = hm.common,
            .text1_prefix = if (text1_longer) hm.longtext_prefix else hm.shorttext_prefix,
            .text1_suffix = if (text1_longer) hm.longtext_suffix else hm.shorttext_suffix,
            .text2_prefix = if (text1_longer) hm.shorttext_prefix else hm.longtext_prefix,
            .text2_suffix = if (text1_longer) hm.shorttext_suffix else hm.longtext_suffix,
        };
    }
    unreachable;
}

///Does a substring of shorttext exist within longtext such that the
///substring is at least half the length of longtext?
pub fn diffHalfMatchI(allocator: Allocator, longtext: []const u8, shorttext: []const u8, i: usize) Allocator.Error!?struct {
    longtext_prefix: []const u8,
    longtext_suffix: []const u8,
    shorttext_prefix: []const u8,
    shorttext_suffix: []const u8,
    common: []const u8, // needs to be freed
} {
    // Start with a 1/4 length substring at position i as a seed.
    const seed = longtext[i .. i + longtext.len / 4];

    var best_common_len: usize = 0;
    var best_common_a: []const u8 = undefined;
    var best_common_b: []const u8 = undefined;
    var best_longtext_a: []const u8 = undefined;
    var best_longtext_b: []const u8 = undefined;
    var best_shorttext_a: []const u8 = undefined;
    var best_shorttext_b: []const u8 = undefined;

    var j_n: ?usize = null;
    while (blk: {
        j_n = std.mem.indexOfPos(u8, shorttext, if (j_n != null) j_n.? + 1 else 0, seed);
        break :blk j_n != null;
    }) {
        const j = j_n.?;
        const prefix_length = diff_funcs.diffCommonPrefix(longtext[i..], shorttext[j..]);
        const suffix_length = diff_funcs.diffCommonSuffix(longtext[0..i], shorttext[0..j]);
        if (best_common_len < suffix_length + prefix_length) {
            best_common_a = shorttext[j - suffix_length .. j];
            best_common_b = shorttext[j .. j + prefix_length];
            best_common_len = best_common_a.len + best_common_b.len;
            best_longtext_a = longtext[0 .. i - suffix_length];
            best_longtext_b = longtext[i + prefix_length ..];
            best_shorttext_a = shorttext[0 .. j - suffix_length];
            best_shorttext_b = shorttext[j + prefix_length ..];
        }
    }

    if (best_common_len * 2 < longtext.len) return null;

    var best_common = try allocator.alloc(u8, best_common_len);
    @memcpy(best_common[0..best_common_a.len], best_common_a);
    @memcpy(best_common[best_common_a.len..], best_common_b);

    return .{
        .longtext_prefix = best_longtext_a,
        .longtext_suffix = best_longtext_b,
        .shorttext_prefix = best_shorttext_a,
        .shorttext_suffix = best_shorttext_b,
        .common = best_common,
    };
}

///Given two strings, compute a score representing whether the internal
///boundary falls on logical boundaries.
///Scores range from 6 (best) to 0 (worst).
pub fn diffCleanupSemanticScore(one: []const u8, two: []const u8) usize {
    if (one.len == 0 and two.len == 0) {
        // Edges are the best.
        return 6;
    }

    const char1 = one[one.length() - 1];
    const char2 = two[0];
    const non_alpha_numeric1 = switch (char1) {
        '0'...'9', 'a'...'z', 'A'...'Z' => false,
        else => true,
    };
    const non_alpha_numeric2 = switch (char2) {
        '0'...'9', 'a'...'z', 'A'...'Z' => false,
        else => true,
    };

    const whitespace1 = non_alpha_numeric1 and switch (char1) {
        '\t', '\r', '\n', 0x0C => true,
        else => false,
    };
    const whitespace2 = non_alpha_numeric2 and switch (char2) {
        '\t', '\r', '\n', 0x0C => true,
        else => false,
    };

    const line_break1 = whitespace1 and switch (char1) {
        '\r', '\n' => true,
        else => false,
    };
    const line_break2 = whitespace2 and switch (char2) {
        '\r', '\n' => true,
        else => false,
    };

    const blank_line1 = line_break1 and utils.blankLineEnd(one);
    const blank_line2 = line_break2 and utils.blankLineStart(two);

    if (blank_line1 or blank_line2) {
        // Five points for blank lines.
        return 5;
    } else if (line_break1 or line_break2) {
        // Four points for line breaks.
        return 4;
    } else if (non_alpha_numeric1 and !whitespace1 and whitespace2) {
        // Three points for end of sentences.
        return 3;
    } else if (whitespace1 or whitespace2) {
        // Two points for whitespace.
        return 2;
    } else if (non_alpha_numeric1 or non_alpha_numeric2) {
        // One point for non-alphanumeric.
        return 1;
    }
    return 0;
}
