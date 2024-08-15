const std = @import("std");
const DMP = @import("diffmatchpatch.zig").DiffMatchPatch;
const DiffPrivate = @import("diff_private.zig");

const diff_max_duration = @import("diff.zig").diff_max_duration;
const Diff = @import("diff.zig").Diff;
const DiffError = @import("diff.zig").DiffError;

const testing = std.testing;
// INFO: these tests have an issue where they wont be deinited if it failes in the middle

fn testString(text: []const u8) []u8 {
    const line = testing.allocator.alloc(u8, text.len) catch @panic("OOM");
    @memcpy(line, text);
    return line;
}

fn diffRebuildTexts(diffs: []Diff) !struct { []const u8, []const u8 } {
    var text1 = std.ArrayList(u8).init(testing.allocator);
    defer text1.deinit();
    var text2 = std.ArrayList(u8).init(testing.allocator);
    defer text2.deinit();

    for (diffs) |*diff| {
        if (diff.operation != .insert) {
            try text1.appendSlice(diff.text);
        }
        if (diff.operation != .delete) {
            try text2.appendSlice(diff.text);
        }
    }

    return .{
        try text1.toOwnedSlice(),
        try text2.toOwnedSlice(),
    };
}

fn testDiffList(diffs: []const Diff) []Diff {
    const diff_o = testing.allocator.alloc(Diff, diffs.len) catch @panic("OOM");
    @memcpy(diff_o, diffs);
    return diff_o;
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
    try testing.expectEqual(0, DiffPrivate.diffCommonOverlap("", "abcd"));
    try testing.expectEqual(3, DiffPrivate.diffCommonOverlap("abc", "abcd"));
    try testing.expectEqual(0, DiffPrivate.diffCommonOverlap("123456", "abcd"));
    try testing.expectEqual(3, DiffPrivate.diffCommonOverlap("123456xxx", "xxxabcd"));

    // Some overly clever languages (C#) may treat ligatures as equal to their
    // component letters.  E.g. U+FB01 == 'fi'
    try testing.expectEqual(0, DiffPrivate.diffCommonOverlap("fi", "\u{fb01}i"));
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
        const actual_n = try DiffPrivate.diffHalfMatch(testing.allocator, dmp.diff_timeout, test_case.text1, test_case.text2);
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
    const actual_n = try DiffPrivate.diffHalfMatch(testing.allocator, dmp.diff_timeout, "qHilloHelloHew", "xHelloHeHulloy");
    defer if (actual_n) |actual| testing.allocator.free(actual.common);
    try testing.expect(actual_n == null);
}

test "bisect split" {
    if (true) return error.SkipZigTest;
    const dmp = DMP.init(testing.allocator);

    const text1 = "STUV\x05WX\x05YZ\x05[";
    const text2 = "WĺĻļ\x05YZ\x05ĽľĿŀZ";

    const diffs = try DiffPrivate.diffBisectSplit(testing.allocator, dmp.diff_timeout, text1, text2, 7, 6, std.time.ns_per_hour);
    defer for (diffs) |*diff| diff.deinit(testing.allocator);
    for (diffs) |*diff| {
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
        var line_array = try DiffPrivate.diffLinesToChars(testing.allocator, &text1, &text2);
        defer line_array.deinit();
        try testing.expectEqualStrings(test_case.expected_text1, text1);
        try testing.expectEqualStrings(test_case.expected_text2, text2);
        for (test_case.expected_lines, line_array.items.*) |expected, item| try testing.expectEqualSlices(u8, expected, item);
    }
}

test "chars to lines" {
    const TestCase = struct {
        diffs: []const Diff,
        lines: DiffPrivate.LineArray,

        expected: []const Diff,
    };

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
                try Diff.fromString(testing.allocator, "\x01\x02\x01", .equal),
                try Diff.fromString(testing.allocator, "\x02\x01\x02", .insert),
            },
            .lines = try DiffPrivate.LineArray.fromSlice(testing.allocator, @constCast(&[_][]const u8{ "", "alpha\n", "beta\n" })),
            .expected = &.{
                try Diff.fromString(testing.allocator, "alpha\nbeta\nalpha\n", .equal),
                try Diff.fromString(testing.allocator, "beta\nalpha\nbeta\n", .insert),
            },
        },
        .{
            .diffs = &.{try Diff.fromSlice(testing.allocator, &chars, .delete)},
            .lines = try DiffPrivate.LineArray.fromSlice(testing.allocator, &long_lines),
            .expected = &.{blk: {
                const str = try std.mem.join(testing.allocator, "", &long_lines);
                defer testing.allocator.free(str);
                break :blk try Diff.fromSlice(testing.allocator, str, .delete);
            }},
        },
    };
    for (test_cases) |test_case| {
        var diffs = @constCast(test_case.diffs);
        defer @constCast(&test_case.lines).deinit();
        defer for (diffs) |*diff| diff.deinit(testing.allocator);
        defer for (test_case.expected) |*diff| @constCast(diff).deinit(testing.allocator);
        try DiffPrivate.diffCharsToLinesLineArray(testing.allocator, &diffs, test_case.lines);

        try testing.expectEqual(diffs.len, test_case.expected.len);
        for (diffs, test_case.expected) |diff, expected| {
            try testing.expectEqual(expected.operation, diff.operation);
            try testing.expectEqualStrings(expected.text, diff.text);
        }
    }
}

