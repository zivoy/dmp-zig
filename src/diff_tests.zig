const DMP = @import("diffmatchpatch.zig");
const DiffPrivate = @import("diff_private.zig");
const std = @import("std");
const testing = std.testing;
//  TODO: tests
//
// test "" {
//     const TestCase = struct {
//     };
//
//     const dmp = DMP.init(testing.allocator);
//
//     for ([_]TestCase{})|test_case|{}
// }

fn testString(text: []const u8) []u8 {
    const line = testing.allocator.alloc(u8, text.len) catch @panic("OOM");
    @memcpy(line, text);
    return line;
}

test "common prefix" {
    const dmp = DMP.init(testing.allocator);
    try testing.expectEqual(0, dmp.diffCommonPrefix("abc", "xyz"));
    try testing.expectEqual(4, dmp.diffCommonPrefix("1234abcdef", "1234xyz"));
    try testing.expectEqual(4, dmp.diffCommonPrefix("1234", "1234xyz"));
}

test "common suffix" {
    const dmp = DMP.init(testing.allocator);
    try testing.expectEqual(0, dmp.diffCommonSuffix("abc", "xyz"));
    try testing.expectEqual(4, dmp.diffCommonSuffix("abcdef1234", "xyz1234"));
    try testing.expectEqual(4, dmp.diffCommonSuffix("1234", "xyz1234"));
}

test "common overlap" {
    if (true) return error.SkipZigTest;
    const dmp = DMP.init(testing.allocator);
    try testing.expectEqual(0, DiffPrivate.diffCommonOverlap(dmp, "", "abcd"));
    try testing.expectEqual(3, DiffPrivate.diffCommonOverlap(dmp, "abc", "abcd"));
    try testing.expectEqual(0, DiffPrivate.diffCommonOverlap(dmp, "123456", "abcd"));
    try testing.expectEqual(3, DiffPrivate.diffCommonOverlap(dmp, "123456xxx", "xxxabcd"));

    // Some overly clever languages (C#) may treat ligatures as equal to their
    // component letters.  E.g. U+FB01 == 'fi'
    try testing.expectEqual(0, DiffPrivate.diffCommonOverlap(dmp, "fi", "\u{fb01}i"));
}

test "halfmatch" {
    const TestCase = struct {
        text1: []const u8,
        text2: []const u8,

        expected: ?struct {
            prefix1: []const u8,
            prefix2: []const u8,
            suffix1: []const u8,
            suffix2: []const u8,
            common: []const u8,
        },
    };

    var dmp = DMP.init(testing.allocator);
    dmp.diff_timeout = 1;

    for ([_]TestCase{
        .{ .text1 = "1234567890", .text2 = "abcdef", .expected = null },
        .{ .text1 = "12345", .text2 = "23", .expected = null },
        .{ .text1 = "1234567890", .text2 = "a345678z", .expected = .{
            .prefix1 = "12",
            .suffix1 = "90",
            .prefix2 = "a",
            .suffix2 = "z",
            .common = "345678",
        } },
        .{ .text1 = "a345678z", .text2 = "1234567890", .expected = .{
            .prefix1 = "a",
            .suffix1 = "z",
            .prefix2 = "12",
            .suffix2 = "90",
            .common = "345678",
        } },
        .{ .text1 = "abc56789z", .text2 = "1234567890", .expected = .{
            .prefix1 = "abc",
            .suffix1 = "z",
            .prefix2 = "1234",
            .suffix2 = "0",
            .common = "56789",
        } },
        .{ .text1 = "a23456xyz", .text2 = "1234567890", .expected = .{
            .prefix1 = "a",
            .suffix1 = "xyz",
            .prefix2 = "1",
            .suffix2 = "7890",
            .common = "23456",
        } },
        .{ .text1 = "121231234123451234123121", .text2 = "a1234123451234z", .expected = .{
            .prefix1 = "12123",
            .suffix1 = "123121",
            .prefix2 = "a",
            .suffix2 = "z",
            .common = "1234123451234",
        } },
        .{ .text1 = "x-=-=-=-=-=-=-=-=-=-=-=-=", .text2 = "xx-=-=-=-=-=-=-=", .expected = .{
            .prefix1 = "",
            .suffix1 = "-=-=-=-=-=",
            .prefix2 = "x",
            .suffix2 = "",
            .common = "x-=-=-=-=-=-=-=",
        } },
        .{ .text1 = "-=-=-=-=-=-=-=-=-=-=-=-=y", .text2 = "-=-=-=-=-=-=-=yy", .expected = .{
            .prefix1 = "-=-=-=-=-=",
            .suffix1 = "",
            .prefix2 = "",
            .suffix2 = "y",
            .common = "-=-=-=-=-=-=-=y",
        } },
        // Optimal diff would be -q+x=H-i+e=lloHe+Hu=llo-Hew+y not -qHillo+x=HelloHe-w+Hulloy
        .{ .text1 = "qHilloHelloHew", .text2 = "xHelloHeHulloy", .expected = .{
            .prefix1 = "qHillo",
            .suffix1 = "w",
            .prefix2 = "x",
            .suffix2 = "Hulloy",
            .common = "HelloHe",
        } },
    }) |test_case| {
        const actual_n = try DiffPrivate.diffHalfMatch(dmp, test_case.text1, test_case.text2);
        defer if (actual_n) |actual| testing.allocator.free(actual.common);
        if (test_case.expected) |expect| {
            try testing.expect(actual_n != null);
            const actual = actual_n.?;
            try testing.expectEqualStrings(expect.prefix1, actual.text1_prefix);
            try testing.expectEqualStrings(expect.prefix2, actual.text2_prefix);
            try testing.expectEqualStrings(expect.suffix1, actual.text1_suffix);
            try testing.expectEqualStrings(expect.suffix2, actual.text2_suffix);
            try testing.expectEqualStrings(expect.common, actual.common);
        } else {
            try testing.expect(actual_n == null);
        }
    }

    dmp.diff_timeout = 0;
    const actual_n = try DiffPrivate.diffHalfMatch(dmp, "qHilloHelloHew", "xHelloHeHulloy");
    defer if (actual_n) |actual| testing.allocator.free(actual.common);
    try testing.expect(actual_n == null);
}

