const DMP = @import("diffmatchpatch.zig");
const std = @import("std");
const testing = std.testing;

test "errors from text" {
    const TestCase = struct {
        patch: [:0]const u8,
        expectedPatchError: ?DMP.PatchError,
    };

    const dmp = DMP.init(testing.allocator);

    for ([_]TestCase{
        .{ .patch = "", .expectedPatchError = null },
        .{ .patch = "@@ -21,18 +22,17 @@\n jump\n-s\n+ed\n  over \n-the\n+a\n %0Alaz\n", .expectedPatchError = null },
        .{ .patch = "@@ -1 +1 @@\n-a\n+b\n", .expectedPatchError = null },
        .{ .patch = "@@ -1,3 +0,0 @@\n-abc\n", .expectedPatchError = null },
        .{ .patch = "@@ -0,0 +1,3 @@\n+abc\n", .expectedPatchError = null },
        .{ .patch = "@@ _0,0 +0,0 @@\n+abc\n", .expectedPatchError = DMP.PatchError.InvalidPatchString },
        .{ .patch = "Bad\nPatch\n", .expectedPatchError = DMP.PatchError.InvalidPatchMode },
    }) |test_case| {
        const patches = dmp.patchFromText(test_case.patch) catch |err| {
            if (test_case.expectedPatchError == null) return err;
            try testing.expectEqual(test_case.expectedPatchError.?, err);
            return;
        };
        defer patches.deinit();
        try testing.expect(test_case.expectedPatchError == null);

        const strpatch = try dmp.patchToText(patches);
        defer testing.allocator.free(strpatch);
        try testing.expectEqualStrings(test_case.patch, strpatch);
    }
}

test "from to text" {
    const dmp = DMP.init(testing.allocator);
    const patch_strs = [_][:0]const u8{
        "@@ -21,18 +22,17 @@\n jump\n-s\n+ed\n  over \n-the\n+a\n  laz\n",
        "@@ -1,9 +1,9 @@\n-f\n+F\n oo+fooba\n@@ -7,9 +7,9 @@\n obar\n-,\n+.\n  tes\n",
    };
    for (patch_strs) |patchstr| {
        const patches = try dmp.patchFromText(patchstr);
        defer patches.deinit();

        const strpatch = try dmp.patchToText(patches);
        defer testing.allocator.free(strpatch);
        try testing.expectEqualStrings(patchstr, strpatch);
    }
}

test "add context" {
    const TestCase = struct {
        patch: [:0]const u8,
        text: [:0]const u8,
        expected: [:0]const u8,
    };

    const dmp = DMP.init(testing.allocator);

    for ([_]TestCase{
        .{ .patch = "@@ -21,4 +21,10 @@\n-jump\n+somersault\n", .text = "The quick brown fox jumps over the lazy dog.", .expected = "@@ -17,12 +17,18 @@\n fox \n-jump\n+somersault\n s ov\n" },
        .{ .patch = "@@ -21,4 +21,10 @@\n-jump\n+somersault\n", .text = "The quick brown fox jumps.", .expected = "@@ -17,10 +17,16 @@\n fox \n-jump\n+somersault\n s.\n" },
        .{ .patch = "@@ -3 +3,2 @@\n-e\n+at\n", .text = "The quick brown fox jumps.", .expected = "@@ -1,7 +1,8 @@\n Th\n-e\n+at\n  qui\n" },
        .{ .patch = "@@ -3 +3,2 @@\n-e\n+at\n", .text = "The quick brown fox jumps.  The quick brown fox crashes.", .expected = "@@ -1,27 +1,28 @@\n Th\n-e\n+at\n  quick brown fox jumps. \n" },
    }) |test_case| {
        const patches = try dmp.patchFromText(test_case.patch);
        defer patches.deinit();

        try dmp.patchAddContext(&patches.items[0], test_case.text);
        const actual = try dmp.patchToText(patches);
        defer testing.allocator.free(actual);
        try testing.expectEqualStrings(test_case.expected, actual);
    }
}