test "cleanup merge" {
    const TestCase = struct {
        diffs: []Diff,
        expected: []const Diff,
    };

    const dmp = DMP.init(testing.allocator);

    const test_cases = [_]TestCase{
        .{
            .diffs = testDiffList(&.{}),
            .expected = &.{},
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "a", .equal),
                try Diff.fromString(testing.allocator, "b", .delete),
                try Diff.fromString(testing.allocator, "c", .insert),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "a", .equal),
                try Diff.fromString(testing.allocator, "b", .delete),
                try Diff.fromString(testing.allocator, "c", .insert),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "a", .equal),
                try Diff.fromString(testing.allocator, "b", .equal),
                try Diff.fromString(testing.allocator, "c", .equal),
            }),
            .expected = &.{try Diff.fromString(testing.allocator, "abc", .equal)},
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "a", .delete),
                try Diff.fromString(testing.allocator, "b", .delete),
                try Diff.fromString(testing.allocator, "c", .delete),
            }),
            .expected = &.{try Diff.fromString(testing.allocator, "abc", .delete)},
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "a", .insert),
                try Diff.fromString(testing.allocator, "b", .insert),
                try Diff.fromString(testing.allocator, "c", .insert),
            }),
            .expected = &.{try Diff.fromString(testing.allocator, "abc", .insert)},
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "a", .delete),
                try Diff.fromString(testing.allocator, "b", .insert),
                try Diff.fromString(testing.allocator, "c", .delete),
                try Diff.fromString(testing.allocator, "d", .insert),
                try Diff.fromString(testing.allocator, "e", .equal),
                try Diff.fromString(testing.allocator, "f", .equal),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "ac", .delete),
                try Diff.fromString(testing.allocator, "bd", .insert),
                try Diff.fromString(testing.allocator, "ef", .equal),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "a", .delete),
                try Diff.fromString(testing.allocator, "abc", .insert),
                try Diff.fromString(testing.allocator, "dc", .delete),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "a", .equal),
                try Diff.fromString(testing.allocator, "d", .delete),
                try Diff.fromString(testing.allocator, "b", .insert),
                try Diff.fromString(testing.allocator, "c", .equal),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "x", .equal),
                try Diff.fromString(testing.allocator, "a", .delete),
                try Diff.fromString(testing.allocator, "abc", .insert),
                try Diff.fromString(testing.allocator, "dc", .delete),
                try Diff.fromString(testing.allocator, "y", .equal),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "xa", .equal),
                try Diff.fromString(testing.allocator, "d", .delete),
                try Diff.fromString(testing.allocator, "b", .insert),
                try Diff.fromString(testing.allocator, "cy", .equal),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "x", .equal),
                try Diff.fromString(testing.allocator, "\u{0101}", .delete),
                try Diff.fromString(testing.allocator, "\u{0101}bc", .insert),
                try Diff.fromString(testing.allocator, "dc", .delete),
                try Diff.fromString(testing.allocator, "y", .equal),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "x\u{0101}", .equal),
                try Diff.fromString(testing.allocator, "d", .delete),
                try Diff.fromString(testing.allocator, "b", .insert),
                try Diff.fromString(testing.allocator, "cy", .equal),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "a", .equal),
                try Diff.fromString(testing.allocator, "ba", .insert),
                try Diff.fromString(testing.allocator, "c", .equal),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "ab", .insert),
                try Diff.fromString(testing.allocator, "ac", .equal),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "c", .equal),
                try Diff.fromString(testing.allocator, "ab", .insert),
                try Diff.fromString(testing.allocator, "a", .equal),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "ca", .equal),
                try Diff.fromString(testing.allocator, "ba", .insert),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "a", .equal),
                try Diff.fromString(testing.allocator, "b", .delete),
                try Diff.fromString(testing.allocator, "c", .equal),
                try Diff.fromString(testing.allocator, "ac", .delete),
                try Diff.fromString(testing.allocator, "x", .equal),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "abc", .delete),
                try Diff.fromString(testing.allocator, "acx", .equal),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "x", .equal),
                try Diff.fromString(testing.allocator, "ca", .delete),
                try Diff.fromString(testing.allocator, "c", .equal),
                try Diff.fromString(testing.allocator, "b", .delete),
                try Diff.fromString(testing.allocator, "a", .equal),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "xca", .equal),
                try Diff.fromString(testing.allocator, "cba", .delete),
            },
        },
    };

    var end: usize = 0;
    defer {
        for (test_cases, 0..) |test_case, i| {
            for (test_case.expected) |*diff| @constCast(diff).deinit(testing.allocator);
            if (i > end) {
                for (test_case.diffs) |*diff| @constCast(diff).deinit(testing.allocator);
                testing.allocator.free(test_case.diffs);
            }
        }
    }

    for (test_cases, 0..) |test_case, i| {
        end = i;
        var diffs = test_case.diffs;
        defer testing.allocator.free(diffs);
        defer for (diffs) |*diff| diff.deinit(testing.allocator);

        try dmp.diffCleanupMerge(&diffs);

        try testing.expectEqual(test_case.expected.len, diffs.len);
        for (test_case.expected, diffs) |expected, diff| {
            try testing.expectEqual(expected.operation, diff.operation);
            try testing.expectEqualStrings(expected.text, diff.text);
        }
    }
}

test "cleanup semantic lossless" {
    const TestCase = struct {
        diffs: []Diff,
        expected: []const Diff,
    };

    const dmp = DMP.init(testing.allocator);

    const test_cases = [_]TestCase{
        .{
            .diffs = testDiffList(&.{}),
            .expected = &.{},
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "AAA\r\n\r\nBBB", .equal),
                try Diff.fromString(testing.allocator, "\r\nDDD\r\n\r\nBBB", .insert),
                try Diff.fromString(testing.allocator, "\r\nEEE", .equal),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "AAA\r\n\r\n", .equal),
                try Diff.fromString(testing.allocator, "BBB\r\nDDD\r\n\r\n", .insert),
                try Diff.fromString(testing.allocator, "BBB\r\nEEE", .equal),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "AAA\r\nBBB", .equal),
                try Diff.fromString(testing.allocator, " DDD\r\nBBB", .insert),
                try Diff.fromString(testing.allocator, " EEE", .equal),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "AAA\r\n", .equal),
                try Diff.fromString(testing.allocator, "BBB DDD\r\n", .insert),
                try Diff.fromString(testing.allocator, "BBB EEE", .equal),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "The c", .equal),
                try Diff.fromString(testing.allocator, "ow and the c", .insert),
                try Diff.fromString(testing.allocator, "at.", .equal),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "The ", .equal),
                try Diff.fromString(testing.allocator, "cow and the ", .insert),
                try Diff.fromString(testing.allocator, "cat.", .equal),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "The-c", .equal),
                try Diff.fromString(testing.allocator, "ow-and-the-c", .insert),
                try Diff.fromString(testing.allocator, "at.", .equal),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "The-", .equal),
                try Diff.fromString(testing.allocator, "cow-and-the-", .insert),
                try Diff.fromString(testing.allocator, "cat.", .equal),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "a", .equal),
                try Diff.fromString(testing.allocator, "a", .delete),
                try Diff.fromString(testing.allocator, "ax", .equal),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "a", .delete),
                try Diff.fromString(testing.allocator, "aax", .equal),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "xa", .equal),
                try Diff.fromString(testing.allocator, "a", .delete),
                try Diff.fromString(testing.allocator, "a", .equal),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "xaa", .equal),
                try Diff.fromString(testing.allocator, "a", .delete),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "The xxx. The ", .equal),
                try Diff.fromString(testing.allocator, "zzz. The ", .insert),
                try Diff.fromString(testing.allocator, "yyy.", .equal),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "The xxx.", .equal),
                try Diff.fromString(testing.allocator, " The zzz.", .insert),
                try Diff.fromString(testing.allocator, " The yyy.", .equal),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "The ♕. The ", .equal),
                try Diff.fromString(testing.allocator, "♔. The ", .insert),
                try Diff.fromString(testing.allocator, "♖.", .equal),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "The ♕.", .equal),
                try Diff.fromString(testing.allocator, " The ♔.", .insert),
                try Diff.fromString(testing.allocator, " The ♖.", .equal),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "♕♕", .equal),
                try Diff.fromString(testing.allocator, "♔♔", .insert),
                try Diff.fromString(testing.allocator, "♖♖", .equal),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "♕♕", .equal),
                try Diff.fromString(testing.allocator, "♔♔", .insert),
                try Diff.fromString(testing.allocator, "♖♖", .equal),
            },
        },
    };

    var end: usize = 0;
    defer {
        for (test_cases, 0..) |test_case, i| {
            for (test_case.expected) |*diff| @constCast(diff).deinit(testing.allocator);
            if (i > end) {
                for (test_case.diffs) |*diff| @constCast(diff).deinit(testing.allocator);
                testing.allocator.free(test_case.diffs);
            }
        }
    }

    for (test_cases, 0..) |test_case, i| {
        end = i;
        var diffs = test_case.diffs;
        defer testing.allocator.free(diffs);
        defer for (diffs) |*diff| diff.deinit(testing.allocator);

        try dmp.diffCleanupSemanticLossless(&diffs);

        try testing.expectEqual(test_case.expected.len, diffs.len);
        for (test_case.expected, diffs) |expected, diff| {
            try testing.expectEqual(expected.operation, diff.operation);
            try testing.expectEqualStrings(expected.text, diff.text);
        }
    }
}

