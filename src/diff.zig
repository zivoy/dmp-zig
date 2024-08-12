const Self = @import("diffmatchpatch.zig");
const std = @import("std");
const utils = @import("utils.zig");

///Find the differences between two texts.
///Run a faster, slightly less optimal diff.
///This method allows the 'checklines' of `diffMainStringStringBool` to be optional.
///Most of the time checklines is wanted, so default to true.
pub fn diffMainStringString(self: Self, text1: [:0]const u8, text2: [:0]const u8) []Self.Diff {
    return self.diffMainStringStringBool(text1, text2, true);
}

///Find the differences between two texts.
pub fn diffMainStringStringBool(self: Self, text1: [:0]const u8, text2: [:0]const u8, check_lines: bool) []Self.Diff {
    _ = self;
    _ = text1;
    _ = text2;
    _ = check_lines;
    @compileError("Not Implemented");
}

///Find the differences between two texts.  Simplifies the problem by
///stripping any common prefix or suffix off the texts before diffing.
fn diffMainStringStringBoolTimeout(self: Self, text1: [:0]const u8, text2: [:0]const u8, check_lines: bool, deadline: std.time.epoch) []Self.Diff {
    _ = self;
    _ = text1;
    _ = text2;
    _ = check_lines;
    _ = deadline;
    @compileError("Not Implemented");
}

///Find the differences between two texts.  Assumes that the texts do not
///have any common prefix or suffix.
fn diffCompute(self: Self, text1: [:0]const u8, text2: [:0]const u8, checklines: bool, deadline: i64) []Self.Diff {
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
fn diffLineMode(self: Self, text1: [:0]const u8, text2: [:0]const u8, deadline: i64) []Self.Diff {
    _ = self;
    _ = text1;
    _ = text2;
    _ = deadline;

    @compileError("Not Implemented");
}

///Find the 'middle snake' of a diff, split the problem in two
///and return the recursively constructed diff.
///See Myers 1986 paper: An O(ND) Difference Algorithm and Its Variations.
fn diffBisect(self: Self, text1: [:0]const u8, text2: [:0]const u8, deadline: i64) []Self.Diff {
    _ = self;
    _ = text1;
    _ = text2;
    _ = deadline;

    @compileError("Not Implemented");
}

///Given the location of the 'middle snake', split the diff in two parts
///and recurse.
fn diffBisectSplit(self: Self, text1: [:0]const u8, text2: [:0]const u8, x: usize, y: usize, deadline: i64) []Self.Diff {
    _ = self;
    _ = text1;
    _ = text2;
    _ = x;
    _ = y;
    _ = deadline;

    @compileError("Not Implemented");
}

///Split two texts into a list of strings.  Reduce the texts to a string of
///hashes where each Unicode character represents one line.
fn diffLinesToChars(self: Self, text1: [:0]const u8, text2: [:0]const u8) struct { [:0]const u8, [:0]const u8, [][:0]const u8 } {
    _ = self;
    _ = text1;
    _ = text2;

    @compileError("Not Implemented");
}

///Split a text into a list of strings.  Reduce the texts to a string of
///hashes where each Unicode character represents one line.
fn diffLinesToCharsMunge(self: Self, text: *[]u8, line_array: *std.ArrayList([]const u8), line_hash: *std.StringHashMap(usize)) std.mem.Allocator.Error!void {
    // changing the implementation to modify the string
    const len_start = text.len;
    const lines = std.mem.splitBackwardsScalar(u8, text, '\n');

    var codes_start = text.len;

    while (lines.next()) |line| {
        var line_value = line_hash.get(line);
        if (line_value == null) {
            try line_array.append(line);
            line_value = line_array.items.len - 1;
            try line_hash.put(line, line_value);
        }

        const len = std.unicode.utf8CodepointSequenceLength(line_value.?) catch @panic("too many lines");
        if (codes_start - lines.index orelse 0 < len) {
            @panic("not enough space do something"); // TODO: implement me
        }
        _ = std.unicode.utf8Encode(@intCast(line_value), text.*[codes_start - len .. codes_start]) catch @panic("couldent write codepoint for some reason");
        codes_start -= len;
    }

    @memcpy(text.*[0..], text[codes_start..len_start]);
    text.*.len = len_start - codes_start;

    if (!self.allocator.resize(text.*[0..len_start], text.len)) {
        //failed to resize
        var new_text = try self.allocator.alloc(u8, text.len);
        @memcpy(&new_text, text);
        self.allocator.free(text[0..len_start]);
        text.* = new_text;
    }
}

///Rehydrate the text in a diff from a string of line hashes to real lines of text.
fn diffCharsToLines(self: Self, diffs: []Self.Diff, line_array: [][:0]const u8) std.mem.Allocator.Error!void {
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
            self.allocator.free(diff.text);
            diff.*.text = new_text;
        }

        i = 0;
        for (text.items) |codepoint| {
            const line = line_array[codepoint];
            @memcpy(diff.text[i..], line);
            i += line.len;
        }
        std.debug.assert(i == diff.text.len);
    }
}

