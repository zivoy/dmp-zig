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

test "diff lines to chars" {
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
    defer for (long_lines) |line| testing.allocator.free(line);
    long_lines[0] = try testing.allocator.alloc(u8, 0);
    for (long_lines[1..], 1..) |*line, i| {
        line.* = try testing.allocator.alloc(u8, if (i < 256) 2 else 3);
        _ = try std.fmt.bufPrint(line.*, "{d}\n", .{i});
    }

    const test_cases = [_]TestCase{
        .{ .text1 = testString(""), .text2 = testString("alpha\r\nbeta\r\n\r\n\r\n"), .expected_text1 = "", .expected_text2 = "\x01\x02\x03\x03", .expected_lines = &.{ "", "alpha\r\n", "beta\r\n", "\r\n" } },
        .{ .text1 = testString("a"), .text2 = testString("b"), .expected_text1 = "\x01", .expected_text2 = "\x02", .expected_lines = &.{ "", "a", "b" } },
        // Omit final newline.
        .{ .text1 = testString("alpha\nbeta\nalpha"), .text2 = testString(""), .expected_text1 = "\x01\x02\x03", .expected_text2 = "", .expected_lines = &.{ "", "alpha\n", "beta\n", "alpha" } },
        // Same lines in Text1 and Text2
        .{ .text1 = testString("abc\ndefg\n12345\n"), .text2 = testString("abc\ndef\n12345\n678"), .expected_text1 = "\x01\x02\x03", .expected_text2 = "\x01\x04\x03\x05", .expected_lines = &.{ "", "abc\n", "defg\n", "12345\n", "def\n", "678" } },
        .{
            .text1 = try std.mem.join(testing.allocator, "", &long_lines),
            .text2 = testString(""),
            .expected_text1 = try std.mem.join(testing.allocator, "", &long_lines),
            .expected_text2 = "",
            .expected_lines = &long_lines,
        },
    };
    defer testing.allocator.free(test_cases[test_cases.len - 1].expected_text1);

    for (test_cases) |test_case| {
        defer testing.allocator.free(test_case.text1);
        defer testing.allocator.free(test_case.text2);
        const line_array = try DiffPrivate.diffLinesToChars(dmp, @constCast(&test_case.text1), @constCast(&test_case.text2));
        defer line_array.deinit();
        try testing.expectEqualStrings(test_case.expected_text1, test_case.text1);
        try testing.expectEqualStrings(test_case.expected_text2, test_case.text2);
        try testing.expectEqual(test_case.expected_lines, line_array.items);
    }
}

test "diff levenstein" {
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