test "cleanup semantic" {
    const TestCase = struct {
        diffs: []Diff,
        expected: []const Diff,
    };

    const dmp = DMP.init(testing.allocator);

    const test_cases = [_]TestCase{
        .{
            .diffs = testDiffList(&.{}),
            .expected = &.{},
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "ab", .delete),
                try Diff.fromString(testing.allocator, "cd", .insert),
                try Diff.fromString(testing.allocator, "12", .equal),
                try Diff.fromString(testing.allocator, "e", .delete),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "ab", .delete),
                try Diff.fromString(testing.allocator, "cd", .insert),
                try Diff.fromString(testing.allocator, "12", .equal),
                try Diff.fromString(testing.allocator, "e", .delete),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "abc", .delete),
                try Diff.fromString(testing.allocator, "ABC", .insert),
                try Diff.fromString(testing.allocator, "1234", .equal),
                try Diff.fromString(testing.allocator, "wxyz", .delete),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "abc", .delete),
                try Diff.fromString(testing.allocator, "ABC", .insert),
                try Diff.fromString(testing.allocator, "1234", .equal),
                try Diff.fromString(testing.allocator, "wxyz", .delete),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "2016-09-01T03:07:1", .equal),
                try Diff.fromString(testing.allocator, "5.15", .insert),
                try Diff.fromString(testing.allocator, "4", .equal),
                try Diff.fromString(testing.allocator, ".", .delete),
                try Diff.fromString(testing.allocator, "80", .equal),
                try Diff.fromString(testing.allocator, "0", .insert),
                try Diff.fromString(testing.allocator, "78", .equal),
                try Diff.fromString(testing.allocator, "3074", .delete),
                try Diff.fromString(testing.allocator, "1Z", .equal),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "2016-09-01T03:07:1", .equal),
                try Diff.fromString(testing.allocator, "5.15", .insert),
                try Diff.fromString(testing.allocator, "4", .equal),
                try Diff.fromString(testing.allocator, ".", .delete),
                try Diff.fromString(testing.allocator, "80", .equal),
                try Diff.fromString(testing.allocator, "0", .insert),
                try Diff.fromString(testing.allocator, "78", .equal),
                try Diff.fromString(testing.allocator, "3074", .delete),
                try Diff.fromString(testing.allocator, "1Z", .equal),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "a", .delete),
                try Diff.fromString(testing.allocator, "b", .equal),
                try Diff.fromString(testing.allocator, "c", .delete),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "abc", .delete),
                try Diff.fromString(testing.allocator, "b", .insert),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "ab", .delete),
                try Diff.fromString(testing.allocator, "cd", .equal),
                try Diff.fromString(testing.allocator, "e", .delete),
                try Diff.fromString(testing.allocator, "f", .equal),
                try Diff.fromString(testing.allocator, "g", .insert),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "abcdef", .delete),
                try Diff.fromString(testing.allocator, "cdfg", .insert),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "1", .insert),
                try Diff.fromString(testing.allocator, "A", .equal),
                try Diff.fromString(testing.allocator, "B", .delete),
                try Diff.fromString(testing.allocator, "2", .insert),
                try Diff.fromString(testing.allocator, "_", .equal),
                try Diff.fromString(testing.allocator, "1", .insert),
                try Diff.fromString(testing.allocator, "A", .equal),
                try Diff.fromString(testing.allocator, "B", .delete),
                try Diff.fromString(testing.allocator, "2", .insert),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "AB_AB", .delete),
                try Diff.fromString(testing.allocator, "1A2_1A2", .insert),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "The c", .equal),
                try Diff.fromString(testing.allocator, "ow and the c", .delete),
                try Diff.fromString(testing.allocator, "at.", .equal),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "The ", .equal),
                try Diff.fromString(testing.allocator, "cow and the ", .delete),
                try Diff.fromString(testing.allocator, "cat.", .equal),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "abcxx", .delete),
                try Diff.fromString(testing.allocator, "xxdef", .insert),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "abcxx", .delete),
                try Diff.fromString(testing.allocator, "xxdef", .insert),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "abcxxx", .delete),
                try Diff.fromString(testing.allocator, "xxxdef", .insert),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "abc", .delete),
                try Diff.fromString(testing.allocator, "xxx", .equal),
                try Diff.fromString(testing.allocator, "def", .insert),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "xxxabc", .delete),
                try Diff.fromString(testing.allocator, "defxxx", .insert),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "def", .insert),
                try Diff.fromString(testing.allocator, "xxx", .equal),
                try Diff.fromString(testing.allocator, "abc", .delete),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "abcd1212", .delete),
                try Diff.fromString(testing.allocator, "1212efghi", .insert),
                try Diff.fromString(testing.allocator, "----", .equal),
                try Diff.fromString(testing.allocator, "A3", .delete),
                try Diff.fromString(testing.allocator, "3BC", .insert),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "abcd", .delete),
                try Diff.fromString(testing.allocator, "1212", .equal),
                try Diff.fromString(testing.allocator, "efghi", .insert),
                try Diff.fromString(testing.allocator, "----", .equal),
                try Diff.fromString(testing.allocator, "A", .delete),
                try Diff.fromString(testing.allocator, "3", .equal),
                try Diff.fromString(testing.allocator, "BC", .insert),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "James McCarthy ", .equal),
                try Diff.fromString(testing.allocator, "close to ", .delete),
                try Diff.fromString(testing.allocator, "sign", .equal),
                try Diff.fromString(testing.allocator, "ing", .delete),
                try Diff.fromString(testing.allocator, "s", .insert),
                try Diff.fromString(testing.allocator, " new ", .equal),
                try Diff.fromString(testing.allocator, "E", .delete),
                try Diff.fromString(testing.allocator, "fi", .insert),
                try Diff.fromString(testing.allocator, "ve", .equal),
                try Diff.fromString(testing.allocator, "-yea", .insert),
                try Diff.fromString(testing.allocator, "r", .equal),
                try Diff.fromString(testing.allocator, "ton", .delete),
                try Diff.fromString(testing.allocator, " deal", .equal),
                try Diff.fromString(testing.allocator, " at Everton", .insert),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "James McCarthy ", .equal),
                try Diff.fromString(testing.allocator, "close to ", .delete),
                try Diff.fromString(testing.allocator, "sign", .equal),
                try Diff.fromString(testing.allocator, "ing", .delete),
                try Diff.fromString(testing.allocator, "s", .insert),
                try Diff.fromString(testing.allocator, " new ", .equal),
                try Diff.fromString(testing.allocator, "five-year deal at ", .insert),
                try Diff.fromString(testing.allocator, "Everton", .equal),
                try Diff.fromString(testing.allocator, " deal", .delete),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "星球大戰：新的希望 ", .insert),
                try Diff.fromString(testing.allocator, "star wars: ", .equal),
                try Diff.fromString(testing.allocator, "episodio iv - un", .delete),
                try Diff.fromString(testing.allocator, "a n", .equal),
                try Diff.fromString(testing.allocator, "u", .delete),
                try Diff.fromString(testing.allocator, "e", .equal),
                try Diff.fromString(testing.allocator, "va", .delete),
                try Diff.fromString(testing.allocator, "w", .insert),
                try Diff.fromString(testing.allocator, " ", .equal),
                try Diff.fromString(testing.allocator, "es", .delete),
                try Diff.fromString(testing.allocator, "ho", .insert),
                try Diff.fromString(testing.allocator, "pe", .equal),
                try Diff.fromString(testing.allocator, "ranza", .delete),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "星球大戰：新的希望 ", .insert),
                try Diff.fromString(testing.allocator, "star wars: ", .equal),
                try Diff.fromString(testing.allocator, "episodio iv - una nueva esperanza", .delete),
                try Diff.fromString(testing.allocator, "a new hope", .insert),
            },
        },
        .{
            .diffs = testDiffList(&.{
                try Diff.fromString(testing.allocator, "킬러 인 ", .insert),
                try Diff.fromString(testing.allocator, "리커버리", .equal),
                try Diff.fromString(testing.allocator, " 보이즈", .delete),
            }),
            .expected = &.{
                try Diff.fromString(testing.allocator, "킬러 인 ", .insert),
                try Diff.fromString(testing.allocator, "리커버리", .equal),
                try Diff.fromString(testing.allocator, " 보이즈", .delete),
            },
        },
    };

    var end: usize = 0;
    defer {
        for (test_cases, 0..) |test_case, i| {
            for (test_case.expected) |*diff| @constCast(diff).deinit(testing.allocator);
            if (i > end) {
                for (test_case.diffs) |*diff| @constCast(diff).deinit(testing.allocator);
                testing.allocator.free(test_case.diffs);
            }
        }
    }

    for (test_cases, 0..) |test_case, i| {
        end = i;
        var diffs = test_case.diffs;
        defer testing.allocator.free(diffs);
        defer for (diffs) |*diff| diff.deinit(testing.allocator);

        try dmp.diffCleanupSemantic(&diffs);

        const err: anyerror!void = blk: {
            testing.expectEqual(test_case.expected.len, diffs.len) catch |err| break :blk err;
            for (test_case.expected, diffs) |expected, diff| {
                testing.expectEqual(expected.operation, diff.operation) catch |err| break :blk err;
                testing.expectEqualStrings(expected.text, diff.text) catch |err| break :blk err;
            }
        };
        err catch |e| {
            std.debug.print("\n{d}\n", .{i + 1});
            for (diffs) |diff| {
                std.debug.print("  {s} - \"{s}\"\n", .{ @tagName(diff.operation), diff.text });
            }
            std.debug.print("\n", .{});
            return e;
        };
    }
}