test "bisect split" {
    if (true) return error.SkipZigTest;
    const dmp = DMP.init(testing.allocator);

    const text1 = "STUV\x05WX\x05YZ\x05[";
    const text2 = "WĺĻļ\x05YZ\x05ĽľĿŀZ";

    const diffs = try DiffPrivate.diffBisectSplit(dmp, text1, text2, 7, 6, std.time.ns_per_hour);
    defer for (diffs) |diff| diff.deinit(testing.allocator);
    for (diffs) |diff| {
        try testing.expect(std.unicode.utf8ValidateSlice(diff.text));
    }
    // TODO: actual expected outcome
}

test "lines to chars" {
    const TestCase = struct {
        text1: []u8,
        text2: []u8,

        expected_text1: []const u8,
        expected_text2: []const u8,
        expected_lines: []const []const u8,
    };

    const dmp = DMP.init(testing.allocator);

    // More than 256 to reveal any 8-bit limitations.
    const n = 300;
    var long_lines: [n + 1][]u8 = undefined;
    defer for (long_lines[1..]) |line| testing.allocator.free(std.mem.span(@as([*c]u8, line.ptr)));
    long_lines[0] = testString("");
    defer testing.allocator.free(long_lines[0]);
    for (long_lines[1..], 1..) |*line, i| {
        const buf = try testing.allocator.allocSentinel(u8, 10, 0);
        line.* = try std.fmt.bufPrint(buf, "{d}\n", .{i});
    }
    var chars: [127 + (n + 1 - 128) * 2]u8 = undefined;
    {
        var pointer: usize = 0;
        for (1..n + 1) |i| {
            const len = std.unicode.utf8CodepointSequenceLength(@intCast(i)) catch @panic("utf length");
            _ = std.unicode.utf8Encode(@intCast(i), chars[pointer .. pointer + len]) catch @panic("utf encode");
            pointer += len;
        }
    }

    const test_cases = [_]TestCase{
        .{ .text1 = testString(""), .text2 = testString("alpha\r\nbeta\r\n\r\n\r\n"), .expected_text1 = "", .expected_text2 = "\x01\x02\x03\x03", .expected_lines = &.{ "", "alpha\r\n", "beta\r\n", "\r\n" } },
        .{ .text1 = testString("a"), .text2 = testString("b"), .expected_text1 = "\x01", .expected_text2 = "\x02", .expected_lines = &.{ "", "a", "b" } },
        // Omit final newline.
        .{ .text1 = testString("alpha\nbeta\nalpha"), .text2 = testString(""), .expected_text1 = "\x01\x02\x03", .expected_text2 = "", .expected_lines = &.{ "", "alpha\n", "beta\n", "alpha" } },
        // Same lines in Text1 and Text2
        .{ .text1 = testString("abc\ndefg\n12345\n"), .text2 = testString("abc\ndef\n12345\n678"), .expected_text1 = "\x01\x02\x03", .expected_text2 = "\x01\x04\x03\x05", .expected_lines = &.{ "", "abc\n", "defg\n", "12345\n", "def\n", "678" } },
        .{ .text1 = try std.mem.join(testing.allocator, "", &long_lines), .text2 = testString(""), .expected_text1 = &chars, .expected_text2 = "", .expected_lines = &long_lines },
    };

    for (test_cases) |test_case| {
        var text1 = test_case.text1;
        var text2 = test_case.text2;
        defer testing.allocator.free(text1);
        defer testing.allocator.free(text2);
        var line_array = try DiffPrivate.diffLinesToChars(dmp, &text1, &text2);
        defer line_array.deinit();
        try testing.expectEqualStrings(test_case.expected_text1, text1);
        try testing.expectEqualStrings(test_case.expected_text2, text2);
        for (test_case.expected_lines, line_array.items.*) |expected, item| try testing.expectEqualSlices(u8, expected, item);
    }
}

