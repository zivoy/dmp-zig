const std = @import("std");
const Self = @import("diffmatchpatch.zig");

///Find the differences between two texts.  Simplifies the problem by
///stripping any common prefix or suffix off the texts before diffing.
pub fn diffMainStringStringBoolTimeout(self: Self, text1: []const u8, text2: []const u8, check_lines: bool, deadline: std.time.epoch) []Self.Diff {
    _ = self;
    _ = text1;
    _ = text2;
    _ = check_lines;
    _ = deadline;
    @compileError("Not Implemented");
}

///Find the differences between two texts.  Assumes that the texts do not
///have any common prefix or suffix.
pub fn diffCompute(self: Self, text1: []const u8, text2: []const u8, checklines: bool, deadline: i64) []Self.Diff {
    _ = self;
    _ = text1;
    _ = text2;
    _ = checklines;
    _ = deadline;

    @compileError("Not Implemented");
}

///Do a quick line-level diff on both strings, then rediff the parts for
///greater accuracy.
///This speedup can produce non-minimal diffs.
pub fn diffLineMode(self: Self, text1: []const u8, text2: []const u8, deadline: i64) []Self.Diff {
    _ = self;
    _ = text1;
    _ = text2;
    _ = deadline;

    @compileError("Not Implemented");
}

///Find the 'middle snake' of a diff, split the problem in two
///and return the recursively constructed diff.
///See Myers 1986 paper: An O(ND) Difference Algorithm and Its Variations.
pub fn diffBisect(self: Self, text1: []const u8, text2: []const u8, deadline: i64) []Self.Diff {
    _ = self;
    _ = text1;
    _ = text2;
    _ = deadline;

    @compileError("Not Implemented");
}

///Given the location of the 'middle snake', split the diff in two parts
///and recurse.
pub fn diffBisectSplit(self: Self, text1: []const u8, text2: []const u8, x: usize, y: usize, deadline: i64) []Self.Diff {
    _ = self;
    _ = text1;
    _ = text2;
    _ = x;
    _ = y;
    _ = deadline;

    @compileError("Not Implemented");
}

pub const LineArray = struct {
    const S = @This();
    items: *[][]const u8,
    array_list: *std.ArrayListUnmanaged([]const u8),
    allocator: std.mem.Allocator,
    pub fn init(allocator: std.mem.Allocator) !S {
        var array_list = try allocator.create(std.ArrayListUnmanaged([]const u8));
        array_list.* = try std.ArrayListUnmanaged([]const u8).initCapacity(allocator, 0);
        return .{
            .items = &array_list.items,
            .array_list = array_list,
            .allocator = allocator,
        };
    }
    pub fn deinit(self: *S) void {
        for (self.array_list.items) |item| self.allocator.free(item);
        self.array_list.deinit(self.allocator);
        self.allocator.destroy(self.array_list);
        self.items = undefined;
    }
    pub fn append(self: S, text: []const u8) std.mem.Allocator.Error!void {
        const text_copy = try self.allocator.alloc(u8, text.len);
        @memcpy(text_copy, text);
        try self.array_list.append(self.allocator, text_copy);
    }
};

///Split two texts into a list of strings.  Reduce the texts to a string of
///hashes where each Unicode character represents one line.
pub fn diffLinesToChars(self: Self, text1: *[]u8, text2: *[]u8) std.mem.Allocator.Error!LineArray {
    var line_array = try LineArray.init(self.allocator);
    errdefer line_array.deinit();
    var line_hash = std.StringHashMap(usize).init(self.allocator);
    defer line_hash.deinit();
    // e.g. linearray[4] == "Hello\n"
    // e.g. linehash.get("Hello\n") == 4

    // "\x00" is a valid character, but various debuggers don't like it.
    // So we'll insert a junk entry to avoid generating a null character.
    try line_array.append("");

    try diffLinesToCharsMunge(self, text1, &line_array, &line_hash);
    try diffLinesToCharsMunge(self, text2, &line_array, &line_hash);

    return line_array;
}