test "cleanup efficiency" {
    if (true) return error.SkipZigTest;
    const TestCase = struct {
        diffs: []Diff,
        expected: []const Diff,
    };

    var dmp = DMP.init(testing.allocator);

    dmp.diff_edit_cost = 4;

    {
        const test_cases = [_]TestCase{
            .{
                .diffs = testDiffList(&.{}),
                .expected = &.{},
            },
            .{
                .diffs = testDiffList(&.{
                    try Diff.fromString(testing.allocator, "ab", .delete),
                    try Diff.fromString(testing.allocator, "12", .insert),
                    try Diff.fromString(testing.allocator, "wxyz", .equal),
                    try Diff.fromString(testing.allocator, "cd", .delete),
                    try Diff.fromString(testing.allocator, "34", .insert),
                }),
                .expected = &.{
                    try Diff.fromString(testing.allocator, "ab", .delete),
                    try Diff.fromString(testing.allocator, "12", .insert),
                    try Diff.fromString(testing.allocator, "wxyz", .equal),
                    try Diff.fromString(testing.allocator, "cd", .delete),
                    try Diff.fromString(testing.allocator, "34", .insert),
                },
            },
            .{
                .diffs = testDiffList(&.{
                    try Diff.fromString(testing.allocator, "ab", .delete),
                    try Diff.fromString(testing.allocator, "12", .insert),
                    try Diff.fromString(testing.allocator, "xyz", .equal),
                    try Diff.fromString(testing.allocator, "cd", .delete),
                    try Diff.fromString(testing.allocator, "34", .insert),
                }),
                .expected = &.{
                    try Diff.fromString(testing.allocator, "abxyzcd", .delete),
                    try Diff.fromString(testing.allocator, "12xyz34", .insert),
                },
            },
            .{
                .diffs = testDiffList(&.{
                    try Diff.fromString(testing.allocator, "12", .insert),
                    try Diff.fromString(testing.allocator, "x", .equal),
                    try Diff.fromString(testing.allocator, "cd", .delete),
                    try Diff.fromString(testing.allocator, "34", .insert),
                }),
                .expected = &.{
                    try Diff.fromString(testing.allocator, "xcd", .delete),
                    try Diff.fromString(testing.allocator, "12x34", .insert),
                },
            },
            .{
                .diffs = testDiffList(&.{
                    try Diff.fromString(testing.allocator, "ab", .delete),
                    try Diff.fromString(testing.allocator, "12", .insert),
                    try Diff.fromString(testing.allocator, "xy", .equal),
                    try Diff.fromString(testing.allocator, "34", .insert),
                    try Diff.fromString(testing.allocator, "z", .equal),
                    try Diff.fromString(testing.allocator, "cd", .delete),
                    try Diff.fromString(testing.allocator, "56", .insert),
                }),
                .expected = &.{
                    try Diff.fromString(testing.allocator, "abxyzcd", .delete),
                    try Diff.fromString(testing.allocator, "12xy34z56", .insert),
                },
            },
        };

        var end: usize = 0;
        defer {
            for (test_cases, 0..) |test_case, i| {
                for (test_case.expected) |*diff| @constCast(diff).deinit(testing.allocator);
                if (i > end) {
                    for (test_case.diffs) |*diff| @constCast(diff).deinit(testing.allocator);
                    testing.allocator.free(test_case.diffs);
                }
            }
        }

        for (test_cases, 0..) |test_case, i| {
            end = i;
            var diffs = test_case.diffs;
            defer testing.allocator.free(diffs);
            defer for (diffs) |*diff| diff.deinit(testing.allocator);

            dmp.diffCleanupEfficiency(&diffs);

            try testing.expectEqual(test_case.expected.len, diffs.len);
            for (test_case.expected, diffs) |expected, diff| {
                try testing.expectEqual(expected.operation, diff.operation);
                try testing.expectEqualStrings(expected.text, diff.text);
            }
        }
    }

    dmp.diff_edit_cost = 4;

    {
        const test_cases = [_]TestCase{
            .{
                .diffs = testDiffList(&.{
                    try Diff.fromString(testing.allocator, "ab", .delete),
                    try Diff.fromString(testing.allocator, "12", .insert),
                    try Diff.fromString(testing.allocator, "wxyz", .equal),
                    try Diff.fromString(testing.allocator, "cd", .delete),
                    try Diff.fromString(testing.allocator, "34", .insert),
                }),
                .expected = &.{
                    try Diff.fromString(testing.allocator, "abwxyzcd", .delete),
                    try Diff.fromString(testing.allocator, "12wxyz34", .insert),
                },
            },
        };

        for (test_cases) |test_case| {
            var diffs = test_case.diffs;
            defer testing.allocator.free(diffs);
            defer for (diffs) |*diff| diff.deinit(testing.allocator);
            defer for (test_case.expected) |*diff| @constCast(diff).deinit(testing.allocator);

            dmp.diffCleanupEfficiency(&diffs);

            try testing.expectEqual(test_case.expected.len, diffs.len);
            for (test_case.expected, diffs) |expected, diff| {
                try testing.expectEqual(expected.operation, diff.operation);
                try testing.expectEqualStrings(expected.text, diff.text);
            }
        }
    }
}