///Determine the common prefix of two strings.
pub fn diffCommonPrefix(self: Self, text1: [:0]const u8, text2: [:0]const u8) usize {
    _ = self;
    const n = @min(text1.len, text2.len);
    for (0..n) |i| {
        if (text1[i] != text2[i]) {
            return i;
        }
    }
    return n;
}

///Determine the common suffix of two strings.
pub fn diffCommonSuffix(self: Self, text1: [:0]const u8, text2: [:0]const u8) usize {
    _ = self;
    const n = @min(text1.len, text2.len);
    for (1..n + 1) |i| {
        if (text1[text1.len - i] != text2[text2.len - i]) {
            return i - 1;
        }
    }
    return n;
}

///Determine if the suffix of one string is the prefix of another.
fn diffCommonOverlap(self: Self, text1: [:0]const u8, text2: [:0]const u8) usize {
    _ = self;
    _ = text1;
    _ = text2;

    @compileError("Not Implemented");
}

///Do the two texts share a substring which is at least half the length of the longer text?
///This speedup can produce non-minimal diffs.
fn diffHalfMatch(self: Self, text1: [:0]const u8, text2: [:0]const u8) std.mem.Allocator.Error!?struct {
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
fn diffHalfMatchI(self: Self, longtext: [:0]const u8, shorttext: [:0]const u8, i: usize) std.mem.Allocator.Error!?struct {
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

///Reduce the number of edits by eliminating semantically trivial equalities.
pub fn diffCleanupSemantic(self: Self, diffs: *[]Self.Diff) void {
    _ = self;
    _ = diffs;
    @compileError("Not Implemented");
}

///Look for single edits surrounded on both sides by equalities
///which can be shifted sideways to align the edit to a word boundary.
///e.g: The c<ins>at c</ins>ame. -> The <ins>cat </ins>came.
pub fn diffCleanupSemanticLossless(self: Self, diffs: *[]Self.Diff) void {
    _ = self;
    _ = diffs;
    @compileError("Not Implemented");
}

///Given two strings, compute a score representing whether the internal
///boundary falls on logical boundaries.
///Scores range from 6 (best) to 0 (worst).
fn diffCleanupSemanticScore(self: Self, one: [:0]const u8, two: [:0]const u8) usize {
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

///Reduce the number of edits by eliminating operationally trivial equalities.
pub fn diffCleanupEfficiency(self: Self, diffs: *[]Self.Diff) void {
    _ = self;
    _ = diffs;
    @compileError("Not Implemented");
}

///Reorder and merge like edit sections.  Merge equalities.
///Any edit section can move as long as it doesn't cross an equality.
pub fn diffCleanupMerge(self: Self, diffs: *[]Self.Diff) void {
    _ = self;
    _ = diffs;
    @compileError("Not Implemented");
}

///loc is a location in text1, compute and return the equivalent location in text2.
///e.g. "The cat" vs "The big cat", 1->1, 5->8
pub fn diffXIndex(self: Self, diffs: []Self.Diff, loc: usize) usize {
    _ = self;
    var chars1: usize = 0;
    var chars2: usize = 0;
    var last_chars1: usize = 0;
    var last_chars2: usize = 0;
    var last_diff: ?Self.Diff = undefined;
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
pub fn diffPrettyHtml(self: Self, diffs: []Self.Diff) std.mem.Allocator.Error![:0]const u8 {
    var text = std.ArrayList(u8).init(self.allocator);
    defer text.deinit();
    try self.diffPrettyHtmlWriter(text.writer(), diffs);
    return text.toOwnedSliceSentinel(0);
}
pub fn diffPrettyHtmlWriter(self: Self, writer: anytype, diffs: []Self.Diff) @TypeOf(writer).Error!void {
    _ = self;
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
pub fn diffPrettyText(self: Self, diffs: []Self.Diff) std.mem.Allocator.Error![:0]const u8 {
    var text = std.ArrayList(u8).init(self.allocator);
    defer text.deinit();
    try self.diffPrettyTextWriter(text.writer(), diffs);
    return text.toOwnedSliceSentinel(0);
}
pub fn diffPrettyTextWriter(self: Self, writer: anytype, diffs: []Self.Diff) @TypeOf(writer).Error!void {
    _ = self;
    for (diffs) |diff|
        switch (diff.operation) {
            .equal => try writer.writeAll(diff.text),
            .insert => try writer.print("\x1b[32m{s}\x1b[0m", .{diff.text}),
            .delete => try writer.print("\x1b[31m{s}\x1b[0m", .{diff.text}),
        };
}

///Compute and return the source text (all equalities and deletions).
pub fn diffText1(self: Self, diffs: []Self.Diff) std.mem.Allocator.Error![:0]const u8 {
    var string = std.ArrayList(u8).init(self.allocator);
    defer string.deinit();

    for (diffs) |diff| if (diff.operation != .insert) {
        try string.appendSlice(diff.text);
    };

    return try string.toOwnedSliceSentinel(0);
}

///Compute and return the destination text (all equalities and insertions).
pub fn diffText2(self: Self, diffs: []Self.Diff) std.mem.Allocator.Error![:0]const u8 {
    var string = std.ArrayList(u8).init(self.allocator);
    defer string.deinit();

    for (diffs) |diff| if (diff.operation != .delete) {
        try string.appendSlice(diff.text);
    };

    return try string.toOwnedSliceSentinel(0);
}

///Compute the Levenshtein distance; the number of inserted, deleted or substituted characters.
pub fn diffLevenshtein(self: Self, diffs: []Self.Diff) usize {
    _ = self;
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
pub fn diffToDelta(self: Self, diffs: []Self.Diff) std.mem.Allocator.Error![:0]const u8 {
    var text = std.ArrayList(u8).init(self.allocator);
    defer text.deinit();
    try self.diffToDeltaWriter(text.writer(), diffs);
    return text.toOwnedSliceSentinel(0);
}
pub fn diffToDeltaWriter(self: Self, writer: anytype, diffs: []Self.Diff) @TypeOf(writer).Error!void {
    _ = self;
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
pub fn diffFromDelta(self: Self, text1: []const u8, delta: []const u8) ![]Self.Diff {
    var diffs = std.ArrayList(Self.Diff).init(self.allocator);

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
                const param_encoded = try self.allocator.alloc(u8, param.len);
                defer self.allocator.free(param_encoded);
                @memcpy(param_encoded, param);
                const line = std.Uri.percentDecodeInPlace(param_encoded);
                try diffs.append(try Self.Diff.fromSlice(self.allocator, line, .insert));
            },
            '-', '=' => {
                const count = try std.fmt.parseInt(isize, param, 10);
                if (count < 0) return Self.DiffError.DeltaContainsNegetiveNumber;

                const line = text1[pointer .. pointer + @as(usize, @intCast(count))];
                pointer += @intCast(count);
                if (token[0] == '=') {
                    try diffs.append(try Self.Diff.fromSlice(self.allocator, line, .equal));
                } else {
                    try diffs.append(try Self.Diff.fromSlice(self.allocator, line, .delete));
                }
            },
            else => return Self.DiffError.DeltaContainsIlligalOperation,
        }
    }
    if (pointer != text1.len) return Self.DiffError.DeltaShorterThenSource;
    return diffs.toOwnedSlice();
}

const testing = std.testing;

comptime {
    _ = @import("diff_tests.zig");
}