test "chars to lines" {
    const TestCase = struct {
        diffs: []const DMP.Diff,
        lines: DiffPrivate.LineArray,

        expected: []const DMP.Diff,
    };

    const dmp = DMP.init(testing.allocator);

    // More than 256 to reveal any 8-bit limitations.
    const n = 300;
    var long_lines: [n + 1][]u8 = undefined;
    defer for (long_lines[1..]) |line| testing.allocator.free(std.mem.span(@as([*c]u8, line.ptr)));
    long_lines[0] = testString("");
    defer testing.allocator.free(long_lines[0]);
    for (long_lines[1..], 1..) |*line, i| {
        const buf = try testing.allocator.allocSentinel(u8, 10, 0);
        line.* = try std.fmt.bufPrint(buf, "{d}\n", .{i});
    }
    var chars: [127 + (n + 1 - 128) * 2]u8 = undefined;
    {
        var pointer: usize = 0;
        for (1..n + 1) |i| {
            const len = std.unicode.utf8CodepointSequenceLength(@intCast(i)) catch @panic("utf length");
            _ = std.unicode.utf8Encode(@intCast(i), chars[pointer .. pointer + len]) catch @panic("utf encode");
            pointer += len;
        }
    }

    const test_cases = [_]TestCase{
        .{
            .diffs = &.{
                try DMP.Diff.fromString(testing.allocator, "\x01\x02\x01", .equal),
                try DMP.Diff.fromString(testing.allocator, "\x02\x01\x02", .insert),
            },
            .lines = try DiffPrivate.LineArray.fromSlice(testing.allocator, @constCast(&[_][]const u8{ "", "alpha\n", "beta\n" })),
            .expected = &.{
                try DMP.Diff.fromString(testing.allocator, "alpha\nbeta\nalpha\n", .equal),
                try DMP.Diff.fromString(testing.allocator, "beta\nalpha\nbeta\n", .insert),
            },
        },
        .{
            .diffs = &.{try DMP.Diff.fromSlice(testing.allocator, &chars, .delete)},
            .lines = try DiffPrivate.LineArray.fromSlice(testing.allocator, &long_lines),
            .expected = &.{blk: {
                const str = try std.mem.join(testing.allocator, "", &long_lines);
                defer testing.allocator.free(str);
                break :blk try DMP.Diff.fromSlice(testing.allocator, str, .delete);
            }},
        },
    };
    for (test_cases) |test_case| {
        var diffs = @constCast(test_case.diffs);
        defer @constCast(&test_case.lines).deinit();
        defer for (diffs) |diff| diff.deinit(testing.allocator);
        defer for (test_case.expected) |diff| diff.deinit(testing.allocator);
        try DiffPrivate.diffCharsToLinesLineArray(dmp, &diffs, test_case.lines);

        try testing.expectEqual(diffs.len, test_case.expected.len);
        for (diffs, test_case.expected) |diff, expected| {
            try testing.expectEqual(expected.operation, diff.operation);
            try testing.expectEqualStrings(expected.text, diff.text);
        }
    }
}