test "pretty html" {
    const dmp = DMP.init(testing.allocator);

    const diffs: []Diff = @constCast(&[_]Diff{
        try Diff.fromString(testing.allocator, "a\n", .equal),
        try Diff.fromString(testing.allocator, "<B>b</B>", .delete),
        try Diff.fromString(testing.allocator, "c&d", .insert),
    });
    const expected_text: []const u8 = "<span>a&para;<br></span><del style=\"background:#ffe6e6;\">&lt;B&gt;b&lt;/B&gt;</del><ins style=\"background:#e6ffe6;\">c&amp;d</ins>";

    defer for (diffs) |*diff| diff.deinit(testing.allocator);

    const actual_text = try dmp.diffPrettyHtml(diffs);
    defer testing.allocator.free(actual_text);
    try testing.expectEqualStrings(expected_text, actual_text);
}

test "pretty text" {
    const dmp = DMP.init(testing.allocator);

    const diffs: []Diff = @constCast(&[_]Diff{
        try Diff.fromString(testing.allocator, "a\n", .equal),
        try Diff.fromString(testing.allocator, "<B>b</B>", .delete),
        try Diff.fromString(testing.allocator, "c&d", .insert),
    });
    const expected_text: []const u8 = "a\n\x1b[31m<B>b</B>\x1b[0m\x1b[32mc&d\x1b[0m";

    defer for (diffs) |*diff| diff.deinit(testing.allocator);

    const actual_text = try dmp.diffPrettyText(diffs);
    defer testing.allocator.free(actual_text);
    try testing.expectEqualStrings(expected_text, actual_text);
}