///Split a text into a list of strings.  Reduce the texts to a string of
///hashes where each Unicode character represents one line.
pub fn diffLinesToCharsMunge(self: Self, text_ref: *[]u8, line_array: *LineArray, line_hash: *std.StringHashMap(usize)) std.mem.Allocator.Error!void {
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

        const len = std.unicode.utf8CodepointSequenceLength(@intCast(line_value.?)) catch @panic("too many lines");
        // TODO: resize less often by doing capacity
        if (text.len - codes_len < len or (len > 1 and std.mem.indexOfScalar(u8, hl[1..@min(hl.len, len - 1)], '\n') != null)) {
            const old_len = text.len;
            const new_len = text.len + (len - (text.len - codes_len));
            text.len = new_len;
            // std.debug.print("\nresizing {d} -> {d} ---- \n", .{ lines.buffer.len, new_len });
            if (!self.allocator.resize(text.ptr[0..old_len], new_len)) {
                //failed to resize
                const new_text = try self.allocator.alloc(u8, new_len);
                @memcpy(new_text, text.ptr[0..old_len]);
                @memset(text.ptr[0..old_len], undefined);
                self.allocator.free(text[0..old_len]);
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
        if (!self.allocator.resize(text.ptr[0..len_start], codes_len)) {
            //failed to resize
            // std.debug.print("failed to resize\n", .{});
            const new_text = try self.allocator.alloc(u8, codes_len);
            @memcpy(new_text, text.ptr[0..codes_len]);
            @memset(text.ptr[0..len_start], undefined);
            self.allocator.free(text.ptr[0..len_start]);
            text = new_text;
        }
    }
    text_ref.* = text;
}

///Rehydrate the text in a diff from a string of line hashes to real lines of text.
pub fn diffCharsToLines(self: Self, diffs: []Self.Diff, line_array: [][:0]const u8) std.mem.Allocator.Error!void {
    var text = std.ArrayList(u21).init(self.allocator);
    defer text.deinit();
    for (diffs) |*diff| {
        text.clearRetainingCapacity();
        try text.ensureTotalCapacity(diff.text.len); // will most likly be shorter but this is the max needed to hold it
        var len: usize = 0;
        var i = 0;
        while (i < diff.text.len) : (i += 1) {
            const length = std.unicode.utf8ByteSequenceLength(diff.text[i]) catch continue;
            const codepoint = std.unicode.utf8Decode(diff.text[i .. i + @as(usize, @intCast(length))]) catch @panic("problem decoding utf8");
            i += @intCast(length - 1);
            text.appendAssumeCapacity(codepoint);
            len += line_array[codepoint].len;
        }

        if (!self.allocator.resize(diff.text, len)) {
            //failed to resize
            const new_text = try self.allocator.alloc(u8, len);
            @memset(diff.text, undefined);
            self.allocator.free(diff.text);
            diff.*.text = new_text;
        }
        diff.text.len = len;

        i = 0;
        for (text.items) |codepoint| {
            const line = line_array[codepoint];
            @memcpy(diff.text[i..], line);
            i += line.len;
        }
        std.debug.assert(i == diff.text.len);
    }
}

///Determine if the suffix of one string is the prefix of another.
pub fn diffCommonOverlap(self: Self, text1: [:0]const u8, text2: [:0]const u8) usize {
    _ = self;
    _ = text1;
    _ = text2;

    @compileError("Not Implemented");
}

///Do the two texts share a substring which is at least half the length of the longer text?
///This speedup can produce non-minimal diffs.
pub fn diffHalfMatch(self: Self, text1: [:0]const u8, text2: [:0]const u8) std.mem.Allocator.Error!?struct {
    text1_prefix: []const u8,
    text1_suffix: []const u8,
    text2_prefix: []const u8,
    text2_suffix: []const u8,
    common: []const u8, // needs to be freed
} {
    if (self.diff_timeout <= 0) {
        // Don't risk returning a non-optimal diff if we have unlimited time.
        return null;
    }

    const text1_longer = text1.length > text2.length;
    const longtext = if (text1_longer) text1 else text2;
    const shorttext = if (text1_longer) text2 else text1;
    if (longtext.length < 4 or shorttext.length * 2 < longtext.length) {
        return null; // Pointless.
    }

    // First check if the second quarter is the seed for a half-match.
    const hm1 = try diffHalfMatchI(self, longtext, shorttext, (longtext.len + 3) / 4);
    errdefer if (hm1) |hm| self.allocator.free(hm.common);
    // Check again based on the third quarter.
    const hm2 = try diffHalfMatchI(self, longtext, shorttext, (longtext.len + 1) / 2);
    errdefer if (hm2) |hm| self.allocator.free(hm.common);

    if (hm1 == null and hm2 == null) return null;
    if (hm1 != null and hm2 != null) {
        // Both matched.  Select the longest.
        if (hm1.?.common.len > hm2.?.common.len) {
            self.allocator.free(hm2.?.common);
        } else {
            self.allocator.free(hm1.?.common);
            hm1 = hm2;
        }

        // leave only one
        hm2 = null;
    }

    if (if (hm1 != null) hm1 else hm2) |hm| {
        return .{
            .common = hm.common,
            .text1_prefix = if (text1_longer) hm.longtext_prefix else hm.shorttext_prefix,
            .text1_suffix = if (text1_longer) hm.longtext_suffix else hm.shorttext_suffix,
            .text2_prefix = if (text1_longer) hm.shorttext_prefix else hm.longtext_prefix,
            .text2_suffix = if (text1_longer) hm.shorttext_suffix else hm.longtext_suffix,
        };
    }
}

///Does a substring of shorttext exist within longtext such that the
///substring is at least half the length of longtext?
pub fn diffHalfMatchI(self: Self, longtext: [:0]const u8, shorttext: [:0]const u8, i: usize) std.mem.Allocator.Error!?struct {
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

    var j: ?usize = null;
    while (blk: {
        j = std.mem.indexOfPos(u8, shorttext, if (j != null) j.? + 1 else 0, seed);
        break :blk j != -1;
    }) {
        const prefix_length = self.diffCommonPrefix(longtext[i..], shorttext[j..]);
        const suffix_length = self.diffCommonSuffix(longtext[0..i], shorttext[0..j]);
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

    var best_common = try self.allocator.alloc(u8, best_common_len);
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
pub fn diffCleanupSemanticScore(self: Self, one: [:0]const u8, two: [:0]const u8) usize {
    _ = self;
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

    const blank_line1 = line_break1 and (std.mem.endsWith(u8, one, "\n\r\n") or std.mem.endsWith(u8, one, "\n\n"));
    const blank_line2 = line_break2 and (std.mem.startsWith(u8, two, "\r\n\r\n") or std.mem.startsWith(u8, two, "\n\n") or std.mem.startsWith(u8, two, "\r\n\n") or std.mem.startsWith(u8, two, "\n\r\n")); // second 2 checks are more unlikly but there to keep consistency with the regex

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