test "cleanup merge" {
    return error.NoTest;
}

test "cleanup semantic lossless" {
    return error.NoTest;
}

test "cleanup semantic" {
    return error.NoTest;
}

test "cleanup efficiency" {
    return error.NoTest;
}

test "pretty html" {
    const dmp = DMP.init(testing.allocator);

    const diffs: []DMP.Diff = @constCast(&[_]DMP.Diff{
        try DMP.Diff.fromString(testing.allocator, "a\n", .equal),
        try DMP.Diff.fromString(testing.allocator, "<B>b</B>", .delete),
        try DMP.Diff.fromString(testing.allocator, "c&d", .insert),
    });
    const expected_text: []const u8 = "<span>a&para;<br></span><del style=\"background:#ffe6e6;\">&lt;B&gt;b&lt;/B&gt;</del><ins style=\"background:#e6ffe6;\">c&amp;d</ins>";

    defer for (diffs) |diff| diff.deinit(testing.allocator);

    const actual_text = try dmp.diffPrettyHtml(diffs);
    defer testing.allocator.free(actual_text);
    try testing.expectEqualStrings(expected_text, actual_text);
}

test "pretty text" {
    const dmp = DMP.init(testing.allocator);

    const diffs: []DMP.Diff = @constCast(&[_]DMP.Diff{
        try DMP.Diff.fromString(testing.allocator, "a\n", .equal),
        try DMP.Diff.fromString(testing.allocator, "<B>b</B>", .delete),
        try DMP.Diff.fromString(testing.allocator, "c&d", .insert),
    });
    const expected_text: []const u8 = "a\n\x1b[31m<B>b</B>\x1b[0m\x1b[32mc&d\x1b[0m";

    defer for (diffs) |diff| diff.deinit(testing.allocator);

    const actual_text = try dmp.diffPrettyText(diffs);
    defer testing.allocator.free(actual_text);
    try testing.expectEqualStrings(expected_text, actual_text);
}

test "diff text" {
    const dmp = DMP.init(testing.allocator);

    const diffs: []DMP.Diff = @constCast(&[_]DMP.Diff{
        try DMP.Diff.fromString(testing.allocator, "jump", .equal),
        try DMP.Diff.fromString(testing.allocator, "s", .delete),
        try DMP.Diff.fromString(testing.allocator, "ed", .insert),
        try DMP.Diff.fromString(testing.allocator, " over ", .equal),
        try DMP.Diff.fromString(testing.allocator, "the", .delete),
        try DMP.Diff.fromString(testing.allocator, "a", .insert),
        try DMP.Diff.fromString(testing.allocator, " lazy", .equal),
    });
    const expected_text1: []const u8 = "jumps over the lazy";
    const expected_text2: []const u8 = "jumped over a lazy";

    defer for (diffs) |diff| diff.deinit(testing.allocator);

    const actual_text1 = try dmp.diffText1(diffs);
    defer testing.allocator.free(actual_text1);
    try testing.expectEqualStrings(expected_text1, actual_text1);

    const actual_text2 = try dmp.diffText2(diffs);
    defer testing.allocator.free(actual_text2);
    try testing.expectEqualStrings(expected_text2, actual_text2);
}