test "diff text" {
    const dmp = DMP.init(testing.allocator);

    const diffs: []Diff = @constCast(&[_]Diff{
        try Diff.fromString(testing.allocator, "jump", .equal),
        try Diff.fromString(testing.allocator, "s", .delete),
        try Diff.fromString(testing.allocator, "ed", .insert),
        try Diff.fromString(testing.allocator, " over ", .equal),
        try Diff.fromString(testing.allocator, "the", .delete),
        try Diff.fromString(testing.allocator, "a", .insert),
        try Diff.fromString(testing.allocator, " lazy", .equal),
    });
    const expected_text1: []const u8 = "jumps over the lazy";
    const expected_text2: []const u8 = "jumped over a lazy";

    defer for (diffs) |*diff| diff.deinit(testing.allocator);

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
        expected_diffs: ?[]const Diff,
    };

    const dmp = DMP.init(testing.allocator);

    const diffs1: []const Diff = &.{
        try Diff.fromString(testing.allocator, "jump", .equal),
        try Diff.fromString(testing.allocator, "s", .delete),
        try Diff.fromString(testing.allocator, "ed", .insert),
        try Diff.fromString(testing.allocator, " over ", .equal),
        try Diff.fromString(testing.allocator, "the", .delete),
        try Diff.fromString(testing.allocator, "a", .insert),
        try Diff.fromString(testing.allocator, " lazy", .equal),
        try Diff.fromString(testing.allocator, "old dog", .insert),
    };
    // errdefer for (diffs1) |*diff| diff.deinit(testing.allocator);

    const text1 = try dmp.diffText1(@constCast(diffs1));
    defer testing.allocator.free(text1);
    try testing.expectEqualStrings("jumps over the lazy", text1);

    const delta1 = try dmp.diffToDelta(@constCast(diffs1));
    defer testing.allocator.free(delta1);
    try testing.expectEqualStrings("=4\t-1\t+ed\t=6\t-3\t+a\t=5\t+old dog", delta1);

    const diffs2: []const Diff = &.{
        try Diff.fromString(testing.allocator, "\u{0680} \x00 \t %", .equal),
        try Diff.fromString(testing.allocator, "\u{0681} \x01 \n ^", .delete),
        try Diff.fromString(testing.allocator, "\u{0682} \x02 \\ |", .insert),
    };
    // errdefer for (diffs2) |*diff| diff.deinit(testing.allocator);

    const text2 = try dmp.diffText1(@constCast(diffs2));
    defer testing.allocator.free(text2);
    try testing.expectEqualStrings("\u{0680} \x00 \t %\u{0681} \x01 \n ^", text2);

    const delta2 = try dmp.diffToDelta(@constCast(diffs2));
    defer testing.allocator.free(delta2);
    try testing.expectEqualStrings("=7\t-7\t+%DA%82 %02 %5C %7C", delta2);

    const diffs3: []const Diff = &.{
        try Diff.fromString(testing.allocator, "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789 - _ . ! ~ * ' ( ) ; / ? : @ & = + $ , # ", .insert),
    };
    // errdefer for (diffs3) |*diff| diff.deinit(testing.allocator);

    const delta3 = try dmp.diffToDelta(@constCast(diffs3));
    defer testing.allocator.free(delta3);
    try testing.expectEqualStrings("+ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789 - _ . ! ~ * ' ( ) ; / ? : @ & = + $ , # ", delta3);

    const test_cases = [_]TestCase{
        .{ .text = "jumps over the lazyx", .delta = "=4\t-1\t+ed\t=6\t-3\t+a\t=5\t+old dog", .expected_error = DiffError.DeltaShorterThenSource, .expected_diffs = null },
        .{ .text = "umps over the lazy", .delta = "=4\t-1\t+ed\t=6\t-3\t+a\t=5\t+old dog", .expected_error = DiffError.DeltaLongerThenSource, .expected_diffs = null },
        .{ .text = "", .delta = "+%c3%xy", .expected_error = DiffError.DeltaContainsInvalidUTF8, .expected_diffs = null },
        .{ .text = "", .delta = "+%c3xy", .expected_error = DiffError.DeltaContainsInvalidUTF8, .expected_diffs = null },
        .{ .text = "", .delta = "a", .expected_error = DiffError.DeltaContainsIlligalOperation, .expected_diffs = null },
        .{ .text = "", .delta = "-", .expected_error = std.fmt.ParseIntError.InvalidCharacter, .expected_diffs = null },
        .{ .text = "", .delta = "--1", .expected_error = DiffError.DeltaContainsNegetiveNumber, .expected_diffs = null },
        .{ .text = "", .delta = "", .expected_error = null, .expected_diffs = &.{} },
        .{ .text = text1, .delta = delta1, .expected_error = null, .expected_diffs = diffs1 },
        .{ .text = text2, .delta = delta2, .expected_error = null, .expected_diffs = diffs2 },
        .{ .text = "", .delta = delta3, .expected_error = null, .expected_diffs = diffs3 },
    };

    for (test_cases) |test_case| {
        defer if (test_case.expected_diffs) |diffs| for (diffs) |*diff| @constCast(diff).deinit(testing.allocator);
        if (dmp.diffFromDelta(test_case.text, test_case.delta)) |diffs| {
            defer testing.allocator.free(diffs);
            defer for (diffs) |*diff| diff.deinit(testing.allocator);

            try testing.expect(test_case.expected_diffs != null);
            try testing.expect(test_case.expected_error == null);

            try testing.expectEqual(test_case.expected_diffs.?.len, diffs.len);

            try testing.expectEqual(test_case.expected_diffs.?.len, diffs.len);
            for (test_case.expected_diffs.?, diffs) |expected, diff| {
                try testing.expectEqual(expected.operation, diff.operation);
                try testing.expectEqualStrings(expected.text, diff.text);
            }
        } else |err| {
            try testing.expect(test_case.expected_diffs == null);
            try testing.expect(test_case.expected_error != null);
            try testing.expectEqual(test_case.expected_error.?, err);
        }
    }
}

test "x index" {
    const TestCase = struct {
        diffs: []const Diff,
        location: usize,
        expected: usize,
    };

    const dmp = DMP.init(testing.allocator);

    for ([_]TestCase{
        .{
            .diffs = &.{
                try Diff.fromString(testing.allocator, "a", .delete),
                try Diff.fromString(testing.allocator, "1234", .insert),
                try Diff.fromString(testing.allocator, "xyz", .equal),
            },
            .location = 2,
            .expected = 5,
        },
        .{
            .diffs = &.{
                try Diff.fromString(testing.allocator, "a", .equal),
                try Diff.fromString(testing.allocator, "1234", .delete),
                try Diff.fromString(testing.allocator, "xyz", .equal),
            },
            .location = 3,
            .expected = 1,
        },
    }) |test_case| {
        const diffs = @constCast(test_case.diffs);
        defer for (diffs) |*diff| diff.deinit(testing.allocator);
        const actual = dmp.diffXIndex(diffs, test_case.location);
        try testing.expectEqual(test_case.expected, actual);
    }
}

test "levenstein" {
    const dmp = DMP.init(testing.allocator);

    var diffs: []Diff = undefined;
    {
        diffs = @constCast(&[_]Diff{
            try Diff.fromString(testing.allocator, "abc", .delete),
            try Diff.fromString(testing.allocator, "1234", .insert),
            try Diff.fromString(testing.allocator, "xyz", .equal),
        })[0..];
        defer for (diffs) |*diff| diff.deinit(testing.allocator);
        try testing.expectEqual(4, dmp.diffLevenshtein(diffs));
    }
    {
        diffs = @constCast(&[_]Diff{
            try Diff.fromString(testing.allocator, "xyz", .equal),
            try Diff.fromString(testing.allocator, "abc", .delete),
            try Diff.fromString(testing.allocator, "1234", .insert),
        })[0..];
        defer for (diffs) |*diff| diff.deinit(testing.allocator);
        try testing.expectEqual(4, dmp.diffLevenshtein(diffs));
    }
    {
        diffs = @constCast(&[_]Diff{
            try Diff.fromString(testing.allocator, "abc", .delete),
            try Diff.fromString(testing.allocator, "xyz", .equal),
            try Diff.fromString(testing.allocator, "1234", .insert),
        });
        defer for (diffs) |*diff| diff.deinit(testing.allocator);
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
        expected: []const Diff,
    };

    for ([_]TestCase{ .{ .deadline = diff_max_duration, .expected = &.{
        try Diff.fromString(testing.allocator, "c", .delete),
        try Diff.fromString(testing.allocator, "m", .insert),
        try Diff.fromString(testing.allocator, "a", .equal),
        try Diff.fromString(testing.allocator, "t", .delete),
        try Diff.fromString(testing.allocator, "p", .insert),
    } }, .{ .deadline = 0, .expected = &.{
        try Diff.fromString(testing.allocator, "cat", .delete),
        try Diff.fromString(testing.allocator, "map", .insert),
    } } }) |test_case| {
        defer for (test_case.expected) |*diff| diff.deinit();

        const actual = try DiffPrivate.diffBisect(testing.allocator, text1, text2, test_case.deadline);
        defer testing.allocator.free(actual);
        defer for (actual) |*diff| diff.deinit();

        try testing.expectEqual(test_case.expected.len, actual.len);
        for (test_case.expected, actual) |expected, diff| {
            try testing.expectEqual(expected.operation, diff.operation);
            try testing.expectEqualStrings(expected.text, diff.text);
        }
    }

    {
        const diffs: []Diff = &.{
            try Diff.fromString(testing.allocator, "��", .equal),
        };
        defer for (diffs) |*diff| diff.deinit();

        const actual = try DiffPrivate.diffBisect(dmp, "\xe0\xe5", "\xe0\xe5", std.time.ns_per_min);
        defer testing.allocator.free(actual);
        defer for (actual) |*diff| diff.deinit();

        try testing.expectEqual(diffs.len, actual.len);
        for (diffs, actual) |expected, diff| {
            try testing.expectEqual(expected.operation, diff.operation);
            try testing.expectEqualStrings(expected.text, diff.text);
        }
    }
}

