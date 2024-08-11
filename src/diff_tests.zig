const DMP = @import("diffmatchpatch.zig");
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
