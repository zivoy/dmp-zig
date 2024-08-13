const std = @import("std");
const utils = @import("utils.zig");

const Self = @This();

///Number of seconds to map a diff before giving up (0 for infinity).
diff_timeout: f32 = 1.0,
///Cost of an empty edit operation in terms of edit characters.
diff_edit_cost: u16 = 4,
///At what point is no match declared (0.0 = perfection, 1.0 = very loose).
match_threshold: f32 = 0.5,
///How far to search for a match (0 = exact location, 1000+ = broad match).
///A match this many characters away from the expected location will add
///1.0 to the score (0.0 is a perfect match).
match_distance: u32 = 1000,
///When deleting a large block of text (over ~64 characters), how close
///do the contents have to be to match the expected contents. (0.0 =
///perfection, 1.0 = very loose).  Note that Match_Threshold controls
///how closely the end points of a delete need to match.
patch_delete_threshold: f32 = 0.5,
///Chunk size for context length.
patch_margin: u16 = 4, // TODO: maybe make some of these comptime known

allocator: std.mem.Allocator,

///Container that determins the number of bits in an int
pub const MatchMaxContainer = u32;
pub const match_max_bits: usize = @bitSizeOf(MatchMaxContainer);

pub fn init(allocator: std.mem.Allocator) Self {
    return .{ .allocator = allocator };
}

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

pub const PatchList = struct {
    items: []Patch,
    allocator: std.mem.Allocator,
    pub fn deinit(self: PatchList) void {
        for (self.items) |patch| patch.deinit(self.allocator);
        self.allocator.free(self.items);
    }
};

pub const PatchDiffsArrayList = std.ArrayListUnmanaged(Diff);
pub const Patch = struct {
    diffs: *PatchDiffsArrayList,
    start1: usize, // TODO: find other u32s that should be usizes
    start2: usize,
    length1: usize,
    length2: usize,

    ///Emulates GNU diff's format.
    ///Header: @@ -382,8 +481,9 @@
    ///Indices are printed as 1-based, not 0-based.
    pub fn format(
        self: Patch,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.writeAll("@@ -");

        if (self.length1 == 0) {
            try writer.print("{d},0", .{self.start1});
        } else if (self.length1 == 1) {
            try writer.print("{d}", .{self.start1 + 1});
        } else {
            try writer.print("{d},{d}", .{ self.start1 + 1, self.length1 });
        }

        try writer.writeAll(" +");

        if (self.length2 == 0) {
            try writer.print("{d},0", .{self.start2});
        } else if (self.length2 == 1) {
            try writer.print("{d}", .{self.start2 + 1});
        } else {
            try writer.print("{d},{d}", .{ self.start2 + 1, self.length2 });
        }

        try writer.writeAll(" @@\n");

        // Escape the body of the patch with %xx notation.
        for (self.diffs.items) |diff| {
            switch (diff.operation) {
                .insert => try writer.writeAll("+"),
                .delete => try writer.writeAll("-"),
                .equal => try writer.writeAll(" "),
            }

            try utils.encodeURI(writer, diff.text);
            try writer.writeAll("\n");
        }
    }

    pub fn init(allocator: std.mem.Allocator, start1: usize, start2: usize, length1: usize, length2: usize) !Patch {
        const diffs = try allocator.create(PatchDiffsArrayList);
        diffs.* = .{};
        return Patch{
            .start1 = start1,
            .start2 = start2,
            .length1 = length1,
            .length2 = length2,
            .diffs = diffs,
        };
    }

    pub fn deinit(self: Patch, allocator: std.mem.Allocator) void {
        for (self.diffs.items) |diff| {
            diff.deinit(allocator);
        }
        self.diffs.deinit(allocator);
        allocator.destroy(self.diffs);
    }
};

pub const MatchError = error{
    PatternTooLong,
};

pub const PatchError = error{
    InvalidPatchString,
    InvalidPatchMode,
};

pub const DiffError = error{
    DeltaShorterThenSource,
    DeltaContainsNegetiveNumber,
    DeltaContainsIlligalOperation,
};

// diff ------------------

pub usingnamespace @import("diff.zig");

// match -----------------

pub usingnamespace @import("match.zig");

// patch -----------------

pub usingnamespace @import("patch.zig");

comptime {
    _ = @import("diff_tests.zig");
    _ = @import("match_test.zig");
    _ = @import("patch_tests.zig");
    _ = @import("utils.zig");
}