test "diff main" {
    if (true) return error.SkipZigTest;
    const TestCase = struct {
        text1: []const u8,
        text2: []const u8,
        expected: []const Diff,
    };

    var dmp = DMP.init(testing.allocator);

    {
        const test_cases = [_]TestCase{
            .{
                .text1 = "",
                .text2 = "",
                .expected = &.{},
            },
            .{
                .text1 = "abc",
                .text2 = "abc",
                .expected = &.{try Diff.fromString(testing.allocator, "abc", .equal)},
            },
            .{
                .text1 = "abc",
                .text2 = "ab123c",
                .expected = &.{
                    try Diff.fromString(testing.allocator, "ab", .equal),
                    try Diff.fromString(testing.allocator, "123", .insert),
                    try Diff.fromString(testing.allocator, "c", .equal),
                },
            },
            .{
                .text1 = "a123bc",
                .text2 = "abc",
                .expected = &.{
                    try Diff.fromString(testing.allocator, "a", .equal),
                    try Diff.fromString(testing.allocator, "123", .delete),
                    try Diff.fromString(testing.allocator, "bc", .equal),
                },
            },
            .{
                .text1 = "abc",
                .text2 = "a123b456c",
                .expected = &.{
                    try Diff.fromString(testing.allocator, "a", .equal),
                    try Diff.fromString(testing.allocator, "123", .insert),
                    try Diff.fromString(testing.allocator, "b", .equal),
                    try Diff.fromString(testing.allocator, "456", .insert),
                    try Diff.fromString(testing.allocator, "c", .equal),
                },
            },
            .{
                .text1 = "a123b456c",
                .text2 = "abc",
                .expected = &.{
                    try Diff.fromString(testing.allocator, "a", .equal),
                    try Diff.fromString(testing.allocator, "123", .delete),
                    try Diff.fromString(testing.allocator, "b", .equal),
                    try Diff.fromString(testing.allocator, "456", .delete),
                    try Diff.fromString(testing.allocator, "c", .equal),
                },
            },
        };

        // Perform a trivial diff.
        for (test_cases) |test_case| {
            defer for (test_case.expected) |*diff| @constCast(diff).deinit(testing.allocator);

            const actual = try dmp.diffMainStringStringBool(test_case.text1, test_case.text2, false);
            defer testing.allocator.free(actual);
            defer for (actual) |*diff| diff.deinit(testing.allocator);

            try testing.expectEqual(test_case.expected.len, actual.len);
            for (test_case.expected, actual) |expected, diff| {
                try testing.expectEqual(expected.operation, diff.operation);
                try testing.expectEqualStrings(expected.text, diff.text);
            }
        }
    }

    // Perform a real diff and switch off the timeout.
    dmp.diff_timeout = 0;

    {
        const test_cases = [_]TestCase{
            .{
                .text1 = "a",
                .text2 = "b",
                .expected = &.{
                    try Diff.fromString(testing.allocator, "a", .delete),
                    try Diff.fromString(testing.allocator, "b", .insert),
                },
            },
            .{
                .text1 = "Apples are a fruit.",
                .text2 = "Bananas are also fruit.",
                .expected = &.{
                    try Diff.fromString(testing.allocator, "Apple", .delete),
                    try Diff.fromString(testing.allocator, "Banana", .insert),
                    try Diff.fromString(testing.allocator, "s are a", .equal),
                    try Diff.fromString(testing.allocator, "lso", .insert),
                    try Diff.fromString(testing.allocator, " fruit.", .equal),
                },
            },
            .{
                .text1 = "ax\t",
                .text2 = "\u{0680}x\u{0000}",
                .expected = &.{
                    try Diff.fromString(testing.allocator, "a", .delete),
                    try Diff.fromString(testing.allocator, "\u{0680}", .insert),
                    try Diff.fromString(testing.allocator, "x", .equal),
                    try Diff.fromString(testing.allocator, "\t", .delete),
                    try Diff.fromString(testing.allocator, "\u{0000}", .insert),
                },
            },
            .{
                .text1 = "1ayb2",
                .text2 = "abxab",
                .expected = &.{
                    try Diff.fromString(testing.allocator, "1", .delete),
                    try Diff.fromString(testing.allocator, "a", .equal),
                    try Diff.fromString(testing.allocator, "y", .delete),
                    try Diff.fromString(testing.allocator, "b", .equal),
                    try Diff.fromString(testing.allocator, "2", .delete),
                    try Diff.fromString(testing.allocator, "xab", .insert),
                },
            },
            .{
                .text1 = "abcy",
                .text2 = "xaxcxabc",
                .expected = &.{
                    try Diff.fromString(testing.allocator, "xaxcx", .insert),
                    try Diff.fromString(testing.allocator, "abc", .equal),
                    try Diff.fromString(testing.allocator, "y", .delete),
                },
            },
            .{
                .text1 = "ABCDa=bcd=efghijklmnopqrsEFGHIJKLMNOefg",
                .text2 = "a-bcd-efghijklmnopqrs",
                .expected = &.{
                    try Diff.fromString(testing.allocator, "ABCD", .delete),
                    try Diff.fromString(testing.allocator, "a", .equal),
                    try Diff.fromString(testing.allocator, "=", .delete),
                    try Diff.fromString(testing.allocator, "-", .insert),
                    try Diff.fromString(testing.allocator, "bcd", .equal),
                    try Diff.fromString(testing.allocator, "=", .delete),
                    try Diff.fromString(testing.allocator, "-", .insert),
                    try Diff.fromString(testing.allocator, "efghijklmnopqrs", .equal),
                    try Diff.fromString(testing.allocator, "EFGHIJKLMNOefg", .delete),
                },
            },
            .{
                .text1 = "a [[Pennsylvania]] and [[New",
                .text2 = " and [[Pennsylvania]]",
                .expected = &.{
                    try Diff.fromString(testing.allocator, " ", .insert),
                    try Diff.fromString(testing.allocator, "a", .equal),
                    try Diff.fromString(testing.allocator, "nd", .insert),
                    try Diff.fromString(testing.allocator, " [[Pennsylvania]]", .equal),
                    try Diff.fromString(testing.allocator, " and [[New", .delete),
                },
            },
        };

        for (test_cases) |test_case| {
            defer for (test_case.expected) |*diff| @constCast(diff).deinit(testing.allocator);

            const actual = try dmp.diffMainStringStringBool(test_case.text1, test_case.text2, false);
            defer testing.allocator.free(actual);
            defer for (actual) |*diff| diff.deinit(testing.allocator);

            try testing.expectEqual(test_case.expected.len, actual.len);
            for (test_case.expected, actual) |expected, diff| {
                try testing.expectEqual(expected.operation, diff.operation);
                try testing.expectEqualStrings(expected.text, diff.text);
            }
        }
    }

    {
        const diffs: []const Diff = &.{
            try Diff.fromString(testing.allocator, "��", .equal),
        };
        defer for (diffs) |*diff| @constCast(diff).deinit(testing.allocator);

        const actual = try dmp.diffMainStringStringBool("\xe0\xe5", "", false);
        defer testing.allocator.free(actual);
        defer for (actual) |*diff| diff.deinit(testing.allocator);

        try testing.expectEqual(diffs, actual.len);
        for (diffs, actual) |expected, diff| {
            try testing.expectEqual(expected.operation, diff.operation);
            try testing.expectEqualStrings(expected.text, diff.text);
        }
    }
}