test "patch make and patch to text" {
    if (true) return error.SkipZigTest;
    const Input = union(enum) {
        diffs: []DMP.Diff,
        text: [:0]const u8,
        none,
    };

    const TestCase = struct {
        input1: Input,
        input2: Input,
        input3: Input,
        expected: [:0]const u8,
    };

    var dmp = DMP.init(testing.allocator);

    var text1: [:0]const u8 = "The quick brown fox jumps over the lazy dog.";
    var text2: [:0]const u8 = "That quick brown fox jumped over a lazy dog.";

    for ([_]TestCase{
        .{ .input1 = .{ .text = "" }, .input2 = .{ .text = "" }, .input3 = .none, .expected = "" },
        .{ .input1 = .{ .text = text2 }, .input2 = .{ .text = text1 }, .input3 = .none, .expected = "@@ -1,8 +1,7 @@\n Th\n-at\n+e\n  qui\n@@ -21,17 +21,18 @@\n jump\n-ed\n+s\n  over \n-a\n+the\n  laz\n" },
        .{ .input1 = .{ .text = text1 }, .input2 = .{ .text = text2 }, .input3 = .none, .expected = "@@ -1,11 +1,12 @@\n Th\n-e\n+at\n  quick b\n@@ -22,18 +22,17 @@\n jump\n-s\n+ed\n  over \n-the\n+a\n  laz\n" },
        .{ .input1 = .{ .diffs = dmp.diffMainStringStringBool(text1, text2, false) }, .input2 = .none, .input3 = .none, .expected = "@@ -1,11 +1,12 @@\n Th\n-e\n+at\n  quick b\n@@ -22,18 +22,17 @@\n jump\n-s\n+ed\n  over \n-the\n+a\n  laz\n" },
        .{ .input1 = .{ .text = text1 }, .input2 = .{ .diffs = dmp.diffMainStringStringBool(text1, text2, false) }, .input3 = .none, .expected = "@@ -1,11 +1,12 @@\n Th\n-e\n+at\n  quick b\n@@ -22,18 +22,17 @@\n jump\n-s\n+ed\n  over \n-the\n+a\n  laz\n" },
        .{ .input1 = .{ .text = text1 }, .input2 = .{ .text = text2 }, .input3 = .{ .diffs = dmp.diffMainStringStringBool(text1, text2, false) }, .expected = "@@ -1,11 +1,12 @@\n Th\n-e\n+at\n  quick b\n@@ -22,18 +22,17 @@\n jump\n-s\n+ed\n  over \n-the\n+a\n  laz\n" },
        .{ .input1 = .{ .text = "`1234567890-=[]\\;',./" }, .input2 = .{ .text = "~!@#$%^&*()_+{}|:\"<>?" }, .input3 = .none, .expected = "@@ -1,21 +1,21 @@\n-%601234567890-=%5B%5D%5C;',./\n+~!@#$%25%5E&*()_+%7B%7D%7C:%22%3C%3E?\n" },
        .{ .input1 = .{ .text = "abcdef" ** 100 }, .input2 = .{ .text = "abcdef" ** 100 ++ "123" }, .input3 = .none, .expected = "@@ -573,28 +573,31 @@\n cdefabcdefabcdefabcdefabcdef\n+123\n" },
        .{ .input1 = .{ .text = "2016-09-01T03:07:14.807830741Z" }, .input2 = .{ .text = "2016-09-01T03:07:15.154800781Z" }, .input3 = .none, .expected = "@@ -15,16 +15,16 @@\n 07:1\n+5.15\n 4\n-.\n 80\n+0\n 78\n-3074\n 1Z\n" },
    }) |test_case| {
        const patches: DMP.PatchList = blk: {
            switch (test_case.input3) {
                .diffs => |diffs| {
                    defer testing.allocator.free(diffs);
                    defer for (diffs) |diff| diff.deinit(testing.allocator);
                    break :blk try dmp.patchMakeStringStringDiffs(test_case.input1.text, test_case.input2.text, diffs);
                },
                .text => unreachable,
                .none => {},
            }
            switch (test_case.input2) {
                .diffs => |diffs| {
                    defer testing.allocator.free(diffs);
                    defer for (diffs) |diff| diff.deinit(testing.allocator);
                    break :blk try dmp.patchMakeStringDiffs(test_case.input1.text, diffs);
                },
                .text => |text| break :blk try dmp.patchMakeStringString(test_case.input1.text, text),
                .none => {},
            }
            switch (test_case.input1) {
                .diffs => |diffs| {
                    defer testing.allocator.free(diffs);
                    defer for (diffs) |diff| diff.deinit(testing.allocator);
                    break :blk try dmp.patchMakeDiffs(diffs);
                },
                .text => unreachable,
                .none => unreachable,
            }
            unreachable;
        };
        defer patches.deinit();

        const actual = try dmp.patchToText(patches);
        defer testing.allocator.free(actual);

        try testing.expectEqualStrings(test_case.expected, actual);
    }

    dmp.diff_timeout = 0;

    text1 = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vivamus ut risus et enim consectetur convallis a non ipsum. Sed nec nibh cursus, interdum libero vel.";
    text2 = "Lorem a ipsum dolor sit amet, consectetur adipiscing elit. Vivamus ut risus et enim consectetur convallis a non ipsum. Sed nec nibh cursus, interdum liberovel.";

    const diffs = dmp.diffMainStringStringBool(text1, text2, true);
    defer testing.allocator.free(diffs);
    defer for (diffs) |diff| diff.deinit(testing.allocator);
    try testing.expectEqual(text1, dmp.diffText1(diffs));
    try testing.expectEqual(text2, dmp.diffText2(diffs));

    const patches = try dmp.patchMakeDiffs(diffs);
    defer patches.deinit();

    const actual = try dmp.patchToText(patches);
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings("@@ -1,14 +1,16 @@\n Lorem \n+a \n ipsum do\n@@ -148,13 +148,12 @@\n m libero\n- \n vel.\n", actual);
}

