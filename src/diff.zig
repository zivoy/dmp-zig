const Self = @import("diffmatchpatch.zig");
const std = @import("std");
const utils = @import("utils.zig");

const DiffPrivate = @import("diff_private.zig");

///Find the differences between two texts.
///Run a faster, slightly less optimal diff.
///This method allows the 'checklines' of `diffMainStringStringBool` to be optional.
///Most of the time checklines is wanted, so default to true.
pub fn diffMainStringString(self: Self, text1: []const u8, text2: []const u8) ![]Self.Diff {
    return self.diffMainStringStringBool(text1, text2, true);
}

///Find the differences between two texts.
pub fn diffMainStringStringBool(self: Self, text1: []const u8, text2: []const u8, check_lines: bool) ![]Self.Diff {
    var deadline: u64 = undefined;
    if (self.diff_timeout > 0) {
        deadline = @intFromFloat(self.diff_timeout * std.time.ns_per_s);
    } else {
        deadline = std.math.maxInt(u64);
    }
    return DiffPrivate.diffMainStringStringBoolTimeout(self, text1, text2, check_lines, deadline);
}

///Determine the common prefix of two strings.
pub fn diffCommonPrefix(self: Self, text1: []const u8, text2: []const u8) usize {
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
pub fn diffCommonSuffix(self: Self, text1: []const u8, text2: []const u8) usize {
    _ = self;
    const n = @min(text1.len, text2.len);
    for (1..n + 1) |i| {
        if (text1[text1.len - i] != text2[text2.len - i]) {
            return i - 1;
        }
    }
    return n;
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

///Reduce the number of edits by eliminating operationally trivial equalities.
pub fn diffCleanupEfficiency(self: Self, diffs: *[]Self.Diff) void {
    _ = self;
    _ = diffs;
    @compileError("Not Implemented");
}

///Reorder and merge like edit sections.  Merge equalities.
///Any edit section can move as long as it doesn't cross an equality.
pub fn diffCleanupMerge(self: Self, diffs: *[]Self.Diff) !void {
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