test "to from delta" {
    const TestCase = struct {
        text: []const u8,
        delta: []const u8,

        expected_error: ?anyerror,
        expected_diffs: ?[]const DMP.Diff,
    };

    const dmp = DMP.init(testing.allocator);

    const diffs1: []const DMP.Diff = &.{
        try DMP.Diff.fromString(testing.allocator, "jump", .equal),
        try DMP.Diff.fromString(testing.allocator, "s", .delete),
        try DMP.Diff.fromString(testing.allocator, "ed", .insert),
        try DMP.Diff.fromString(testing.allocator, " over ", .equal),
        try DMP.Diff.fromString(testing.allocator, "the", .delete),
        try DMP.Diff.fromString(testing.allocator, "a", .insert),
        try DMP.Diff.fromString(testing.allocator, " lazy", .equal),
        try DMP.Diff.fromString(testing.allocator, "old dog", .insert),
    };
    // errdefer for (diffs1) |diff| diff.deinit(testing.allocator);

    const text1 = try dmp.diffText1(@constCast(diffs1));
    defer testing.allocator.free(text1);
    try testing.expectEqualStrings("jumps over the lazy", text1);

    const delta1 = try dmp.diffToDelta(@constCast(diffs1));
    defer testing.allocator.free(delta1);
    try testing.expectEqualStrings("=4\t-1\t+ed\t=6\t-3\t+a\t=5\t+old dog", delta1);

    const diffs2: []const DMP.Diff = &.{
        try DMP.Diff.fromString(testing.allocator, "\u{0680} \x00 \t %", .equal),
        try DMP.Diff.fromString(testing.allocator, "\u{0681} \x01 \n ^", .delete),
        try DMP.Diff.fromString(testing.allocator, "\u{0682} \x02 \\ |", .insert),
    };
    // errdefer for (diffs2) |diff| diff.deinit(testing.allocator);

    const text2 = try dmp.diffText1(@constCast(diffs2));
    defer testing.allocator.free(text2);
    try testing.expectEqualStrings("\u{0680} \x00 \t %\u{0681} \x01 \n ^", text2);

    const delta2 = try dmp.diffToDelta(@constCast(diffs2));
    defer testing.allocator.free(delta2);
    try testing.expectEqualStrings("=7\t-7\t+%DA%82 %02 %5C %7C", delta2);

    const diffs3: []const DMP.Diff = &.{
        try DMP.Diff.fromString(testing.allocator, "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789 - _ . ! ~ * ' ( ) ; / ? : @ & = + $ , # ", .insert),
    };
    // errdefer for (diffs3) |diff| diff.deinit(testing.allocator);

    const delta3 = try dmp.diffToDelta(@constCast(diffs3));
    defer testing.allocator.free(delta3);
    try testing.expectEqualStrings("+ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789 - _ . ! ~ * ' ( ) ; / ? : @ & = + $ , # ", delta3);

    for ([_]TestCase{
        .{ .text = "jumps over the lazyx", .delta = "=4\t-1\t+ed\t=6\t-3\t+a\t=5\t+old dog", .expected_error = DMP.DiffError.DeltaShorterThenSource, .expected_diffs = null },
        .{ .text = "umps over the lazy", .delta = "=4\t-1\t+ed\t=6\t-3\t+a\t=5\t+old dog", .expected_error = DMP.DiffError.DeltaLongerThenSource, .expected_diffs = null },
        .{ .text = "", .delta = "+%c3%xy", .expected_error = DMP.DiffError.DeltaContainsInvalidUTF8, .expected_diffs = null },
        .{ .text = "", .delta = "+%c3xy", .expected_error = DMP.DiffError.DeltaContainsInvalidUTF8, .expected_diffs = null },
        .{ .text = "", .delta = "a", .expected_error = DMP.DiffError.DeltaContainsIlligalOperation, .expected_diffs = null },
        .{ .text = "", .delta = "-", .expected_error = std.fmt.ParseIntError.InvalidCharacter, .expected_diffs = null },
        .{ .text = "", .delta = "--1", .expected_error = DMP.DiffError.DeltaContainsNegetiveNumber, .expected_diffs = null },
        .{ .text = "", .delta = "", .expected_error = null, .expected_diffs = &.{} },
        .{ .text = text1, .delta = delta1, .expected_error = null, .expected_diffs = diffs1 },
        .{ .text = text2, .delta = delta2, .expected_error = null, .expected_diffs = diffs2 },
        .{ .text = "", .delta = delta3, .expected_error = null, .expected_diffs = diffs3 },
    }) |test_case| {
        defer if (test_case.expected_diffs) |diffs| for (diffs) |diff| diff.deinit(testing.allocator);
        if (dmp.diffFromDelta(test_case.text, test_case.delta)) |diffs| {
            defer testing.allocator.free(diffs);
            defer for (diffs) |diff| diff.deinit(testing.allocator);

            try testing.expect(test_case.expected_diffs != null);
            try testing.expect(test_case.expected_error == null);

            try testing.expectEqual(test_case.expected_diffs.?.len, diffs.len);
            try testing.expectEqualDeep(test_case.expected_diffs.?, diffs);
        } else |err| {
            try testing.expect(test_case.expected_diffs == null);
            try testing.expect(test_case.expected_error != null);
            try testing.expectEqual(test_case.expected_error.?, err);
        }
    }
}