test "split max" {
    if (true) return error.SkipZigTest;
    const TestCase = struct {
        text1: [:0]const u8,
        text2: [:0]const u8,
        expected: [:0]const u8,
    };

    const dmp = DMP.init(testing.allocator);

    for ([_]TestCase{
        .{ .text1 = "abcdefghijklmnopqrstuvwxyz01234567890", .text2 = "XabXcdXefXghXijXklXmnXopXqrXstXuvXwxXyzX01X23X45X67X89X0", .expected = "@@ -1,32 +1,46 @@\n+X\n ab\n+X\n cd\n+X\n ef\n+X\n gh\n+X\n ij\n+X\n kl\n+X\n mn\n+X\n op\n+X\n qr\n+X\n st\n+X\n uv\n+X\n wx\n+X\n yz\n+X\n 012345\n@@ -25,13 +39,18 @@\n zX01\n+X\n 23\n+X\n 45\n+X\n 67\n+X\n 89\n+X\n 0\n" },
        .{ .text1 = "abcdef1234567890123456789012345678901234567890123456789012345678901234567890uvwxyz", .text2 = "abcdefuvwxyz", .expected = "@@ -3,78 +3,8 @@\n cdef\n-1234567890123456789012345678901234567890123456789012345678901234567890\n uvwx\n" },
        .{ .text1 = "1234567890123456789012345678901234567890123456789012345678901234567890", .text2 = "abc", .expected = "@@ -1,32 +1,4 @@\n-1234567890123456789012345678\n 9012\n@@ -29,32 +1,4 @@\n-9012345678901234567890123456\n 7890\n@@ -57,14 +1,3 @@\n-78901234567890\n+abc\n" },
        .{ .text1 = "abcdefghij , h : 0 , t : 1 abcdefghij , h : 0 , t : 1 abcdefghij , h : 0 , t : 1", .text2 = "abcdefghij , h : 1 , t : 1 abcdefghij , h : 1 , t : 1 abcdefghij , h : 0 , t : 1", .expected = "@@ -2,32 +2,32 @@\n bcdefghij , h : \n-0\n+1\n  , t : 1 abcdef\n@@ -29,32 +29,32 @@\n bcdefghij , h : \n-0\n+1\n  , t : 1 abcdef\n" },
    }) |test_case| {
        var patches = try dmp.patchMakeStringString(test_case.text1, test_case.text2);
        defer patches.deinit();

        try dmp.patchSplitMax(&patches);

        const actual = try dmp.patchToText(patches);
        defer testing.allocator.free(actual);
        try testing.expectEqualStrings(test_case.expected, actual);
    }
}

test "add padding" {
    if (true) return error.SkipZigTest;
    const TestCase = struct {
        text1: [:0]const u8,
        text2: [:0]const u8,
        expected: [:0]const u8,
        expected_with_padding: [:0]const u8,
    };

    const dmp = DMP.init(testing.allocator);

    for ([_]TestCase{
        .{ .text1 = "", .text2 = "test", .expected = "@@ -0,0 +1,4 @@\n+test\n", .expected_with_padding = "@@ -1,8 +1,12 @@\n %01%02%03%04\n+test\n %01%02%03%04\n" },
        .{ .text1 = "XY", .text2 = "XtestY", .expected = "@@ -1,2 +1,6 @@\n X\n+test\n Y\n", .expected_with_padding = "@@ -2,8 +2,12 @@\n %02%03%04X\n+test\n Y%01%02%03\n" },
        .{ .text1 = "XXXXYYYY", .text2 = "XXXXtestYYYY", .expected = "@@ -1,8 +1,12 @@\n XXXX\n+test\n YYYY\n", .expected_with_padding = "@@ -5,8 +5,12 @@\n XXXX\n+test\n YYYY\n" },
    }) |test_case| {
        var patches = try dmp.patchMakeStringString(test_case.text1, test_case.text2);
        defer patches.deinit();

        const actual = try dmp.patchToText(patches);
        defer testing.allocator.free(actual);
        try testing.expectEqualStrings(test_case.expected, actual);

        const actual_with_padding = try dmp.patchAddPadding(&patches);
        defer testing.allocator.free(actual_with_padding);
        try testing.expectEqualStrings(test_case.expected_with_padding, actual_with_padding);
    }
}

