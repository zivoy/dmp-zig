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

    pub fn deinit(self: Diff, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
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
    _ = allocator;
    _ = diffs;
    @compileError("Not Implemented");
}

///Look for single edits surrounded on both sides by equalities
///which can be shifted sideways to align the edit to a word boundary.
///e.g: The c<ins>at c</ins>ame. -> The <ins>cat </ins>came.
pub fn diffCleanupSemanticLossless(allocator: Allocator, diffs: *[]Diff) !void {
    _ = allocator;
    _ = diffs;
    @compileError("Not Implemented");
}

///Reduce the number of edits by eliminating operationally trivial equalities.
pub fn diffCleanupEfficiency(allocator: Allocator, diffs: *[]Diff) !void {
    _ = allocator;
    _ = diffs;
    @compileError("Not Implemented");
}

///Reorder and merge like edit sections.  Merge equalities.
///Any edit section can move as long as it doesn't cross an equality.
pub fn diffCleanupMerge(allocator: Allocator, diffs: *[]Diff) !void {
    _ = allocator;
    _ = diffs;
    @compileError("Not Implemented");
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
    errdefer for (diffs.items) |diff| diff.deinit(allocator);

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