test "x index" {
    const TestCase = struct {
        diffs: []const DMP.Diff,
        location: usize,
        expected: usize,
    };

    const dmp = DMP.init(testing.allocator);

    for ([_]TestCase{
        .{
            .diffs = &.{
                try DMP.Diff.fromString(testing.allocator, "a", .delete),
                try DMP.Diff.fromString(testing.allocator, "1234", .insert),
                try DMP.Diff.fromString(testing.allocator, "xyz", .equal),
            },
            .location = 2,
            .expected = 5,
        },
        .{
            .diffs = &.{
                try DMP.Diff.fromString(testing.allocator, "a", .equal),
                try DMP.Diff.fromString(testing.allocator, "1234", .delete),
                try DMP.Diff.fromString(testing.allocator, "xyz", .equal),
            },
            .location = 3,
            .expected = 1,
        },
    }) |test_case| {
        const diffs = @constCast(test_case.diffs);
        defer for (diffs) |diff| diff.deinit(testing.allocator);
        const actual = dmp.diffXIndex(diffs, test_case.location);
        try testing.expectEqual(test_case.expected, actual);
    }
}

test "levenstein" {
    const dmp = DMP.init(testing.allocator);

    var diffs: []DMP.Diff = undefined;
    {
        diffs = @constCast(&[_]DMP.Diff{
            try DMP.Diff.fromString(testing.allocator, "abc", .delete),
            try DMP.Diff.fromString(testing.allocator, "1234", .insert),
            try DMP.Diff.fromString(testing.allocator, "xyz", .equal),
        })[0..];
        defer for (diffs) |diff| diff.deinit(testing.allocator);
        try testing.expectEqual(4, dmp.diffLevenshtein(diffs));
    }
    {
        diffs = @constCast(&[_]DMP.Diff{
            try DMP.Diff.fromString(testing.allocator, "xyz", .equal),
            try DMP.Diff.fromString(testing.allocator, "abc", .delete),
            try DMP.Diff.fromString(testing.allocator, "1234", .insert),
        })[0..];
        defer for (diffs) |diff| diff.deinit(testing.allocator);
        try testing.expectEqual(4, dmp.diffLevenshtein(diffs));
    }
    {
        diffs = @constCast(&[_]DMP.Diff{
            try DMP.Diff.fromString(testing.allocator, "abc", .delete),
            try DMP.Diff.fromString(testing.allocator, "xyz", .equal),
            try DMP.Diff.fromString(testing.allocator, "1234", .insert),
        });
        defer for (diffs) |diff| diff.deinit(testing.allocator);
        try testing.expectEqual(7, dmp.diffLevenshtein(diffs));
    }
}

test "bisect" {
    if (true) return error.SkipZigTest;
    const dmp = DMP.init(testing.allocator);

    const text1: []const u8 = "cat";
    const text2: []const u8 = "map";

    const TestCase = struct {
        deadline: u64,
        expected: []const DMP.Diff,
    };

    for ([_]TestCase{ .{ .deadline = DMP.diff_max_duration, .expected = &.{
        try DMP.Diff.fromString(testing.allocator, "c", .delete),
        try DMP.Diff.fromString(testing.allocator, "m", .insert),
        try DMP.Diff.fromString(testing.allocator, "a", .equal),
        try DMP.Diff.fromString(testing.allocator, "t", .delete),
        try DMP.Diff.fromString(testing.allocator, "p", .insert),
    } }, .{ .deadline = 0, .expected = &.{
        try DMP.Diff.fromString(testing.allocator, "cat", .delete),
        try DMP.Diff.fromString(testing.allocator, "map", .insert),
    } } }) |test_case| {
        defer for (test_case.expected) |diff| diff.deinit();

        const actual = try DiffPrivate.diffBisect(dmp, text1, text2, test_case.deadline);
        defer testing.allocator.free(actual);
        defer for (actual) |diff| diff.deinit();

        try testing.expectEqualDeep(test_case.expected, actual);
    }
}

test "diff main" {
    return error.NoTest;
}