test "patch apply" {
    if (true) return error.SkipZigTest;
    const TestCase = struct {
        text1: [:0]const u8,
        text2: [:0]const u8,
        text_base: [:0]const u8,

        expected: [:0]const u8,
        expected_applies: []bool,
    };

    var dmp = DMP.init(testing.allocator);
    dmp.match_distance = 1000;
    dmp.match_threshold = 0.5;
    dmp.patch_delete_threshold = 0.5;

    for ([_]TestCase{
        .{ .text1 = "", .text2 = "", .text_base = "Hello world.", .expected = "Hello world.", .expected_applies = @constCast(&[_]bool{}) },
        .{ .text1 = "The quick brown fox jumps over the lazy dog.", .text2 = "That quick brown fox jumped over a lazy dog.", .text_base = "The quick brown fox jumps over the lazy dog.", .expected = "That quick brown fox jumped over a lazy dog.", .expected_applies = @constCast(&[_]bool{ true, true }) },
        .{ .text1 = "The quick brown fox jumps over the lazy dog.", .text2 = "That quick brown fox jumped over a lazy dog.", .text_base = "The quick red rabbit jumps over the tired tiger.", .expected = "That quick red rabbit jumped over a tired tiger.", .expected_applies = @constCast(&[_]bool{ true, true }) },
        .{ .text1 = "The quick brown fox jumps over the lazy dog.", .text2 = "That quick brown fox jumped over a lazy dog.", .text_base = "I am the very model of a modern major general.", .expected = "I am the very model of a modern major general.", .expected_applies = @constCast(&[_]bool{ false, false }) },
        .{ .text1 = "x1234567890123456789012345678901234567890123456789012345678901234567890y", .text2 = "xabcy", .text_base = "x123456789012345678901234567890-----++++++++++-----123456789012345678901234567890y", .expected = "xabcy", .expected_applies = @constCast(&[_]bool{ true, true }) },
        .{ .text1 = "x1234567890123456789012345678901234567890123456789012345678901234567890y", .text2 = "xabcy", .text_base = "x12345678901234567890---------------++++++++++---------------12345678901234567890y", .expected = "xabc12345678901234567890---------------++++++++++---------------12345678901234567890y", .expected_applies = @constCast(&[_]bool{ false, true }) },
    }) |test_case| {
        const patches = try dmp.patchMakeStringString(test_case.text1, test_case.text2);
        defer patches.deinit();

        const actual, const actual_applies = try dmp.patchApply(patches, test_case.text_base);
        defer testing.allocator.free(actual);
        defer testing.allocator.free(actual_applies);

        try testing.expectEqualStrings(test_case.expected, actual);
        try testing.expectEqual(test_case.expected_applies, actual_applies);
    }
}

test "patch format" {
    const patch = try DMP.Patch.init(testing.allocator, 20, 21, 18, 17);
    try patch.diffs.appendSlice(testing.allocator, &[_]DMP.Diff{
        try DMP.Diff.fromString(testing.allocator, "jump", .equal),
        try DMP.Diff.fromString(testing.allocator, "s", .delete),
        try DMP.Diff.fromString(testing.allocator, "ed", .insert),
        try DMP.Diff.fromString(testing.allocator, " over ", .equal),
        try DMP.Diff.fromString(testing.allocator, "the", .delete),
        try DMP.Diff.fromString(testing.allocator, "a", .insert),
        try DMP.Diff.fromString(testing.allocator, "\nlaz", .equal),
    });

    defer patch.deinit(testing.allocator);
    const expect = "@@ -21,18 +22,17 @@\n jump\n-s\n+ed\n  over \n-the\n+a\n %0Alaz\n";

    var arraylist = std.ArrayList(u8).init(testing.allocator);
    defer arraylist.deinit();
    const writer = arraylist.writer();

    try std.fmt.format(writer, "{}", .{patch});
    try testing.expectEqualStrings(expect, arraylist.items);
}
