const std = @import("std");
const utils = @import("utils.zig");

const diff = @import("diff.zig");
const match = @import("match.zig");
const patch = @import("patch.zig");

comptime {
    _ = @import("diff_test.zig");
    _ = @import("match_test.zig");
    _ = @import("patch_test.zig");
    _ = @import("utils.zig");
}

pub const DiffMatchPatch = DiffMatchPatchCustom(u32);

pub const MatchError = match.MatchError;
pub const PatchError = patch.PatchError;
pub const DiffError = diff.DiffError;

pub const DiffOperation = diff.DiffOperation;
pub const Diff = diff.Diff;
pub const diff_max_duration = diff.diff_max_duration;

pub const PatchList = patch.PatchList;
pub const PatchDiffsArrayList = patch.PatchDiffsArrayList;
pub const Patch = patch.Patch;

///DiffMatchPatch struct
///the container that determins the number of bits in an int
fn DiffMatchPatchCustom(MatchMaxContainer: type) type {
    return struct {
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
        patch_margin: u16 = 4,

        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        // TODO: move doc comments here

        // diff ------------------
        pub inline fn diffMainStringString(self: Self, text1: []const u8, text2: []const u8) ![]Diff {
            return diff.diffMainStringString(self.allocator, self.diff_timeout, text1, text2);
        }
        pub inline fn diffMainStringStringBool(self: Self, text1: []const u8, text2: []const u8, check_lines: bool) ![]Diff {
            return diff.diffMainStringStringBool(self.allocator, self.diff_timeout, text1, text2, check_lines);
        }
        pub inline fn diffCommonPrefix(self: Self, text1: []const u8, text2: []const u8) usize {
            _ = self;
            return diff.diffCommonPrefix(text1, text2);
        }
        pub inline fn diffCommonSuffix(self: Self, text1: []const u8, text2: []const u8) usize {
            _ = self;
            return diff.diffCommonSuffix(text1, text2);
        }
        pub inline fn diffCleanupSemantic(self: Self, diffs: *[]Diff) !void {
            return diff.diffCleanupSemantic(self.allocator, diffs);
        }
        pub inline fn diffCleanupSemanticLossless(self: Self, diffs: *[]Diff) !void {
            return diff.diffCleanupSemanticLossless(self.allocator, diffs);
        }
        pub inline fn diffCleanupEfficiency(self: Self, diffs: *[]Diff) !void {
            return diff.diffCleanupEfficiency(self.allocator, diffs);
        }
        pub inline fn diffCleanupMerge(self: Self, diffs: *[]Diff) !void {
            return diff.diffCleanupMerge(self.allocator, diffs);
        }
        pub inline fn diffXIndex(self: Self, diffs: []Diff, loc: usize) usize {
            _ = self;
            return diff.diffXIndex(diffs, loc);
        }
        pub inline fn diffPrettyHtml(self: Self, diffs: []Diff) std.mem.Allocator.Error![:0]const u8 {
            return diff.diffPrettyHtml(self.allocator, diffs);
        }
        pub inline fn diffPrettyHtmlWriter(self: Self, writer: anytype, diffs: []Diff) @TypeOf(writer).Error!void {
            _ = self;
            return diff.diffPrettyHtmlWriter(writer, diffs);
        }
        pub inline fn diffPrettyText(self: Self, diffs: []Diff) std.mem.Allocator.Error![:0]const u8 {
            return diff.diffPrettyText(self.allocator, diffs);
        }
        pub inline fn diffPrettyTextWriter(self: Self, writer: anytype, diffs: []Diff) @TypeOf(writer).Error!void {
            _ = self;
            return diff.diffPrettyTextWriter(writer, diffs);
        }
        pub inline fn diffText1(self: Self, diffs: []Diff) std.mem.Allocator.Error![:0]const u8 {
            return diff.diffText1(self.allocator, diffs);
        }
        pub inline fn diffText2(self: Self, diffs: []Diff) std.mem.Allocator.Error![:0]const u8 {
            return diff.diffText2(self.allocator, diffs);
        }
        pub fn diffLevenshtein(self: Self, diffs: []Diff) usize {
            _ = self;
            return diff.diffLevenshtein(diffs);
        }
        pub inline fn diffToDelta(self: Self, diffs: []Diff) std.mem.Allocator.Error![:0]const u8 {
            return diff.diffToDelta(self.allocator, diffs);
        }
        pub inline fn diffToDeltaWriter(self: Self, writer: anytype, diffs: []Diff) @TypeOf(writer).Error!void {
            _ = self;
            return diff.diffToDeltaWriter(writer, diffs);
        }
        pub fn diffFromDelta(self: Self, text1: []const u8, delta: []const u8) (DiffError || std.fmt.ParseIntError || std.mem.Allocator.Error)![]Diff {
            return diff.diffFromDelta(self.allocator, text1, delta);
        }

        // match -----------------
        pub inline fn matchMain(self: Self, text: []const u8, pattern: []const u8, loc: usize) (MatchError || std.mem.Allocator.Error)!?usize {
            return match.matchMain(MatchMaxContainer, self.allocator, self.match_distance, self.match_threshold, text, pattern, loc);
        }
        pub inline fn matchBitap(self: Self, text: []const u8, pattern: []const u8, loc: usize) (MatchError || std.mem.Allocator.Error)!?usize {
            return match.matchBitap(MatchMaxContainer, self.allocator, self.match_distance, self.match_threshold, text, pattern, loc);
        }

        // patch -----------------
        pub inline fn patchAddContext(self: Self, p: *Patch, text: []const u8) std.mem.Allocator.Error!void {
            return patch.patchAddContext(MatchMaxContainer, self.allocator, self.patch_margin, p, text);
        }
        pub inline fn patchMakeStringString(self: Self, text1: [:0]const u8, text2: [:0]const u8) !PatchList {
            return patch.patchMakeStringString(MatchMaxContainer, self.allocator, self.patch_margin, self.diff_timeout, text1, text2);
        }
        pub inline fn patchMakeDiffs(self: Self, diffs: []Diff) !PatchList {
            return patch.patchMakeDiffs(MatchMaxContainer, self.allocator, self.patch_margin, diffs);
        }
        pub inline fn patchMakeStringStringDiffs(self: Self, text1: [:0]const u8, text2: [:0]const u8, diffs: []Diff) !PatchList {
            return patch.patchMakeStringStringDiffs(MatchMaxContainer, self.allocator, self.patch_margin, text1, text2, diffs);
        }
        pub inline fn patchMakeStringDiffs(self: Self, text1: [:0]const u8, diffs: []Diff) std.mem.Allocator.Error!PatchList {
            return patch.patchMakeStringDiffs(MatchMaxContainer, self.allocator, self.patch_margin, text1, diffs);
        }
        pub inline fn patchDeepCopy(self: Self, patches: PatchList) std.mem.Allocator.Error!PatchList {
            return patch.patchDeepCopy(self.allocator, patches);
        }
        pub inline fn patchApply(self: Self, patches: PatchList, text: [:0]const u8) !struct { []const u8, []bool } {
            return patch.patchApply(MatchMaxContainer, self.allocator, self.patch_delete_threshold, patches, text);
        }
        pub inline fn patchAddPadding(self: Self, patches: *PatchList) std.mem.Allocator.Error![:0]const u8 {
            return patch.patchAddPadding(self.allocator, self.patch_margin, patches);
        }
        pub inline fn patchSplitMax(self: Self, patches: *PatchList) !void {
            return patch.patchSplitMax(MatchMaxContainer, self.allocator, self.patch_margin, patches);
        }
        pub inline fn patchToText(self: Self, patches: PatchList) ![:0]const u8 {
            return patch.patchToText(self.allocator, patches);
        }
        pub inline fn patchFromText(self: Self, textline: [:0]const u8) (PatchError || std.mem.Allocator.Error)!PatchList {
            return patch.patchFromText(self.allocator, textline);
        }
    };
}