test "diff main with timeout" {
    if (true) return error.SkipZigTest;
    var dmp = DMP.init(testing.allocator);
    dmp.diff_timeout = 0.1; // 100 ms

    // Increase the text lengths by 1024 times to ensure a timeout.
    const increase = 1 << 10;
    const a = "`Twas brillig, and the slithy toves\nDid gyre and gimble in the wabe:\nAll mimsy were the borogoves,\nAnd the mome raths outgrabe.\n" ** increase;
    const b = "I am the very model of a modern major general,\nI've information vegetable, animal, and mineral,\nI know the kings of England, and I quote the fights historical,\nFrom Marathon to Waterloo, in order categorical.\n" ** increase;

    var timer = try std.time.Timer.start();
    const diffs = try dmp.diffMainStringStringBool(a, b, true);
    for (diffs) |*diff| diff.deinit(testing.allocator);
    testing.allocator.free(diffs);
    const delta: f64 = @floatFromInt(timer.read());

    try testing.expect(delta >= dmp.diff_timeout * std.time.ns_per_s);

    // Test that we didn't take forever (be forgiving).
    // Theoretically this test could fail very occasionally if the
    // OS task swaps or locks up for a second at the wrong moment.
    try testing.expect(delta < (dmp.diff_timeout * std.time.ns_per_s * 2));
}

test "diff main linemode" {
    if (true) return error.SkipZigTest;
    const TestCase = struct {
        text1: []const u8,
        text2: []const u8,
    };

    var dmp = DMP.init(testing.allocator);
    dmp.diff_timeout = 0;

    // Test cases must be at least 100 chars long to pass the cutoff.
    const test_cases = [_]TestCase{
        .{
            .text1 = "1234567890\n" ** 13,
            .text2 = "abcdefghij\n" ** 13,
        },
        .{
            .text1 = "1234567890" ** 13,
            .text2 = "abcdefghij" ** 13,
        },
        .{
            .text1 = "1234567890\n" ** 13,
            .text2 = "abcdefghij\n1234567890\n1234567890\n1234567890\nabcdefghij\n1234567890\n1234567890\n1234567890\nabcdefghij\n1234567890\n1234567890\n1234567890\nabcdefghij\n",
        },
    };

    for (test_cases) |test_case| {
        const diffs_linemode = try dmp.diffMainStringStringBool(test_case.text1, test_case.text2, true);
        defer testing.allocator.free(diffs_linemode);
        defer for (diffs_linemode) |*diff| diff.deinit(testing.allocator);
        const diffs_textmode = try dmp.diffMainStringStringBool(test_case.text1, test_case.text2, false);
        defer testing.allocator.free(diffs_textmode);
        defer for (diffs_textmode) |*diff| diff.deinit(testing.allocator);

        const linemode_text1, const linemode_text2 = try diffRebuildTexts(diffs_linemode);
        defer testing.allocator.free(linemode_text1);
        defer testing.allocator.free(linemode_text2);
        const textmode_text1, const textmode_text2 = try diffRebuildTexts(diffs_textmode);
        defer testing.allocator.free(textmode_text1);
        defer testing.allocator.free(textmode_text2);

        try testing.expectEqualStrings(textmode_text1, linemode_text1);
        try testing.expectEqualStrings(textmode_text2, linemode_text2);
    }
}

test "partial line index" {
    if (true) return error.SkipZigTest;
    const dmp = DMP.init(testing.allocator);
    var text1 = testString(
        \\line1
        \\line2
        \\line3
        \\line 3
        \\line 4
        \\line 5
        \\line 6
        \\line 7
        \\line 8
        \\line 9
        \\line 10 text1
    );
    defer testing.allocator.free(text1);
    var text2 = testString(
        \\line 1
        \\line 2
        \\line 3
        \\line 4
        \\line 5
        \\line 6
        \\line 7
        \\line 8
        \\line 9
        \\line 10 text2
    );
    defer testing.allocator.free(text2);

    var linearray = try DiffPrivate.diffLinesToChars(testing.allocator, &text1, &text2);
    defer linearray.deinit();

    var diffs = try dmp.diffMainStringStringBool(text1, text2, false);
    defer testing.allocator.free(diffs);
    defer for (diffs) |*diff| diff.deinit(testing.allocator);

    try DiffPrivate.diffCharsToLinesLineArray(testing.allocator, &diffs, linearray);

    const expect: []const Diff = &.{
        try Diff.fromString(testing.allocator, "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\n", .equal),
        try Diff.fromString(testing.allocator, "line 10 text1", .delete),
        try Diff.fromString(testing.allocator, "line 10 text2", .insert),
    };
    defer for (expect) |*diff| @constCast(diff).deinit(testing.allocator);

    try testing.expectEqual(expect.len, diffs.len);
    for (expect, diffs) |expected, diff| {
        try testing.expectEqual(expected.operation, diff.operation);
        try testing.expectEqualStrings(expected.text, diff.text);
    }
}
