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
fn diffLinesToCharsMunge(self: Self, text: [:0]const u8, lineArray: [][:0]const u8, lineHash: std.StringHashMapUnmanaged(usize)) [:0]const u8 {
    _ = self;
    _ = text;
    _ = lineArray;
    _ = lineHash;

    @compileError("Not Implemented");
}

///Rehydrate the text in a diff from a string of line hashes to real lines of
///text.
fn diffCharsToLines(self: Self, diffs: *[]Self.Diff, lineArray: [][:0]const u8) void {
    _ = self;
    _ = diffs;
    _ = lineArray;

    @compileError("Not Implemented");
}

///Determine the common prefix of two strings.
pub fn diffCommonPrefix(self: Self, text1: [:0]const u8, text2: [:0]const u8) usize {
    _ = self;
    _ = text1;
    _ = text2;

    @compileError("Not Implemented");
}

///Determine the common suffix of two strings.
pub fn diffCommonSuffix(self: Self, text1: [:0]const u8, text2: [:0]const u8) usize {
    _ = self;
    _ = text1;
    _ = text2;

    @compileError("Not Implemented");
}

///Determine if the suffix of one string is the prefix of another.
fn diffCommonOverlap(self: Self, text1: [:0]const u8, text2: [:0]const u8) usize {
    _ = self;
    _ = text1;
    _ = text2;

    @compileError("Not Implemented");
}

///Do the two texts share a substring which is at least half the length of
///the longer text?
///This speedup can produce non-minimal diffs.
fn diffHalfMatch(self: Self, text1: [:0]const u8, text2: [:0]const u8) [][:0]const u8 {
    _ = self;
    _ = text1;
    _ = text2;

    @compileError("Not Implemented");
}

///Does a substring of shorttext exist within longtext such that the
///substring is at least half the length of longtext?
fn diffHalfMatchI(self: Self, longtext: [:0]const u8, shorttext: [:0]const u8, i: usize) [][:0]const u8 {
    _ = self;
    _ = longtext;
    _ = shorttext;
    _ = i;

    @compileError("Not Implemented");
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
